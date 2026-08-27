import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// A switch built to match the rest of the system rather than the platform.
///
/// The knob travels on an emphasised curve and stretches slightly in the
/// direction of travel before settling — the same squash the balls use, at a
/// tenth of the amplitude. It costs nothing and it is the reason the control
/// feels like part of the same object as the board.
class DSwitch extends StatelessWidget {
  const DSwitch({super.key, required this.value, required this.onChanged, this.accent = DS.gold});

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  static const double _w = 46;
  static const double _h = 27;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: value ? 1 : 0, end: value ? 1 : 0),
          duration: DS.tBase,
          curve: Ease.emphasized,
          builder: (BuildContext context, double t, _) {
            const double pad = 3.0;
            const double knob = _h - pad * 2;
            // Stretch peaks mid-travel, so the knob leans into the movement.
            final double stretch = 1 + (t * (1 - t)) * 1.1;
            final double kw = knob * stretch;
            final double left = pad + (_w - pad * 2 - kw) * t;

            return Container(
              width: _w,
              height: _h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DS.rPill),
                color: Color.lerp(
                  const Color(0xFFFFFFFF).withValues(alpha: 0.07),
                  accent.withValues(alpha: 0.26),
                  t,
                ),
                border: Border.all(
                  color: Color.lerp(DS.hairline, accent.withValues(alpha: 0.55), t)!,
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: left,
                    top: pad,
                    child: Container(
                      width: kw,
                      height: knob,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(DS.rPill),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color.lerp(const Color(0xFFE6EAF2), DS.goldSoft, t)!,
                            Color.lerp(const Color(0xFF9AA5B8), DS.goldDeep, t)!,
                          ],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: (t > 0.5 ? accent : const Color(0xFF000000))
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
