import 'package:flutter/foundation.dart';

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

    return Level(
      id: json['i'] as int,
      chapter: json['ch'] as int,
      capacity: capacity,
      colorCount: json['c'] as int,
      emptyTubes: json['e'] as int,
      par: json['p'] as int,
      parIsOptimal: (json['x'] as int) == 1,
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

  int get tubeCount => tubes.length;
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
