import 'package:bubble_sort/engine/game_controller.dart';
import 'package:bubble_sort/services/audio_service.dart';
import 'package:bubble_sort/services/haptic_service.dart';
import 'package:bubble_sort/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_harness.dart';

/// Pacing, as opposed to rules.
///
/// [GameController] owns *when* things happen, and the answers to those
/// questions are what the game feels like. They are also invisible to the
/// rules tests, which is how the controller ended up silently discarding taps
/// that arrived while a pour was in the air — the board was always correct, it
/// just ignored you every 340ms.
Future<GameController> _controller(int levelId) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SettingsService settings = await SettingsService.load();
  return GameController(
    level: loadCatalog().byId(levelId),
    audio: AudioService(settings),
    haptics: HapticService(settings),
  );
}

/// The first legal pour on the board, as (from, to).
(int, int)? _anyPour(GameController c) {
  for (int i = 0; i < c.state.tubeCount; i++) {
    for (int j = 0; j < c.state.tubeCount; j++) {
      if (c.state.canPour(i, j)) return (i, j);
    }
  }
  return null;
}

void main() {
  testWidgets('a tap arriving mid-flight is queued, not dropped',
      (WidgetTester tester) async {
    final GameController c = await _controller(200);
    addTearDown(c.dispose);

    final (int, int) first = _anyPour(c)!;
    c
      ..tapTube(first.$1)
      ..tapTube(first.$2);
    expect(c.moves, 1);
    expect(c.flight, isNotNull, reason: 'the first pour should be in the air');

    // Half way through the arc — the window where taps used to vanish.
    await tester.pump(GameController.flightDuration ~/ 2);

    final (int, int) second = _anyPour(c)!;
    c
      ..tapTube(second.$1)
      ..tapTube(second.$2);

    // Acknowledged immediately, but not yet launched: one pour in the air.
    expect(c.hasQueuedPour, isTrue);
    expect(c.moves, 1);

    // The rest of the first arc, plus a frame.
    await tester.pump(GameController.flightDuration);
    expect(c.moves, 2, reason: 'the queued pour must launch when the first lands');
    expect(c.hasQueuedPour, isFalse);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('chained pours leave no idle frame between them',
      (WidgetTester tester) async {
    final GameController c = await _controller(200);
    addTearDown(c.dispose);

    final (int, int) first = _anyPour(c)!;
    c
      ..tapTube(first.$1)
      ..tapTube(first.$2);
    await tester.pump(GameController.flightDuration ~/ 2);

    final (int, int) second = _anyPour(c)!;
    c
      ..tapTube(second.$1)
      ..tapTube(second.$2);

    // Land the first pour exactly. The second must already be travelling —
    // if the board ever paints with nothing in the air between two chained
    // moves, the player sees a stutter.
    await tester.pump(GameController.flightDuration ~/ 2);
    expect(c.flight, isNotNull);
    expect(c.status, GameStatus.resolving);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a third tap while one is already queued is refused',
      (WidgetTester tester) async {
    final GameController c = await _controller(200);
    addTearDown(c.dispose);

    final (int, int) first = _anyPour(c)!;
    c
      ..tapTube(first.$1)
      ..tapTube(first.$2);
    await tester.pump(GameController.flightDuration ~/ 3);

    final (int, int) second = _anyPour(c)!;
    c
      ..tapTube(second.$1)
      ..tapTube(second.$2);
    expect(c.hasQueuedPour, isTrue);

    // Queue depth is one on purpose: acting on a board two moves ahead of the
    // one being displayed is not responsiveness, it is a board running away.
    c.tapTube(0);
    expect(c.selected, isNull);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the seal token advances only on seals', (WidgetTester tester) async {
    final GameController c = await _controller(200);
    addTearDown(c.dispose);

    expect(c.sealToken, 0);

    // Several ordinary pours. Each advances the flight counter; none of them
    // may advance the seal counter, or a chained pour after a seal restarts
    // the shatter that is still playing.
    for (int n = 0; n < 3; n++) {
      final (int, int)? p = _anyPour(c);
      if (p == null) break;
      c
        ..tapTube(p.$1)
        ..tapTube(p.$2);
      await tester.pump(GameController.flightDuration * 2);
      if (c.state.isSealed(p.$2)) break; // a seal is allowed to bump it
      expect(c.sealToken, 0, reason: 'pour $n sealed nothing');
      expect(c.flightToken, n + 1);
    }

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('undo and restart discard a queued pour', (WidgetTester tester) async {
    final GameController c = await _controller(200);
    addTearDown(c.dispose);

    final (int, int) first = _anyPour(c)!;
    c
      ..tapTube(first.$1)
      ..tapTube(first.$2);
    await tester.pump(GameController.flightDuration ~/ 2);
    final (int, int) second = _anyPour(c)!;
    c
      ..tapTube(second.$1)
      ..tapTube(second.$2);
    expect(c.hasQueuedPour, isTrue);

    c.restart();
    expect(c.hasQueuedPour, isFalse);
    expect(c.moves, 0);

    // And the queued pour must not resurface when the cancelled arc's timer
    // would have fired.
    await tester.pump(const Duration(seconds: 2));
    expect(c.moves, 0);
  });
}
