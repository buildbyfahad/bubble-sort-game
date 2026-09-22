import 'package:flutter/foundation.dart';

/// What kind of level this is. Ordinary levels are the campaign; the other
/// two change the rules rather than just the board.
enum LevelMode {
  /// The default. No budget, nothing concealed unless [Level.hiddenVessels]
  /// says so.
  normal,

  /// A hard pour budget. Every pour counts, including ones later undone, and
  /// exceeding the budget fails the board. Undo is still allowed — it just no
  /// longer refunds the pour, which turns it from a safety net into a choice.
  precision,

  /// The chapter finale: one more colour than the rest of the chapter, its
  /// own completion cue, and a cosmetic reward.
  boss,
}

/// Pure level data - no Flutter widgets, no colours, no layout.
///
/// Levels are content, not code. Keeping them behind this plain model is what
/// lets the catalogue hold a thousand entries (and be regenerated wholesale)
/// without a single change to the game or UI layer.
@immutable
class Level {
  const Level({
    required this.id,
    required this.chapter,
    required this.capacity,
    required this.colorCount,
    required this.emptyTubes,
    required this.par,
    required this.parIsOptimal,
    required this.tubes,
    this.mode = LevelMode.normal,
    this.hiddenVessels = 0,
    this.traits = const <int>[],
  });

  /// Decodes one entry of `assets/levels/levels.json`.
  ///
  /// Keys are single characters and vessel contents are a base-36 string
  /// ("0012,2201,,"), which keeps a thousand levels down to ~100 KB. The cost
  /// is that this is the only place in the app allowed to know that encoding.
  factory Level.fromJson(Map<String, dynamic> json) {
    final int capacity = json['k'] as int;
    final List<List<int>> tubes = (json['t'] as String)
        .split(',')
        .map((String tube) =>
            tube.split('').map((String c) => int.parse(c, radix: 36)).toList())
        .toList();

    // Per-vessel obstacle, one character each: '.' plain, 'n' narrow neck,
    // a base-36 digit for a colour lock. Absent means a board with none.
    final String? v = json['v'] as String?;
    final List<int> traits = <int>[
      for (int i = 0; i < tubes.length; i++)
        if (v == null || i >= v.length)
          0
        else if (v[i] == 'n')
          1 // narrow
        else if (v[i] == '.')
          0
        else
          (int.parse(v[i], radix: 36) + 1) << 1, // colour lock
    ];

    return Level(
      id: json['i'] as int,
      chapter: json['ch'] as int,
      capacity: capacity,
      colorCount: json['c'] as int,
      emptyTubes: json['e'] as int,
      par: json['p'] as int,
      parIsOptimal: (json['x'] as int) == 1,
      mode: LevelMode.values[(json['m'] as int?) ?? 0],
      hiddenVessels: (json['h'] as int?) ?? 0,
      traits: traits,
      tubes: tubes,
    );
  }

  final int id;

  /// 1-based chapter this level belongs to.
  final int chapter;

  /// Balls per vessel.
  final int capacity;

  /// How many distinct hues appear. Also the number of filled vessels.
  final int colorCount;

  /// Spare vessels provided as working space.
  final int emptyTubes;

  /// The shortest solution the generator found. Used to rate the player's
  /// result, never to gate progress.
  final int par;

  /// True when [par] was proven optimal by exhaustive search rather than found
  /// by a beam search. The distinction never reaches the player, but it keeps
  /// the catalogue honest about which numbers are guarantees.
  final bool parIsOptimal;

  /// Bottom-up contents. `tubes[t][0]` is the ball resting on the base.
  /// Values index into the shared hue palette.
  final List<List<int>> tubes;

  final LevelMode mode;

  /// How many of the filled vessels (the first ones, since the catalogue
  /// orders vessels filled-first) start with everything below their top ball
  /// concealed. Zero for an ordinary level.
  final int hiddenVessels;

  /// Packed per-vessel obstacles; see `BoardState.traits`. Empty when the
  /// board has none, which is most of them.
  final List<int> traits;

  int get tubeCount => tubes.length;

  bool get isBoss => mode == LevelMode.boss;
  bool get isPrecision => mode == LevelMode.precision;
  bool get hasHiddenBalls => hiddenVessels > 0;
  bool get hasNarrow => traits.any((int t) => (t & 1) != 0);
  bool get hasColourLock => traits.any((int t) => (t >> 1) != 0);
  bool get hasObstacles => traits.any((int t) => t != 0);

  /// The pour budget on a precision level. Par plus a little slack: par on a
  /// beam-found board is close to optimal, and demanding it exactly would make
  /// the mode a memory test of the solver's line rather than a puzzle.
  int get pourBudget => par + 2;
}

/// A named run of levels. Chapters exist so a thousand-level list has somewhere
/// to breathe - both in the level picker and in the player's head.
@immutable
class Chapter {
  const Chapter({
    required this.number,
    required this.name,
    required this.from,
    required this.to,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        number: json['n'] as int,
        name: json['name'] as String,
        from: json['from'] as int,
        to: json['to'] as int,
      );

  final int number;
  final String name;

  /// Inclusive level id range.
  final int from;
  final int to;

  int get length => to - from + 1;

  bool contains(int levelId) => levelId >= from && levelId <= to;
}
