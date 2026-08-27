import 'package:bubble_sort/data/level.dart';
import 'package:bubble_sort/engine/board_state.dart';
import 'package:bubble_sort/engine/game_controller.dart';
import 'package:bubble_sort/engine/solver.dart';
import 'package:bubble_sort/ui/screens/game_screen.dart';
import 'package:bubble_sort/ui/screens/home_screen.dart';
import 'package:bubble_sort/ui/screens/level_complete.dart';
import 'package:bubble_sort/ui/screens/levels_screen.dart';
import 'package:bubble_sort/ui/widgets/tube.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_harness.dart';

/// Renders the README's screenshots straight out of the app's own screens into
/// `docs/screenshots/`.
///
/// Same argument as `brand_assets_test.dart`: a screenshot taken by hand on a
/// device is a photograph of one moment in one build, and it starts lying the
/// day after it is committed. Nobody ever remembers to retake it. Rendering
/// them from the real widgets means a stale screenshot is a **test failure**
/// rather than something a reader notices before the author does.
///
/// So on a normal `flutter test` run this is a guard. To update the images
/// after an intentional visual change:
///
///   flutter test --update-goldens test/screenshots_test.dart
///
/// A progressed save file is mocked in so the shots show a game in play rather
/// than a fresh install with every number at zero.

/// Enough cleared levels to put the player mid-chapter, with a spread of
/// results so the road shows all three grades rather than a run of identical
/// nodes.
///
/// The scores are derived from each level's real par rather than picked out of
/// the air. Invented numbers were all comfortably under par, so every node
/// graded flawless and the road rendered a monochrome run of gold — a
/// screenshot that quietly hid a feature it was supposed to be showing.
Map<String, Object> _progressed({int upTo = 27}) {
  final Map<String, Object> prefs = <String, Object>{
    'progress.seenTutorial': true,
    'progress.hints': 5,
  };
  for (int i = 1; i <= upTo; i++) {
    final int par = loadCatalog().byId(i).par;
    prefs['progress.best.$i'] = switch (i % 3) {
      0 => par, // flawless — gold
      1 => (par * 1.25).ceil(), // great — aqua
      _ => (par * 1.7).ceil(), // solved — muted
    };
  }
  return prefs;
}

void main() {
  setUpAll(loadAppFonts);

  renderTest('01 — home', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: const HomeScreen(),
      prefs: _progressed(),
    )));
    await settle(tester, steps: 30);
    await expectLater(
      find.byType(Navigator),
      matchesGoldenFile('../docs/screenshots/01-home.png'),
    );
  });

  renderTest('02 — the road', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: const LevelsScreen(),
      prefs: _progressed(),
    )));
    await settle(tester, steps: 30);
    await expectLater(
      find.byType(Navigator),
      matchesGoldenFile('../docs/screenshots/02-road.png'),
    );
  });

  renderTest('03 — gameplay', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: const GameScreen(levelId: 240),
      prefs: _progressed(upTo: 239),
    )));
    await settle(tester, steps: 20);

    // Lift a stack, so the shot shows the game's core interaction rather than
    // a board sitting at rest. Tapped through the real widget, not by poking
    // the controller — if the vessel's hit box ever breaks, this shot breaks
    // with it.
    final BoardState board = BoardState(
      loadCatalog().byId(240).tubes,
      loadCatalog().byId(240).capacity,
    );
    await tester.tap(find.byType(Tube).at(_anySource(board)));
    await settle(tester, steps: 10);
    await expectLater(
      find.byType(Navigator),
      matchesGoldenFile('../docs/screenshots/03-gameplay.png'),
    );
  });

  renderTest('04 — a vessel shattering', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: const GameScreen(levelId: 160),
      prefs: _progressed(upTo: 159),
    )));
    await settle(tester, steps: 12);

    // Walk the solver's line until the move that seals a vessel, then stop
    // inside the celebration. The shatter is the game's reward beat and cannot
    // be photographed from a board at rest.
    //
    // The line is planned on a private mirror of the rules and played through
    // real taps on the real vessels, which keeps this out of the screen's
    // internals — no test-only hook has to exist in the production widget for
    // a screenshot's benefit.
    final Level level = loadCatalog().byId(160);
    BoardState mirror = BoardState(level.tubes, level.capacity);

    bool sealed = false;
    for (int guard = 0; guard < 40 && !sealed; guard++) {
      final SolverHint? h =
          Solver.solve(SolverRequest(mirror.toRaw(), mirror.capacity));
      if (h == null) break;

      final BoardState next = mirror.pour(h.from, h.to).$1;
      sealed = next.isSealed(h.to);

      await tester.tap(find.byType(Tube).at(h.from));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.byType(Tube).at(h.to));
      mirror = next;

      if (sealed) {
        // Land, then a beat into the fracture — cracks travelling, shards up.
        await tester.pump(GameController.flightDuration);
        await tester.pump(const Duration(milliseconds: 190));
      } else {
        await settle(tester, steps: 8, ms: 60);
      }
    }
    expect(sealed, isTrue, reason: 'the solver never reached a sealing move');

    await expectLater(
      find.byType(Navigator),
      matchesGoldenFile('../docs/screenshots/04-shatter.png'),
    );
    await settle(tester, steps: 40);
  });

  renderTest('05 — level complete', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      prefs: _progressed(),
      child: LevelCompleteSheet(
        level: loadCatalog().byId(120),
        moves: 11,
        best: 11,
        improved: true,
        hintsAwarded: 1,
        overallBefore: 0.026,
        overallAfter: 0.028,
        hasNext: true,
        onNext: () {},
        onReplay: () {},
        onHome: () {},
      ),
    )));
    await settle(tester, steps: 40, ms: 60);
    await expectLater(
      find.byType(Navigator),
      matchesGoldenFile('../docs/screenshots/05-complete.png'),
    );
  });
}

/// The first vessel a pour can legally leave from.
int _anySource(BoardState board) {
  for (int i = 0; i < board.tubeCount; i++) {
    for (int j = 0; j < board.tubeCount; j++) {
      if (board.canPour(i, j)) return i;
    }
  }
  return 0;
}
