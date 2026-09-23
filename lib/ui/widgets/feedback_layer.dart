import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';

/// Transient, purely decorative feedback drawn over the board.
///
/// The board's own animations — the landing squash, the seal bloom — are
/// *physical*: they describe what the objects did. They are also, by design,
/// small, and play-testing was blunt about the result: "no animation, I got
/// nothing". A ball settling 16% flatter for 220ms is craft the player never
/// consciously sees.
///
/// This layer is the opposite and unapologetic about it: numbers that leap off
/// the vessel, a burst of colour, a word. None of it describes anything
/// physical. All of it exists to tell the player, unmissably, that the thing
/// they just did mattered. Every effect is short, none blocks input, and the
/// whole layer is skipped entirely when nothing is active.
class BoardFeedback extends StatefulWidget {
  const BoardFeedback({super.key, required this.controller});

  /// Fires effects. Held by the board, which knows where its vessels are.
  final FeedbackController controller;

  @override
  State<BoardFeedback> createState() => _BoardFeedbackState();
}

/// Lets the board spawn effects without this widget knowing anything about
/// vessels, pours or game rules.
class FeedbackController extends ChangeNotifier {
  final List<_Effect> _effects = <_Effect>[];

  /// Monotonic clock for the layer, in seconds since the first effect.
  double _now = 0;

  bool get isEmpty => _effects.isEmpty;

  void burst(Offset at, Color colour, {int count = 18, double power = 1.0}) {
    _effects.add(_Burst(at: at, colour: colour, count: count, power: power, born: _now));
    notifyListeners();
  }

  void float(Offset at, String text, Color colour, {double scale = 1.0}) {
    _effects.add(_FloatText(at: at, text: text, colour: colour, scale: scale, born: _now));
    notifyListeners();
  }

  /// A word across the middle of the board — used only for a flow milestone,
  /// which is the one event that is about the player rather than the board.
  void shout(Offset at, String text, Color colour) {
    _effects.add(_Shout(at: at, text: text, colour: colour, born: _now));
    notifyListeners();
  }

  void _advance(double dt) {
    _now += dt;
    _effects.removeWhere((_Effect e) => _now - e.born > e.life);
  }

  void clear() {
    _effects.clear();
    notifyListeners();
  }
}

class _BoardFeedbackState extends State<BoardFeedback>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (widget.controller.isEmpty) return;
    widget.controller._advance(dt.clamp(0.0, 0.05));
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _FeedbackPainter(widget.controller),
      ),
    );
  }
}

// ----------------------------------------------------------------- effects

abstract class _Effect {
  _Effect({required this.born});
  final double born;
  double get life;
  void paint(Canvas canvas, Size size, double t, TextDirection dir);
}

/// A shower of hue-coloured motes thrown out of a vessel.
class _Burst extends _Effect {
  _Burst({
    required this.at,
    required this.colour,
    required this.count,
    required this.power,
    required super.born,
  }) {
    final math.Random r = math.Random(at.dx.round() * 31 + count);
    for (int i = 0; i < count; i++) {
      // Biased upward: debris thrown out of the mouth, not a symmetrical
      // firework.
      final double a = -math.pi / 2 + (r.nextDouble() - 0.5) * 2.4;
      final double speed = (120 + r.nextDouble() * 260) * power;
      _v.add(Offset(math.cos(a) * speed, math.sin(a) * speed));
      _size.add(2.0 + r.nextDouble() * 3.6);
      _spin.add((r.nextDouble() - 0.5) * 10);
    }
  }

  final Offset at;
  final Color colour;
  final int count;
  final double power;
  final List<Offset> _v = <Offset>[];
  final List<double> _size = <double>[];
  final List<double> _spin = <double>[];

  @override
  double get life => 0.85;

  @override
  void paint(Canvas canvas, Size size, double t, TextDirection dir) {
    final double p = t / life;
    final double fade = (1 - p) * (1 - p);
    for (int i = 0; i < _v.length; i++) {
      // Ballistic, with drag — motes that fly straight read as a screensaver.
      final double drag = 1 - math.exp(-t * 3.2);
      final Offset pos = at +
          Offset(_v[i].dx * drag / 3.2, _v[i].dy * drag / 3.2) +
          Offset(0, 420 * t * t * 0.5);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(_spin[i] * t);
      final double s = _size[i] * (0.6 + fade * 0.7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s, height: s * 1.6),
          Radius.circular(s * 0.35),
        ),
        Paint()..color = colour.withValues(alpha: 0.95 * fade),
      );
      canvas.restore();
    }
  }
}

/// A number that leaps off the vessel and falls back as it fades.
class _FloatText extends _Effect {
  _FloatText({
    required this.at,
    required this.text,
    required this.colour,
    required this.scale,
    required super.born,
  });

  final Offset at;
  final String text;
  final Color colour;
  final double scale;

  @override
  double get life => 1.05;

  @override
  void paint(Canvas canvas, Size size, double t, TextDirection dir) {
    final double p = (t / life).clamp(0.0, 1.0);
    // Out fast, then drifts. A linear rise reads as a tooltip.
    final double rise = (1 - math.pow(1 - p, 3).toDouble()) * 80;
    final double fade = p < 0.15 ? p / 0.15 : (1 - (p - 0.15) / 0.85);
    final double pop = p < 0.18 ? 0.5 + (p / 0.18) * 0.68 : 1.18 - (p - 0.18) * 0.18;

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: Type.numeral.copyWith(
          fontSize: 22 * scale,
          color: colour.withValues(alpha: fade.clamp(0.0, 1.0)),
          shadows: <Shadow>[
            Shadow(color: DS.inkDeep.withValues(alpha: 0.9 * fade), blurRadius: 8),
          ],
        ),
      ),
      textDirection: dir,
    )..layout();

    canvas.save();
    canvas.translate(at.dx, at.dy - rise);
    canvas.scale(pop);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}

/// A word, big, across the board.
class _Shout extends _Effect {
  _Shout({
    required this.at,
    required this.text,
    required this.colour,
    required super.born,
  });

  final Offset at;
  final String text;
  final Color colour;

  @override
  double get life => 0.95;

  @override
  void paint(Canvas canvas, Size size, double t, TextDirection dir) {
    final double p = (t / life).clamp(0.0, 1.0);
    // Slams in, holds, then lifts away.
    final double scale = p < 0.14
        ? 1.9 - (p / 0.14) * 0.9
        : (p > 0.7 ? 1.0 + (p - 0.7) * 0.7 : 1.0);
    final double fade = p < 0.1 ? p / 0.1 : (p > 0.6 ? 1 - (p - 0.6) / 0.4 : 1.0);

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: Type.titleLg.copyWith(
          fontSize: 34,
          color: colour.withValues(alpha: fade.clamp(0.0, 1.0)),
          shadows: <Shadow>[
            Shadow(color: colour.withValues(alpha: 0.5 * fade), blurRadius: 24),
            Shadow(color: DS.inkDeep.withValues(alpha: 0.9 * fade), blurRadius: 10),
          ],
        ),
      ),
      textDirection: dir,
    )..layout();

    canvas.save();
    canvas.translate(at.dx, at.dy - p * 26);
    canvas.scale(scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}

class _FeedbackPainter extends CustomPainter {
  _FeedbackPainter(this.controller) : super(repaint: controller);

  final FeedbackController controller;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _Effect e in controller._effects) {
      e.paint(canvas, size, controller._now - e.born, TextDirection.ltr);
    }
  }

  @override
  bool shouldRepaint(_FeedbackPainter old) => true;
}
