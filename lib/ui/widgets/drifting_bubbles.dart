import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// Slow, out-of-focus balls rising behind the menu.
///
/// A menu that is a logo on a flat ground reads as a settings screen. This is
/// the cheapest way to make it read as a *game*, and it uses the game's own
/// vocabulary — the balls from the board, thrown far out of focus — rather
/// than the particles or confetti every other title in the category reaches
/// for.
///
/// Three rules keep it from becoming noise:
///
///  * **Very low contrast.** Each ball is a soft radial fill at a few per cent
///    alpha. If a player ever consciously notices one, it is too strong.
///  * **Different speeds.** Each rises at its own rate, so the field never
///    reads as one texture sliding upward.
///  * **Cheap.** Painted as plain gradients, quantised to roughly twelve
///    frames a second, and wrapped in a repaint boundary. The menu is the one
///    screen where there is budget for this; it is not used on the board.
class DriftingBubbles extends StatefulWidget {
  const DriftingBubbles({super.key, this.count = 9, this.opacity = 1.0});

  final int count;

  /// Scales the whole field, for screens that want it fainter still.
  final double opacity;

  @override
  State<DriftingBubbles> createState() => _DriftingBubblesState();
}

class _DriftingBubblesState extends State<DriftingBubbles>
    with SingleTickerProviderStateMixin {
  /// One full pass of the slowest ball. Long enough that the loop is never
  /// perceived.
  static const Duration _period = Duration(seconds: 64);

  /// Distinct frames per cycle — about twelve a second, same reasoning as the
  /// ambient background: nothing here moves fast enough to justify 60.
  static const double _steps = 780;

  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _period)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (BuildContext context, _) => CustomPaint(
              size: Size.infinite,
              painter: _BubblePainter(
                (_c.value * _steps).floorToDouble() / _steps,
                widget.count,
                widget.opacity,
              ),
            ),
          ),
        ),
      );
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.t, this.count, this.opacity);

  final double t;
  final int count;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < count; i++) {
      // Everything about a given ball is derived from its index, so the field
      // is identical on every rebuild and costs no stored state.
      final math.Random r = math.Random(i * 7919 + 17);

      final double speed = 0.45 + r.nextDouble() * 0.85;
      final double phase = r.nextDouble();
      // Rises, wraps, and drifts sideways on a slow sine so the columns never
      // look like they are on rails.
      final double p = (t * speed + phase) % 1.0;
      final double x = size.width *
          (0.08 +
              r.nextDouble() * 0.84 +
              math.sin((t * 2 + phase) * math.pi * 2) * 0.035);
      final double y = size.height * (1.15 - p * 1.3);

      final double radius = size.width * (0.055 + r.nextDouble() * 0.10);
      final BubbleHue hue = DS.hues[r.nextInt(DS.hues.length)];

      // Fades in off the bottom and out at the top, so nothing ever pops.
      final double edge = math.min(p / 0.18, (1 - p) / 0.22).clamp(0.0, 1.0);
      final double alpha = 0.052 * edge * opacity;
      if (alpha <= 0.001) continue;

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(x - radius * 0.3, y - radius * 0.35),
            radius,
            <Color>[
              hue.light.withValues(alpha: alpha * 1.6),
              hue.base.withValues(alpha: alpha),
              hue.deep.withValues(alpha: 0),
            ],
            <double>[0.0, 0.55, 1.0],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.t != t || old.count != count || old.opacity != opacity;
}
