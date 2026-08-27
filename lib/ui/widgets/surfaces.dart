import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// The one card treatment used everywhere.
///
/// A card is a top-lit slab: a barely-there vertical gradient, a hairline that
/// is brighter along the top edge, and a wide soft shadow. Defining it once
/// means every surface in the game catches light from the same direction —
/// which is most of what "designed as a system" actually means in practice.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DS.s20),
    this.radius = DS.rLg,
    this.elevated = true,
    this.tint,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool elevated;

  /// Optional accent wash — used by the level-complete sheet.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(DS.surfaceRaised, tint ?? DS.surfaceRaised, tint == null ? 0 : 0.10)!,
            DS.surface,
          ],
        ),
        border: Border.all(color: DS.hairline, width: 1),
        boxShadow: elevated ? DS.e1 : null,
      ),
      child: child,
    );
  }
}

/// A thin capsule progress track.
///
/// Animates its own fill whenever the value changes, so progress is always
/// seen moving rather than found already moved — the difference between the
/// player registering their progress and not noticing it.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({
    super.key,
    required this.value,
    this.height = 5,
    this.color = DS.gold,
    this.duration = DS.tSlow,
  });

  final double value;
  final double height;
  final Color color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(DS.rPill),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: duration,
            curve: Ease.emphasized,
            builder: (BuildContext context, double v, _) => Container(
              // Any non-zero progress gets a visible stub. A single level out
              // of a thousand is 0.1% of the track - drawn honestly that is a
              // lone dot, which reads as a rendering fault rather than as "you
              // have started".
              width: (c.maxWidth * v).clamp(v > 0 ? height * 3 : 0.0, c.maxWidth),
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DS.rPill),
                gradient: LinearGradient(
                  colors: <Color>[color.withValues(alpha: 0.75), color],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-vessel completion readout on the game screen: one pip per vessel that
/// needs sealing, filling as the board resolves. More legible at a glance than
/// a number, and it costs a single row of pixels.
class PipRow extends StatelessWidget {
  const PipRow({super.key, required this.total, required this.filled, this.color = DS.aqua});

  final int total;
  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < total; i++)
          AnimatedContainer(
            duration: DS.tBase,
            curve: Ease.emphasized,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i < filled ? 18 : 7,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DS.rPill),
              color: i < filled ? color : const Color(0xFFFFFFFF).withValues(alpha: 0.16),
              boxShadow: i < filled
                  ? <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8)]
                  : null,
            ),
          ),
      ],
    );
  }
}
