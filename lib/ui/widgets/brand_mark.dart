import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// The Bubble Sort mark, drawn at any size.
///
/// Three vessels holding sorted colour, with one ball caught mid-pour above
/// them. It is the same drawing at every scale the brand appears - the app
/// icon, the splash, and the menu - so the identity is one shape rather than a
/// family of lookalikes.
///
/// Two things make it survive being shrunk to a 48px launcher tile, which is
/// where most game marks fall apart:
///
///  * The vessels are **filled**, not outlined. Thin outlined glass turns to
///    grey mush below about 64px; solid capsules keep their silhouette down to
///    the smallest tile Android will ask for.
///  * There are exactly four elements, at three different heights. The
///    staggered tops give the mark an asymmetric, recognisable outline instead
///    of reading as a generic bar chart.
class BrandMark extends StatefulWidget {
  const BrandMark({
    super.key,
    this.size = 96,
    this.pourProgress = 0.86,
    this.showBall = true,
    this.animate = false,
  });

  final double size;

  /// Where the ball sits along its arc, 0 to 1. Fixed for static uses, so the
  /// launcher icon and the splash always show the same frame.
  ///
  /// The default sits late in the arc deliberately: near the apex the ball
  /// floats free of the vessels and reads as a stray dot, while near the end it
  /// is clearly about to drop into the emptiest one.
  final double pourProgress;

  final bool showBall;

  /// Loops the ball across the vessels. Used on the menu and the splash, where
  /// a mark that moves once, slowly, is the cheapest way to signal that a
  /// product was made rather than assembled - and it teaches the game's verb
  /// before the player has pressed anything.
  ///
  /// The fill levels deliberately stay put while it runs. Draining one vessel
  /// into another looks right for a single pass and then has to snap back at
  /// the top of the loop, which is far more noticeable than the loop itself.
  final bool animate;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 5200),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// The ball crosses during the first 45% of the cycle and rests for the
  /// remainder, so the mark is still far more often than it is moving.
  double get _progress {
    final AnimationController? c = _c;
    if (c == null) return widget.pourProgress;
    return (c.value / 0.45).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final Widget painted = RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _BrandMarkPainter(
            pourProgress: _progress,
            showBall: widget.showBall,
          ),
          isComplex: true,
        ),
      ),
    );

    final AnimationController? c = _c;
    if (c == null) return painted;
    return AnimatedBuilder(animation: c, builder: (BuildContext context, _) => painted);
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter({required this.pourProgress, required this.showBall});

  final double pourProgress;
  final bool showBall;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;

    // Layout on a 100-unit grid, then scale. Keeps the proportions identical
    // whether this is painted at 48px or 1024px.
    final double u = s / 100;

    // Equal-height vessels, varied fills.
    //
    // Staggering the vessel *tops* was the first attempt and it read as a bar
    // chart: the unfilled upper halves are close to the ground colour, so all
    // the eye keeps at small sizes is three coloured blocks of different
    // heights. Levelling the tops gives the mark one clean silhouette, and
    // moving the variation into the fill levels keeps it from looking static.
    final double vw = 19 * u;
    final double gap = 7 * u;
    final double baseY = 92 * u;
    final double vesselTop = 30 * u;
    final List<double> heights =
        List<double>.filled(3, baseY - vesselTop);
    final List<double> fillFrac = <double>[0.46, 0.74, 0.30];
    // Warm, cool, warm - so no two neighbours share a temperature and the mark
    // stays readable in greyscale.
    final List<List<Color>> inks = <List<Color>>[
      <Color>[DS.hues[1].light, DS.hues[1].base], // amber
      <Color>[DS.hues[3].light, DS.hues[3].base], // jade
      <Color>[DS.hues[6].light, DS.hues[6].base], // rose
    ];

    final double totalW = vw * 3 + gap * 2;
    final double x0 = (size.width - totalW) / 2;

    for (int i = 0; i < 3; i++) {
      final double left = x0 + i * (vw + gap);
      final double top = baseY - heights[i];
      final Rect body = Rect.fromLTWH(left, top, vw, heights[i]);
      final RRect vessel = RRect.fromRectAndCorners(
        body,
        topLeft: Radius.circular(vw * 0.30),
        topRight: Radius.circular(vw * 0.30),
        bottomLeft: Radius.circular(vw * 0.48),
        bottomRight: Radius.circular(vw * 0.48),
      );

      // Glass body: a solid, slightly lifted slab so the vessel exists as a
      // shape even where it holds nothing.
      canvas.drawRRect(
        vessel,
        Paint()
          ..shader = ui.Gradient.linear(
            body.topCenter,
            body.bottomCenter,
            <Color>[
              const Color(0xFF39435A),
              const Color(0xFF1B2130),
            ],
          ),
      );

      // Contents, clipped to the vessel.
      final double fillH = heights[i] * fillFrac[i];
      final Rect liquid = Rect.fromLTWH(left, baseY - fillH, vw, fillH);
      canvas.save();
      canvas.clipRRect(vessel);
      canvas.drawRRect(
        RRect.fromRectAndRadius(liquid, Radius.circular(vw * 0.42)),
        Paint()
          ..shader = ui.Gradient.linear(
            liquid.topCenter,
            liquid.bottomCenter,
            inks[i],
          ),
      );
      canvas.restore();

      // A single catch-light down the left wall. One soft band, never two hard
      // stripes - the same rule the in-game vessels follow.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + vw * 0.16, top + heights[i] * 0.10, vw * 0.15,
              heights[i] * 0.62),
          Radius.circular(vw * 0.09),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, top),
            Offset(0, top + heights[i]),
            <Color>[
              const Color(0x40FFFFFF),
              const Color(0x00FFFFFF),
            ],
          ),
      );

      // Bright rim across the mouth.
      canvas.drawLine(
        Offset(left + vw * 0.26, top + 1.1 * u),
        Offset(left + vw * 0.74, top + 1.1 * u),
        Paint()
          ..strokeWidth = 1.6 * u
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x59FFFFFF),
      );
    }

    if (!showBall) return;

    // The ball mid-pour: the one element that says this is a game about
    // moving colour, not a chart.
    // Held just above the emptiest vessel, close enough that it reads as
    // about to drop in rather than as a stray dot in the corner.
    final double srcX = x0 + vw / 2;
    final double dstX = x0 + 2 * (vw + gap) + vw / 2;
    final double x = srcX + (dstX - srcX) * Ease.emphasized.transform(pourProgress);
    // Rests just above the rim at either end and lifts through the middle, so
    // the travel reads as a pour rather than a slide.
    final double hover = vesselTop - 9.5 * u;
    final double y = hover - math.sin(pourProgress * math.pi) * 7.0 * u;

    final double r = 8.6 * u;
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(x - r * 0.34, y - r * 0.40),
          r * 1.3,
          <Color>[DS.goldSoft, DS.gold, DS.goldDeep],
          <double>[0.0, 0.48, 1.0],
        ),
    );
    // Specular, matching the in-game balls.
    canvas.drawCircle(
      Offset(x - r * 0.32, y - r * 0.38),
      r * 0.30,
      Paint()..color = const Color(0x8CFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) =>
      old.pourProgress != pourProgress || old.showBall != showBall;
}

/// The ink plate the mark sits on for the launcher icon and splash.
///
/// A warm off-centre glow over the app's own ground colour, so the icon shares
/// its lighting with the first screen the player sees rather than being a flat
/// coloured square with a logo pasted on.
class BrandPlate extends StatelessWidget {
  const BrandPlate({super.key, required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _PlatePainter(),
          child: Center(child: child),
        ),
      );
}

class _PlatePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = DS.ink);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.28, size.height * 0.20),
          size.width * 0.95,
          <Color>[
            DS.gold.withValues(alpha: 0.20),
            DS.gold.withValues(alpha: 0.05),
            const Color(0x00000000),
          ],
          <double>[0.0, 0.42, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.85, size.height * 0.92),
          size.width * 0.8,
          <Color>[
            DS.aqua.withValues(alpha: 0.10),
            const Color(0x00000000),
          ],
        )
        ..blendMode = BlendMode.plus,
    );

    // Vignette, so the plate reads as lit rather than tinted.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.46),
          math.max(size.width, size.height) * 0.75,
          <Color>[
            const Color(0x00000000),
            const Color(0x00000000),
            DS.inkDeep.withValues(alpha: 0.55),
          ],
          <double>[0.0, 0.55, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_PlatePainter old) => false;
}
