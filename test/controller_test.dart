import 'package:bubble_sort/data/level.dart';
import 'package:bubble_sort/engine/board_state.dart';
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
  _hiddenTests();
  _precisionTests();
  _flowTests();

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


// ------------------------------------------------------------------ hidden

void _hiddenTests() {
  test('a concealed vessel hides everything but its mouth', () {
    final BoardState b = BoardState.withHidden(
      <List<int>>[<int>[0, 1, 2, 3], <int>[1, 1], <int>[]], 4, 1);
    expect(b.hiddenBelow, <int>[3, 0, 0]);
    expect(b.isHidden(0, 3), isFalse, reason: 'the top is always visible');
    expect(b.isHidden(0, 2), isTrue);
    expect(b.isHidden(0, 0), isTrue);
  });

  test('pouring off the top reveals the ball beneath, and undo does not re-hide it', () {
    BoardState b = BoardState.withHidden(
      <List<int>>[<int>[0, 1, 2, 3], <int>[3], <int>[]], 4, 1);
    final (BoardState next, Pour p) = b.pour(0, 1);
    expect(next.hiddenBelow[0], 2, reason: 'the new mouth has been seen');
    expect(next.isHidden(0, 2), isFalse);

    // What the player has seen, they have seen.
    b = next.unpour(p);
    expect(b.hiddenBelow[0], 2);
  });

  test('the rules never see concealment', () {
    final BoardState b = BoardState.withHidden(
      <List<int>>[<int>[0, 1, 2, 3], <int>[3], <int>[]], 4, 1);
    // canPour is decided by the true top ball, hidden or not.
    expect(b.canPour(0, 1), isTrue);
    expect(b.canonicalKey(), BoardState(b.toRaw(), 4).canonicalKey(),
        reason: 'the solver must see the same board');
  });
}

// --------------------------------------------------------------- precision

Level _precision() => Level(
      id: 999999,
      chapter: 1,
      capacity: 4,
      colorCount: 2,
      emptyTubes: 1,
      // Par is set artificially low so the budget (par + 2) is exactly two
      // pours — enough to make progress, not enough to finish.
      par: 0,
      parIsOptimal: true,
      mode: LevelMode.precision,
      tubes: <List<int>>[<int>[0, 0, 1, 1], <int>[1, 1, 0, 0], <int>[]],
    );

Future<GameController> _precisionController() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SettingsService settings = await SettingsService.load();
  return GameController(
    level: _precision(),
    audio: AudioService(settings),
    haptics: HapticService(settings),
  );
}

void _precisionTests() {
  testWidgets('the budget is charged for every pour, undo included',
      (WidgetTester tester) async {
    final GameController c = await _precisionController();
    addTearDown(c.dispose);
    expect(c.poursLeft, c.level.pourBudget);

    c
      ..tapTube(0)
      ..tapTube(2);
    await tester.pump(GameController.flightDuration * 2);
    expect(c.poursLeft, c.level.pourBudget - 1);

    c.undo();
    expect(c.moves, 0, reason: 'undo takes the pour back');
    expect(c.poursLeft, c.level.pourBudget - 1,
        reason: 'but the budget does not refund it');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('running out of pours fails the board and stops input',
      (WidgetTester tester) async {
    final GameController c = await _precisionController();
    addTearDown(c.dispose);
    bool failed = false;
    c.onFailed = () => failed = true;

    // Two legal pours that make progress but do not finish: the 1-run off
    // vessel 0 into the spare, then the 0-run off vessel 1 onto vessel 0.
    // That leaves two half-vessels of 1s and no budget.
    c
      ..tapTube(0)
      ..tapTube(2);
    await tester.pump(GameController.flightDuration * 2);
    c
      ..tapTube(1)
      ..tapTube(0);
    await tester.pump(GameController.flightDuration * 2);

    expect(failed, isTrue);
    expect(c.status, GameStatus.failed);

    final int before = c.moves;
    c
      ..tapTube(1)
      ..tapTube(2);
    await tester.pump(GameController.flightDuration * 2);
    expect(c.moves, before, reason: 'a failed board takes no more input');
    await tester.pump(const Duration(seconds: 2));
  });
}

// -------------------------------------------------------------------- flow

void _flowTests() {
  test('the multiplier climbs a quarter per seal and caps at two', () {
    expect(GameController.multiplierFor(0), 1.0);
    expect(GameController.multiplierFor(1), 1.0);
    expect(GameController.multiplierFor(2), 1.25);
    expect(GameController.multiplierFor(3), 1.5);
    expect(GameController.multiplierFor(5), 2.0);
    expect(GameController.multiplierFor(9), 2.0);
  });
}
