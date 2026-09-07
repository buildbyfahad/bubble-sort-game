import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/board_state.dart';
import '../../engine/game_controller.dart';
import 'bubble.dart';
import 'tube.dart';

/// Resolved layout for one board: how big a ball is, how the vessels are
/// arranged, and where every slot sits in board coordinates.
///
/// Computed once per constraint change and shared by the vessels and the
/// flight overlay, so a ball in the air and a ball at rest are guaranteed to
/// agree on where "slot 2 of vessel 5" is.
class BoardLayout {
  BoardLayout({required this.tubeCount, required this.capacity, required this.available}) {
    // Try every sensible row count and keep whichever yields the largest ball.
    //
    // A fixed rule ("two rows above five vessels") is wrong once boards get
    // wide: fourteen vessels across three rows is height-bound and produces a
    // smaller ball than the same fourteen across two. Solving for the best
    // arrangement instead means one piece of code handles a four-vessel
    // tutorial and a fourteen-vessel finale equally well.
    const double gapRatio = 0.34;
    // Rows need real separation once boards stack three deep: each row
    // reserves headroom for lifted stacks, and a hairline gap lets a lifted
    // ball read as belonging to the row above it.
    const double rowGapRatio = 0.26;

    // Ball size cap.
    //
    // Was 54, which on a four- or five-vessel board produced vessels so large
    // they read as a different game from the ten-vessel boards later on. The
    // board should look like one object at every size; a cap this high made
    // early levels look like a children's version of the same app.
    const double maxBall = 46.0;

    // Below this a ball stops being comfortably tappable and the colour is
    // hard to read at arm's length, so wrapping to another row is the better
    // trade even on a small board.
    const double minBall = 26.0;

    // Boards up to this size are always laid out in a single row.
    //
    // The row solver below optimises for ball size, and on five vessels that
    // means two rows of three-and-two — which is a few per cent larger and
    // looks broken, because a lone pair beneath a row of three reads as a
    // mistake rather than as a layout. Under about six vessels the eye wants
    // one line and will accept smaller balls to get it.
    const int singleRowMax = 6;

    double ballFor(int r) {
      final int cols = (tubeCount / r).ceil();
      if (cols * r - tubeCount >= cols) return 0; // an entirely empty last row
      final double widthUnits = cols * 1.46 + (cols - 1) * gapRatio;
      final double heightUnits =
          r * (capacity * 1.04 + 0.40 + 1.20) + (r - 1) * rowGapRatio;
      return math.min(
        math.min(available.width / widthUnits, available.height / heightUnits),
        maxBall,
      );
    }

    const int maxRows = 4;
    double bestBall = 0;
    for (int r = 1; r <= maxRows; r++) {
      bestBall = math.max(bestBall, ballFor(r));
    }

    // Then take the *fewest* rows that come close to that best.
    //
    // Maximising ball size alone is the wrong objective. On a four-vessel
    // board the size cap binds long before the width does, so splitting into
    // two rows of two wins by a few percent - and looks broken, because the
    // two spare vessels end up marooned on a row of their own. One row is
    // obviously right there. The tolerance keeps that preference while still
    // wrapping when wrapping genuinely buys something, as it does the moment a
    // board runs past about six vessels.
    const double tolerance = 0.92;
    int chosenRows = maxRows;
    for (int r = 1; r <= maxRows; r++) {
      if (ballFor(r) >= bestBall * tolerance) {
        chosenRows = r;
        break;
      }
    }

    // Small boards override the solver entirely, provided one row still leaves
    // the balls big enough to touch.
    if (tubeCount <= singleRowMax && ballFor(1) >= minBall) chosenRows = 1;

    rows = chosenRows;

    perRow = (tubeCount / rows).ceil();
    ball = ballFor(rows);

    // How many vessels sit on each row, distributed as evenly as possible.
    //
    // Filling rows to `ceil(n/rows)` and letting the last row take what is
    // left puts thirteen vessels on rows of 5, 5 and 3 — a short final row
    // reads as something that ran out rather than as a composition. Spreading
    // the remainder gives 5, 4, 4.
    rowCounts = <int>[];
    final int base = tubeCount ~/ rows;
    final int extra = tubeCount % rows;
    for (int r = 0; r < rows; r++) {
      rowCounts.add(base + (r < extra ? 1 : 0));
    }

    metrics = TubeMetrics(ball, capacity);
    gap = ball * gapRatio;
    rowGap = ball * rowGapRatio;

    final double totalH = rows * metrics.totalHeight + (rows - 1) * rowGap;
    // Centre the *vessels*, not the layout box. The box also contains the
    // headroom reserved above the top row for lifted stacks, and centring that
    // pushes the visible board low in a way the eye reads as misaligned.
    //
    // Clamped at zero, because that optical shift is a luxury and the headroom
    // is not. On a height-bound board the ball size is solved so the layout is
    // exactly as tall as the space available, so the shift has nothing to give
    // and simply pushes the top row's lift zone off the top of the board — at
    // which point selecting a vessel in the first row throws its stack over
    // the status line and into the top bar.
    final double top =
        math.max(0, (available.height - totalH) / 2 - metrics.liftZone / 2);

    origins = <Offset>[];
    int index = 0;
    for (int row = 0; row < rows; row++) {
      final int inRow = rowCounts[row];
      final double rowW = inRow * metrics.width + (inRow - 1) * gap;
      final double rowLeft = (available.width - rowW) / 2;
      for (int col = 0; col < inRow; col++) {
        origins.add(Offset(
          rowLeft + col * (metrics.width + gap),
          top + row * (metrics.totalHeight + rowGap),
        ));
        index++;
      }
    }
    assert(index == tubeCount, 'every vessel must be placed exactly once');
  }

  final int tubeCount;
  final int capacity;
  final Size available;

  late final int rows;
  late final int perRow;

  /// Vessels on each row, most-populated first. See the constructor.
  late final List<int> rowCounts;
  late final double ball;
  late final double gap;
  late final double rowGap;
  late final TubeMetrics metrics;
  late final List<Offset> origins;

  Offset slotCenter(int tube, int slot) => origins[tube] + metrics.ballCenter(slot);
  Offset liftedCenter(int tube, int k) => origins[tube] + metrics.liftCenter(k);
  double rimTop(int tube) => origins[tube].dy;
}

/// The board: vessels laid out to fit, plus the overlay that carries balls
/// between them.
class BoardView extends StatelessWidget {
  const BoardView({super.key, required this.controller, required this.colorAssist, this.guideTube});

  final GameController controller;
  final bool colorAssist;

  /// Vessel the first-run guide is pointing at, if any.
  final int? guideTube;

  @override
  Widget build(BuildContext context) {
    // The board subscribes to its own controller rather than trusting an
    // ancestor to rebuild it. Anything that owns game state and paints it
    // should be self-sufficient; the alternative is a board that silently
    // stops animating the moment it is used somewhere new.
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final BoardLayout layout = BoardLayout(
            tubeCount: controller.level.tubeCount,
            capacity: controller.level.capacity,
            available: Size(c.maxWidth, c.maxHeight),
          );

          final BoardState state = controller.state;
          final List<List<int>> visible = controller.visibleTubes;
          final Pour? flight = controller.flight;
          final int? selected = controller.selected;

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              for (int i = 0; i < layout.tubeCount; i++)
                Positioned(
                  left: layout.origins[i].dx,
                  top: layout.origins[i].dy,
                  // One layer per vessel. Without this, the flight overlay
                  // animating at 60fps repaints the entire board — every
                  // vessel, every ball, every pane of glass — on every frame
                  // of every pour, which on a fourteen-vessel board is the
                  // single largest avoidable cost in the game.
                  child: RepaintBoundary(
                    child: Tube(
                      contents: visible[i],
                      metrics: layout.metrics,
                      selected: selected == i,
                      liftCount: selected == i ? state.topRun(i) : 0,
                      sealed: state.isSealed(i) && flight?.to != i,
                      colorAssist: colorAssist,
                      rejectToken: controller.rejected == i ? controller.rejectToken : -1,
                      settleToken: _settleTokenFor(i),
                      settleCount: _settleCountFor(i),
                      sealToken: controller.justSealed.contains(i) ? controller.sealToken : -1,
                      // Vessel index and level id together, so no two vessels on
                      // a board crack alike and no level is a repeat of the last.
                      fractureSeed: i * 31 + controller.level.id * 7,
                      hinted: controller.hint?.to == i,
                      // Finished vessels step back so attention stays on the
                      // unsolved ones, without them disappearing.
                      dim: state.isSealed(i) && flight?.to != i ? 0.20 : 0.0,
                      onTap: () => controller.tapTube(i),
                    ),
                  ),
                ),
              if (guideTube != null && guideTube! < layout.tubeCount)
                Positioned(
                  left: layout.origins[guideTube!].dx,
                  top: layout.origins[guideTube!].dy,
                  width: layout.metrics.width,
                  height: layout.metrics.totalHeight,
                  child: IgnorePointer(child: _TapGuide(metrics: layout.metrics)),
                ),
              if (flight != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _FlightOverlay(
                      key: ValueKey<int>(controller.flightToken),
                      layout: layout,
                      pour: flight,
                      destBase: visible[flight.to].length,
                      colorAssist: colorAssist,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // The settle animation belongs to whichever vessel most recently received a
  // pour; -1 means "nothing to play".
  int _settleTokenFor(int i) {
    final Pour? last = controller.flight;
    if (last != null) return -1; // still in the air
    return controller.lastLandedTube == i ? controller.flightToken : -1;
  }

  int _settleCountFor(int i) => controller.lastLandedTube == i ? controller.lastLandedCount : 0;
}

/// Carries the balls of one pour from the mouth of the source vessel to the
/// floor of the destination.
///
/// The path is deliberately not a straight line and not a single curve: it
/// lifts, travels, then drops, with a different easing on each axis. That is
/// what reads as "poured" rather than "tweened" — a ball that slides
/// diagonally across the board is the single most common tell of a prototype.
class _FlightOverlay extends StatefulWidget {
  const _FlightOverlay({
    super.key,
    required this.layout,
    required this.pour,
    required this.destBase,
    required this.colorAssist,
  });

  final BoardLayout layout;
  final Pour pour;

  /// How many balls were already in the destination when the pour began.
  final int destBase;
  final bool colorAssist;

  @override
  State<_FlightOverlay> createState() => _FlightOverlayState();
}

class _FlightOverlayState extends State<_FlightOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: GameController.flightDuration,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardLayout l = widget.layout;
    final Pour p = widget.pour;
    final BubbleHue hue = DS.hues[p.hue];

    // Clear the taller of the two mouths with room to spare.
    final double apexY = math.min(l.rimTop(p.from), l.rimTop(p.to)) - l.ball * 0.15;

    // Later balls in the run leave slightly after the first, so a four-ball
    // pour arrives as a stream rather than a block.
    final double stagger = p.count > 1 ? math.min(0.09, 0.24 / (p.count - 1)) : 0.0;

    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        final List<Widget> balls = <Widget>[];
        for (int j = 0; j < p.count; j++) {
          final double start = j * stagger;
          final double t = ((_c.value - start) / (1 - start)).clamp(0.0, 1.0);

          final Offset from = l.liftedCenter(p.from, j);
          final Offset to = l.slotCenter(p.to, widget.destBase + j);
          final Offset pos = _path(from, to, apexY, t, l.ball);

          // A touch of scale-up at the apex sells the ball moving toward the
          // viewer as it clears the rim.
          final double arcHeight = math.sin(t.clamp(0.0, 1.0) * math.pi);
          final double scale = 1 + arcHeight * 0.06;

          balls.add(
            Positioned(
              left: pos.dx - l.ball / 2,
              top: pos.dy - l.ball / 2,
              child: Transform.scale(
                scale: scale,
                child: Bubble(
                  hue: hue,
                  size: l.ball,
                  colorAssist: widget.colorAssist,
                  elevation: 1 + arcHeight * 1.6,
                ),
              ),
            ),
          );
        }
        return Stack(clipBehavior: Clip.none, children: balls);
      },
    );
  }

  /// Three-phase path. Vertical and horizontal motion are eased separately and
  /// overlap only in the middle, which is what gives the arc its weight.
  Offset _path(Offset from, Offset to, double apexY, double t, double ball) {
    // Rise
    const double riseEnd = 0.30;
    // Cross
    const double crossStart = 0.16;
    const double crossEnd = 0.74;
    // Fall
    const double fallStart = 0.66;

    double y;
    if (t <= riseEnd) {
      y = _lerp(from.dy, apexY, Curves.easeOutCubic.transform(t / riseEnd));
    } else if (t >= fallStart) {
      final double f = (t - fallStart) / (1 - fallStart);
      y = _lerp(apexY, to.dy, Curves.easeInCubic.transform(f));
    } else {
      // A shallow lofted arc through the middle rather than a flat carry.
      final double m = (t - riseEnd) / (fallStart - riseEnd);
      y = apexY - math.sin(m * math.pi) * ball * 0.16;
    }

    final double cx = ((t - crossStart) / (crossEnd - crossStart)).clamp(0.0, 1.0);
    final double x = _lerp(from.dx, to.dx, Ease.emphasized.transform(cx));

    return Offset(x, y);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// First-run pointer: a soft dot with a single ring expanding out of it, sat
/// over the vessel the player should touch.
///
/// Deliberately not an illustrated hand. A drawn hand cursor is both a visual
/// register the rest of the game does not use and an instant tell of a
/// template — a tap indicator says the same thing in the game's own language.
class _TapGuide extends StatefulWidget {
  const _TapGuide({required this.metrics});

  final TubeMetrics metrics;

  @override
  State<_TapGuide> createState() => _TapGuideState();
}

class _TapGuideState extends State<_TapGuide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (BuildContext context, _) =>
        CustomPaint(painter: _TapGuidePainter(_c.value, widget.metrics)),
  );
}

class _TapGuidePainter extends CustomPainter {
  _TapGuidePainter(this.t, this.metrics);

  final double t;
  final TubeMetrics metrics;

  @override
  void paint(Canvas canvas, Size size) {
    // The guide traces the vessel's own silhouette rather than sitting on top
    // of its contents. A dot floating over the balls reads as a rendering
    // artefact; a halo on the outline reads as "this one".
    final Rect body = Rect.fromLTWH(0, metrics.liftZone, size.width, metrics.bodyHeight);
    RRect shape(double inflate) => RRect.fromRectAndCorners(
      body.inflate(inflate),
      topLeft: Radius.circular(size.width * 0.20 + inflate),
      topRight: Radius.circular(size.width * 0.20 + inflate),
      bottomLeft: Radius.circular(size.width * 0.46 + inflate),
      bottomRight: Radius.circular(size.width * 0.46 + inflate),
    );

    // A steady halo, so the target is legible at any moment of the cycle.
    final double breathe = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    canvas.drawRRect(
      shape(2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = DS.gold.withValues(alpha: 0.35 + breathe * 0.35),
    );

    // Plus one ring travelling outward per cycle.
    final double p = (t / 0.68).clamp(0.0, 1.0);
    if (p < 1) {
      final double e = Curves.easeOutCubic.transform(p);
      canvas.drawRRect(
        shape(2.5 + e * metrics.ball * 0.55),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1 - e * 0.65)
          ..color = DS.gold.withValues(alpha: 0.45 * (1 - e) * (1 - e)),
      );
    }
  }

  @override
  bool shouldRepaint(_TapGuidePainter old) => old.t != t;
}
