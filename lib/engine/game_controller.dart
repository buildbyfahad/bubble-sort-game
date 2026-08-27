import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/level.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import 'board_state.dart';
import 'solver.dart';

enum GameStatus { playing, resolving, solved }

/// Orchestrates one playthrough of one level.
///
/// This is the seam between pure rules ([BoardState]) and presentation. It owns
/// *when* things happen — selection, the flight of a pour, the beat where a
/// vessel seals, the pause before the win sheet — while the widgets own only
/// *how* those moments look. Feedback (audio, haptics) is fired from here so a
/// cue can never be attached to a rebuild instead of to an event.
class GameController extends ChangeNotifier {
  GameController({
    required this.level,
    required AudioService audio,
    required HapticService haptics,
  })  : _audio = audio,
        _haptics = haptics,
        _state = BoardState(level.tubes, level.capacity);

  final Level level;
  final AudioService _audio;
  final HapticService _haptics;

  BoardState _state;
  BoardState get state => _state;

  GameStatus _status = GameStatus.playing;
  GameStatus get status => _status;

  int? _selected;
  int? get selected => _selected;

  final List<Pour> _history = <Pour>[];
  int get moves => _history.length;
  bool get canUndo => _history.isNotEmpty && _flight == null && _status != GameStatus.solved;

  /// The pour currently in the air. While this is set, the destination's
  /// arriving balls are withheld from the board and drawn by the flight
  /// overlay instead, so a ball is never in two places at once.
  Pour? _flight;
  Pour? get flight => _flight;

  /// A pour the player asked for while another was still in the air.
  ///
  /// The rules layer has *already* applied the in-flight pour to [_state] — the
  /// flight is a rendering concern, not a logical one — so a tap arriving
  /// mid-flight can be validated and acknowledged immediately, and only its
  /// launch has to wait. That is the whole reason this exists: the previous
  /// version dropped those taps on the floor, which is felt as the game
  /// ignoring you rather than as the game being busy.
  ///
  /// Depth one, deliberately. Buffering a queue of moves stops feeling
  /// responsive and starts feeling like the board is running away.
  (int, int)? _queued;
  bool get hasQueuedPour => _queued != null;

  /// Increments on every launch; the board view keys its flight animation off
  /// this so two pours in quick succession can never share an animation.
  int _flightToken = 0;
  int get flightToken => _flightToken;

  /// The vessel that most recently received a pour, and how many balls it
  /// took. The board plays its landing squash from these.
  int _lastLandedTube = -1;
  int _lastLandedCount = 0;
  int get lastLandedTube => _lastLandedTube;
  int get lastLandedCount => _lastLandedCount;

  /// Vessels that sealed on the most recent pour — the board plays its
  /// shatter on these and then clears them.
  Set<int> _justSealed = <int>{};
  Set<int> get justSealed => _justSealed;

  /// Increments once per seal, and *only* per seal.
  ///
  /// The board used to key the shatter off [flightToken], which is wrong the
  /// moment pours can be chained: draining a queued pour immediately after a
  /// seal bumps the flight counter, the vessel sees a new token, and it breaks
  /// a second time while the first break is still on screen.
  int _sealToken = 0;
  int get sealToken => _sealToken;

  /// Vessel currently refusing a tap, for the shake animation.
  int? _rejected;
  int? get rejected => _rejected;
  int _rejectToken = 0;
  int get rejectToken => _rejectToken;

  SolverHint? _hint;
  SolverHint? get hint => _hint;
  bool _hintPending = false;
  bool get hintPending => _hintPending;

  bool get isStuck => _flight == null && _status == GameStatus.playing && _state.isStuck;

  /// Called when the level is cleared, after the celebration beat has started.
  VoidCallback? onSolved;

  Timer? _flightTimer;
  Timer? _sealTimer;
  Timer? _rejectTimer;

  /// The trailing landing cues of the current pour. Held so a restart or a
  /// dispose mid-run cannot leave plops arriving over a board that has already
  /// moved on.
  final List<Timer> _landCues = <Timer>[];

  /// Duration the board view uses for the flight arc. Held here so the logical
  /// hand-off and the animation can never drift apart.
  ///
  /// 190ms is close to the floor for an arc that still reads as thrown rather
  /// than teleported, and it is the single most load-bearing number in how
  /// fast the game feels: the player cannot start the next pour until this
  /// one lands, so every millisecond here is a millisecond of input latency on
  /// a chain of moves. It was 340.
  static const Duration flightDuration = Duration(milliseconds: 190);

  /// How long the seal bloom gets to itself before the win sheet arrives.
  /// Nothing is blocked during it — it only paces the celebration.
  static const Duration _sealBeat = Duration(milliseconds: 440);

  /// Spacing between the landing cues of successive balls in one pour, so a
  /// four-ball run is heard as a run.
  static const Duration _landStagger = Duration(milliseconds: 42);

  /// What the board should render right now: the true state, minus the balls
  /// still travelling.
  List<List<int>> get visibleTubes {
    final List<List<int>> tubes = _state.toRaw();
    final Pour? f = _flight;
    if (f != null) {
      tubes[f.to].removeRange(tubes[f.to].length - f.count, tubes[f.to].length);
    }
    return tubes;
  }

  // ------------------------------------------------------------------- input

  void tapTube(int i) {
    if (_status == GameStatus.solved) return;
    // A pour is already queued behind the one in the air. Taking a third would
    // mean acting on a board the player cannot see yet.
    if (_queued != null) return;

    _hint = null;

    final int? sel = _selected;
    if (sel == null) {
      _trySelect(i);
      return;
    }

    if (sel == i) {
      _selected = null;
      _audio.tap();
      notifyListeners();
      return;
    }

    if (_state.canPour(sel, i)) {
      if (_flight != null) {
        // Acknowledge now, launch on landing. The stack visibly leaves the
        // source immediately, so the input is confirmed at touch-up even
        // though the arc has to wait its turn.
        _queued = (sel, i);
        _selected = null;
        _audio.lift();
        _haptics.select();
        notifyListeners();
      } else {
        _launch(sel, i);
      }
      return;
    }

    // The tap was not a legal destination. If it *is* a legal source, treat it
    // as the player changing their mind rather than as an error — punishing a
    // reasonable intention is what makes a puzzle game feel hostile.
    if (_canSelect(i)) {
      _selected = i;
      _audio.lift();
      _haptics.select();
      notifyListeners();
      return;
    }

    _reject(i);
  }

  bool _canSelect(int i) => !_state.isEmpty(i) && !_state.isSealed(i);

  void _trySelect(int i) {
    if (!_canSelect(i)) {
      _reject(i);
      return;
    }
    _selected = i;
    _audio.lift();
    _haptics.select();
    notifyListeners();
  }

  void _reject(int i) {
    _rejected = i;
    _rejectToken++;
    _haptics.reject();
    _audio.reject();
    notifyListeners();
    _rejectTimer?.cancel();
    _rejectTimer = Timer(const Duration(milliseconds: 300), () {
      _rejected = null;
      notifyListeners();
    });
  }

  // -------------------------------------------------------------------- pour

  void _launch(int from, int to) {
    final int sealedBefore = _state.sealedCount;
    final (BoardState next, Pour pour) = _state.pour(from, to);
    _state = next;
    _history.add(pour);
    _selected = null;
    _flight = pour;
    _flightToken++;
    _status = GameStatus.resolving;
    notifyListeners();

    _flightTimer?.cancel();
    _flightTimer = Timer(flightDuration, () => _land(pour, sealedBefore));
  }

  void _land(Pour pour, int sealedBefore) {
    _flight = null;
    _lastLandedTube = pour.to;
    _lastLandedCount = pour.count;
    _haptics.land();

    // One cue per ball, spaced to match the staggered settle the board plays.
    _cancelLandCues();
    _audio.land(0);
    for (int j = 1; j < pour.count; j++) {
      _landCues.add(Timer(_landStagger * j, () => _audio.land(j)));
    }

    final int sealedNow = _state.sealedCount;
    if (sealedNow > sealedBefore && _state.isSealed(pour.to)) {
      _justSealed = <int>{pour.to};
      _sealToken++;
      _audio.seal(sealedNow);
      _haptics.seal();
    } else {
      _justSealed = <int>{};
    }

    final bool solved = _state.isSolved;
    _status = solved ? GameStatus.resolving : GameStatus.playing;

    _sealTimer?.cancel();
    if (_justSealed.isNotEmpty || solved) {
      // Let the seal celebration breathe before the win sheet arrives.
      // Stacking the sheet on top of the shatter is what turns a reward into
      // noise.
      _sealTimer = Timer(_sealBeat, () {
        _justSealed = <int>{};
        if (solved) {
          _status = GameStatus.solved;
          _audio.win();
          _haptics.celebrate();
          onSolved?.call();
        }
        notifyListeners();
      });
    }

    // Drain the queue *last*, and launch straight into the next arc rather
    // than notifying first — the board never paints an idle frame between two
    // chained pours. Note this runs even when a vessel just sealed: the seal
    // beat above is already scheduled and plays alongside the next pour. A
    // reward animation must never be something the player has to wait out.
    final (int, int)? next = _queued;
    _queued = null;
    if (next != null && !solved && _state.canPour(next.$1, next.$2)) {
      _launch(next.$1, next.$2);
      return;
    }

    notifyListeners();
  }

  void _cancelLandCues() {
    for (final Timer t in _landCues) {
      t.cancel();
    }
    _landCues.clear();
  }

  // -------------------------------------------------------- undo / restart

  void undo() {
    if (!canUndo) return;
    final Pour p = _history.removeLast();
    _state = _state.unpour(p);
    _selected = null;
    _queued = null;
    _lastLandedTube = -1;
    _lastLandedCount = 0;
    _justSealed = <int>{};
    _hint = null;
    _status = GameStatus.playing;
    _audio.tap();
    _haptics.select();
    notifyListeners();
  }

  void restart() {
    _flightTimer?.cancel();
    _sealTimer?.cancel();
    _cancelLandCues();
    _state = BoardState(level.tubes, level.capacity);
    _history.clear();
    _selected = null;
    _queued = null;
    _flight = null;
    _lastLandedTube = -1;
    _lastLandedCount = 0;
    _justSealed = <int>{};
    _hint = null;
    _status = GameStatus.playing;
    _audio.tap();
    _haptics.select();
    notifyListeners();
  }

  // -------------------------------------------------------------------- hint

  /// Asks the solver for a move on a winning line. Runs off the main isolate;
  /// [hintPending] lets the button show progress instead of freezing.
  Future<bool> requestHint() async {
    if (_hintPending || _flight != null || _queued != null) return false;
    if (_status == GameStatus.solved) return false;
    _hintPending = true;
    _selected = null;
    notifyListeners();

    final SolverHint? h = await Solver.findHint(_state);

    _hintPending = false;
    _hint = h;
    if (h != null) {
      _selected = h.from;
      _audio.lift();
      _haptics.select();
    } else {
      _audio.reject();
    }
    notifyListeners();
    return h != null;
  }

  void clearHint() {
    if (_hint == null) return;
    _hint = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _flightTimer?.cancel();
    _sealTimer?.cancel();
    _rejectTimer?.cancel();
    _cancelLandCues();
    super.dispose();
  }
}
