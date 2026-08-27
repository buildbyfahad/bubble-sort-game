import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// The ground every screen sits on.
///
/// Three very large, very low-opacity colour fields drift on long, mutually
/// prime periods, so the background never visibly loops and never draws
/// attention. The point is not "an animated background" — it is that the
/// screen is never completely static, which is most of the difference between
/// a product that feels alive and one that feels like a screenshot.
///
/// Painted as plain radial gradients (no blur filters, no particles) and
/// wrapped in a repaint boundary, so the cost is a few full-screen gradient
/// fills and nothing else.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.intensity = 1.0,
  });

  final Widget child;

  /// Dialled down on the game screen so the board is unambiguously the
  /// brightest thing on the display.
  final double intensity;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  /// Distinct frames per full 90-second cycle — about twelve a second.
  static const double _steps = 1100;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 90),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: DS.ink),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (BuildContext context, _) => CustomPaint(
              // Quantised, so this repaints ~12 times a second instead of 60
              // or 120.
              //
              // This is the background of every screen in the game, and it is
              // three full-screen radial gradients — the most expensive thing
              // drawn anywhere outside the board. At a 90-second period the
              // fields move about a thousandth of the screen per frame, which
              // is invisible; paying for that on every vsync is a straight
              // transfer out of the board's frame budget. Rebuilding the
              // widget stays cheap because shouldRepaint compares the
              // quantised value and declines the repaint.
              painter: _AmbientPainter(
                (_c.value * _steps).floorToDouble() / _steps,
                widget.intensity,
              ),
              isComplex: true,
              willChange: true,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t, this.intensity);

  final double t;
  final double intensity;

  void _field(Canvas canvas, Size size, Offset centre, double radius, Color color, double alpha) {
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          radius,
          <Color>[
            color.withValues(alpha: alpha * intensity),
            color.withValues(alpha: alpha * intensity * 0.35),
            color.withValues(alpha: 0),
          ],
          <double>[0.0, 0.45, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double a = t * 2 * math.pi;

    // Warm field, upper left.
    _field(
      canvas,
      size,
      Offset(w * (0.22 + 0.10 * math.sin(a)), h * (0.16 + 0.06 * math.cos(a * 0.73))),
      w * 0.92,
      DS.gold,
      0.052,
    );

    // Cool field, lower right, on a different period.
    _field(
      canvas,
      size,
      Offset(w * (0.86 + 0.09 * math.cos(a * 0.61)), h * (0.72 + 0.07 * math.sin(a * 0.44))),
      w * 0.88,
      DS.aqua,
      0.045,
    );

    // A deep violet mass low on the screen, anchoring the composition.
    _field(
      canvas,
      size,
      Offset(w * (0.42 + 0.06 * math.sin(a * 0.37 + 1.2)), h * (1.02 + 0.04 * math.cos(a * 0.29))),
      w * 1.05,
      const Color(0xFF6B5BD8),
      0.055,
    );

    // Vignette. Pulls the eye to the centre and keeps the colour fields from
    // bleeding off the edges as bright smears.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.44),
          math.max(w, h) * 0.78,
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
  bool shouldRepaint(_AmbientPainter old) => old.t != t || old.intensity != intensity;
}
