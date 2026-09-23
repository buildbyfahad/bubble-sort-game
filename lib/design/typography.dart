import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Two bundled variable faces, used with intent:
///
/// * **Sora** — geometric, wide-aperture, distinctive numerals. Reserved for
///   the wordmark, level numbers and anything that should feel like a title.
/// * **Inter** — a workhorse UI face with excellent small-size legibility.
///   Everything else.
///
/// Both ship as variable fonts, so weight is set through [FontVariation] as
/// well as [FontWeight]; that gives real optical weights instead of the
/// synthetic faux-bold the engine would otherwise fake.
class Type {
  Type._();

  static const String display = 'Baloo2';
  static const String ui = 'Baloo2';

  static List<FontVariation> _w(double weight) => <FontVariation>[FontVariation('wght', weight)];

  static TextStyle _sora(double size, double weight, {double? spacing, double? height, Color? color}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
        fontVariations: _w(weight),
        // Null when unspecified, so the style INHERITS from the nearest
        // DefaultTextStyle. Baking a default here meant no style in the game
        // could ever adapt to the surface it sat on — which is fine while
        // every surface is the same colour, and is why the cards came out
        // with invisible titles the moment they went light.
        color: color,
      );

  static TextStyle _inter(double size, double weight, {double? spacing, double? height, Color? color}) =>
      TextStyle(
        fontFamily: ui,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
        fontVariations: _w(weight),
        color: color,
      );

  /// The wordmark. Light weight at a large size with generous tracking is what
  /// separates a considered logotype from a bold-sans app title.
  // Weight 300 was drawn for a near-black ground, where a hairline reads as
  // elegant. On a bright violet sky it simply disappears.
  static TextStyle get wordmark => _sora(44, 800, spacing: 2.0, height: 1.0);

  static TextStyle get titleLg => _sora(32, 800, spacing: 0, height: 1.1);
  static TextStyle get titleMd => _sora(24, 700, spacing: 0, height: 1.15);

  /// Large numerals — level numbers, counters.
  static TextStyle get numeral => _sora(38, 800, spacing: -0.5, height: 1.0);
  static TextStyle get numeralSm => _sora(19, 700, spacing: -0.2, height: 1.0);

  /// Small-caps-style label: uppercase with wide tracking. Used sparingly for
  /// section and status labels.
  static TextStyle get label => _inter(12, 700, spacing: 0.7, height: 1.0, color: DS.textTertiary);
  // White, not textSecondary: this is the screen-title style and it sits on
  // the lightest part of the sky.
  static TextStyle get labelBright => _inter(12, 700, spacing: 0.7, height: 1.0, color: DS.textPrimary);

  static TextStyle get body => _inter(15, 500, height: 1.4, color: DS.textSecondary);
  static TextStyle get bodyStrong => _inter(15.5, 700, height: 1.3);
  static TextStyle get caption => _inter(13, 500, height: 1.3, color: DS.textTertiary);

  /// Primary button text.
  // ---------------------------------------------------------------- on light
  //
  // The four styles below bake a light colour, so they are unreadable on a
  // card. [SoftCard] provides a dark DefaultTextStyle, which the *uncoloured*
  // styles (titles, numerals, bodyStrong) pick up on their own — these are
  // the explicit counterparts for the four that cannot.
  static TextStyle get labelInk => label.copyWith(color: DS.inkSoft);
  static TextStyle get labelInkStrong => label.copyWith(color: DS.inkBody);
  static TextStyle get captionInk => caption.copyWith(color: DS.inkSoft);
  static TextStyle get bodyInk => body.copyWith(color: DS.inkBody);

  static TextStyle get button => _inter(19, 800, spacing: 0.2, color: DS.textOnGold);
  static TextStyle get buttonGhost => _inter(14.5, 700, spacing: 0.3);
}
