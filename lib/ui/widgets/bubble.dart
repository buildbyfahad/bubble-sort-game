import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// A single ball.
///
/// The brief here was "not a cheap circle, and not a shiny plastic toy". What
/// separates the two is where the light goes: a cheap circle is one flat fill,
/// a toy is one huge white blob. This paints a *satin* sphere — five stacked
/// passes that describe a real lighting setup:
///
///   1. a soft contact shadow on the surface below it
///   2. a body gradient lit from the upper-left
///   3. a bounce-light arc along the lower edge (light coming back up off the
///      vessel floor) — this is the pass that makes it read as three-dimensional
///   4. a terminator: subtle darkening right at the circumference
///   5. one small, soft specular highlight — deliberately understated
///
/// Everything is drawn with gradients rather than blur filters. Visually the
/// difference is negligible; on a mid-range Android phone with 28 of these on
/// screen it is the difference between a smooth board and a stuttering one.
class Bubble extends StatelessWidget {
  const Bubble({
    super.key,
    required this.hue,
    required this.size,
    this.colorAssist = false,
    this.elevation = 1.0,
    this.dim = 0.0,
  });

  final BubbleHue hue;
  final double size;

  /// Draws the hue's redundant shape marker.
  final bool colorAssist;

  /// Scales the cast shadow — a lifted ball throws a longer, softer one.
  final double elevation;

  /// 0 = fully lit, 1 = pushed back. Used to de-emphasise vessels that are not
  /// part of the current interaction.
  final double dim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BubblePainter(
          hue: hue,
          colorAssist: colorAssist,
          elevation: elevation,
          dim: dim,
        ),
        isComplex: true,
        willChange: false,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.hue,
    required this.colorAssist,
    required this.elevation,
    required this.dim,
  });

  final BubbleHue hue;
  final bool colorAssist;
  final double elevation;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final double d = size.shortestSide;
    final double r = d / 2;
    final Offset c = Offset(size.width / 2, size.height / 2);

    // 1 — contact shadow. Tinted with the ball's own deep tone rather than
    // black, so colours sit in the vessel instead of on top of it.
    final double shadowSpread = r * (0.86 + 0.30 * elevation);
    final Rect shadowRect = Rect.fromCenter(
      center: c + Offset(0, r * (0.62 + 0.34 * elevation)),
      width: shadowSpread * 2.0,
      height: shadowSpread * (0.86 - 0.28 * elevation),
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..shader = ui.Gradient.radial(
          shadowRect.center,
          shadowRect.width / 2,
          <Color>[
            hue.deep.withValues(alpha: 0.42 / (1 + elevation * 0.9)),
            hue.deep.withValues(alpha: 0.0),
          ],
          <double>[0.0, 1.0],
          TileMode.clamp,
          Matrix4.diagonal3Values(1, shadowRect.height / shadowRect.width, 1).storage,
        ),
    );

    final double lit = 1.0 - dim * 0.45;
    Color mix(Color a, double t) => Color.lerp(a, DS.inkDeep, dim * 0.35)!.withValues(
          alpha: a.a * lit.clamp(0.0, 1.0),
        );

    // 2 — body. Key light from upper-left; the gradient centre sits off-axis
    // and the radius runs past the edge so the terminator stays soft.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-r * 0.34, -r * 0.40),
          r * 1.32,
          <Color>[
            mix(hue.light, 0),
            mix(hue.base, 0),
            mix(hue.deep, 0),
          ],
          <double>[0.0, 0.48, 1.0],
        ),
    );

    // 3 — bounce light. A crescent of the hue's light tone hugging the lower
    // right, faked with an off-centre radial that only reaches the rim.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(r * 0.30, r * 0.62),
          r * 0.86,
          <Color>[
            hue.light.withValues(alpha: 0.0),
            hue.light.withValues(alpha: 0.30 * lit),
            hue.light.withValues(alpha: 0.0),
          ],
          <double>[0.30, 0.80, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );

    // 4 — terminator. Darkens only the outermost few percent, which is what
    // stops the sphere reading as a flat disc against the vessel glass.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          <Color>[
            hue.deep.withValues(alpha: 0.0),
            hue.deep.withValues(alpha: 0.0),
            hue.deep.withValues(alpha: 0.34),
          ],
          <double>[0.0, 0.80, 1.0],
        ),
    );

    // 5 — specular. Small, soft-edged, and offset toward the key light. A hard
    // white ellipse here is exactly what makes a ball look like moulded
    // plastic, so the falloff starts immediately.
    final Rect spec = Rect.fromCenter(
      center: c + Offset(-r * 0.33, -r * 0.42),
      width: r * 0.82,
      height: r * 0.60,
    );
    canvas.save();
    canvas.translate(spec.center.dx, spec.center.dy);
    canvas.rotate(-0.5);
    canvas.translate(-spec.center.dx, -spec.center.dy);
    canvas.drawOval(
      spec,
      Paint()
        ..shader = ui.Gradient.radial(
          spec.center,
          spec.width / 2,
          <Color>[
            const Color(0xFFFFFFFF).withValues(alpha: 0.46 * lit),
            const Color(0xFFFFFFFF).withValues(alpha: 0.10 * lit),
            const Color(0x00FFFFFF),
          ],
          <double>[0.0, 0.45, 1.0],
          TileMode.clamp,
          Matrix4.diagonal3Values(1, spec.height / spec.width, 1).storage,
        ),
    );
    canvas.restore();

    if (colorAssist) _paintGlyph(canvas, c, r, lit);
  }

  /// Redundant encoding for colour-vision deficiency. Kept at low contrast and
  /// small scale: it should be findable when you look for it and invisible
  /// when you are not.
  void _paintGlyph(Canvas canvas, Offset c, double r, double lit) {
    final Paint p = Paint()
      ..color = const Color(0xFF0B0D12).withValues(alpha: 0.34 * lit)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = const Color(0xFF0B0D12).withValues(alpha: 0.30 * lit);
    final double g = r * 0.40;

    switch (hue.glyph) {
      case HueGlyph.dot:
        canvas.drawCircle(c, g * 0.52, fill);
      case HueGlyph.ring:
        canvas.drawCircle(c, g * 0.72, p);
      case HueGlyph.bar:
        canvas.drawLine(c + Offset(-g, 0), c + Offset(g, 0), p);
      case HueGlyph.triangle:
        _poly(canvas, c, g, 3, -math.pi / 2, p);
      case HueGlyph.diamond:
        _poly(canvas, c, g, 4, -math.pi / 2, p);
      case HueGlyph.cross:
        canvas.drawLine(c + Offset(-g * 0.75, 0), c + Offset(g * 0.75, 0), p);
        canvas.drawLine(c + Offset(0, -g * 0.75), c + Offset(0, g * 0.75), p);
      case HueGlyph.chevron:
        final Path path = Path()
          ..moveTo(c.dx - g * 0.8, c.dy + g * 0.35)
          ..lineTo(c.dx, c.dy - g * 0.45)
          ..lineTo(c.dx + g * 0.8, c.dy + g * 0.35);
        canvas.drawPath(path, p);
      case HueGlyph.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: g * 1.35, height: g * 1.35),
            Radius.circular(g * 0.28),
          ),
          p,
        );
      case HueGlyph.arc:
        canvas.drawArc(
          Rect.fromCircle(center: c + Offset(0, g * 0.30), radius: g * 0.85),
          math.pi,
          math.pi,
          false,
          p,
        );
      case HueGlyph.dash:
        canvas.drawLine(c + Offset(-g, -g * 0.45), c + Offset(g, -g * 0.45), p);
        canvas.drawLine(c + Offset(-g, g * 0.45), c + Offset(g, g * 0.45), p);
      case HueGlyph.star:
        for (int i = 0; i < 3; i++) {
          final double a = -math.pi / 2 + i * math.pi / 3;
          canvas.drawLine(
            c + Offset(math.cos(a) * g * 0.85, math.sin(a) * g * 0.85),
            c - Offset(math.cos(a) * g * 0.85, math.sin(a) * g * 0.85),
            p,
          );
        }
      case HueGlyph.hex:
        _poly(canvas, c, g * 0.9, 6, -math.pi / 2, p);
    }
  }

  void _poly(Canvas canvas, Offset c, double radius, int sides, double start, Paint p) {
    final Path path = Path();
    for (int i = 0; i < sides; i++) {
      final double a = start + i * 2 * math.pi / sides;
      final Offset pt = c + Offset(math.cos(a) * radius, math.sin(a) * radius);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.hue != hue ||
      old.colorAssist != colorAssist ||
      old.elevation != elevation ||
      old.dim != dim;
}
