import 'package:flutter/widgets.dart';

import '../../data/daily_challenge.dart';
import '../../data/level.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../transitions.dart';
import '../widgets/ambient_background.dart';
import '../widgets/buttons.dart';
import '../widgets/drifting_bubbles.dart';
import '../widgets/icons.dart';
import '../widgets/brand_mark.dart';
import '../widgets/logo.dart';
import '../widgets/surfaces.dart';
import 'collection_screen.dart';
import 'daily_sheet.dart';
import 'game_screen.dart';
import 'levels_screen.dart';
import 'settings_sheet.dart';
import 'shop_sheet.dart';

/// The first three seconds.
///
/// The composition stays sparse where it can afford to: one identity block
/// owning the upper half, one card of state, one gold button. The economy is
/// deliberately kept to the *edges* of that — balances in the utility row, the
/// daily on one strip under the progress card — rather than given cards of
/// their own. A menu that is four competing reward widgets and a logo is the
/// look this design is trying not to have; hierarchy is what makes the screen
/// read as expensive, and the hierarchy has to survive the shop existing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The daily is offered once per launch, not once per return to the menu.
  /// Re-presenting it every time the player backs out of a level would turn a
  /// reward into an obstacle.
  bool _offeredDaily = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_offeredDaily) return;
    _offeredDaily = true;

    final AppScope scope = AppScope.of(context);
    if (!scope.wallet.canClaimDaily) return;

    // After the first frame, so the sheet rises over a menu that is already
    // composed rather than appearing on top of a half-built screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openDaily(scope);
    });
  }

  void _openDaily(AppScope scope) {
    scope.audio.whoosh();
    Navigator.of(context).push(sheetRoute<void>(const DailyRewardSheet()));
  }

  void _openShop(AppScope scope) {
    scope.audio.tap();
    Navigator.of(context).push(sheetRoute<void>(const ShopSheet()));
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    // Pushed harder here than anywhere else in the game. The menu is mostly
    // negative space by design, and unlit negative space reads as an empty
    // container; a visible warm/cool wash turns the same emptiness into
    // atmosphere.
    return AmbientBackground(
      intensity: 1.9,
      child: Stack(
        children: <Widget>[
          // Behind everything, and only on the menu. The board has its own
          // motion and does not need atmosphere competing with it.
          const Positioned.fill(child: DriftingBubbles()),
          SafeArea(
        child: Observes(
          listenables: <Listenable>[scope.progress, scope.wallet],
          builder: (BuildContext context) {
            final int total = scope.catalog.length;
            final int cleared = scope.progress.clearedCount;
            final int nextId = scope.progress.currentLevelId;
            final bool finishedAll = cleared == total;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // --- utility row ------------------------------------------
                  Padding(
                    padding: const EdgeInsets.only(top: DS.s8),
                    child: Row(
                      children: <Widget>[
                        RiseIn(
                          index: 0,
                          child: _BalancePill(
                            coins: scope.wallet.coins,
                            hints: scope.wallet.hints,
                            onTap: () => _openShop(scope),
                          ),
                        ),
                        const Spacer(),
                        RiseIn(
                          index: 0,
                          child: GhostIconButton(
                            icon: DIcons.grid,
                            semanticLabel: 'Collection',
                            onTap: () {
                              scope.audio.whoosh();
                              Navigator.of(context).push(riseRoute<void>(const CollectionScreen()));
                            },
                          ),
                        ),
                        const SizedBox(width: DS.s8),
                        RiseIn(
                          index: 0,
                          child: GhostIconButton(
                            icon: DIcons.settings,
                            semanticLabel: 'Settings',
                            onTap: () {
                              scope.audio.tap();
                              Navigator.of(context).push(sheetRoute<void>(const SettingsSheet()));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- identity ---------------------------------------------
                  // Weighted 3:7 rather than centred, so the identity block
                  // lands in the optical upper third and the action block owns
                  // the bottom. A centred logo with equal air above and below
                  // is what makes a menu feel like a placeholder.
                  const Spacer(flex: 4),
                  RiseIn(
                    index: 1,
                    distance: 26,
                    child: Column(
                      children: <Widget>[
                        const BrandMark(size: 124, animate: true),
                        const SizedBox(height: DS.s20),
                        const Wordmark(),
                        const SizedBox(height: DS.s16),
                        Text(
                          'POUR · SETTLE · SOLVE',
                          textAlign: TextAlign.center,
                          style: Type.label.copyWith(color: DS.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 5),

                  // Where the player actually is, in words, above the numbers.
                  // The gap between the identity block and the action block
                  // used to be empty ground; a player returning after a week
                  // had to read a percentage to remember where they had got
                  // to, and a chapter name is the thing they remember.
                  RiseIn(
                    index: 2,
                    child: Center(
                      child: Column(
                        children: <Widget>[
                          Text(
                            'CHAPTER ${scope.catalog.chapterOf(nextId).number.toString().padLeft(2, '0')}',
                            style: Type.label.copyWith(
                              color: DS.gold.withValues(alpha: 0.55),
                              letterSpacing: 2.2,
                            ),
                          ),
                          const SizedBox(height: DS.s8),
                          Text(
                            scope.catalog.chapterOf(nextId).name,
                            style: Type.titleMd.copyWith(fontSize: 23),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // --- state ------------------------------------------------
                  RiseIn(
                    index: 3,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // The card *is* the map's summary, so it opens the map.
                      // A separate labelled button underneath was a second
                      // route to the same place and one more thing competing
                      // with the only control that matters here.
                      onTap: () {
                        scope.audio.whoosh();
                        Navigator.of(context).push(riseRoute<void>(const LevelsScreen()));
                      },
                      child: SoftCard(
                      padding: const EdgeInsets.fromLTRB(DS.s20, DS.s16, DS.s20, DS.s20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text('PROGRESS', style: Type.label),
                                    const SizedBox(height: DS.s8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: <Widget>[
                                        Text('$cleared', style: Type.numeral),
                                        Text(
                                          ' / $total',
                                          style: Type.numeralSm.copyWith(color: DS.textTertiary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // The hint count used to sit here too. It moved
                              // to the balance pill when coins arrived — two
                              // readouts of the same number on one screen is
                              // how a menu starts looking like a dashboard.
                              Padding(
                                padding: const EdgeInsets.only(bottom: DS.s4),
                                child: Text(
                                  '${((cleared / total) * 100).toStringAsFixed(1)}%',
                                  style: Type.numeralSm.copyWith(color: DS.textTertiary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: DS.s16),
                          ProgressTrack(value: scope.progress.completion),
                          const SizedBox(height: DS.s12),
                          Row(
                            children: <Widget>[
                              const DIcon(DIcons.map, size: 13, color: DS.textTertiary),
                              const SizedBox(width: DS.s8),
                              Text('VIEW THE ROAD', style: Type.label),
                              const Spacer(),
                              const DIcon(DIcons.next, size: 12, color: DS.textTertiary),
                            ],
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),

                  const SizedBox(height: DS.s12),

                  RiseIn(
                    index: 4,
                    child: _TodayCard(
                      rewardReady: scope.wallet.canClaimDaily,
                      streak: scope.wallet.canClaimDaily
                          ? scope.wallet.streakIfClaimed
                          : scope.wallet.streak,
                      challenge: DailyChallenge.levelForNormal(scope.wallet.today, scope.catalog),
                      challengeDone: scope.progress.isDailyCleared(scope.wallet.today),
                      onReward: () => _openDaily(scope),
                      onChallenge: () {
                        final Level l =
                            DailyChallenge.levelForNormal(scope.wallet.today, scope.catalog);
                        scope.audio.whoosh();
                        Navigator.of(context).push(
                          riseRoute<void>(GameScreen(levelId: l.id, daily: true)),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: DS.s16),

                  // --- the one obvious thing to press -----------------------
                  RiseIn(
                    index: 5,
                    child: PrimaryButton(
                      label: cleared == 0 ? 'Play' : (finishedAll ? 'Play again' : 'Continue'),
                      sublabel: 'LEVEL $nextId',
                      onTap: () {
                        scope.audio.whoosh();
                        Navigator.of(context).push(
                          riseRoute<void>(GameScreen(levelId: nextId)),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: DS.s32),
                ],
              ),
            );
          },
        ),
      ),
        ],
      ),
    );
  }
}

/// Coins and hints, as one tappable control that opens the shop.
///
/// One pill rather than two readouts: the player has a wallet, not two
/// unrelated numbers, and giving it a single hit target means the shop is
/// reachable from the menu without spending a row on a button that says SHOP.
class _BalancePill extends StatefulWidget {
  const _BalancePill({required this.coins, required this.hints, required this.onTap});

  final int coins;
  final int hints;
  final VoidCallback onTap;

  @override
  State<_BalancePill> createState() => _BalancePillState();
}

class _BalancePillState extends State<_BalancePill>
    with TickerProviderStateMixin, PressMixin {
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => pressDown(),
        onTapCancel: pressUp,
        onTapUp: (_) => pressUp(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: press,
          builder: (BuildContext context, _) => Transform.scale(
            scale: 1 - press.value.clamp(0.0, 1.0) * 0.04,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DS.rPill),
                color: const Color(0x0DFFFFFF),
                border: Border.all(color: DS.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const DIcon(DIcons.coin, size: 14, color: DS.gold),
                  const SizedBox(width: DS.s4),
                  Text(
                    '${widget.coins}',
                    style: Type.numeralSm.copyWith(fontSize: 14, color: DS.gold),
                  ),
                  Container(
                    width: 1,
                    height: 13,
                    margin: const EdgeInsets.symmetric(horizontal: DS.s12),
                    color: const Color(0x1AFFFFFF),
                  ),
                  const DIcon(DIcons.hint, size: 14, color: DS.aqua),
                  const SizedBox(width: DS.s4),
                  Text(
                    '${widget.hints}',
                    style: Type.numeralSm.copyWith(fontSize: 14, color: DS.aqua),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Today: the reward and the challenge, as two rows of one card.
///
/// Two things that reset on the same calendar day belong together, and a
/// menu that gave each its own card would be a menu of cards. Each row has
/// two states with genuinely different weights: something to do is gold and
/// carries a chevron; something done is a quiet line of text.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.rewardReady,
    required this.streak,
    required this.challenge,
    required this.challengeDone,
    required this.onReward,
    required this.onChallenge,
  });

  final bool rewardReady;
  final int streak;
  final Level challenge;
  final bool challengeDone;
  final VoidCallback onReward;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DS.rMd),
          color: const Color(0x08FFFFFF),
          border: Border.all(color: DS.hairline),
        ),
        child: Column(
          children: <Widget>[
            _TodayRow(
              icon: DIcons.flame,
              live: rewardReady,
              title: rewardReady ? 'Daily reward ready' : 'Daily reward claimed',
              detail: rewardReady
                  ? 'Day $streak'
                  : (streak > 0 ? '$streak day streak' : ''),
              onTap: onReward,
            ),
            Container(height: 1, color: const Color(0x0DFFFFFF)),
            _TodayRow(
              icon: DIcons.play,
              live: !challengeDone,
              title: challengeDone ? 'Challenge cleared' : "Today's challenge",
              detail: challengeDone
                  ? 'Back tomorrow'
                  : '${challenge.colorCount} colours · +${DailyChallenge.reward}',
              onTap: onChallenge,
            ),
          ],
        ),
      );
}

class _TodayRow extends StatefulWidget {
  const _TodayRow({
    required this.icon,
    required this.live,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final DIcons icon;
  final bool live;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  State<_TodayRow> createState() => _TodayRowState();
}

class _TodayRowState extends State<_TodayRow> with TickerProviderStateMixin, PressMixin {
  @override
  Widget build(BuildContext context) {
    final Color accent = widget.live ? DS.gold : DS.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => pressDown(),
      onTapCancel: pressUp,
      onTapUp: (_) => pressUp(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: press,
        builder: (BuildContext context, _) => Opacity(
          opacity: 1 - press.value.clamp(0.0, 1.0) * 0.25,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
            decoration: BoxDecoration(
              color: widget.live ? DS.gold.withValues(alpha: 0.06) : null,
            ),
            child: Row(
              children: <Widget>[
                DIcon(widget.icon, size: 15, color: accent),
                const SizedBox(width: DS.s12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: widget.live
                        ? Type.bodyStrong.copyWith(color: DS.gold, fontSize: 13.5)
                        : Type.caption,
                  ),
                ),
                if (widget.detail.isNotEmpty)
                  Text(
                    widget.detail,
                    style: Type.caption.copyWith(
                      color: widget.live ? DS.gold.withValues(alpha: 0.7) : DS.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                if (widget.live) ...<Widget>[
                  const SizedBox(width: DS.s8),
                  const DIcon(DIcons.next, size: 13, color: DS.gold),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
