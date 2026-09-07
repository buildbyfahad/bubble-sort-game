import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the player *has*, as opposed to what they have *done*.
///
/// [ProgressService] owns the record of play — which levels are cleared, in
/// how many pours. This owns the economy on top of it: coins, hints, and the
/// daily streak. Splitting them that way keeps the rules of the game and the
/// rules of the reward loop from growing into each other, which matters
/// because the second set changes far more often than the first.
///
/// Everything is local. There is no server, no account and no receipt — a
/// determined player can edit their own save, and that is a trade worth making
/// for a single-player puzzle game with no leaderboard to protect.
class WalletService extends ChangeNotifier {
  WalletService._(this._prefs, this._clock);

  static const String _kCoins = 'wallet.coins';
  static const String _kHints = 'wallet.hints';
  static const String _kStreak = 'wallet.streak';
  static const String _kLastClaim = 'wallet.lastClaimDay';

  /// The key hints used to live under, on [ProgressService].
  static const String _kLegacyHints = 'progress.hints';

  /// Hints the player starts with, so the mechanic is discoverable without
  /// having to be bought first.
  static const int startingHints = 3;

  final SharedPreferences _prefs;

  /// Injectable so the daily-reward tests can travel in time without waiting
  /// a day, and so a device clock in a different timezone is one thing to
  /// reason about rather than several.
  final DateTime Function() _clock;

  static Future<WalletService> load({DateTime Function()? clock}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final WalletService w = WalletService._(prefs, clock ?? DateTime.now);
    await w._migrate();
    return w;
  }

  /// Moves hints out of the progress store, where they used to live before
  /// there was an economy to put them in. Runs once; harmless afterwards.
  Future<void> _migrate() async {
    if (_prefs.containsKey(_kLegacyHints) && !_prefs.containsKey(_kHints)) {
      await _prefs.setInt(_kHints, _prefs.getInt(_kLegacyHints)!);
      await _prefs.remove(_kLegacyHints);
    }
  }

  // ----------------------------------------------------------------- balances

  int get coins => _prefs.getInt(_kCoins) ?? 0;

  int get hints => _prefs.getInt(_kHints) ?? startingHints;

  Future<void> grantCoins(int n) async {
    if (n <= 0) return;
    await _prefs.setInt(_kCoins, coins + n);
    notifyListeners();
  }

  /// Returns false when the player cannot afford it, so callers can refuse
  /// without having to check the balance themselves and race with it.
  Future<bool> spendCoins(int n) async {
    if (n <= 0 || coins < n) return false;
    await _prefs.setInt(_kCoins, coins - n);
    notifyListeners();
    return true;
  }

  Future<void> grantHints(int n) async {
    if (n <= 0) return;
    await _prefs.setInt(_kHints, hints + n);
    notifyListeners();
  }

  Future<bool> spendHint() async {
    final int h = hints;
    if (h <= 0) return false;
    await _prefs.setInt(_kHints, h - 1);
    notifyListeners();
    return true;
  }

  // -------------------------------------------------------------- level pay

  /// Coins for clearing a board.
  ///
  /// A replay pays a token amount rather than nothing *and* rather than the
  /// full rate. Nothing at all makes replaying a solved level feel pointless;
  /// the full rate makes level 1 an ATM, and the moment a player works that
  /// out the entire economy stops meaning anything.
  static int payoutFor({required bool flawless, required bool great, required bool firstClear}) {
    if (!firstClear) return 5;
    if (flawless) return 50;
    if (great) return 30;
    return 15;
  }

  // ------------------------------------------------------------------ daily

  /// Days since the epoch in *local* time.
  ///
  /// Deliberately not UTC. "Come back tomorrow" has to mean the player's
  /// tomorrow, or someone west of Greenwich loses a streak they turned up for.
  int get _today {
    final DateTime n = _clock();
    return DateTime(n.year, n.month, n.day).difference(DateTime(1970)).inDays;
  }

  int get _lastClaimDay => _prefs.getInt(_kLastClaim) ?? -1;

  /// Consecutive days claimed. Zero before the first ever claim.
  int get streak {
    final int s = _prefs.getInt(_kStreak) ?? 0;
    // A streak that has already lapsed reads as broken immediately, rather
    // than showing yesterday's number until the player claims again and
    // watches it silently reset under them.
    if (s == 0) return 0;
    final int gap = _today - _lastClaimDay;
    return gap <= 1 ? s : 0;
  }

  bool get canClaimDaily => _lastClaimDay != _today;

  /// What the streak becomes if the player claims right now.
  int get streakIfClaimed {
    if (!canClaimDaily) return streak;
    return _today - _lastClaimDay == 1 ? (_prefs.getInt(_kStreak) ?? 0) + 1 : 1;
  }

  /// Position in the seven-day cycle a given streak length lands on.
  static int cycleDayFor(int streak) => streak <= 0 ? 1 : ((streak - 1) % 7) + 1;

  /// The reward ladder. Escalates across a week and resets to the foot of the
  /// ladder on the eighth day, so there is always a visible next rung rather
  /// than a number that grows without shape.
  static DailyReward rewardFor(int cycleDay) => switch (cycleDay) {
        1 => const DailyReward(coins: 40),
        2 => const DailyReward(coins: 60),
        3 => const DailyReward(coins: 80, hints: 1),
        4 => const DailyReward(coins: 100),
        5 => const DailyReward(coins: 130),
        6 => const DailyReward(coins: 160),
        _ => const DailyReward(coins: 250, hints: 3),
      };

  /// The seven rungs, for the row of pips on the daily card.
  static List<DailyReward> get ladder =>
      <DailyReward>[for (int d = 1; d <= 7; d++) rewardFor(d)];

  /// Claims today's reward. Returns null if it was already claimed.
  Future<DailyReward?> claimDaily() async {
    if (!canClaimDaily) return null;
    final int next = streakIfClaimed;
    final DailyReward reward = rewardFor(cycleDayFor(next));

    await _prefs.setInt(_kStreak, next);
    await _prefs.setInt(_kLastClaim, _today);
    await _prefs.setInt(_kCoins, coins + reward.coins);
    if (reward.hints > 0) await _prefs.setInt(_kHints, hints + reward.hints);

    notifyListeners();
    return reward;
  }

  // ------------------------------------------------------------------ reset

  Future<void> resetAll() async {
    await _prefs.remove(_kCoins);
    await _prefs.remove(_kHints);
    await _prefs.remove(_kStreak);
    await _prefs.remove(_kLastClaim);
    await _prefs.remove(_kLegacyHints);
    notifyListeners();
  }
}

/// One rung of the daily ladder.
@immutable
class DailyReward {
  const DailyReward({required this.coins, this.hints = 0});

  final int coins;
  final int hints;
}

/// What the shop sells.
///
/// A short list on purpose. A shop with fourteen bundles in it is a shop that
/// has stopped being a reward and started being a checkout.
@immutable
class ShopItem {
  const ShopItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.hints,
    required this.price,
  });

  final String id;
  final String label;
  final String detail;
  final int hints;
  final int price;

  static const List<ShopItem> all = <ShopItem>[
    ShopItem(id: 'hint1', label: 'One hint', detail: 'A single solving move', hints: 1, price: 80),
    ShopItem(
      id: 'hint5',
      label: 'Five hints',
      detail: 'Twenty per cent off',
      hints: 5,
      price: 320,
    ),
    ShopItem(
      id: 'hint15',
      label: 'Fifteen hints',
      detail: 'A third off',
      hints: 15,
      price: 800,
    ),
  ];
}
