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
  BoardState(List<List<int>> tubes, this.capacity)
      : tubes = List<List<int>>.unmodifiable(
          tubes.map((List<int> t) => List<int>.unmodifiable(t)),
        );

  /// Bottom-up contents per vessel; values are hue indices.
  final List<List<int>> tubes;
  final int capacity;

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
    if (tubes[to].isEmpty) {
      // Moving a single-hue stack into an empty vessel achieves nothing and
      // only pads the move counter, so the rules forbid it outright.
      return !isPure(from);
    }
    return tubes[to].last == tubes[from].last;
  }

  /// Applies a pour that [canPour] has already approved.
  (BoardState, Pour) pour(int from, int to) {
    assert(canPour(from, to));
    final List<List<int>> next = _mutableCopy();
    final int hue = next[from].last;
    final int room = capacity - next[to].length;
    int moved = 0;
    while (next[from].isNotEmpty && next[from].last == hue && moved < room) {
      next[to].add(next[from].removeLast());
      moved++;
    }
    return (
      BoardState(next, capacity),
      Pour(from: from, to: to, count: moved, hue: hue),
    );
  }

  /// Exact inverse of [pour], used by undo.
  BoardState unpour(Pour p) {
    final List<List<int>> next = _mutableCopy();
    for (int k = 0; k < p.count; k++) {
      next[p.from].add(next[p.to].removeLast());
    }
    return BoardState(next, capacity);
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
  String canonicalKey() {
    final List<String> parts =
        tubes.map((List<int> t) => t.join(',')).toList(growable: false)..sort();
    return parts.join('|');
  }

  /// Flat, isolate-friendly representation for the solver.
  List<List<int>> toRaw() => _mutableCopy();
}
