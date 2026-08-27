import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show SliverLayoutDimensions;
import 'package:flutter/widgets.dart';

import '../../data/level.dart';
import '../../data/level_catalog.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../transitions.dart';
import '../widgets/ambient_background.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import 'game_screen.dart';
import 'level_complete.dart' show ClearGrade, gradeFor;

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

const double _nodeRow = 104;
const double _bannerRow = 104;
const double _footerRow = 190;
const double _topPad = 8;

/// Node diameter, and how far the path swings off centre.
const double _nodeSize = 66;
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
  const LevelsScreen({super.key});

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
      scope.haptics.reject();
      scope.audio.reject();
      return;
    }
    scope.audio.whoosh();
    scope.haptics.select();
    Navigator.of(context).pushReplacement(riseRoute<void>(GameScreen(levelId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    return AmbientBackground(
      intensity: 0.85,
      child: SafeArea(
        child: Observes(
          listenables: <Listenable>[scope.progress],
          builder: (BuildContext context) {
            final _MapPlan plan = _planFor(scope);
            final int frontier = scope.progress.currentLevelId;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _MapHeader(
                  cleared: scope.progress.clearedCount,
                  total: scope.catalog.length,
                  chapter: scope.catalog.chapterOf(frontier),
                  onBack: () {
                    scope.audio.tap();
                    Navigator.of(context).pop();
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

class _MapHeader extends StatelessWidget {
  const _MapHeader({
    required this.cleared,
    required this.total,
    required this.chapter,
    required this.onBack,
  });

  final int cleared;
  final int total;
  final Chapter chapter;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, DS.s12),
        child: Row(
          children: <Widget>[
            GhostIconButton(icon: DIcons.back, semanticLabel: 'Back', onTap: onBack),
            Expanded(
              child: Column(
                children: <Widget>[
                  Text('THE ROAD', style: Type.labelBright),
                  const SizedBox(height: DS.s4),
                  Text('$cleared of $total cleared', style: Type.caption),
                ],
              ),
            ),
            const SizedBox(width: 44),
          ],
        ),
      );
}

// ----------------------------------------------------------------- banners

/// A chapter gate. Breaks the road, names the stretch ahead, and carries that
/// stretch's own completion count — so a player forty levels deep still has a
/// nearby, finishable target.
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
      padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, DS.s12),
      child: Opacity(
        opacity: reached ? 1 : 0.5,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _Rule(accent: accent, fadeToward: -1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DS.s12),
                  child: Text(
                    'CHAPTER ${chapter.number.toString().padLeft(2, '0')}',
                    style: Type.label.copyWith(color: accent, letterSpacing: 1.4),
                  ),
                ),
                Expanded(child: _Rule(accent: accent, fadeToward: 1)),
              ],
            ),
            const SizedBox(height: DS.s8),
            Text(
              chapter.name,
              style: Type.titleMd.copyWith(fontSize: 21),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DS.s8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (complete) ...<Widget>[
                  const DIcon(DIcons.check, size: 11, color: DS.aqua),
                  const SizedBox(width: DS.s4),
                ] else if (!reached) ...<Widget>[
                  const DIcon(DIcons.lock, size: 11, color: DS.textTertiary),
                  const SizedBox(width: DS.s4),
                ],
                Text(
                  '$cleared / ${chapter.length}',
                  style: Type.label.copyWith(color: accent, letterSpacing: 0.8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A hairline that fades out toward one end, so the banner reads as a gate the
/// road passes through rather than as a divider dropped on top of it.
class _Rule extends StatelessWidget {
  const _Rule({required this.accent, required this.fadeToward});

  final Color accent;

  /// -1 fades toward the left edge, 1 toward the right.
  final int fadeToward;

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fadeToward < 0 ? Alignment.centerLeft : Alignment.centerRight,
            end: fadeToward < 0 ? Alignment.centerRight : Alignment.centerLeft,
            colors: <Color>[
              accent.withValues(alpha: 0.0),
              accent.withValues(alpha: 0.30),
            ],
          ),
        ),
      );
}

// -------------------------------------------------------------------- road

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
                    painter: _TrackPainter(row: row, walked: walked),
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

  static const double _grooveWidth = 17;
  static const double _lineWidth = 6;

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

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _grooveWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = DS.inkDeep.withValues(alpha: 0.55),
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
          final double breathe =
              widget.isCurrent ? 0.5 + 0.5 * math.sin(widget.pulse.value * math.pi * 2) : 0.0;

          return Transform.scale(
            scale: (1 - press.value * 0.07) * (widget.isCurrent ? 1.10 : 1.0),
            child: CustomPaint(
              painter: _NodePainter(
                accent: accent,
                cleared: widget.cleared,
                unlocked: widget.unlocked,
                isCurrent: widget.isCurrent,
                breathe: breathe,
              ),
              child: Center(
                child: widget.unlocked
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '${widget.id}',
                            style: Type.numeral.copyWith(
                              fontSize: widget.id > 999 ? 17 : 20,
                              color: widget.isCurrent ? DS.gold : DS.textPrimary,
                            ),
                          ),
                          if (widget.cleared && widget.best != null)
                            Text(
                              '${widget.best}',
                              style: Type.label.copyWith(
                                fontSize: 9,
                                color: accent,
                                letterSpacing: 0.4,
                              ),
                            ),
                        ],
                      )
                    : DIcon(DIcons.lock, size: 17, color: DS.textTertiary.withValues(alpha: 0.8)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NodePainter extends CustomPainter {
  _NodePainter({
    required this.accent,
    required this.cleared,
    required this.unlocked,
    required this.isCurrent,
    required this.breathe,
  });

  final Color accent;
  final bool cleared;
  final bool unlocked;
  final bool isCurrent;
  final double breathe;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;

    // The current node throws light onto the road around it. It is the only
    // lit thing on the map, which is what makes "where am I" a non-question.
    if (isCurrent) {
      canvas.drawCircle(
        c,
        r * (1.5 + breathe * 0.34),
        Paint()
          ..color = DS.gold.withValues(alpha: 0.16 + breathe * 0.10)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
      );
      canvas.drawCircle(
        c,
        r * (1.02 + breathe * 0.20),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * (1 - breathe * 0.5)
          ..color = DS.gold.withValues(alpha: 0.45 * (1 - breathe)),
      );
    }

    // Contact shadow, so the medallion sits on the road rather than floating
    // over it.
    canvas.drawCircle(
      c + Offset(0, r * 0.18),
      r * 0.92,
      Paint()
        ..color = DS.inkDeep.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );

    // Body: lit from above, like everything else in the game.
    canvas.drawCircle(
      c,
      r * 0.88,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, c.dy - r),
          Offset(c.dx, c.dy + r),
          <Color>[
            Color.lerp(DS.surfaceHigh, accent, unlocked ? 0.16 : 0.02)!,
            DS.surface,
          ],
        ),
    );

    // Rim. Thickest and brightest on the node the player should press.
    canvas.drawCircle(
      c,
      r * 0.88,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCurrent ? 2.6 : (cleared ? 1.8 : 1.2)
        ..color = accent.withValues(alpha: unlocked ? (isCurrent ? 0.95 : 0.55) : 0.22),
    );

    // A cleared node gets a ring segment rather than a badge: it reads as a
    // completed gauge, and it does not cover the number the way a tick would.
    if (cleared) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.78),
        -math.pi / 2,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = accent.withValues(alpha: 0.30),
      );
    }

    // Specular pip, top-left. One highlight is what separates a disc from a
    // dome.
    canvas.drawCircle(
      c + Offset(-r * 0.30, -r * 0.36),
      r * 0.20,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: unlocked ? 0.10 : 0.04)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18),
    );
  }

  @override
  bool shouldRepaint(_NodePainter old) =>
      old.accent != accent ||
      old.cleared != cleared ||
      old.unlocked != unlocked ||
      old.isCurrent != isCurrent ||
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
