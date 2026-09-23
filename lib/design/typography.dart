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

  static const String display = 'Sora';
  static const String ui = 'Inter';

  static List<FontVariation> _w(double weight) => <FontVariation>[FontVariation('wght', weight)];

  static TextStyle _sora(double size, double weight, {double? spacing, double? height, Color? color}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
        fontVariations: _w(weight),
        color: color ?? DS.textPrimary,
      );

  static TextStyle _inter(double size, double weight, {double? spacing, double? height, Color? color}) =>
      TextStyle(
        fontFamily: ui,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
        fontVariations: _w(weight),
        color: color ?? DS.textPrimary,
      );

  /// The wordmark. Light weight at a large size with generous tracking is what
  /// separates a considered logotype from a bold-sans app title.
  // Weight 300 was drawn for a near-black ground, where a hairline reads as
  // elegant. On a bright violet sky it simply disappears.
  static TextStyle get wordmark => _sora(39, 800, spacing: 8.0, height: 1.0);

  static TextStyle get titleLg => _sora(30, 800, spacing: -0.4, height: 1.1);
  static TextStyle get titleMd => _sora(22, 700, spacing: -0.2, height: 1.18);

  /// Large numerals — level numbers, counters.
  static TextStyle get numeral => _sora(36, 800, spacing: -1.2, height: 1.0);
  static TextStyle get numeralSm => _sora(18, 700, spacing: -0.4, height: 1.0);

  /// Small-caps-style label: uppercase with wide tracking. Used sparingly for
  /// section and status labels.
  static TextStyle get label => _inter(11.5, 700, spacing: 1.2, height: 1.0, color: DS.textTertiary);
  static TextStyle get labelBright => _inter(11.5, 700, spacing: 1.2, height: 1.0, color: DS.textSecondary);

  static TextStyle get body => _inter(14.5, 400, height: 1.45, color: DS.textSecondary);
  static TextStyle get bodyStrong => _inter(15, 700, height: 1.35);
  static TextStyle get caption => _inter(12.5, 400, height: 1.35, color: DS.textTertiary);

  /// Primary button text.
  static TextStyle get button => _inter(17.5, 800, spacing: 0.4, color: DS.textOnGold);
  static TextStyle get buttonGhost => _inter(14, 500, spacing: 0.3, color: DS.textSecondary);
}
