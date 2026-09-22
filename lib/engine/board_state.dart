import 'package:flutter/foundation.dart';

/// A single pour, recorded so it can be animated and undone exactly.
@immutable
class Pour {
  const Pour({
    required this.from,
    required this.to,
    required this.count,
    required this.hue,
  });

  final int from;
  final int to;

  /// How many identically-coloured balls travelled. A pour always moves the
  /// whole matching run that fits, never a single ball — that is what makes
  /// the game feel decisive instead of fiddly.
  final int count;

  final int hue;
}

/// The rules of the game, and nothing else.
///
/// Deliberately free of Flutter, colours, timing and layout: this class can be
/// unit-tested, run inside a solver isolate, or replayed headlessly. Every
/// operation returns a new [BoardState]; nothing mutates in place, which is
/// what makes undo a one-liner and animation state easy to reason about.
@immutable
class BoardState {
  BoardState(
    List<List<int>> tubes,
    this.capacity, {
    List<int>? hiddenBelow,
    List<int>? traits,
  })  : tubes = List<List<int>>.unmodifiable(
          tubes.map((List<int> t) => List<int>.unmodifiable(t)),
        ),
        hiddenBelow = List<int>.unmodifiable(
          hiddenBelow ?? List<int>.filled(tubes.length, 0),
        ),
        // Normalised to one entry per vessel rather than taken as given.
        // A board with no obstacles carries an *empty* trait list — that is
        // the common case and the cheapest thing to store — so indexing the
        // caller's list directly would range-error on every ordinary level.
        traits = List<int>.unmodifiable(<int>[
          for (int i = 0; i < tubes.length; i++)
            (traits != null && i < traits.length) ? traits[i] : 0,
        ]);

  /// A board with the first [hiddenVessels] vessels concealed below the top.
  factory BoardState.withHidden(
    List<List<int>> tubes,
    int capacity,
    int hiddenVessels, {
    List<int>? traits,
  }) {
    final List<int> hidden = List<int>.filled(tubes.length, 0);
    for (int i = 0; i < hiddenVessels && i < tubes.length; i++) {
      // Everything but the ball at the mouth. A vessel with one ball hides
      // nothing.
      hidden[i] = tubes[i].isEmpty ? 0 : tubes[i].length - 1;
    }
    return BoardState(tubes, capacity, hiddenBelow: hidden, traits: traits);
  }

  /// Bottom-up contents per vessel; values are hue indices.
  final List<List<int>> tubes;
  final int capacity;

  /// Per vessel, how many balls counted from the *base* are still concealed.
  ///
  /// Concealment is a rendering fact, not a rules fact: the rules always see
  /// the true contents, and so does the solver. It is kept here rather than
  /// in the widget layer because it has to survive every pour — and the only
  /// thing that knows a pour happened is this class.
  ///
  /// It only ever decreases. A ball can only leave a vessel from the top, so
  /// hidden balls stay at the bottom and are revealed as the balls above them
  /// go. Undo does not re-hide: what the player has seen, they have seen.
  final List<int> hiddenBelow;

  /// Whether the ball at [slot] (0 = base) of vessel [i] is concealed.
  bool isHidden(int i, int slot) => slot < hiddenBelow[i];

  bool get hasHidden => hiddenBelow.any((int n) => n > 0);

  /// Per-vessel obstacle, packed into one int so it crosses the isolate
  /// boundary as plain data.
  ///
  ///   bit 0      narrow neck — pours one ball at a time, not a whole run
  ///   bits 1..   colour lock, as `hue + 1`; zero means unlocked
  ///
  /// Packed rather than held as two lists because the solver keys on it on
  /// its hot path, and an int compares and concatenates far more cheaply than
  /// a pair of nullable fields.
  final List<int> traits;

  static int packTrait({bool narrow = false, int? lockedHue}) =>
      (narrow ? 1 : 0) | ((lockedHue == null ? 0 : lockedHue + 1) << 1);

  static bool traitNarrow(int t) => (t & 1) != 0;
  static int? traitLockedHue(int t) => (t >> 1) == 0 ? null : (t >> 1) - 1;

  /// This vessel empties one ball at a time.
  bool isNarrow(int i) => traitNarrow(traits[i]);

  /// The only hue this vessel will accept, or null.
  int? lockedHue(int i) => traitLockedHue(traits[i]);

  bool get hasObstacles => traits.any((int t) => t != 0);

  int get tubeCount => tubes.length;

  List<List<int>> _mutableCopy() =>
      tubes.map((List<int> t) => List<int>.of(t)).toList(growable: false);

  bool isEmpty(int i) => tubes[i].isEmpty;
  bool isFull(int i) => tubes[i].length == capacity;

  /// The hue sitting at the mouth of the vessel, or null if it is empty.
  int? topHue(int i) => tubes[i].isEmpty ? null : tubes[i].last;

  /// Length of the run of identical hues at the mouth.
  int topRun(int i) {
    final List<int> t = tubes[i];
    if (t.isEmpty) return 0;
    final int c = t.last;
    int n = 0;
    for (int k = t.length - 1; k >= 0 && t[k] == c; k--) {
      n++;
    }
    return n;
  }

  /// A vessel is *sealed* once it holds a full set of one hue. Sealed vessels
  /// are locked: the player cannot pour out of them, which removes a whole
  /// class of accidental self-sabotage.
  bool isSealed(int i) {
    final List<int> t = tubes[i];
    return t.length == capacity && t.every((int c) => c == t.first);
  }

  /// True when a vessel holds a single hue but is not yet full — used only for
  /// subtle visual feedback, never for rules.
  bool isPure(int i) {
    final List<int> t = tubes[i];
    return t.isNotEmpty && t.every((int c) => c == t.first);
  }

  bool get isSolved {
    for (int i = 0; i < tubes.length; i++) {
      if (tubes[i].isEmpty) continue;
      if (!isSealed(i)) return false;
    }
    return true;
  }

  bool canPour(int from, int to) {
    if (from == to) return false;
    if (tubes[from].isEmpty) return false;
    if (isSealed(from)) return false;
    if (isFull(to)) return false;

    final int hue = tubes[from].last;

    // A colour-locked vessel takes one hue and nothing else, ever.
    final int? lock = lockedHue(to);
    if (lock != null && lock != hue) return false;

    if (tubes[to].isEmpty) {
      // Moving a single-hue stack into an empty vessel achieves nothing and
      // only pads the move counter, so the rules forbid it outright — unless
      // the destination is locked to that hue, in which case it is the only
      // place the colour can ever be sealed and the move is the whole point.
      return !isPure(from) || lock == hue;
    }
    return tubes[to].last == hue;
  }

  /// Applies a pour that [canPour] has already approved.
  (BoardState, Pour) pour(int from, int to) {
    assert(canPour(from, to));
    final List<List<int>> next = _mutableCopy();
    final int hue = next[from].last;
    // A narrow neck lets exactly one ball past, however long the run is. This
    // is the whole obstacle: it does not forbid anything, it makes the move
    // the player has stopped thinking about cost three times as much.
    final int room = isNarrow(from) ? 1 : capacity - next[to].length;
    int moved = 0;
    while (next[from].isNotEmpty && next[from].last == hue && moved < room) {
      next[to].add(next[from].removeLast());
      moved++;
    }
    // Whatever is now at the mouth of the source has been seen.
    final List<int> hidden = List<int>.of(hiddenBelow);
    final int remaining = next[from].length;
    if (hidden[from] > remaining - 1) hidden[from] = remaining > 0 ? remaining - 1 : 0;

    return (
      BoardState(next, capacity, hiddenBelow: hidden, traits: traits),
      Pour(from: from, to: to, count: moved, hue: hue),
    );
  }

  /// Exact inverse of [pour], used by undo.
  BoardState unpour(Pour p) {
    final List<List<int>> next = _mutableCopy();
    for (int k = 0; k < p.count; k++) {
      next[p.from].add(next[p.to].removeLast());
    }
    // Concealment carries over unchanged — see [hiddenBelow].
    return BoardState(next, capacity, hiddenBelow: hiddenBelow, traits: traits);
  }

  /// True when no legal pour exists — a dead end the player can only leave via
  /// undo or restart.
  bool get isStuck {
    if (isSolved) return false;
    for (int i = 0; i < tubes.length; i++) {
      for (int j = 0; j < tubes.length; j++) {
        if (canPour(i, j)) return false;
      }
    }
    return true;
  }

  int get sealedCount {
    int n = 0;
    for (int i = 0; i < tubes.length; i++) {
      if (isSealed(i)) n++;
    }
    return n;
  }

  /// Order-independent identity, so two boards that differ only by which
  /// vessel holds which stack collapse to one search node.
  ///
  /// Each vessel's trait is folded in *before* the sort. Without that, two
  /// boards where a stack sits in a plain vessel and in a narrow one would
  /// collapse to the same node — and the search would answer a question the
  /// player was not asked.
  String canonicalKey() {
    final List<String> parts = <String>[
      for (int i = 0; i < tubes.length; i++) '${traits[i]}:${tubes[i].join(',')}',
    ]..sort();
    return parts.join('|');
  }

  /// Flat, isolate-friendly representation for the solver.
  List<List<int>> toRaw() => _mutableCopy();
}
