import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/typography.dart';

/// The wordmark: two words, stacked and optically justified.
///
/// "BUBBLE SORT" on one line at a size worth reading would run the full width
/// of a phone, so the lockup stacks it. Stacking two words of different letter
/// counts and centring them leaves a ragged, accidental-looking block - so the
/// tracking of each line is *solved* for a shared target width instead of being
/// picked by eye. Both lines end up exactly the same width, which is what makes
/// a stacked logotype read as drawn rather than as centred text.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.fontSize, this.maxWidth});

  final double? fontSize;

  /// Width both lines are justified to. Defaults to a share of the space
  /// available, capped so the mark never sprawls on a tablet.
  final double? maxWidth;

  static const List<String> _lines = <String>['BUBBLE', 'SORT'];

  /// Letter spacing that makes [text] measure exactly [target] wide.
  ///
  /// Flutter adds the spacing after *every* glyph including the last, so the
  /// run is one increment wider than it looks and sits one increment right of
  /// centre. Both are compensated for at the call site.
  static double _trackingFor(String text, TextStyle style, double target) {
    final TextPainter probe = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(letterSpacing: 0)),
      textDirection: TextDirection.ltr,
    )..layout();
    return (target - probe.width) / text.length;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double width = maxWidth ??
            (c.hasBoundedWidth ? math.min(c.maxWidth * 0.74, 268.0) : 268.0);
        // Sized from the lockup's width so the proportions hold at any scale.
        final double size = fontSize ?? width * 0.185;
        final TextStyle base = Type.wordmark.copyWith(fontSize: size, height: 1.0);

        return ShaderMask(
          shaderCallback: (Rect r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFB9C2D4)],
          ).createShader(r),
          blendMode: BlendMode.srcIn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < _lines.length; i++)
                Builder(
                  builder: (BuildContext context) {
                    final String line = _lines[i];
                    final double tracking = _trackingFor(line, base, width);
                    return Padding(
                      padding: EdgeInsets.only(
                        // Cancels the trailing letter-space so the line is
                        // centred on its glyphs, not on its advance width.
                        left: tracking,
                        top: i == 0 ? 0 : size * 0.22,
                      ),
                      child: Text(
                        line,
                        style: base.copyWith(letterSpacing: tracking),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
