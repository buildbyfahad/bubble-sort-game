import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the interaction vocabulary.
///
/// Feedback used to be attached at call sites, and the result was exactly what
/// play-testing reported: the same control made a noise on one screen and none
/// on the next. An audit found `buttons.dart` with twenty-eight tap handlers
/// and zero cues.
///
/// The rule is now that *components* fire feedback, through `Fx`. These tests
/// enforce that rule against the source, because it is a rule about where code
/// lives and no runtime assertion can catch it being broken.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('every interactive component fires its own feedback', () {
    const Map<String, int> expected = <String, int>{
      // primary, ghost, dock (tap + refuse), text action
      'lib/ui/widgets/buttons.dart': 5,
      'lib/ui/widgets/switch.dart': 1,
    };
    for (final MapEntry<String, int> e in expected.entries) {
      final int found = 'Fx.'.allMatches(read(e.key)).length;
      expect(found, greaterThanOrEqualTo(e.value),
          reason: '${e.key} should fire feedback from the component itself, '
              'not leave it to whoever uses it');
    }
  });

  test('screens do not fire raw interface cues themselves', () {
    // A screen playing its own tap is either a duplicate of the one the
    // component already played, or a sign the control is bypassing Fx. Board
    // and reward cues are a different matter — those are *events*, not
    // interactions, and belong to whatever detected them.
    const Set<String> interfaceOnly = <String>{'tap(', 'press(', 'toggleOn(', 'toggleOff('};
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f
        in Directory('lib/ui/screens').listSync().whereType<File>()) {
      final String src = (f as File).readAsStringSync();
      for (final String cue in interfaceOnly) {
        if (src.contains('audio.$cue')) offenders.add('${f.path}: audio.$cue');
      }
    }
    expect(offenders, isEmpty,
        reason: 'these should go through Fx so the vocabulary stays consistent');
  });

  test('the vocabulary pairs a sound with a vibration everywhere', () {
    // Every Fx entry point must do both. A cue with no haptic is inaudible on
    // a muted phone; a haptic with no cue is invisible on a loud one.
    final String src = read('lib/ui/feedback.dart');
    final RegExp method = RegExp(r'static void (\w+)\([^)]*\)\s*\{(.*?)\n  \}', dotAll: true);
    final Iterable<RegExpMatch> ms = method.allMatches(src);
    expect(ms.length, greaterThanOrEqualTo(7), reason: 'expected the full vocabulary');
    for (final RegExpMatch m in ms) {
      final String body = m.group(2)!;
      expect(body.contains('audio.'), isTrue, reason: 'Fx.${m.group(1)} has no sound');
      expect(body.contains('haptics.'), isTrue, reason: 'Fx.${m.group(1)} has no haptic');
    }
  });
}
