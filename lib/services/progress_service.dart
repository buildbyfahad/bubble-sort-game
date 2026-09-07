import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted progress: which levels are cleared and in how many pours.
///
/// Coins, hints and the daily streak live in [WalletService] instead. The
/// split is between what the player has *done* and what they *have* — the
/// second set is the reward loop and changes far more often than the rules of
/// play, and letting the two share a service means every tweak to the economy
/// reaches into the record of the game.
///
/// Kept separate from the game engine so a level can be played, replayed or
/// previewed without touching saved state until the player actually wins.
///
/// Cleared levels are held in memory as a set, and the two figures the UI reads
/// constantly - how many are cleared, and which level is next - are maintained
/// incrementally. The obvious implementation walks all levels on every call;
/// that is invisible at ten levels and a scan of a thousand on every rebuild of
/// the menu at this size.
class ProgressService extends ChangeNotifier {
  ProgressService._(this._prefs, this._totalLevels) {
    for (int i = 1; i <= _totalLevels; i++) {
      if (_prefs.containsKey('$_kBest$i')) _cleared.add(i);
    }
    _recomputeCurrent();
  }

  static const String _kBest = 'progress.best.';
  static const String _kSeenTutorial = 'progress.seenTutorial';

  final SharedPreferences _prefs;
  final int _totalLevels;

  final Set<int> _cleared = <int>{};
  int _currentLevelId = 1;

  static Future<ProgressService> load(int totalLevels) async =>
      ProgressService._(await SharedPreferences.getInstance(), totalLevels);

  /// Best (lowest) pour count recorded for a level, or null if never cleared.
  int? bestFor(int levelId) => _prefs.getInt('$_kBest$levelId');

  bool isCleared(int levelId) => _cleared.contains(levelId);

  int get clearedCount => _cleared.length;

  int get totalLevels => _totalLevels;

  /// The level the PLAY button should drop the player into: the first one they
  /// have not cleared, falling back to the last level once everything is done.
  int get currentLevelId => _currentLevelId;

  /// A level is playable once the one before it is cleared.
  bool isUnlocked(int levelId) => levelId == 1 || isCleared(levelId - 1);

  double get completion => _totalLevels == 0 ? 0 : _cleared.length / _totalLevels;

  /// Cleared levels within an inclusive id range - used for per-chapter counts.
  int clearedBetween(int from, int to) {
    int n = 0;
    for (int i = from; i <= to; i++) {
      if (_cleared.contains(i)) n++;
    }
    return n;
  }

  bool get seenTutorial => _prefs.getBool(_kSeenTutorial) ?? false;

  Future<void> markTutorialSeen() async {
    await _prefs.setBool(_kSeenTutorial, true);
    notifyListeners();
  }

  /// Records a clear. Returns true when this beat a previous best, so the UI
  /// can call it out.
  Future<bool> recordClear(int levelId, int moves) async {
    final int? prev = bestFor(levelId);
    final bool improved = prev != null && moves < prev;
    if (prev == null || moves < prev) {
      await _prefs.setInt('$_kBest$levelId', moves);
    }
    if (_cleared.add(levelId)) _recomputeCurrent();
    notifyListeners();
    return improved;
  }

  Future<void> resetAll() async {
    for (final int i in _cleared) {
      await _prefs.remove('$_kBest$i');
    }
    _cleared.clear();
    await _prefs.remove(_kSeenTutorial);
    _currentLevelId = 1;
    notifyListeners();
  }

  /// Walks forward from the current position rather than from level 1. Clearing
  /// happens in order almost always, so this is a step or two of work.
  void _recomputeCurrent() {
    int i = _currentLevelId;
    while (i < _totalLevels && _cleared.contains(i)) {
      i++;
    }
    // Replaying an earlier level must not drag the marker backwards, and a
    // fully cleared catalogue parks on the last level.
    _currentLevelId = i.clamp(1, _totalLevels);
  }
}
