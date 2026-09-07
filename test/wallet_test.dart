import 'package:bubble_sort/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The economy.
///
/// Almost all of the risk here is in the daily streak, because it is the only
/// part of the game whose behaviour depends on the calendar — and a streak bug
/// is invisible in testing and infuriating in the wild, since by definition it
/// only shows up a day later.
Future<WalletService> _wallet(DateTime at, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return WalletService.load(clock: () => at);
}

int _dayIndex(DateTime d) =>
    DateTime(d.year, d.month, d.day).difference(DateTime(1970)).inDays;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('balances', () {
    test('hints start stocked so the mechanic is discoverable', () async {
      final WalletService w = await _wallet(DateTime(2026, 8, 27));
      expect(w.hints, WalletService.startingHints);
      expect(w.coins, 0);
    });

    test('spending refuses rather than going negative', () async {
      final WalletService w = await _wallet(DateTime(2026, 8, 27));
      await w.grantCoins(50);
      expect(await w.spendCoins(80), isFalse);
      expect(w.coins, 50, reason: 'a refused purchase must not deduct');
      expect(await w.spendCoins(50), isTrue);
      expect(w.coins, 0);
    });

    test('hints carried over from the old progress store are not lost',
        () async {
      // Hints used to live under ProgressService's key. A player mid-catalogue
      // when the economy shipped must not open the app to find them gone.
      final WalletService w = await _wallet(
        DateTime(2026, 8, 27),
        <String, Object>{'progress.hints': 11},
      );
      expect(w.hints, 11);
    });
  });

  group('payout', () {
    test('scales with grade on a first clear', () {
      expect(WalletService.payoutFor(flawless: true, great: false, firstClear: true), 50);
      expect(WalletService.payoutFor(flawless: false, great: true, firstClear: true), 30);
      expect(WalletService.payoutFor(flawless: false, great: false, firstClear: true), 15);
    });

    test('a replay pays a token amount, whatever the grade', () {
      // Otherwise level 1 is an ATM, and the moment a player works that out
      // the whole economy stops meaning anything.
      expect(WalletService.payoutFor(flawless: true, great: false, firstClear: false), 5);
      expect(WalletService.payoutFor(flawless: false, great: false, firstClear: false), 5);
    });
  });

  group('daily streak', () {
    test('a first claim starts the streak at one', () async {
      final WalletService w = await _wallet(DateTime(2026, 8, 27));
      expect(w.canClaimDaily, isTrue);
      expect(w.streak, 0);

      final DailyReward? r = await w.claimDaily();
      expect(r, isNotNull);
      expect(w.streak, 1);
      expect(w.coins, WalletService.rewardFor(1).coins);
      expect(w.canClaimDaily, isFalse);
    });

    test('a second claim on the same day is refused', () async {
      final WalletService w = await _wallet(DateTime(2026, 8, 27));
      await w.claimDaily();
      final int after = w.coins;

      expect(await w.claimDaily(), isNull);
      expect(w.coins, after, reason: 'a refused claim must not pay out');
      expect(w.streak, 1);
    });

    test('claiming on consecutive days extends the streak', () async {
      final Map<String, Object> prefs = <String, Object>{
        'wallet.streak': 3,
        'wallet.lastClaimDay': _dayIndex(DateTime(2026, 8, 26)),
      };
      final WalletService w = await _wallet(DateTime(2026, 8, 27), prefs);
      expect(w.streak, 3);
      expect(w.streakIfClaimed, 4);

      await w.claimDaily();
      expect(w.streak, 4);
      expect(w.coins, WalletService.rewardFor(4).coins);
    });

    test('missing a day breaks the streak back to one', () async {
      final Map<String, Object> prefs = <String, Object>{
        'wallet.streak': 6,
        'wallet.lastClaimDay': _dayIndex(DateTime(2026, 8, 24)),
      };
      final WalletService w = await _wallet(DateTime(2026, 8, 27), prefs);

      // Reads as broken immediately, rather than showing a stale 6 until the
      // player claims and watches it silently reset under them.
      expect(w.streak, 0);
      expect(w.streakIfClaimed, 1);

      await w.claimDaily();
      expect(w.streak, 1);
    });

    test('the ladder cycles every seven days and escalates within a week', () {
      expect(WalletService.cycleDayFor(1), 1);
      expect(WalletService.cycleDayFor(7), 7);
      expect(WalletService.cycleDayFor(8), 1, reason: 'day 8 returns to the foot');
      expect(WalletService.cycleDayFor(15), 1);

      for (int d = 2; d <= 7; d++) {
        expect(
          WalletService.rewardFor(d).coins,
          greaterThan(WalletService.rewardFor(d - 1).coins),
          reason: 'day $d must be worth more than day ${d - 1}',
        );
      }
      expect(WalletService.rewardFor(7).hints, greaterThan(0),
          reason: 'the end of the week should pay in more than coins');
    });

    test('the seventh-day prize is actually reachable', () async {
      WalletService w = await _wallet(DateTime(2026, 8, 20));
      await w.claimDaily();

      for (int i = 1; i < 7; i++) {
        final DateTime day = DateTime(2026, 8, 20).add(Duration(days: i));
        w = await _wallet(day, <String, Object>{
          'wallet.streak': i,
          'wallet.lastClaimDay': _dayIndex(day.subtract(const Duration(days: 1))),
          'wallet.coins': 0,
        });
        await w.claimDaily();
        expect(w.streak, i + 1);
      }
      expect(w.coins, WalletService.rewardFor(7).coins);
      expect(w.hints, WalletService.startingHints + WalletService.rewardFor(7).hints);
    });

    test('a streak survives crossing a month boundary', () async {
      // Day arithmetic done on day-of-month rather than an epoch index breaks
      // exactly here, and only once a month.
      final WalletService w = await _wallet(
        DateTime(2026, 9, 1),
        <String, Object>{
          'wallet.streak': 4,
          'wallet.lastClaimDay': _dayIndex(DateTime(2026, 8, 31)),
        },
      );
      expect(w.streak, 4);
      expect(w.streakIfClaimed, 5);
    });
  });
}
