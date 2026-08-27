import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'level.dart';

/// The level catalogue, loaded once from `assets/levels/levels.json`.
///
/// Levels used to be a `const` list in Dart source. That stops being the right
/// shape somewhere in the low hundreds: a thousand entries would be ~8000 lines
/// of generated code compiled into the binary, reviewed on every diff, and
/// impossible to regenerate without touching source control. As an asset it is
/// ~100 KB of data, parsed once at boot in a few milliseconds, and swapping in
/// a new catalogue is a file copy.
///
/// Decoding happens on a background isolate, so a thousand levels never costs a
/// frame on the splash screen.
class LevelCatalog {
  const LevelCatalog._(this.levels, this.chapters);

  static const String assetPath = 'assets/levels/levels.json';

  final List<Level> levels;
  final List<Chapter> chapters;

  int get length => levels.length;

  /// Levels are 1-based and stored in order, so this is a direct index.
  Level byId(int id) {
    assert(id >= 1 && id <= levels.length, 'level $id is out of range');
    return levels[id - 1];
  }

  Chapter chapterOf(int levelId) => chapters[byId(levelId).chapter - 1];

  Chapter chapterByNumber(int number) => chapters[number - 1];

  /// Levels belonging to [chapter], as a view over the shared list.
  Iterable<Level> levelsIn(Chapter chapter) =>
      levels.getRange(chapter.from - 1, chapter.to);

  static Future<LevelCatalog> load() async {
    final String raw = await rootBundle.loadString(assetPath);
    return compute(_parse, raw);
  }

  /// Runs on a worker isolate - must stay a top-level/static function.
  static LevelCatalog _parse(String raw) {
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    final List<Level> levels = <Level>[
      for (final dynamic e in json['levels'] as List<dynamic>)
        Level.fromJson(e as Map<String, dynamic>),
    ];
    final List<Chapter> chapters = <Chapter>[
      for (final dynamic e in json['chapters'] as List<dynamic>)
        Chapter.fromJson(e as Map<String, dynamic>),
    ];

    assert(() {
      for (int i = 0; i < levels.length; i++) {
        if (levels[i].id != i + 1) {
          throw StateError('level ids must be contiguous and 1-based');
        }
      }
      return true;
    }());

    return LevelCatalog._(
      List<Level>.unmodifiable(levels),
      List<Chapter>.unmodifiable(chapters),
    );
  }

  /// For tests that need a catalogue without touching the asset bundle.
  @visibleForTesting
  static LevelCatalog fromRaw(String raw) => _parse(raw);
}
