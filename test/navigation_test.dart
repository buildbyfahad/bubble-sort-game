import 'package:bubble_sort/app.dart';
import 'package:bubble_sort/data/level_catalog.dart';
import 'package:bubble_sort/ui/screens/game_screen.dart';
import 'package:bubble_sort/services/wallet_service.dart';
import 'package:bubble_sort/ui/screens/daily_sheet.dart';
import 'package:bubble_sort/ui/screens/home_screen.dart';
import 'package:bubble_sort/ui/screens/levels_screen.dart';
import 'package:bubble_sort/ui/screens/settings_sheet.dart';
import 'package:bubble_sort/ui/widgets/board_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_harness.dart';

/// Drives the real app the way a player does.
///
/// The golden tests wrap each screen in an [AppScope] of their own, which means
/// they cannot see whether the *app* actually provides one where it is needed.
/// It did not: the scope sat around `home`, and every pushed route is a sibling
/// of `home` rather than a descendant, so tapping PLAY threw. These tests exist
/// to make that class of mistake impossible to reintroduce.
void main() {
  setUpAll(loadAppFonts);

  /// Boots the real app.
  ///
  /// The wallet is seeded as already-claimed-today by default: the home screen
  /// offers the daily reward on first build, and a sheet over the menu would
  /// turn every test below into a test of the daily reward. Pass
  /// `dailyReady: true` to exercise that path deliberately.
  Future<void> boot(WidgetTester tester, {bool dailyReady = false}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (!dailyReady) 'wallet.lastClaimDay': todayIndex(),
    });
    final LevelCatalog catalog = loadCatalog();
    await tester.pumpWidget(
      BubbleSortApp(loadCatalog: () async => catalog),
    );
    // Past the splash's minimum hold, then a few frames to settle the switch.
    await tester.pump(const Duration(milliseconds: 1400));
    await settle(tester, steps: 16);
  }

  testWidgets('the daily reward is offered on launch, and pays out',
      (WidgetTester tester) async {
    useHandset(tester);
    await boot(tester, dailyReady: true);

    // Offered without being asked for — this is the game's day-2 hook, and it
    // has to arrive on its own.
    expect(find.byType(DailyRewardSheet), findsOneWidget);
    expect(find.text('CLAIM'), findsOneWidget);

    await tester.tap(find.text('CLAIM'));
    await settle(tester, steps: 20);

    // Day one of the ladder.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('wallet.coins'), WalletService.rewardFor(1).coins);
    expect(prefs.getInt('wallet.streak'), 1);

    // And it cannot be taken twice.
    expect(find.text('CLAIM'), findsNothing);
    await drainTimers(tester);
  });

  testWidgets('the app boots into the menu', (WidgetTester tester) async {
    useHandset(tester);
    await boot(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('PLAY reaches a playable board', (WidgetTester tester) async {
    useHandset(tester);
    await boot(tester);

    await tester.tap(find.text('PLAY'));
    await settle(tester, steps: 20);

    expect(tester.takeException(), isNull);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(BoardView), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('the levels screen and settings sheet open from the menu',
      (WidgetTester tester) async {
    useHandset(tester);
    await boot(tester);

    await tester.tap(find.text('The road'));
    await settle(tester, steps: 20);
    expect(tester.takeException(), isNull);
    expect(find.byType(LevelsScreen), findsOneWidget);

    // Back out, then open settings.
    final NavigatorState nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await settle(tester, steps: 16);

    await tester.tap(find.byType(HomeScreen).first, warnIfMissed: false);
    final Finder gear = find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == 'GhostIconButton',
    );
    await tester.tap(gear.first);
    await settle(tester, steps: 20);
    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsSheet), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('a pour on level 1 registers and can be undone',
      (WidgetTester tester) async {
    useHandset(tester);
    await boot(tester);
    await tester.tap(find.text('PLAY'));
    await settle(tester, steps: 20);

    // Level 1 is [amber-topped, vermilion-topped, empty, empty]; pouring the
    // first vessel's top ball into a spare is legal.
    final Rect board = tester.getRect(find.byType(BoardView));
    Offset vessel(int i) => Offset(
          board.left + board.width * (0.125 + 0.25 * i),
          board.center.dy,
        );

    await tester.tapAt(vessel(0));
    await settle(tester, steps: 8);
    await tester.tapAt(vessel(2));
    await settle(tester, steps: 20);

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsWidgets, reason: 'the move counter should read 1');

    await tester.tap(find.text('UNDO'));
    await settle(tester, steps: 16);
    expect(tester.takeException(), isNull);
    await drainTimers(tester);
  });
}
