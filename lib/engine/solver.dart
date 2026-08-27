import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'board_state.dart';

/// Payload for the isolate hop — plain data only.
@immutable
class SolverRequest {
  const SolverRequest(this.tubes, this.capacity);
  final List<List<int>> tubes;
  final int capacity;
}

/// The first move of a winning line, plus how long that line is.
@immutable
class SolverHint {
  const SolverHint({required this.from, required this.to, required this.remaining});
  final int from;
  final int to;

  /// Pours still required after this one. Lets the UI say something honest
  /// ("3 moves left") rather than a generic nudge.
  final int remaining;
}

/// Greedy best-first search over pour-groups.
///
/// Optimal search (BFS) is used offline in `tools/gen_levels.js` to compute
/// each level's par; at runtime we only need *a* winning line, fast, so this
/// trades optimality for a bounded node count that never blocks a frame.
/// It always runs on a background isolate via [findHint].
class Solver {
  Solver._();

  /// Distance-to-goal estimate: how much sorting work is left. Counts, per
  /// vessel, the balls sitting above a colour change — those are exactly the
  /// balls that must move at least once.
  static int _heuristic(List<List<int>> tubes, int capacity) {
    int h = 0;
    for (final List<int> t in tubes) {
      if (t.isEmpty) continue;
      bool broken = false;
      for (int i = 1; i < t.length; i++) {
        if (t[i] != t[i - 1]) broken = true;
        if (broken) h++;
      }
      if (!broken && t.length < capacity) h++; // pure but unfinished
    }
    return h;
  }

  static bool _solved(List<List<int>> tubes, int capacity) {
    for (final List<int> t in tubes) {
      if (t.isEmpty) continue;
      if (t.length != capacity) return false;
      for (final int c in t) {
        if (c != t.first) return false;
      }
    }
    return true;
  }

  static String _key(List<List<int>> tubes) {
    final List<String> parts = tubes.map((List<int> t) => t.join(',')).toList()..sort();
    return parts.join('|');
  }

  static List<List<int>> _legalMoves(List<List<int>> tubes, int capacity) {
    final List<List<int>> out = <List<int>>[];
    for (int i = 0; i < tubes.length; i++) {
      final List<int> from = tubes[i];
      if (from.isEmpty) continue;
      final int c = from.last;
      bool pure = true;
      for (final int x in from) {
        if (x != c) {
          pure = false;
          break;
        }
      }
      if (pure && from.length == capacity) continue; // sealed
      for (int j = 0; j < tubes.length; j++) {
        if (i == j) continue;
        final List<int> to = tubes[j];
        if (to.length == capacity) continue;
        if (to.isEmpty) {
          if (pure) continue;
          out.add(<int>[i, j]);
        } else if (to.last == c) {
          out.add(<int>[i, j]);
        }
      }
    }
    return out;
  }

  static List<List<int>> _apply(List<List<int>> tubes, int from, int to, int capacity) {
    final List<List<int>> n = tubes.map((List<int> t) => List<int>.of(t)).toList();
    final int c = n[from].last;
    int room = capacity - n[to].length;
    while (n[from].isNotEmpty && n[from].last == c && room > 0) {
      n[to].add(n[from].removeLast());
      room--;
    }
    return n;
  }

  static const int _nodeCap = 120000;

  /// Runs on a background isolate. Returns null if no line was found inside
  /// the node budget (which, for a solvable board of this size, effectively
  /// means the player has reached a dead end).
  static SolverHint? solve(SolverRequest req) {
    final List<List<int>> start = req.tubes.map((List<int> t) => List<int>.of(t)).toList();
    final int cap = req.capacity;
    if (_solved(start, cap)) return null;

    // Node id -> (parent id, first-move from, first-move to, depth).
    final List<List<List<int>>> states = <List<List<int>>>[start];
    final List<int> firstFrom = <int>[-1];
    final List<int> firstTo = <int>[-1];
    final List<int> depth = <int>[0];

    final HashSet<String> seen = HashSet<String>()..add(_key(start));

    // Priority queue keyed by f = depth + 2*heuristic. Weighting the heuristic
    // makes the search dive for a solution rather than sweep for the shortest
    // one — the right trade for a hint.
    final PriorityQueue queue = PriorityQueue()..push(_heuristic(start, cap) * 2, 0);

    int expanded = 0;
    while (!queue.isEmpty && expanded < _nodeCap) {
      final int id = queue.pop();
      expanded++;
      final List<List<int>> cur = states[id];

      for (final List<int> m in _legalMoves(cur, cap)) {
        final List<List<int>> next = _apply(cur, m[0], m[1], cap);
        final String k = _key(next);
        if (!seen.add(k)) continue;

        final int childId = states.length;
        states.add(next);
        depth.add(depth[id] + 1);
        // Propagate the root's first move down every branch, so a solved leaf
        // immediately names the move to play now.
        firstFrom.add(id == 0 ? m[0] : firstFrom[id]);
        firstTo.add(id == 0 ? m[1] : firstTo[id]);

        if (_solved(next, cap)) {
          return SolverHint(
            from: firstFrom[childId],
            to: firstTo[childId],
            remaining: depth[childId] - 1,
          );
        }
        queue.push(depth[childId] + _heuristic(next, cap) * 2, childId);
      }
    }
    return null;
  }

  /// Convenience wrapper — hands the search to a worker isolate so the hint
  /// button never costs a dropped frame.
  static Future<SolverHint?> findHint(BoardState state) {
    return compute<SolverRequest, SolverHint?>(
      solve,
      SolverRequest(state.toRaw(), state.capacity),
    );
  }
}

/// Minimal binary min-heap. Written out rather than pulled in as a dependency
/// because it is twenty lines and lives on the hot path of the search.
class PriorityQueue {
  final List<int> _priority = <int>[];
  final List<int> _value = <int>[];

  bool get isEmpty => _value.isEmpty;

  void push(int priority, int value) {
    _priority.add(priority);
    _value.add(value);
    int i = _value.length - 1;
    while (i > 0) {
      final int parent = (i - 1) >> 1;
      if (_priority[parent] <= _priority[i]) break;
      _swap(parent, i);
      i = parent;
    }
  }

  int pop() {
    final int top = _value.first;
    final int last = _value.length - 1;
    _swap(0, last);
    _priority.removeLast();
    _value.removeLast();
    int i = 0;
    while (true) {
      final int l = i * 2 + 1;
      final int r = l + 1;
      int smallest = i;
      if (l < _value.length && _priority[l] < _priority[smallest]) smallest = l;
      if (r < _value.length && _priority[r] < _priority[smallest]) smallest = r;
      if (smallest == i) break;
      _swap(i, smallest);
      i = smallest;
    }
    return top;
  }

  void _swap(int a, int b) {
    final int p = _priority[a];
    _priority[a] = _priority[b];
    _priority[b] = p;
    final int v = _value[a];
    _value[a] = _value[b];
    _value[b] = v;
  }
}
