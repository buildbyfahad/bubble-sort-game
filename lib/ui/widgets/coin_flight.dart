import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../feedback.dart';

/// Coins flying from where they were won to where they are kept.
///
/// Collecting a reward used to be a number changing. That is information, not
/// a reward — play-testing put it plainly: *"no animation when the user
/// collects"*. The whole point of a payout is the half-second in which the
/// player watches something come to them, and every game in the category
/// spends that half-second the same way for good reason.
///
/// Each coin takes its own arc, leaves on its own beat, and ticks on arrival,
/// so a payout of fifty lands as a *stream* rather than one lump. The counter
/// is driven by arrivals rather than by a tween, which is what makes the
/// number and the motion agree.
class CoinFlight extends StatefulWidget {
  const CoinFlight({
    super.key,
    required this.controller,
    this.coinSize = 22,
  });

  final CoinFlightController controller;
  final double coinSize;

  @override
  State<CoinFlight> createState() => _CoinFlightState();
}

/// Fires flights. Held by whichever screen knows where the coins came from.
class CoinFlightController extends ChangeNotifier {
  final List<_Coin> _coins = <_Coin>[];
  double _now = 0;

  bool get isEmpty => _coins.isEmpty;

  /// Sends [count] coins from [from] to [to].
  ///
  /// [onArrive] fires once per coin as it lands, so the caller can tick a
  /// counter and play a cue without having to guess at the timing.
  void send({
    required Offset from,
    required Offset to,
    int count = 12,
    VoidCallback? onArrive,
  }) {
    final math.Random r = math.Random(from.dx.round() * 131 + count);
    for (int i = 0; i < count; i++) {
      _coins.add(_Coin(
        from: from + Offset((r.nextDouble() - 0.5) * 46, (r.nextDouble() - 0.5) * 30),
        to: to,
        // A control point off to one side gives each coin its own curve;
        // a dozen coins on one path reads as a single object smearing.
        bow: Offset((r.nextDouble() - 0.5) * 260, -60 - r.nextDouble() * 170),
        born: _now + i * 0.045,
        life: 0.52 + r.nextDouble() * 0.20,
        spin: (r.nextDouble() - 0.5) * 8,
        onArrive: onArrive,
      ));
    }
    notifyListeners();
  }

  void _advance(double dt) {
    _now += dt;
    _coins.removeWhere((_Coin c) {
      final bool done = _now - c.born > c.life;
      if (done && !c.arrived) {
        c.arrived = true;
        c.onArrive?.call();
      }
      return done;
    });
  }

  void clear() {
    _coins.clear();
    notifyListeners();
  }
}

class _Coin {
  _Coin({
    required this.from,
    required this.to,
    required this.bow,
    required this.born,
    required this.life,
    required this.spin,
    this.onArrive,
  });

  final Offset from;
  final Offset to;
  final Offset bow;
  final double born;
  final double life;
  final double spin;
  final VoidCallback? onArrive;
  bool arrived = false;
}

class _CoinFlightState extends State<CoinFlight> with SingleTickerProviderStateMixin {
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
        painter: _CoinPainter(widget.controller, widget.coinSize),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter(this.controller, this.size) : super(repaint: controller);

  final CoinFlightController controller;
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final _Coin c in controller._coins) {
      final double t = (controller._now - c.born) / c.life;
      if (t <= 0 || t >= 1) continue;
      // Ease-in: coins hang for a moment, then are pulled in hard. A linear
      // flight reads as a file transfer.
      final double e = t * t * (3 - 2 * t);
      final Offset mid = Offset.lerp(c.from, c.to, 0.5)! + c.bow;
      final Offset p = _quad(c.from, mid, c.to, e);

      // Squashes toward the destination as it accelerates.
      final double scale = (1.0 - e * 0.35) * (t < 0.12 ? t / 0.12 : 1.0);
      final double r = size / 2 * scale;
      if (r <= 0.3) continue;

      canvas.save();
      canvas.translate(p.dx, p.dy);
      // Spun on its Y axis, so it flashes edge-on like a tossed coin.
      final double flip = math.cos(c.spin * t * math.pi + 0.7).abs().clamp(0.18, 1.0);
      canvas.scale(flip, 1.0);

      canvas.drawCircle(Offset.zero, r, Paint()..color = DS.goldDeep);
      canvas.drawCircle(Offset.zero, r * 0.86, Paint()..color = DS.gold);
      canvas.drawCircle(
        Offset(-r * 0.22, -r * 0.24),
        r * 0.26,
        Paint()..color = DS.goldSoft.withValues(alpha: 0.9),
      );
      canvas.restore();
    }
  }

  static Offset _quad(Offset a, Offset b, Offset c, double t) {
    final double u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * b.dx + t * t * c.dx,
      u * u * a.dy + 2 * u * t * b.dy + t * t * c.dy,
    );
  }

  @override
  bool shouldRepaint(_CoinPainter old) => true;
}

/// Convenience: a flight plus the tick-on-arrival cue, which every caller
/// wants and none should have to remember.
void sendCoins(
  BuildContext context,
  CoinFlightController controller, {
  required Offset from,
  required Offset to,
  required int amount,
  VoidCallback? onTick,
}) {
  // Never more coins than the payout, never so many they read as confetti.
  final int count = amount.clamp(1, 16);
  controller.send(
    from: from,
    to: to,
    count: count,
    onArrive: () {
      Fx.coinLand(context);
      onTick?.call();
    },
  );
}
