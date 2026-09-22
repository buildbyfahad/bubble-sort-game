import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/cosmetics.dart';
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
    this.hidden = false,
    this.style = BallStyle.classic,
  });

  /// The equipped look. Every style keeps the hue exactly — a cosmetic that
  /// changed the colours would change the puzzle.
  final BallStyle style;

  /// Concealed: drawn as an unlit glass sphere with a question mark, in no
  /// colour at all. The hue is still passed so the widget's identity is
  /// stable when it is revealed, but nothing about it may leak through — a
  /// tint would turn a memory puzzle back into a matching one.
  final bool hidden;

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
    if (hidden) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HiddenBubblePainter(dim: dim)),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BubblePainter(
          hue: hue,
          colorAssist: colorAssist,
          elevation: elevation,
          dim: dim,
          style: style,
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
    required this.style,
  });

  final BubbleHue hue;
  final bool colorAssist;
  final double elevation;
  final double dim;
  final BallStyle style;

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

    // The other looks each own their whole render after the shadow. They are
    // separate lighting models, not tweaks to this one, and sharing passes
    // between them is how every style ends up looking like the classic with
    // a sticker on it.
    switch (style) {
      case BallStyle.classic:
        break;
      case BallStyle.candy:
        _paintCandy(canvas, c, r, lit, mix);
        if (colorAssist) _paintGlyph(canvas, c, r, lit);
        return;
      case BallStyle.ink:
        _paintInk(canvas, c, r, lit, mix);
        if (colorAssist) _paintGlyph(canvas, c, r, lit);
        return;
      case BallStyle.gem:
        _paintGem(canvas, c, r, lit, mix);
        if (colorAssist) _paintGlyph(canvas, c, r, lit);
        return;
      case BallStyle.neon:
        _paintNeon(canvas, c, r, lit, mix);
        if (colorAssist) _paintGlyph(canvas, c, r, lit);
        return;
      case BallStyle.planet:
        _paintPlanet(canvas, c, r, lit, mix);
        if (colorAssist) _paintGlyph(canvas, c, r, lit);
        return;
    }

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

  // ------------------------------------------------------------- the looks

  /// Hard candy: a saturated body, a huge sharp specular and a white stripe.
  /// Everything the classic deliberately avoids, on purpose — this is the
  /// "toy" look, and it should feel like one.
  void _paintCandy(Canvas canvas, Offset c, double r, double lit, Color Function(Color, double) mix) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-r * 0.25, -r * 0.30),
          r * 1.15,
          <Color>[mix(hue.light, 0), mix(hue.base, 0), mix(hue.deep, 0)],
          <double>[0.0, 0.40, 1.0],
        ),
    );
    // A diagonal gloss band across the upper half.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.6);
    canvas.drawRect(
      Rect.fromLTWH(-r * 1.2, -r * 0.55, r * 2.4, r * 0.30),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.30 * lit),
    );
    canvas.restore();
    // The hard specular.
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(-r * 0.36, -r * 0.44), width: r * 0.50, height: r * 0.34),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85 * lit),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, <Color>[
          hue.deep.withValues(alpha: 0), hue.deep.withValues(alpha: 0), hue.deep.withValues(alpha: 0.45),
        ], <double>[0.0, 0.82, 1.0]),
    );
  }

  /// Ink: matte, no specular at all, a soft darkening toward the edge like a
  /// drop of pigment. The quietest of the looks.
  void _paintInk(Canvas canvas, Offset c, double r, double lit, Color Function(Color, double) mix) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-r * 0.10, -r * 0.12),
          r * 1.05,
          <Color>[mix(hue.base, 0), mix(hue.base, 0), mix(hue.deep, 0)],
          <double>[0.0, 0.55, 1.0],
        ),
    );
    // A faint, broad bloom where the key light would fall — not a highlight,
    // more like paper showing through.
    canvas.drawCircle(
      c + Offset(-r * 0.30, -r * 0.30),
      r * 0.55,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-r * 0.30, -r * 0.30),
          r * 0.55,
          <Color>[hue.light.withValues(alpha: 0.22 * lit), hue.light.withValues(alpha: 0)],
        ),
    );
  }

  /// Gemstone: a cut stone. A dark body with a ring of facets — lighter where
  /// they face the key light, darker where they face away — and a bright
  /// table on top.
  void _paintGem(Canvas canvas, Offset c, double r, double lit, Color Function(Color, double) mix) {
    canvas.drawCircle(c, r, Paint()..color = mix(hue.deep, 0));
    const int facets = 8;
    for (int i = 0; i < facets; i++) {
      final double a0 = i * 2 * math.pi / facets - math.pi / 2;
      final double a1 = (i + 1) * 2 * math.pi / facets - math.pi / 2;
      final double mid = (a0 + a1) / 2;
      // How much this facet faces the upper-left light.
      final double facing = (math.cos(mid + math.pi * 0.75) + 1) / 2;
      final Path f = Path()
        ..moveTo(c.dx + math.cos(a0) * r * 0.55, c.dy + math.sin(a0) * r * 0.55)
        ..lineTo(c.dx + math.cos(a0) * r, c.dy + math.sin(a0) * r)
        ..lineTo(c.dx + math.cos(a1) * r, c.dy + math.sin(a1) * r)
        ..lineTo(c.dx + math.cos(a1) * r * 0.55, c.dy + math.sin(a1) * r * 0.55)
        ..close();
      canvas.drawPath(
        f,
        Paint()..color = Color.lerp(mix(hue.deep, 0), mix(hue.light, 0), 0.15 + facing * 0.75)!,
      );
      canvas.drawPath(
        f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = hue.deep.withValues(alpha: 0.5),
      );
    }
    // The table.
    final Path table = Path();
    for (int i = 0; i < facets; i++) {
      final double a = i * 2 * math.pi / facets - math.pi / 2;
      final Offset p = Offset(c.dx + math.cos(a) * r * 0.55, c.dy + math.sin(a) * r * 0.55);
      i == 0 ? table.moveTo(p.dx, p.dy) : table.lineTo(p.dx, p.dy);
    }
    table.close();
    canvas.drawPath(
      table,
      Paint()
        ..shader = ui.Gradient.linear(
          c + Offset(-r * 0.5, -r * 0.5),
          c + Offset(r * 0.5, r * 0.5),
          <Color>[mix(hue.light, 0), mix(hue.base, 0)],
        ),
    );
    canvas.drawCircle(
      c + Offset(-r * 0.22, -r * 0.26),
      r * 0.12,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7 * lit),
    );
  }

  /// Neon: a near-black core with the hue as a glowing rim and a hot centre
  /// spot, like a tube light seen end-on. Reads best on the dark ground.
  void _paintNeon(Canvas canvas, Offset c, double r, double lit, Color Function(Color, double) mix) {
    canvas.drawCircle(c, r * 0.96, Paint()..color = mix(DS.inkDeep, 0));
    // Outer glow, past the rim.
    canvas.drawCircle(
      c,
      r * 1.06,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 1.06, <Color>[
          hue.base.withValues(alpha: 0), hue.base.withValues(alpha: 0.55 * lit), hue.base.withValues(alpha: 0),
        ], <double>[0.72, 0.90, 1.0])
        ..blendMode = BlendMode.plus,
    );
    // The rim itself.
    canvas.drawCircle(
      c,
      r * 0.88,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = mix(hue.light, 0),
    );
    // The hot centre.
    canvas.drawCircle(
      c,
      r * 0.36,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 0.36, <Color>[
          Color.lerp(hue.light, const Color(0xFFFFFFFF), 0.5)!.withValues(alpha: 0.95 * lit),
          hue.base.withValues(alpha: 0.6 * lit),
          hue.base.withValues(alpha: 0),
        ], <double>[0.0, 0.5, 1.0])
        ..blendMode = BlendMode.plus,
    );
  }

  /// Planets: the classic sphere with a tilted ring and a band of cloud.
  void _paintPlanet(Canvas canvas, Offset c, double r, double lit, Color Function(Color, double) mix) {
    final double body = r * 0.78;
    // Ring, back half first so the planet occludes it.
    void ring(bool front) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.42);
      final Rect rr = Rect.fromCenter(center: Offset.zero, width: r * 2.0, height: r * 0.62);
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = hue.light.withValues(alpha: (front ? 0.85 : 0.45) * lit);
      canvas.drawArc(rr, front ? 0 : math.pi, math.pi, false, p);
      canvas.restore();
    }
    ring(false);
    canvas.drawCircle(
      c,
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-body * 0.34, -body * 0.40),
          body * 1.32,
          <Color>[mix(hue.light, 0), mix(hue.base, 0), mix(hue.deep, 0)],
          <double>[0.0, 0.48, 1.0],
        ),
    );
    // A band across the equator.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: body)));
    canvas.drawRect(
      Rect.fromCenter(center: c + Offset(0, body * 0.18), width: body * 2.2, height: body * 0.26),
      Paint()..color = hue.deep.withValues(alpha: 0.35 * lit),
    );
    canvas.drawRect(
      Rect.fromCenter(center: c + Offset(0, -body * 0.30), width: body * 2.2, height: body * 0.12),
      Paint()..color = hue.light.withValues(alpha: 0.28 * lit),
    );
    canvas.restore();
    canvas.drawCircle(
      c,
      body,
      Paint()
        ..shader = ui.Gradient.radial(c, body, <Color>[
          hue.deep.withValues(alpha: 0), hue.deep.withValues(alpha: 0), hue.deep.withValues(alpha: 0.4),
        ], <double>[0.0, 0.78, 1.0]),
    );
    ring(true);
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
      old.style != style ||
      old.hue != hue ||
      old.colorAssist != colorAssist ||
      old.elevation != elevation ||
      old.dim != dim;
}


/// A concealed ball: dark glass, one specular, a question mark.
///
/// Drawn in the vessel's own greys so it reads as "there is a ball here and
/// you cannot see it" rather than as a ball of some ninth colour.
class _HiddenBubblePainter extends CustomPainter {
  _HiddenBubblePainter({required this.dim});

  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset c = Offset(r, r);
    final double lit = 1 - dim * 0.6;

    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(r * 0.72, r * 0.68),
          r * 1.15,
          <Color>[
            Color.lerp(DS.surfaceHigh, const Color(0xFFFFFFFF), 0.10 * lit)!,
            DS.surfaceRaised,
            DS.inkDeep,
          ],
          <double>[0.0, 0.55, 1.0],
        ),
    );
    canvas.drawCircle(
      c,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = DS.hairlineStrong,
    );
    // The specular is what keeps it a sphere and not a disc.
    canvas.drawCircle(
      Offset(r * 0.66, r * 0.58),
      r * 0.16,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.14 * lit),
    );

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: r * 1.05,
          fontWeight: FontWeight.w600,
          color: DS.textSecondary.withValues(alpha: 0.7 * lit),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_HiddenBubblePainter old) => old.dim != dim;
}
