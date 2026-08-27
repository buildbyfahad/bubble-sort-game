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
  static TextStyle get wordmark => _sora(39, 300, spacing: 12.0, height: 1.0);

  static TextStyle get titleLg => _sora(28, 600, spacing: -0.2, height: 1.15);
  static TextStyle get titleMd => _sora(21, 600, spacing: -0.1, height: 1.2);

  /// Large numerals — level numbers, counters.
  static TextStyle get numeral => _sora(34, 500, spacing: -1.0, height: 1.0);
  static TextStyle get numeralSm => _sora(17, 500, spacing: -0.3, height: 1.0);

  /// Small-caps-style label: uppercase with wide tracking. Used sparingly for
  /// section and status labels.
  static TextStyle get label => _inter(11, 600, spacing: 2.0, height: 1.0, color: DS.textTertiary);
  static TextStyle get labelBright => _inter(11, 600, spacing: 2.0, height: 1.0, color: DS.textSecondary);

  static TextStyle get body => _inter(14.5, 400, height: 1.45, color: DS.textSecondary);
  static TextStyle get bodyStrong => _inter(14.5, 500, height: 1.4);
  static TextStyle get caption => _inter(12.5, 400, height: 1.35, color: DS.textTertiary);

  /// Primary button text.
  static TextStyle get button => _inter(16, 600, spacing: 0.6, color: DS.textOnGold);
  static TextStyle get buttonGhost => _inter(14, 500, spacing: 0.3, color: DS.textSecondary);
}
