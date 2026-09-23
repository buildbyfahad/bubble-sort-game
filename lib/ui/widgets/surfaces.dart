import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';

/// The one card treatment used everywhere.
///
/// A light slab on the violet sky, with a soft tinted shadow under it.
///
/// It used to be a dark slab, which worked on a near-black ground and stopped
/// working the moment the ground became bright: the sky spans the middle of
/// the value range, so a panel has to be clearly lighter or clearly darker
/// than it to read as a panel at all. There is no middle to sit in.
///
/// The card provides a dark [DefaultTextStyle] for its subtree, which every
/// type style that does not bake its own colour — titles, numerals, bodyStrong
/// — picks up automatically. The four that do bake one have `…Ink`
/// counterparts in [Type].
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
    // A sticker, not a pane.
    //
    // Casual-game surfaces read as physical objects: a solid face, a darker
    // body under it, and an outline holding the whole thing together. A soft
    // 1px hairline is an app's card — correct on a dark ground where the edge
    // is a catch-light, and on a bright one it just makes the panel float
    // with nothing holding it down.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 2),
        color: DS.cardUnder,
        boxShadow: elevated ? DS.e2 : null,
      ),
      padding: const EdgeInsets.only(bottom: DS.bevel),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              DS.card,
              Color.lerp(DS.cardSoft, tint ?? DS.cardSoft, tint == null ? 0 : 0.16)!,
            ],
          ),
        ),
        child: DefaultTextStyle.merge(
          style: Type.body.copyWith(color: DS.inkStrong),
          child: child,
        ),
      ),
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
          // A 6%-white track was a groove on a dark card and is invisible on
          // a light one. Tinted ink instead, which reads on both.
          color: DS.inkSoft.withValues(alpha: 0.22),
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
