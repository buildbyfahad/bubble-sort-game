import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import 'icons.dart';

/// Shared press mechanics.
///
/// Down is fast and slightly under-scaled; release overshoots by a hair and
/// settles. The overshoot comes from letting the controller travel past zero
/// with an elastic curve, which is a much better approximation of a physical
/// key than a symmetric ease — and it is the single interaction the player
/// will perform hundreds of times, so it is worth getting exactly right.
mixin PressMixin<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  late final AnimationController press = AnimationController(
    vsync: this,
    duration: DS.tPress,
    lowerBound: -0.45,
    upperBound: 1.0,
    value: 0,
  );

  void pressDown() => press.animateTo(1, duration: DS.tPress, curve: Curves.easeOutCubic);

  void pressUp() =>
      press.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.elasticOut);

  @override
  void dispose() {
    press.dispose();
    super.dispose();
  }
}

/// The single most important control in the product: the PLAY button.
///
/// It carries a slow idle pulse in its glow — not in its geometry. Buttons
/// that bounce or shake to attract attention read as nagging; a light source
/// that breathes reads as confidence.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.sublabel,
    this.idlePulse = true,
    this.expand = true,
  });

  final String label;

  /// Small caps line under the label — used for "Level 07 · First Pour".
  final String? sublabel;

  final VoidCallback onTap;
  final bool idlePulse;
  final bool expand;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with TickerProviderStateMixin, PressMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.idlePulse) _idle.repeat(reverse: true);
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => pressDown(),
      onTapCancel: pressUp,
      onTapUp: (_) => pressUp(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[press, _idle]),
        builder: (BuildContext context, Widget? child) {
          final double p = press.value;
          final double breathe = Ease.breathe.transform(_idle.value);
          final double scale = 1 - p * 0.038;
          // The glow both dims and tucks under the button as it is pressed,
          // as though it has moved closer to the surface it sits on.
          final double glow = (0.30 + breathe * 0.14) * (1 - p * 0.75);
          final double lift = (1 - p * 0.9);

          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.expand ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: DS.s32, vertical: DS.s20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DS.rXl),
                // A near-flat fill with a short sheen across the top third.
                // A full-height light-to-dark ramp plus a tight coloured drop
                // shadow is a bevel, and a bevel is the fastest way to date a
                // button by a decade.
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFFF9D794), DS.gold, Color(0xFFE7B355)],
                  stops: <double>[0.0, 0.38, 1.0],
                ),
                boxShadow: <BoxShadow>[
                  // One wide, low-opacity cast of light. Negative spread keeps
                  // it under the button instead of haloing around it.
                  BoxShadow(
                    color: DS.goldDeep.withValues(alpha: glow * 0.55),
                    blurRadius: 46 * lift,
                    spreadRadius: -8,
                    offset: Offset(0, 18 * lift),
                  ),
                  BoxShadow(
                    color: DS.inkDeep.withValues(alpha: 0.45),
                    blurRadius: 20,
                    spreadRadius: -10,
                    offset: Offset(0, 8 * lift),
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.label.toUpperCase(), style: Type.button, textAlign: TextAlign.center),
            if (widget.sublabel != null) ...<Widget>[
              const SizedBox(height: DS.s4),
              Text(
                widget.sublabel!,
                style: Type.label.copyWith(color: DS.textOnGold.withValues(alpha: 0.62)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A quiet circular control — top-bar utilities. Reads as an affordance
/// without competing with anything.
class GhostIconButton extends StatefulWidget {
  const GhostIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.semanticLabel,
  });

  final DIcons icon;
  final VoidCallback onTap;
  final double size;
  final String? semanticLabel;

  @override
  State<GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<GhostIconButton>
    with TickerProviderStateMixin, PressMixin {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => pressDown(),
        onTapCancel: pressUp,
        onTapUp: (_) => pressUp(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: press,
          builder: (BuildContext context, _) {
            final double p = press.value.clamp(0.0, 1.0);
            return Transform.scale(
              scale: 1 - press.value * 0.07,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    const Color(0xFFFFFFFF).withValues(alpha: 0.045),
                    const Color(0xFFFFFFFF).withValues(alpha: 0.10),
                    p,
                  ),
                  border: Border.all(color: DS.hairline, width: 1),
                ),
                child: Center(
                  child: DIcon(
                    widget.icon,
                    size: widget.size * 0.48,
                    color: Color.lerp(DS.textSecondary, DS.textPrimary, p)!,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One control in the gameplay dock: icon over a small label, with an optional
/// count badge. Disabled state fades rather than greying out, so the dock never
/// develops dead-looking holes.
class DockButton extends StatefulWidget {
  const DockButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.badge,
    this.accent,
    this.busy = false,
  });

  final DIcons icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final int? badge;
  final Color? accent;
  final bool busy;

  @override
  State<DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<DockButton> with TickerProviderStateMixin, PressMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didUpdateWidget(DockButton old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.busy && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color tint = widget.accent ?? DS.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => pressDown() : null,
      onTapCancel: widget.enabled ? pressUp : null,
      onTapUp: widget.enabled ? (_) => pressUp() : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedOpacity(
        duration: DS.tFast,
        opacity: widget.enabled ? 1 : 0.32,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[press, _spin]),
          builder: (BuildContext context, _) {
            final double p = press.value.clamp(0.0, 1.0);
            return Transform.scale(
              scale: 1 - press.value * 0.08,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: 26,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: <Widget>[
                          Transform.rotate(
                            angle: widget.busy ? _spin.value * 2 * math.pi : 0,
                            child: DIcon(
                              widget.icon,
                              size: 23,
                              color: Color.lerp(tint, DS.textPrimary, p)!,
                            ),
                          ),
                          if (widget.badge != null)
                            Positioned(
                              right: -12,
                              top: -4,
                              child: _Badge(count: widget.badge!, accent: widget.accent ?? DS.gold),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DS.s4),
                    Text(widget.label.toUpperCase(), style: Type.label),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        constraints: const BoxConstraints(minWidth: 17),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(DS.rPill),
        ),
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          style: Type.label.copyWith(
            color: DS.textOnGold,
            fontSize: 10,
            letterSpacing: 0,
          ),
        ),
      );
}

/// Low-emphasis text action — "Levels", "Restart progress". Underplayed on
/// purpose: the home screen should have exactly one obvious thing to press.
class TextAction extends StatefulWidget {
  const TextAction({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final DIcons? icon;
  final VoidCallback onTap;

  @override
  State<TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<TextAction> with TickerProviderStateMixin, PressMixin {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => pressDown(),
      onTapCancel: pressUp,
      onTapUp: (_) => pressUp(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: press,
        builder: (BuildContext context, _) {
          final double p = press.value.clamp(0.0, 1.0);
          return Transform.scale(
            scale: 1 - press.value * 0.05,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: DS.s20, vertical: DS.s12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DS.rPill),
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.03 + p * 0.05),
                border: Border.all(color: DS.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    DIcon(widget.icon!, size: 17, color: Color.lerp(DS.textTertiary, DS.textSecondary, p)!),
                    const SizedBox(width: DS.s8),
                  ],
                  Text(widget.label, style: Type.buttonGhost),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
