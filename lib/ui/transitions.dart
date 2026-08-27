import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// Screen transitions.
///
/// Both directions use the same idea: the outgoing screen recedes slightly and
/// fades while the incoming one rises into place. Nothing slides in from the
/// side — lateral slides imply a spatial relationship between screens that
/// this game does not have, and they are the default that makes an app feel
/// like a stack of forms.
Route<T> riseRoute<T>(Widget page, {Duration? duration}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration ?? DS.tRoute,
    reverseTransitionDuration: DS.tFast,
    opaque: false,
    barrierColor: null,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondary,
      Widget child,
    ) {
      final double t = Ease.emphasized.transform(animation.value);
      final double s = Ease.emphasized.transform(secondary.value);

      return Opacity(
        opacity: (t * (1 - s * 0.85)).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 26 - s * 14),
          child: Transform.scale(
            scale: 0.985 + t * 0.015 - s * 0.02,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Modal sheets rise from the bottom edge with a soft scrim.
Route<T> sheetRoute<T>(Widget page, {bool dismissible = true}) {
  return PageRouteBuilder<T>(
    transitionDuration: DS.tRoute,
    reverseTransitionDuration: DS.tFast,
    opaque: false,
    barrierColor: DS.inkDeep.withValues(alpha: 0.62),
    barrierDismissible: dismissible,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondary,
      Widget child,
    ) {
      final double t = Ease.emphasized.transform(animation.value);
      return Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 48), child: child),
      );
    },
  );
}

/// A one-shot entrance for content within a screen: fade plus a short rise,
/// staggered by [index]. Used to bring the home screen in as a sequence rather
/// than all at once.
class RiseIn extends StatefulWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.index = 0,
    this.distance = 18,
    this.stagger = const Duration(milliseconds: 52),
    this.delay = Duration.zero,
  });

  final Widget child;
  final int index;
  final double distance;
  final Duration stagger;
  final Duration delay;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay + widget.stagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) {
          final double t = Ease.out.transform(_c.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * widget.distance), child: child),
          );
        },
        child: widget.child,
      );
}
