import 'package:bubble_sort/engine/game_controller.dart';
import 'package:bubble_sort/engine/solver.dart';
import 'package:bubble_sort/services/audio_service.dart';
import 'package:bubble_sort/services/haptic_service.dart';
import 'package:bubble_sort/services/settings_service.dart';
import 'package:bubble_sort/ui/screens/game_screen.dart';
import 'package:bubble_sort/ui/screens/level_complete.dart';
import 'package:bubble_sort/ui/screens/home_screen.dart';
import 'package:bubble_sort/ui/screens/levels_screen.dart';
import 'package:bubble_sort/ui/screens/settings_sheet.dart';
import 'package:bubble_sort/ui/widgets/board_view.dart';
import 'dart:async';

import 'package:bubble_sort/app.dart';
import 'package:bubble_sort/data/level_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_harness.dart';

/// Renders every screen to a PNG under `test/goldens/`.
///
/// These exist to be *looked at*. A game like this cannot be reviewed from its
/// source: the whole point is whether the spacing, weight and light read as
/// premium, and that is only answerable by looking at a frame.
void main() {
  setUpAll(loadAppFonts);

  renderTest('boot — the first frame the player sees', (WidgetTester tester) async {
    useHandset(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // A loader that never completes parks the app on its boot screen, which is
    // what the native splash hands over to. The two must show the same mark on
    // the same ground or the hand-off flickers.
    await tester.pumpWidget(
      BubbleSortApp(loadCatalog: () => Completer<LevelCatalog>().future),
    );
    await settle(tester, steps: 20);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/boot.png'));
    // The splash's minimum-hold timer and the audio init timeout are still
    // armed; the binding refuses to end a test with pending timers.
    await drainTimers(tester);
  });

  renderTest('home — fresh install', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(child: const HomeScreen())));
    await settle(tester);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/home_fresh.png'));
  });

  renderTest('home — mid progress', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: const HomeScreen(),
      prefs: <String, Object>{
        'progress.best.1': 3,
        'progress.best.2': 6,
        'progress.best.3': 9,
        'progress.best.4': 12,
        'progress.hints': 5,
        'progress.seenTutorial': true,
      },
    )));
    await settle(tester);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/home_progress.png'));
  });

  renderTest('game — first level with tutorial', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(child: const GameScreen(levelId: 1))));
    await settle(tester);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/game_l1_tutorial.png'));
  });

  renderTest('game — level 1000, densest board, one vessel selected',
      (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: const GameScreen(levelId: 1000),
      prefs: <String, Object>{
        for (int i = 1; i < 1000; i++) 'progress.best.$i': 10,
        'progress.seenTutorial': true,
      },
    )));
    await settle(tester);

    // Pick up a stack so the golden shows the selected state, the lift and the
    // shadow behaviour rather than a board at rest.
    await tester.tap(find.byType(BoardView), warnIfMissed: false);
    final Finder board = find.byType(BoardView);
    final Rect r = tester.getRect(board);
    await tester.tapAt(Offset(r.left + r.width * 0.12, r.top + r.height * 0.30));
    await settle(tester, steps: 12);
    await expectLater(board, matchesGoldenFile('goldens/game_l1000_selected.png'));
  });

  renderTest('board — a vessel sealing', (WidgetTester tester) async {
    useHandset(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService settings = await SettingsService.load();
    final GameController c = GameController(
      level: loadCatalog().byId(160),
      audio: AudioService(settings),
      haptics: HapticService(settings),
    );
    await tester.pumpWidget(harness(
      Center(
        child: SizedBox(
          width: 345,
          height: 560,
          child: BoardView(controller: c, colorAssist: false),
        ),
      ),
    ));
    await settle(tester, steps: 6);

    // Walk the solver's line, looking ahead one pour at a time, and stop on the
    // move that seals a vessel. The seal is the game's core reward beat and
    // cannot be judged from a board at rest.
    bool sealed = false;
    for (int guard = 0; guard < 30 && !sealed; guard++) {
      final SolverHint? h =
          Solver.solve(SolverRequest(c.state.toRaw(), c.state.capacity));
      if (h == null) break;
      sealed = c.state.pour(h.from, h.to).$1.isSealed(h.to);

      c.tapTube(h.from);
      await tester.pump(const Duration(milliseconds: 220));
      c.tapTube(h.to);

      if (sealed) {
        // Land inside the bloom: the flight, plus a beat of the seal animation.
        await tester.pump(const Duration(milliseconds: 340));
        await tester.pump(const Duration(milliseconds: 180));
      } else {
        await settle(tester, steps: 10, ms: 60);
      }
    }
    expect(sealed, isTrue, reason: 'the solver never reached a sealing move');

    await expectLater(find.byType(BoardView), matchesGoldenFile('goldens/board_sealing.png'));

    // And the state that actually persists. The celebration is a second long;
    // the etched fracture it leaves behind is on screen for the rest of the
    // level, so it is the frame more worth locking down of the two.
    await settle(tester, steps: 24);
    await expectLater(find.byType(BoardView), matchesGoldenFile('goldens/board_sealed.png'));

    c.dispose();
  });

  renderTest('board — colour assist on', (WidgetTester tester) async {
    useHandset(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService settings = await SettingsService.load();
    final GameController c = GameController(
      level: loadCatalog().byId(1000),
      audio: AudioService(settings),
      haptics: HapticService(settings),
    );
    await tester.pumpWidget(harness(
      Center(
        child: SizedBox(
          width: 361,
          height: 560,
          child: BoardView(controller: c, colorAssist: true),
        ),
      ),
    ));
    await settle(tester, steps: 8);
    await expectLater(find.byType(BoardView), matchesGoldenFile('goldens/board_assist.png'));
  });

  renderTest('board — mid-pour, ball in flight', (WidgetTester tester) async {
    useHandset(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService settings = await SettingsService.load();
    final GameController c = GameController(
      level: loadCatalog().byId(85),
      audio: AudioService(settings),
      haptics: HapticService(settings),
    );
    await tester.pumpWidget(harness(
      Center(
        child: SizedBox(
          width: 361,
          height: 480,
          child: BoardView(controller: c, colorAssist: false),
        ),
      ),
    ));
    await settle(tester, steps: 6);
    // Level 3 opens with a legal pour from vessel 0 to the first empty one.
    c.tapTube(0);
    await tester.pump(const Duration(milliseconds: 260));
    c.tapTube(3);
    // One zero-length frame to build the flight overlay (its animation starts
    // when the widget is created), then advance into the middle of the arc.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    await expectLater(find.byType(BoardView), matchesGoldenFile('goldens/board_in_flight.png'));
    // Let the pour finish so the controller's timers are not left pending.
    await settle(tester, steps: 20);
    c.dispose();
  });

  renderTest('level complete sheet', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: LevelCompleteSheet(
        level: loadCatalog().byId(120),
        moves: 11,
        best: 11,
        improved: true,
        hintsAwarded: 1,
        overallBefore: 0.4,
        overallAfter: 0.5,
        hasNext: true,
        onNext: () {},
        onReplay: () {},
        onHome: () {},
      ),
    )));
    // Mid-celebration: bloom open, motes rising, counters still running.
    await settle(tester, steps: 12, ms: 60);
    await expectLater(
        find.byType(Navigator), matchesGoldenFile('goldens/level_complete_celebrating.png'));
    // And the settled state the player actually reads.
    await settle(tester, steps: 30, ms: 60);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/level_complete.png'));
  });

  renderTest('levels', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(
      child: const LevelsScreen(),
      prefs: <String, Object>{
        'progress.best.1': 3,
        'progress.best.2': 6,
        'progress.best.3': 9,
        'progress.seenTutorial': true,
      },
    )));
    await settle(tester, steps: 20);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/levels.png'));
  });

  renderTest('settings', (WidgetTester tester) async {
    useHandset(tester);
    await tester.pumpWidget(harness(await buildScope(child: const SettingsSheet())));
    await settle(tester);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/settings.png'));
  });
}
