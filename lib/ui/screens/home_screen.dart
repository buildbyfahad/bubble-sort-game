import 'package:flutter/widgets.dart';

import '../../data/daily_challenge.dart';
import '../../data/level.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../feedback.dart';
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
/// This screen used to be a dashboard. It led with a card headed PROGRESS
/// containing "12 / 1000" and "1.2%", over a progress bar, and the only
/// genuinely game-like object on it was the play button at the bottom. That is
/// the composition of an analytics view, and it is most of why the menu kept
/// reading as an app that happens to contain a puzzle.
///
/// A percentage is a fact about a database. What a player wants to know on
/// opening a game is: where am I, and what do I press. So the identity block
/// owns the top, the chapter they are in is named rather than counted, the two
/// things that reset today are a pair of objects they can hit, and the play
/// button is the largest thing on screen. The thousand-level total still
/// exists — it just lives on the road, which is where a total belongs.
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
    Fx.navigate(context);
    Navigator.of(context).push(sheetRoute<void>(const DailyRewardSheet()));
  }

  void _openShop(AppScope scope) {
    Fx.navigate(context);
    Navigator.of(context).push(sheetRoute<void>(const ShopSheet()));
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    // Pushed harder here than anywhere else in the game. The menu is mostly
    // negative space by design, and unlit negative space reads as an empty
    // container; a visible warm/cool wash turns the same emptiness into
    // atmosphere. It matters more now that the ground itself is low-chroma:
    // this is where the screen's colour comes from.
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
                final int cleared = scope.progress.clearedCount;
                final int total = scope.catalog.length;
                final int nextId = scope.progress.currentLevelId;
                final bool finishedAll = cleared == total;
                final Level challenge =
                    DailyChallenge.levelForNormal(scope.wallet.today, scope.catalog);
                final bool challengeDone =
                    scope.progress.isDailyCleared(scope.wallet.today);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DS.s20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // --- utility row --------------------------------------
                      Padding(
                        padding: const EdgeInsets.only(top: DS.s8),
                        child: Row(
                          children: <Widget>[
                            RiseIn(
                              index: 0,
                              child: StickerPill(
                                icon: DIcons.coin,
                                value: '${scope.wallet.coins}',
                                accent: DS.gold,
                                deep: DS.goldDeep,
                                onTap: () => _openShop(scope),
                                trailingStud: true,
                                semanticLabel: 'Coins',
                              ),
                            ),
                            const SizedBox(width: DS.s8),
                            RiseIn(
                              index: 0,
                              child: StickerPill(
                                icon: DIcons.hint,
                                value: '${scope.wallet.hints}',
                                accent: DS.aqua,
                                deep: DS.aquaDeep,
                                onTap: () => _openShop(scope),
                                semanticLabel: 'Hints',
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
                                  Navigator.of(context)
                                      .push(riseRoute<void>(const CollectionScreen()));
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
                                  Navigator.of(context)
                                      .push(sheetRoute<void>(const SettingsSheet()));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // --- identity -----------------------------------------
                      // 5:4 rather than 4:5. The identity block wants to sit a
                      // little above centre; it used to have a progress card
                      // under it taking up the slack, and without one the old
                      // ratio left a hole between the wordmark and the tiles.
                      const Spacer(flex: 5),
                      RiseIn(
                        index: 1,
                        distance: 26,
                        child: Column(
                          children: <Widget>[
                            const BrandMark(size: 108, animate: true),
                            const SizedBox(height: DS.s16),
                            const Wordmark(),
                            const SizedBox(height: DS.s16),
                            // Where the player is, named rather than counted.
                            // A chapter name is the thing someone returning
                            // after a week actually remembers; "34.1%" is not.
                            _ChapterRibbon(
                              number: scope.catalog.chapterOf(nextId).number,
                              name: scope.catalog.chapterOf(nextId).name,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 4),

                      // --- today --------------------------------------------
                      // Two objects, not two rows of a list. Both reset on the
                      // same calendar day, both are worth coins, and both are
                      // things to hit — so they are the same size and sit side
                      // by side, which is how a game presents a choice.
                      RiseIn(
                        index: 2,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: _Tile(
                                icon: DIcons.flame,
                                title: 'DAILY',
                                detail: scope.wallet.canClaimDaily
                                    ? 'Day ${scope.wallet.streakIfClaimed}'
                                    : (scope.wallet.streak > 0
                                        ? '${scope.wallet.streak} day streak'
                                        : 'Claimed'),
                                live: scope.wallet.canClaimDaily,
                                accent: DS.punch,
                                deep: DS.punchDeep,
                                onTap: () => _openDaily(scope),
                              ),
                            ),
                            const SizedBox(width: DS.s12),
                            Expanded(
                              child: _Tile(
                                icon: DIcons.play,
                                title: challengeDone ? 'CLEARED' : "Today's challenge",
                                detail: challengeDone
                                    ? 'Back tomorrow'
                                    : '${challenge.colorCount} colours · +${DailyChallenge.reward}',
                                live: !challengeDone,
                                accent: DS.aqua,
                                deep: DS.aquaDeep,
                                onTap: () {
                                  scope.audio.whoosh();
                                  Navigator.of(context).push(
                                    riseRoute<void>(
                                        GameScreen(levelId: challenge.id, daily: true)),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: DS.s16),

                      // --- the one obvious thing to press -------------------
                      RiseIn(
                        index: 3,
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

                      const SizedBox(height: DS.s12),

                      // --- the road -----------------------------------------
                      // Second in the hierarchy on purpose. Most sessions want
                      // the next level, not the map; the map is for choosing,
                      // which is the rarer intent.
                      RiseIn(
                        index: 4,
                        child: _RoadBar(
                          cleared: cleared,
                          total: total,
                          completion: scope.progress.completion,
                          onTap: () {
                            scope.audio.whoosh();
                            Navigator.of(context).push(riseRoute<void>(const LevelsScreen()));
                          },
                        ),
                      ),

                      const SizedBox(height: DS.s24),
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

/// Chapter identity, as a small banner rather than two stacked labels.
///
/// The number is the quiet part and the name is the loud one, which is the
/// opposite of how progress readouts usually order them — and the right way
/// round for something meant to be remembered rather than tracked.
class _ChapterRibbon extends StatelessWidget {
  const _ChapterRibbon({required this.number, required this.name});

  final int number;
  final String name;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DS.rXs),
              color: DS.gold.withValues(alpha: 0.16),
              border: Border.all(color: DS.gold.withValues(alpha: 0.34), width: 1.5),
            ),
            child: Text(
              number.toString().padLeft(2, '0'),
              style: Type.numeralSm.copyWith(fontSize: 13, color: DS.gold),
            ),
          ),
          const SizedBox(width: DS.s12),
          Text(name, style: Type.titleMd.copyWith(fontSize: 21, color: DS.textPrimary)),
        ],
      );
}

/// One of the two "today" objects.
///
/// Live and spent are genuinely different states, so they are drawn as
/// different objects rather than the same object at two opacities: a live tile
/// is a saturated face with an outline and a bevel the finger can sink, and a
/// spent one is a flat recess with no bevel at all. Nothing needs to be read
/// to tell them apart.
class _Tile extends StatefulWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.live,
    required this.accent,
    required this.deep,
    required this.onTap,
  });

  final DIcons icon;
  final String title;
  final String detail;
  final bool live;
  final Color accent;
  final Color deep;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> with TickerProviderStateMixin, PressMixin {
  @override
  Widget build(BuildContext context) {
    final bool live = widget.live;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => pressDown(),
      onTapCancel: pressUp,
      onTapUp: (_) => pressUp(),
      onTap: () {
        Fx.tap(context);
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: press,
        builder: (BuildContext context, Widget? child) {
          final double p = press.value.clamp(0.0, 1.0);
          final double sink = live ? DS.bevel * p : 0;

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DS.rMd + 2),
              color: live ? widget.deep : const Color(0x14FFFFFF),
              border: Border.all(
                color: live ? DS.outline : const Color(0x1FFFFFFF),
                width: live ? DS.stroke : 1.5,
              ),
              boxShadow: live
                  ? DS.glow(widget.deep, opacity: 0.22, blur: 20, y: 6)
                  : null,
            ),
            padding: live
                ? EdgeInsets.only(top: sink, bottom: DS.bevel - sink)
                : EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.fromLTRB(DS.s12, DS.s12, DS.s12, DS.s12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DS.rMd),
                gradient: live
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color.lerp(widget.accent, const Color(0xFFFFFFFF), 0.28)!,
                          widget.accent,
                        ],
                      )
                    : null,
              ),
              child: child,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DIcon(
              widget.icon,
              size: 17,
              color: live ? DS.outline : DS.textTertiary,
            ),
            const SizedBox(height: DS.s8),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.bodyStrong.copyWith(
                fontSize: 13.5,
                color: live ? DS.outline : DS.textSecondary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              widget.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.caption.copyWith(
                fontSize: 11.5,
                color: live
                    ? DS.outline.withValues(alpha: 0.62)
                    : DS.textTertiary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The way to the map, with the thousand-level total riding along on it.
///
/// The count and the track used to be the headline of a PROGRESS card. They
/// are the same two facts; the difference is that here they are an attribute
/// of the thing they describe rather than the reason the screen exists.
class _RoadBar extends StatefulWidget {
  const _RoadBar({
    required this.cleared,
    required this.total,
    required this.completion,
    required this.onTap,
  });

  final int cleared;
  final int total;
  final double completion;
  final VoidCallback onTap;

  @override
  State<_RoadBar> createState() => _RoadBarState();
}

class _RoadBarState extends State<_RoadBar> with TickerProviderStateMixin, PressMixin {
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => pressDown(),
        onTapCancel: pressUp,
        onTapUp: (_) => pressUp(),
        onTap: () {
          Fx.tap(context);
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: press,
          builder: (BuildContext context, Widget? child) {
            final double p = press.value.clamp(0.0, 1.0);
            final double sink = DS.bevel * p;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DS.rMd + 2),
                color: DS.outline,
                border: Border.all(color: DS.outline, width: DS.stroke),
              ),
              padding: EdgeInsets.only(top: sink, bottom: DS.bevel - sink),
              child: Container(
                padding: const EdgeInsets.fromLTRB(DS.s16, DS.s12, DS.s16, DS.s12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DS.rMd),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[DS.surfaceRaised, DS.surface],
                  ),
                ),
                child: child,
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const DIcon(DIcons.map, size: 14, color: DS.gold),
                  const SizedBox(width: DS.s8),
                  Text('VIEW THE ROAD',
                      style: Type.label.copyWith(color: DS.textPrimary)),
                  const Spacer(),
                  Text(
                    '${widget.cleared}',
                    style: Type.numeralSm.copyWith(fontSize: 15, color: DS.gold),
                  ),
                  Text(
                    ' / ${widget.total}',
                    style: Type.caption.copyWith(fontSize: 11.5, color: DS.textTertiary),
                  ),
                  const SizedBox(width: DS.s8),
                  const DIcon(DIcons.next, size: 12, color: DS.textTertiary),
                ],
              ),
              const SizedBox(height: DS.s12),
              ProgressTrack(value: widget.completion, height: 6),
            ],
          ),
        ),
      );
}
