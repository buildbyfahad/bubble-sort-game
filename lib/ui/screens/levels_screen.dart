import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show SliverLayoutDimensions;
import 'package:flutter/widgets.dart';

import '../../data/level.dart';
import '../../data/level_catalog.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../feedback.dart';
import '../transitions.dart';
import '../widgets/ambient_background.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import 'collection_screen.dart';
import 'daily_sheet.dart';
import 'game_screen.dart';
import 'settings_sheet.dart';
import 'shop_sheet.dart';
import 'level_complete.dart' show ClearGrade, gradeFor;

/// The road — and the game's home screen.
///
/// There used to be a menu in front of this: launch, a daily popup, a lobby
/// with six entry points, *then* a decision to open the map, *then* a
/// decision about which level. Six things between opening the app and
/// playing it, on the most-repeated path in the product.
///
/// The map is the home screen now. Launch lands the player on the road at
/// their own level with one lit node, and everything else — shop, collection,
/// settings, the daily — hangs off it as chips. Win a level and you come back
/// here to watch the next node open.
///
/// The journey.
///
/// This used to be a grid of numbered tiles, which is a *menu*: it tells the
/// player how much is left and nothing else. A map tells them where they are.
/// The difference matters because progress in a thousand-level puzzle game is
/// the whole product — the levels are almost incidental — and a scrollbar is a
/// bad way to render a thousand of anything.
///
/// Three ideas do the work:
///
///   * **A road, not a list.** Nodes sit on a serpentine path with a drawn
///     track between them. The path is walked in gold behind the player and
///     lies unlit ahead, so position is readable at a glance from ten feet.
///   * **A horizon.** The map stops a short way past the furthest unlocked
///     level rather than running to level 1000. Being able to scroll past
///     nine hundred padlocks is demoralising and tells the player nothing;
///     seeing a handful of nodes ahead, fading out, is an invitation.
///   * **Chapters as gates.** Each chapter opens with a banner that breaks the
///     path, so a run of forty levels has a beginning and an end.
///
/// It is built as one flat sliver list of fixed-height rows — one row per
/// level, one per chapter banner — so only the dozen rows actually on screen
/// are ever built. Every node's position is a pure function of its index,
/// which is what lets the scroll offset for "where the player is" be computed
/// arithmetically instead of by measuring anything.

/// How far past the frontier the road stays visible. Enough to see where the
/// next chapter starts; not enough to browse.
const int _lookahead = 8;

const double _nodeRow = 116;
const double _bannerRow = 128;
const double _footerRow = 190;
const double _topPad = 8;

/// Node diameter, and how far the path swings off centre.
const double _nodeSize = 78;
const double _swing = 0.28;

/// Radians of the serpentine per level. A shade under a fifth of a turn, so
/// the path completes a full S about every eight levels — often enough to read
/// as winding, rarely enough that consecutive nodes stay comfortably apart.
const double _swingRate = 0.80;

// ---------------------------------------------------------------- the plan

sealed class _Row {
  const _Row();
  double get height;
}

class _BannerRow extends _Row {
  const _BannerRow(this.chapter);
  final Chapter chapter;

  @override
  double get height => _bannerRow;
}

class _NodeRow extends _Row {
  const _NodeRow({
    required this.id,
    required this.x,
    required this.prevX,
    required this.nextX,
  });

  final int id;

  /// Horizontal position as a fraction of the map's width, along with those of
  /// the neighbours this row has to draw half a segment toward. Null means the
  /// path is broken there — a chapter banner, or the end of the road.
  final double x;
  final double? prevX;
  final double? nextX;

  @override
  double get height => _nodeRow;
}

class _HorizonRow extends _Row {
  const _HorizonRow({required this.nextChapter, required this.fromX, required this.toX});

  /// The chapter waiting beyond the horizon, if the player has not reached the
  /// end of the catalogue.
  final Chapter? nextChapter;

  /// Where the last node sat, and where the next one would have. The road
  /// carries on toward it and fades out, so the edge of the map reads as the
  /// road continuing rather than as the road being cut off.
  final double fromX;
  final double toX;

  @override
  double get height => _footerRow;
}

/// The whole map, resolved to a list of rows plus the offsets needed to jump
/// to any level.
class _MapPlan {
  _MapPlan(LevelCatalog catalog, int frontier) {
    final int horizon = math.min(catalog.length, frontier + _lookahead);
    final int lastChapter = catalog.chapterOf(horizon).number;

    for (int c = 1; c <= lastChapter; c++) {
      final Chapter chapter = catalog.chapterByNumber(c);
      rows.add(_BannerRow(chapter));

      final int last = math.min(chapter.to, horizon);
      for (int id = chapter.from; id <= last; id++) {
        final int i = id - chapter.from;
        rows.add(_NodeRow(
          id: id,
          x: _xFor(i),
          // The path breaks at a banner: the first node of a chapter has
          // nothing above it and the last has nothing below.
          prevX: id == chapter.from ? null : _xFor(i - 1),
          // The road breaks at a chapter boundary, but *not* at the horizon:
          // there the last node keeps its lower half so the fading stub below
          // it continues an unbroken line.
          nextX: id == chapter.to ? null : _xFor(i + 1),
        ));
      }
    }

    // What lies past the horizon is the next chapter the player has not
    // reached — not `chapterOf(horizon + 1)`, which is usually the chapter
    // they are already standing in and would name their own location as their
    // destination.
    final int aheadNumber = catalog.chapterOf(horizon).number + 1;
    final int lastIndexInChapter = horizon - catalog.chapterOf(horizon).from;
    rows.add(_HorizonRow(
      nextChapter: horizon >= catalog.length || aheadNumber > catalog.chapters.length
          ? null
          : catalog.chapterByNumber(aheadNumber),
      fromX: _xFor(lastIndexInChapter),
      toX: _xFor(lastIndexInChapter + 1),
    ));

    // Offsets come from one pass over the finished row list rather than from a
    // running total kept during construction — the heights are the single
    // source of truth for both the list and the jump-to-level scroll, and
    // maintaining that sum twice is how the two silently drift apart.
    double y = _topPad;
    for (final _Row r in rows) {
      if (r is _NodeRow) _offsetOf[r.id] = y;
      y += r.height;
    }
  }

  final List<_Row> rows = <_Row>[];
  final Map<int, double> _offsetOf = <int, double>{};

  /// Where [id] sits from the top of the scrollable, or null if the horizon
  /// stops short of it.
  double? offsetOf(int id) => _offsetOf[id];

  static double _xFor(int indexInChapter) =>
      0.5 + math.sin(indexInChapter * _swingRate) * _swing;
}

// --------------------------------------------------------------- the screen

class LevelsScreen extends StatefulWidget {
  const LevelsScreen({super.key, this.isHome = false});

  /// True only when the road is the app's root. Play-testing preferred a menu
  /// in front of it — landing straight on the map read as being dropped into
  /// the middle of something — so the default is now "pushed", with a back
  /// button.
  final bool isHome;

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> with SingleTickerProviderStateMixin {
  ScrollController? _scroll;
  _MapPlan? _plan;
  int _planFrontier = -1;

  /// Drives the pulse on the current node and the shimmer along the walked
  /// path. One controller for the whole map — a ticker per node would be a
  /// hundred tickers on a fast scroll.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _scroll?.dispose();
    _pulse.dispose();
    super.dispose();
  }

  _MapPlan _planFor(AppScope scope) {
    final int frontier = scope.progress.currentLevelId;
    // Rebuilt only when the horizon actually moves, which is at most once per
    // level cleared — not on every rebuild of the list.
    if (_plan == null || frontier != _planFrontier) {
      _plan = _MapPlan(scope.catalog, frontier);
      _planFrontier = frontier;
    }
    return _plan!;
  }

  void _open(BuildContext context, AppScope scope, int id) {
    if (!scope.progress.isUnlocked(id)) {
      Fx.refuse(context);
      return;
    }
    Fx.navigate(context);
    // push, NOT pushReplacement.
    //
    // Replacing was right while the road was pushed on top of a menu: swap
    // road for level, and back returned to the menu. The moment the road
    // became the root it meant replacing the *only* route, so backing out of
    // a level popped an empty navigator and left a black screen.
    Navigator.of(context).push(riseRoute<void>(GameScreen(levelId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    return AmbientBackground(
      intensity: 0.85,
      atmosphere: Atmosphere.forChapter(
        scope.catalog.chapterOf(scope.progress.currentLevelId).number,
      ),
      child: SafeArea(
        child: Observes(
          listenables: <Listenable>[scope.progress],
          builder: (BuildContext context) {
            final _MapPlan plan = _planFor(scope);
            final int frontier = scope.progress.currentLevelId;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _RoadBar(
                  isHome: widget.isHome,
                  coins: scope.wallet.coins,
                  hints: scope.wallet.hints,
                  cleared: scope.progress.clearedCount,
                  total: scope.catalog.length,
                  todayReady: scope.wallet.canClaimDaily ||
                      !scope.progress.isDailyCleared(scope.wallet.today),
                  onBack: () {
                    Fx.tap(context);
                    Navigator.of(context).pop();
                  },
                  onToday: () {
                    Fx.navigate(context);
                    Navigator.of(context).push(sheetRoute<void>(const DailyRewardSheet()));
                  },
                  onCollection: () {
                    Fx.navigate(context);
                    Navigator.of(context).push(riseRoute<void>(const CollectionScreen()));
                  },
                  onShop: () {
                    Fx.navigate(context);
                    Navigator.of(context).push(sheetRoute<void>(const ShopSheet()));
                  },
                  onSettings: () {
                    Fx.navigate(context);
                    Navigator.of(context).push(sheetRoute<void>(const SettingsSheet()));
                  },
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints c) {
                      // Park the player's node a little above centre: the eye
                      // wants to see where it is going more than where it has
                      // been, so the road ahead gets the larger half.
                      _scroll ??= ScrollController(
                        initialScrollOffset: math.max(
                          0,
                          (plan.offsetOf(frontier) ?? 0) - c.maxHeight * 0.42,
                        ),
                      );

                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(top: _topPad),
                        itemCount: plan.rows.length,
                        // Every row's height is known up front, so the list can
                        // resolve any scroll offset without laying out what it
                        // is scrolling past.
                        itemExtentBuilder: (int i, SliverLayoutDimensions _) =>
                            plan.rows[i].height,
                        itemBuilder: (BuildContext context, int i) => _buildRow(
                          context,
                          scope,
                          plan.rows[i],
                          frontier,
                          c.maxWidth,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    AppScope scope,
    _Row row,
    int frontier,
    double width,
  ) {
    switch (row) {
      case _BannerRow(:final Chapter chapter):
        return _ChapterBanner(
          chapter: chapter,
          cleared: scope.progress.clearedBetween(chapter.from, chapter.to),
          reached: scope.progress.isUnlocked(chapter.from),
        );

      case _NodeRow():
        final bool cleared = scope.progress.isCleared(row.id);
        final bool unlocked = scope.progress.isUnlocked(row.id);
        final int? best = scope.progress.bestFor(row.id);
        return _PathRow(
          row: row,
          width: width,
          walked: row.id <= frontier,
          pulse: _pulse,
          node: _LevelNode(
            id: row.id,
            cleared: cleared,
            unlocked: unlocked,
            isCurrent: row.id == frontier,
            grade: cleared && best != null
                ? gradeFor(best, scope.catalog.byId(row.id).par)
                : null,
            best: best,
            pulse: _pulse,
            onTap: () => _open(context, scope, row.id),
          ),
        );

      case _HorizonRow():
        return _Horizon(row: row);
    }
  }
}

// ------------------------------------------------------------------ header

/// The road's own chrome: what the player has, and every other screen.
///
/// Deliberately chips rather than a menu. The road is the home screen, so
/// these are the *only* things competing with the one lit node, and each is
/// the smallest thing that can still be tapped.
class _RoadBar extends StatelessWidget {
  const _RoadBar({
    required this.isHome,
    required this.coins,
    required this.hints,
    required this.cleared,
    required this.total,
    required this.todayReady,
    required this.onBack,
    required this.onToday,
    required this.onCollection,
    required this.onShop,
    required this.onSettings,
  });

  final bool isHome;
  final int coins;
  final int hints;
  final int cleared;
  final int total;
  final bool todayReady;
  final VoidCallback onBack;
  final VoidCallback onToday;
  final VoidCallback onCollection;
  final VoidCallback onShop;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(DS.s12, DS.s8, DS.s12, DS.s8),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                if (!isHome) ...<Widget>[
                  GhostIconButton(icon: DIcons.back, semanticLabel: 'Back', onTap: onBack),
                  const SizedBox(width: DS.s8),
                ],
                _Purse(coins: coins, hints: hints, onTap: onShop),
                const Spacer(),
                _Chip(
                  icon: DIcons.flame,
                  badge: todayReady,
                  semanticLabel: 'Today',
                  onTap: onToday,
                ),
                const SizedBox(width: DS.s8),
                _Chip(
                  icon: DIcons.grid,
                  semanticLabel: 'Collection',
                  onTap: onCollection,
                ),
                const SizedBox(width: DS.s8),
                _Chip(
                  icon: DIcons.settings,
                  semanticLabel: 'Settings',
                  onTap: onSettings,
                ),
              ],
            ),
            const SizedBox(height: DS.s8),
            Text('$cleared of $total cleared',
                style: Type.caption.copyWith(color: DS.textSecondary)),
          ],
        ),
      );
}

/// What the player has, as one tappable control that opens the shop.
class _Purse extends StatelessWidget {
  const _Purse({required this.coins, required this.hints, required this.onTap});

  final int coins;
  final int hints;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Fx.tap(context);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DS.rPill),
            color: DS.ink.withValues(alpha: 0.42),
            border: Border.all(color: DS.outline, width: DS.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const DIcon(DIcons.coin, size: 15, color: DS.gold),
              const SizedBox(width: DS.s4),
              Text('$coins', style: Type.numeralSm.copyWith(fontSize: 15, color: DS.gold)),
              const SizedBox(width: DS.s12),
              const DIcon(DIcons.hint, size: 15, color: DS.aqua),
              const SizedBox(width: DS.s4),
              Text('$hints', style: Type.numeralSm.copyWith(fontSize: 15, color: DS.aqua)),
            ],
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.badge = false,
  });

  final DIcons icon;
  final String semanticLabel;
  final VoidCallback onTap;

  /// A dot, not a count. The player needs to know there is something here,
  /// not how many things.
  final bool badge;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Fx.tap(context);
            onTap();
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DS.ink.withValues(alpha: 0.42),
                  border: Border.all(color: DS.outline, width: DS.stroke),
                ),
                child: Center(child: DIcon(icon, size: 20, color: DS.textPrimary)),
              ),
              if (badge)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DS.punch,
                      border: Border.all(color: DS.outline, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

// ----------------------------------------------------------------- banners

/// A chapter gate. Breaks the road, names the stretch ahead, and carries that
/// stretch's own completion count — so a player forty levels deep still has a
/// nearby, finishable target.
/// A chapter gate, drawn as a ribbon.
///
/// It was a rounded card with three lines of text in it, which is a *label*.
/// A chapter is a milestone, and a milestone on a game map is a banner: a
/// plate with swallowtail ends and folded tails behind it. The road runs
/// behind it, so the player passes through rather than past.
class _ChapterBanner extends StatelessWidget {
  const _ChapterBanner({
    required this.chapter,
    required this.cleared,
    required this.reached,
  });

  final Chapter chapter;
  final int cleared;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final bool complete = cleared == chapter.length;
    final Color accent = complete ? DS.aqua : (reached ? DS.gold : DS.textTertiary);

    return Padding(
      // Wide margins: the ribbon's tails hang outside its own box, and at
      // the old padding they ran off the screen.
      padding: const EdgeInsets.fromLTRB(DS.s40, DS.s20, DS.s40, DS.s12),
      child: Opacity(
        opacity: reached ? 1 : 0.55,
        child: CustomPaint(
          painter: _RibbonPainter(accent: accent, lit: reached),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, DS.s12, DS.s24, DS.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'CHAPTER ${chapter.number.toString().padLeft(2, '0')}',
                  style: Type.label.copyWith(
                    color: DS.textPrimary.withValues(alpha: 0.75),
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: DS.s4),
                Text(
                  chapter.name,
                  style: Type.titleMd.copyWith(
                    fontSize: 23,
                    color: DS.textPrimary,
                    shadows: <Shadow>[
                      Shadow(color: DS.outline, blurRadius: 0, offset: const Offset(0, 2)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DS.s8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (complete) ...<Widget>[
                      const DIcon(DIcons.check, size: 12, color: DS.textPrimary),
                      const SizedBox(width: DS.s4),
                    ] else if (!reached) ...<Widget>[
                      const DIcon(DIcons.lock, size: 12, color: DS.textPrimary),
                      const SizedBox(width: DS.s4),
                    ],
                    Text(
                      '$cleared / ${chapter.length}',
                      style: Type.label.copyWith(
                        color: DS.textPrimary.withValues(alpha: 0.85),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({required this.accent, required this.lit});

  final Color accent;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    const double tail = 26;
    const double notch = 14;

    // The folded tails behind, darker, so the banner reads as cloth with
    // something behind it rather than as a cut-out shape.
    for (final bool left in <bool>[true, false]) {
      final double x = left ? 0 : w;
      final double dir = left ? 1 : -1;
      final Path t = Path()
        ..moveTo(x + dir * tail * 0.4, h * 0.16)
        ..lineTo(x + dir * tail * 0.4, h * 0.86)
        ..lineTo(x - dir * tail * 0.55, h * 0.72)
        ..lineTo(x - dir * tail * 0.55, h * 0.30)
        ..close();
      canvas.drawPath(t, Paint()..color = DS.outline);
      canvas.drawPath(
        t.shift(Offset(dir * 2, 0)),
        Paint()..color = Color.lerp(accent, DS.outline, 0.45)!,
      );
    }

    // The plate: a rectangle with swallowtail ends.
    final Path plate = Path()
      ..moveTo(tail, 0)
      ..lineTo(w - tail, 0)
      ..lineTo(w, 0)
      ..lineTo(w - notch, h / 2)
      ..lineTo(w, h)
      ..lineTo(tail, h)
      ..lineTo(0, h)
      ..lineTo(notch, h / 2)
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = DS.stroke * 2
        ..strokeJoin = StrokeJoin.round
        ..color = DS.outline,
    );
    canvas.drawPath(
      plate,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, h),
          <Color>[
            Color.lerp(accent, const Color(0xFFFFFFFF), lit ? 0.22 : 0.05)!,
            Color.lerp(accent, DS.outline, 0.42)!,
          ],
        ),
    );
    // A highlight along the top fold.
    canvas.drawLine(
      Offset(notch + 6, 5),
      Offset(w - notch - 6, 5),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFFFFF).withValues(alpha: lit ? 0.30 : 0.10),
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.accent != accent || old.lit != lit;
}

// -------------------------------------------------------------------- road

/// Scenery.
///
/// The road used to run down an empty black field, which made a thousand
/// levels feel like a spreadsheet with a line drawn on it. This fills the
/// margins either side with vessels, drifting motes and faint contour rings —
/// the game's own vocabulary rather than trees and clouds borrowed from
/// somewhere else.
///
/// Every piece is a pure function of the row index, so it is deterministic
/// (the same level always has the same scenery, and scrolling back does not
/// reshuffle it), costs no state, and needs no layout pass. It is drawn behind
/// the track and never inside the corridor the nodes occupy.
class _SceneryPainter extends CustomPainter {
  _SceneryPainter({required this.index, required this.walked});

  /// The level's own id — the seed for everything here.
  final int index;

  /// Behind the player, the scenery picks up the road's warmth.
  final bool walked;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final math.Random r = math.Random(index * 2654435761 & 0x7FFFFFFF);

    final Color tint = walked
        ? DS.goldDeep.withValues(alpha: 0.11)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.05);

    // --- a contour ring, occasionally -------------------------------------
    if (r.nextInt(3) == 0) {
      final bool left = r.nextBool();
      final Offset c = Offset(left ? w * 0.12 : w * 0.88, h * r.nextDouble());
      final double rad = w * (0.10 + r.nextDouble() * 0.14);
      for (int k = 0; k < 2; k++) {
        canvas.drawCircle(
          c,
          rad + k * w * 0.05,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = tint.withValues(alpha: tint.a * (0.7 - k * 0.3)),
        );
      }
    }

    // --- a small vessel in the margin --------------------------------------
    if (r.nextInt(4) == 0) {
      final bool left = r.nextBool();
      final double vw = w * (0.045 + r.nextDouble() * 0.02);
      final double vh = vw * 2.6;
      final Rect body = Rect.fromLTWH(
        left ? w * 0.06 : w * 0.90,
        h * 0.2 + r.nextDouble() * h * 0.4,
        vw,
        vh,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          body,
          topLeft: Radius.circular(vw * 0.22),
          topRight: Radius.circular(vw * 0.22),
          bottomLeft: Radius.circular(vw * 0.46),
          bottomRight: Radius.circular(vw * 0.46),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = tint,
      );
      // A hint of contents, so it reads as one of the game's vessels rather
      // than as a rounded rectangle.
      if (walked) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(body.left, body.bottom - vh * 0.34, vw, vh * 0.34),
            Radius.circular(vw * 0.4),
          ),
          Paint()..color = DS.hues[index % DS.hues.length].base.withValues(alpha: 0.16),
        );
      }
    }

    // --- motes -------------------------------------------------------------
    final int motes = 2 + r.nextInt(3);
    for (int i = 0; i < motes; i++) {
      // Kept out of the middle third, where the nodes and the track live.
      final double x = r.nextBool()
          ? w * (0.03 + r.nextDouble() * 0.16)
          : w * (0.81 + r.nextDouble() * 0.16);
      canvas.drawCircle(
        Offset(x, h * r.nextDouble()),
        1.0 + r.nextDouble() * 1.6,
        Paint()..color = tint.withValues(alpha: tint.a * (0.6 + r.nextDouble() * 0.8)),
      );
    }
  }

  @override
  bool shouldRepaint(_SceneryPainter old) =>
      old.index != index || old.walked != walked;
}

/// One level's slice of the map: the track running through it, and its node.
///
/// Each row paints only its own half-segments — from the midpoint above it to
/// the midpoint below — which is what makes a continuous road out of a list
/// that only ever builds the rows on screen.
class _PathRow extends StatelessWidget {
  const _PathRow({
    required this.row,
    required this.width,
    required this.walked,
    required this.pulse,
    required this.node,
  });

  final _NodeRow row;
  final double width;

  /// True once the player has reached this level — the track behind them is
  /// lit, the track ahead is not.
  final bool walked;

  final Animation<double> pulse;
  final Widget node;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _nodeRow,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SceneryPainter(index: row.id, walked: walked),
                    foregroundPainter: _TrackPainter(row: row, walked: walked),
                  ),
                ),
              ),
            ),
            Positioned(
              left: row.x * width - _nodeSize / 2,
              top: (_nodeRow - _nodeSize) / 2,
              width: _nodeSize,
              height: _nodeSize,
              child: node,
            ),
          ],
        ),
      );
}

/// The road surface.
///
/// Two strokes: a wide dark groove that reads as a channel cut into the
/// ground, and a narrower coloured line inside it. Ahead of the player the
/// inner line is dashed and dim — a route that exists but has not been taken.
class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.row, required this.walked});

  final _NodeRow row;
  final bool walked;

  static const double _grooveWidth = 22;
  static const double _lineWidth = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset here = Offset(row.x * w, h / 2);

    final Path path = Path();
    bool any = false;

    if (row.prevX != null) {
      final Offset up = Offset((row.prevX! + row.x) / 2 * w, 0);
      path.moveTo(up.dx, up.dy);
      // Control point on the node's own horizontal, so successive rows meet
      // with matching tangents and the joins are invisible.
      path.quadraticBezierTo(here.dx, h * 0.25, here.dx, here.dy);
      any = true;
    }
    if (row.nextX != null) {
      final Offset down = Offset((row.x + row.nextX!) / 2 * w, h);
      // Continues the existing subpath when there was one above, so the road
      // through this row is a single stroke and the dashes below stay in step
      // with the dashes above.
      if (!any) path.moveTo(here.dx, here.dy);
      path.quadraticBezierTo(here.dx, h * 0.75, down.dx, down.dy);
      any = true;
    }
    if (!any) return;

    // The road's own outline, drawn widest and first.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _grooveWidth + DS.stroke * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = DS.outline,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _grooveWidth - 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = DS.surfaceRaised.withValues(alpha: walked ? 0.95 : 0.7),
    );

    if (walked) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _lineWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = ui.Gradient.linear(
            Offset(0, 0),
            Offset(0, h),
            <Color>[
              DS.goldDeep.withValues(alpha: 0.85),
              DS.gold.withValues(alpha: 0.65),
            ],
          ),
      );
    } else {
      // Dashed, and only just visible. The road ahead should be legible as a
      // route without competing with the node the player is meant to press.
      _dash(
        canvas,
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _lineWidth - 1.5
          ..strokeCap = StrokeCap.round
          ..color = DS.textTertiary.withValues(alpha: 0.35),
      );
    }
  }

  /// Strokes [path] as a dashed line. Flutter has no dash support on Paint, and
  /// walking the metrics is both the standard workaround and cheap at this
  /// length.
  static void _dash(Canvas canvas, Path path, Paint paint) {
    const double on = 9;
    const double off = 9;
    for (final ui.PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), paint);
        d += on + off;
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.walked != walked ||
      old.row.x != row.x ||
      old.row.prevX != row.prevX ||
      old.row.nextX != row.nextX;
}

// ------------------------------------------------------------------- nodes

/// One level on the road.
///
/// Four states, each with its own read at a glance rather than its own label:
/// cleared nodes carry the colour of how well they were cleared, the current
/// node is the only thing on the screen that moves, unlocked-but-unplayed
/// nodes are plain, and locked nodes recede.
class _LevelNode extends StatefulWidget {
  const _LevelNode({
    required this.id,
    required this.cleared,
    required this.unlocked,
    required this.isCurrent,
    required this.grade,
    required this.best,
    required this.pulse,
    required this.onTap,
  });

  final int id;
  final bool cleared;
  final bool unlocked;
  final bool isCurrent;
  final ClearGrade? grade;
  final int? best;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  State<_LevelNode> createState() => _LevelNodeState();
}

class _LevelNodeState extends State<_LevelNode> with TickerProviderStateMixin, PressMixin {
  Color get _accent {
    if (widget.isCurrent) return DS.gold;
    if (widget.cleared) {
      return switch (widget.grade) {
        ClearGrade.flawless => DS.gold,
        ClearGrade.great => DS.aqua,
        _ => DS.aquaDeep,
      };
    }
    return widget.unlocked ? DS.textSecondary : DS.textTertiary;
  }

  /// How many stars a cleared level shows. Three tiers, and a cleared level
  /// always shows at least one — the grade says how *well*, never whether.
  int get _stars => switch (widget.grade) {
        ClearGrade.flawless => 3,
        ClearGrade.great => 2,
        ClearGrade.clear => 1,
        null => 0,
      };

  @override
  Widget build(BuildContext context) {
    final Color accent = _accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => pressDown(),
      onTapCancel: pressUp,
      onTapUp: (_) => pressUp(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[press, if (widget.isCurrent) widget.pulse]),
        builder: (BuildContext context, _) {
          final double t = widget.isCurrent ? widget.pulse.value : 0.0;
          final double breathe = widget.isCurrent ? 0.5 + 0.5 * math.sin(t * math.pi * 2) : 0.0;
          // The one node the player is meant to press bobs. Nothing else on
          // the screen moves, so the eye goes there without being told.
          final double bob = widget.isCurrent ? math.sin(t * math.pi * 2) * 3.0 : 0.0;

          return Transform.translate(
            offset: Offset(0, bob),
            child: Transform.scale(
              scale: (1 - press.value.clamp(0.0, 1.0) * 0.07) *
                  (widget.isCurrent ? 1.14 : 1.0),
              child: CustomPaint(
                painter: _NodePainter(
                  accent: accent,
                  cleared: widget.cleared,
                  unlocked: widget.unlocked,
                  isCurrent: widget.isCurrent,
                  breathe: breathe,
                  spin: t,
                  stars: _stars,
                ),
                child: Center(
                  child: widget.unlocked
                      ? Text(
                          '${widget.id}',
                          style: Type.numeral.copyWith(
                            fontSize: widget.id > 999 ? 18 : 22,
                            color: widget.isCurrent ? DS.gold : DS.textPrimary,
                            shadows: <Shadow>[
                              Shadow(color: DS.outline, blurRadius: 0, offset: const Offset(0, 2)),
                            ],
                          ),
                        )
                      : DIcon(DIcons.lock,
                          size: 18, color: DS.textTertiary.withValues(alpha: 0.8)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A level on the road, drawn as an object rather than a disc.
///
/// The node used to be a circle with a number in it. That is a diagram. A
/// level on a game map is a *thing*: it has a frame, it carries its result
/// where the eye lands first, and the one you are meant to press announces
/// itself. Three treatments, and they differ in construction rather than only
/// in colour:
///
///   locked    a flat slug, sunk into the road, no frame
///   cleared   a framed medallion with its stars above it
///   current   a gold-crowned medallion with rays turning behind it
class _NodePainter extends CustomPainter {
  _NodePainter({
    required this.accent,
    required this.cleared,
    required this.unlocked,
    required this.isCurrent,
    required this.breathe,
    required this.spin,
    required this.stars,
  });

  final Color accent;
  final bool cleared;
  final bool unlocked;
  final bool isCurrent;
  final double breathe;

  /// 0..1, one full turn of the rays behind the current node.
  final double spin;

  /// 0-3, shown above a cleared node.
  final int stars;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;

    if (isCurrent) _paintRays(canvas, c, r);

    // --- the drop the node sits in ----------------------------------------
    canvas.drawCircle(
      c + Offset(0, r * 0.16),
      r * 0.92,
      Paint()
        ..color = DS.outline.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18),
    );

    // --- outline, then body -----------------------------------------------
    final double body = r * 0.82;
    canvas.drawCircle(c, body + DS.stroke, Paint()..color = DS.outline);
    canvas.drawCircle(
      c,
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, c.dy - body),
          Offset(c.dx, c.dy + body),
          <Color>[
            Color.lerp(DS.surfaceHigh, accent, unlocked ? 0.22 : 0.04)!,
            Color.lerp(DS.ink, accent, unlocked ? 0.06 : 0.0)!,
          ],
        ),
    );

    // A bright arc along the top inside edge — the node catches the same
    // light as everything else in the game.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: body * 0.86),
      math.pi * 1.15,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = body * 0.10
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFFFFF).withValues(alpha: unlocked ? 0.16 : 0.05),
    );

    // --- the frame ---------------------------------------------------------
    if (cleared || isCurrent) _paintFrame(canvas, c, body);

    // --- stars -------------------------------------------------------------
    if (stars > 0) _paintStars(canvas, c, r);
  }

  /// Rays turning behind the one node the player should press. Slow, and
  /// alternating long and short so it reads as a burst rather than a fan.
  void _paintRays(Canvas canvas, Offset c, double r) {
    const int count = 12;
    final double glow = 0.20 + breathe * 0.14;
    canvas.drawCircle(
      c,
      r * (1.45 + breathe * 0.22),
      Paint()
        ..color = DS.gold.withValues(alpha: glow * 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(spin * math.pi * 0.5);
    for (int i = 0; i < count; i++) {
      final double a = i * 2 * math.pi / count;
      final double len = r * (i.isEven ? 1.62 : 1.34);
      final Path ray = Path()
        ..moveTo(math.cos(a - 0.07) * r * 0.95, math.sin(a - 0.07) * r * 0.95)
        ..lineTo(math.cos(a) * len, math.sin(a) * len)
        ..lineTo(math.cos(a + 0.07) * r * 0.95, math.sin(a + 0.07) * r * 0.95)
        ..close();
      canvas.drawPath(
        ray,
        Paint()..color = DS.gold.withValues(alpha: (i.isEven ? 0.26 : 0.15) * (0.6 + breathe * 0.4)),
      );
    }
    canvas.restore();
  }

  /// A ring with studs around it — the detail that makes a node read as a
  /// minted object rather than a stroked circle.
  void _paintFrame(Canvas canvas, Offset c, double body) {
    final double ring = body + DS.stroke * 0.5;
    canvas.drawCircle(
      c,
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCurrent ? 4.0 : 3.0
        ..color = accent,
    );
    canvas.drawCircle(
      c,
      ring - 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: 0.35),
    );
    final int studs = isCurrent ? 12 : 8;
    for (int i = 0; i < studs; i++) {
      final double a = i * 2 * math.pi / studs - math.pi / 2;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * ring,
        isCurrent ? 2.6 : 2.0,
        Paint()..color = accent,
      );
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * ring,
        isCurrent ? 1.3 : 1.0,
        Paint()..color = DS.outline.withValues(alpha: 0.5),
      );
    }
  }

  /// Stars, arched over the node.
  ///
  /// The design notes argued against stars on the clear sheet — a row of them
  /// implies an incomplete result whenever the player does not get three. On
  /// a *map* the argument inverts: the player is looking back at forty levels
  /// at once and wants to see, at a glance, which ones are worth returning
  /// to. Nothing else reads that fast.
  void _paintStars(Canvas canvas, Offset c, double r) {
    final double arc = r * 0.94;
    for (int i = 0; i < 3; i++) {
      final double a = -math.pi / 2 + (i - 1) * 0.52;
      final Offset p = c + Offset(math.cos(a), math.sin(a)) * arc;
      final bool earned = i < stars;
      _star(
        canvas,
        p,
        earned ? 7.2 : 5.6,
        earned ? DS.gold : DS.ink.withValues(alpha: 0.75),
      );
    }
  }

  void _star(Canvas canvas, Offset c, double radius, Color colour) {
    final Path p = Path();
    for (int i = 0; i < 10; i++) {
      final double a = -math.pi / 2 + i * math.pi / 5;
      final double rr = i.isEven ? radius : radius * 0.46;
      final Offset pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = DS.stroke
        ..strokeJoin = StrokeJoin.round
        ..color = DS.outline,
    );
    canvas.drawPath(p, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_NodePainter old) =>
      old.accent != accent ||
      old.cleared != cleared ||
      old.unlocked != unlocked ||
      old.isCurrent != isCurrent ||
      old.stars != stars ||
      old.spin != spin ||
      old.breathe != breathe;
}

// ----------------------------------------------------------------- horizon

/// Where the road stops.
///
/// Not an error state and not a paywall — the point is to make the edge of the
/// map read as *more road*, so the last thing the player sees on this screen
/// is the name of the chapter they are working toward.
class _Horizon extends StatelessWidget {
  const _Horizon({required this.row});

  final _HorizonRow row;

  /// How far down the row the road stub runs before it has fully faded.
  static const double _stub = 78;

  @override
  Widget build(BuildContext context) {
    final Chapter? next = row.nextChapter;

    return SizedBox(
      height: _footerRow,
      child: Column(
        children: <Widget>[
          // The road carrying on and dissolving, drawn from where the last
          // node actually sat. Centring this under the page instead — which is
          // what it did first — leaves the pips floating unattached to a road
          // that ended two thirds of the way to the left.
          SizedBox(
            height: _stub,
            width: double.infinity,
            child: CustomPaint(painter: _HorizonPainter(row)),
          ),
          const SizedBox(height: DS.s12),
          if (next != null) ...<Widget>[
            Text(
              'NEXT · CHAPTER ${next.number.toString().padLeft(2, '0')}',
              style: Type.label.copyWith(color: DS.textTertiary, letterSpacing: 1.4),
            ),
            const SizedBox(height: DS.s8),
            Text(next.name, style: Type.bodyStrong.copyWith(color: DS.textSecondary)),
          ] else
            Text(
              'The road ends here. Every level cleared.',
              style: Type.bodyStrong.copyWith(color: DS.gold),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// The last of the road: a stub that fades out, then three pips continuing
/// along the line it was travelling.
class _HorizonPainter extends CustomPainter {
  _HorizonPainter(this.row);

  final _HorizonRow row;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Same construction as a normal row's lower half, so the join at the top
    // edge is invisible.
    final Offset from = Offset(row.fromX * w, 0);
    final Offset toward = Offset((row.fromX + row.toX) / 2 * w, h * 0.42);

    final Path stub = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(from.dx, h * 0.18, toward.dx, toward.dy);

    canvas.drawPath(
      stub,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _TrackPainter._grooveWidth - 3
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, toward.dy),
          <Color>[
            DS.surfaceRaised.withValues(alpha: 0.7),
            DS.surfaceRaised.withValues(alpha: 0.0),
          ],
        ),
    );

    // Three pips, shrinking and dimming, carrying on in the same direction.
    final Offset step = Offset(
      (toward.dx - from.dx) * 0.30,
      (toward.dy) * 0.30,
    );
    for (int i = 0; i < 3; i++) {
      final Offset c = toward + step * (i + 1).toDouble();
      canvas.drawCircle(
        c,
        3.4 - i * 0.8,
        Paint()..color = DS.textTertiary.withValues(alpha: 0.32 - i * 0.09),
      );
    }
  }

  @override
  bool shouldRepaint(_HorizonPainter old) =>
      old.row.fromX != row.fromX || old.row.toX != row.toX;
}
