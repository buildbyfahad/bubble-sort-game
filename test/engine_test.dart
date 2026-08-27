import 'package:bubble_sort/data/level.dart';
import 'package:bubble_sort/data/level_catalog.dart';
import 'package:bubble_sort/design/tokens.dart';
import 'package:bubble_sort/engine/board_state.dart';
import 'package:bubble_sort/engine/solver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_harness.dart';

/// Rules and content checks. These run headlessly because the engine has no
/// dependency on Flutter's widget layer — which is most of the reason it is
/// worth keeping the two apart.
void main() {
  group('BoardState', () {
    test('a pour moves the whole matching run that fits', () {
      final BoardState s = BoardState(<List<int>>[
        <int>[0, 1, 1, 1],
        <int>[1],
      ], 4);
      final (BoardState next, Pour p) = s.pour(0, 1);
      expect(p.count, 3);
      expect(p.hue, 1);
      expect(next.tubes[0], <int>[0]);
      expect(next.tubes[1], <int>[1, 1, 1, 1]);
    });

    test('a pour is capped by the destination\'s remaining room', () {
      final BoardState s = BoardState(<List<int>>[
        <int>[1, 1, 1, 1],
        <int>[1, 1],
      ], 4);
      // Source is sealed, so it cannot be poured from at all.
      expect(s.canPour(0, 1), isFalse);

      final BoardState t = BoardState(<List<int>>[
        <int>[0, 1, 1, 1],
        <int>[1, 1],
      ], 4);
      final (BoardState next, Pour p) = t.pour(0, 1);
      expect(p.count, 2);
      expect(next.tubes[0], <int>[0, 1]);
    });

    test('sealed vessels are locked and single-hue stacks cannot be re-parked', () {
      final BoardState s = BoardState(<List<int>>[
        <int>[2, 2, 2, 2], // sealed
        <int>[3, 3], // pure but unfinished
        <int>[],
      ], 4);
      expect(s.canPour(0, 2), isFalse, reason: 'sealed source');
      expect(s.canPour(1, 2), isFalse, reason: 'pure stack into empty achieves nothing');
    });

    test('unpour is an exact inverse of pour', () {
      final BoardState s = BoardState(<List<int>>[
        <int>[0, 1, 1],
        <int>[1],
        <int>[2, 0],
      ], 4);
      final (BoardState next, Pour p) = s.pour(0, 1);
      expect(next.unpour(p).tubes, s.tubes);
    });

    test('isStuck is true only when no legal pour remains', () {
      final BoardState open = BoardState(<List<int>>[
        <int>[0, 1],
        <int>[1],
      ], 4);
      expect(open.isStuck, isFalse);

      final BoardState dead = BoardState(<List<int>>[
        <int>[0, 1, 2, 3],
        <int>[1, 2, 3, 0],
      ], 4);
      expect(dead.isStuck, isTrue);
    });

    test('a board of sealed vessels is solved', () {
      expect(
        BoardState(<List<int>>[
          <int>[0, 0, 0, 0],
          <int>[],
          <int>[1, 1, 1, 1],
        ], 4).isSolved,
        isTrue,
      );
    });
  });

  group('level catalogue', () {
    late LevelCatalog catalog;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      catalog = loadCatalog();
    });

    test('holds a full thousand levels across contiguous chapters', () {
      expect(catalog.length, 1000);
      expect(catalog.chapters, isNotEmpty);

      int expectedNext = 1;
      for (final Chapter c in catalog.chapters) {
        expect(c.from, expectedNext, reason: 'chapter ${c.number} does not follow the last');
        expect(c.to, greaterThanOrEqualTo(c.from));
        expect(c.name, isNotEmpty);
        expectedNext = c.to + 1;
      }
      expect(expectedNext - 1, catalog.length, reason: 'chapters must cover every level');
    });

    test('every level is well formed', () {
      for (final Level l in catalog.levels) {
        expect(l.tubes.length, l.colorCount + l.emptyTubes,
            reason: 'level ${l.id} has the wrong vessel count');

        // Each hue must appear exactly `capacity` times, or the board is
        // unsolvable by construction.
        final Map<int, int> counts = <int, int>{};
        for (final List<int> t in l.tubes) {
          expect(t.length, anyOf(0, l.capacity), reason: 'level ${l.id} has a ragged vessel');
          for (final int c in t) {
            counts[c] = (counts[c] ?? 0) + 1;
          }
        }
        expect(counts.length, l.colorCount, reason: 'level ${l.id} hue count');
        for (final int c in counts.values) {
          expect(c, l.capacity, reason: 'level ${l.id} has an uneven hue');
        }
        expect(BoardState(l.tubes, l.capacity).isSolved, isFalse,
            reason: 'level ${l.id} starts already solved');
      }
    });

    test('no level needs more hues than the palette provides', () {
      for (final Level l in catalog.levels) {
        for (final List<int> t in l.tubes) {
          for (final int c in t) {
            expect(c, lessThan(DS.hues.length),
                reason: 'level ${l.id} references hue $c, beyond the palette');
          }
        }
      }
    });

    test('difficulty rises inside every chapter', () {
      for (final Chapter c in catalog.chapters) {
        final List<Level> inChapter = catalog.levelsIn(c).toList();
        for (int i = 1; i < inChapter.length; i++) {
          final Level prev = inChapter[i - 1];
          final Level cur = inChapter[i];
          expect(cur.colorCount, greaterThanOrEqualTo(prev.colorCount),
              reason: 'level ${cur.id} uses fewer hues than the one before it');
          if (cur.colorCount == prev.colorCount) {
            expect(cur.par, greaterThanOrEqualTo(prev.par),
                reason: 'level ${cur.id} is easier than the one before it');
          }
        }
      }
    });

    test("par never undercuts the board's own lower bound", () {
      // A pour can merge at most one run away, and the goal holds exactly one
      // run per hue - so `runs - hues` is a floor on the pours required. A par
      // below it would mean the generator recorded something impossible.
      for (final Level l in catalog.levels) {
        int runs = 0;
        for (final List<int> t in l.tubes) {
          if (t.isEmpty) continue;
          runs++;
          for (int i = 1; i < t.length; i++) {
            if (t[i] != t[i - 1]) runs++;
          }
        }
        expect(l.par, greaterThanOrEqualTo(runs - l.colorCount),
            reason: 'level ${l.id} claims a par below what is possible');
      }
    });

    test('the first levels stay gentle enough to learn on', () {
      expect(catalog.byId(1).colorCount, lessThanOrEqualTo(2));
      expect(catalog.byId(1).par, lessThanOrEqualTo(4));
      for (int i = 1; i <= 10; i++) {
        expect(catalog.byId(i).colorCount, lessThanOrEqualTo(4),
            reason: 'level $i is too busy for the opening run');
      }
    });

    test('the runtime solver finishes a sample spanning the whole catalogue', () {
      // Every fortieth level, so each chapter is represented. Running all 1000
      // through the solver would dominate the suite for little extra signal.
      for (int id = 1; id <= catalog.length; id += 40) {
        final Level l = catalog.byId(id);
        final SolverHint? h = Solver.solve(SolverRequest(l.tubes, l.capacity));
        expect(h, isNotNull, reason: 'level $id defeated the hint solver');
        expect(BoardState(l.tubes, l.capacity).canPour(h!.from, h.to), isTrue,
            reason: 'level $id got an illegal hint');
      }
    });

    test('following the solver to the end actually solves a hard level', () {
      final Level l = catalog.byId(catalog.length);
      BoardState s = BoardState(l.tubes, l.capacity);
      int guard = 0;
      while (!s.isSolved && guard++ < 400) {
        final SolverHint? h = Solver.solve(SolverRequest(s.toRaw(), s.capacity));
        expect(h, isNotNull, reason: 'solver gave up at move $guard');
        s = s.pour(h!.from, h.to).$1;
      }
      expect(s.isSolved, isTrue);
    });
  });
}
