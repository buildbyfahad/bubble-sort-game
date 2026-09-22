import 'dart:math' as math;

import 'level.dart';
import 'level_catalog.dart';

/// One level per calendar day, the same for everyone.
///
/// Chosen deterministically from the day, so two players comparing notes are
/// talking about the same board — the closest thing to a shared event a game
/// with no server can have. Drawn from the middle of the catalogue: far enough
/// in to be a real puzzle, not so far that a new player is locked out of the
/// one thing that is supposed to bring them back tomorrow.
class DailyChallenge {
  DailyChallenge._();

  static const int reward = 120;

  /// Lowest and highest campaign level a challenge may be drawn from.
  static const int _from = 40;
  static const int _to = 420;

  static Level levelFor(int dayIndex, LevelCatalog catalog) {
    // A fixed multiplier hash rather than Random(seed): the sequence has to be
    // identical on every platform and every Dart version, forever.
    final int h = (dayIndex * 2654435761) & 0x7FFFFFFF;
    final int hi = math.min(_to, catalog.length);
    final int id = _from + (h % (hi - _from + 1));
    return catalog.byId(id);
  }

  /// Ordinary levels only. A challenge that is also a precision level or a
  /// finale would be two rule changes at once.
  static Level levelForNormal(int dayIndex, LevelCatalog catalog) {
    Level l = levelFor(dayIndex, catalog);
    int step = 0;
    while (l.mode != LevelMode.normal && step < 20) {
      step++;
      l = catalog.byId(math.min(catalog.length, l.id + step));
    }
    return l;
  }
}
