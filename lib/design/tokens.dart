
import 'package:flutter/widgets.dart';

/// The single source of truth for Bubble Sort's visual language.
///
/// Nothing in the UI layer is allowed to invent a colour, radius, duration or
/// gap — it all comes from here, which is what keeps the game feeling like one
/// designed object rather than a pile of screens.
class DS {
  DS._();

  // ---------------------------------------------------------------- surfaces
  //
  // The ground is a deep blue-black rather than pure black: pure black flattens
  // shadows and makes everything read as cheap. Each step up is a small,
  // slightly-desaturated lift so elevation is felt, not announced.
  static const Color ink = Color(0xFF0A0C12);
  static const Color inkDeep = Color(0xFF06070B);
  static const Color surface = Color(0xFF11141C);
  static const Color surfaceRaised = Color(0xFF171B25);
  static const Color surfaceHigh = Color(0xFF1E2330);

  /// Hairline used on card and vessel edges. Light at 6–10% reads as a
  /// catch-light on an edge, not as a border.
  static const Color hairline = Color(0x14FFFFFF);
  static const Color hairlineStrong = Color(0x24FFFFFF);

  // ------------------------------------------------------------------- brand
  //
  // Warm gold against cool ink. Almost every game in this genre reaches for
  // candy brights on white; a warm accent on a cool dark ground is the whole
  // signature.
  static const Color gold = Color(0xFFF3C56B);
  static const Color goldDeep = Color(0xFFD9A03F);
  static const Color goldSoft = Color(0xFFFFE0A6);

  /// Cool counterpoint — used for success, progress and completion glow.
  static const Color aqua = Color(0xFF5FD6C4);
  static const Color aquaDeep = Color(0xFF2AA697);

  // -------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFFF2F4F8);
  static const Color textSecondary = Color(0xFF9BA6BC);
  static const Color textTertiary = Color(0xFF5F6979);
  static const Color textOnGold = Color(0xFF231A08);

  // ------------------------------------------------------------ bubble palette
  //
  // Eight hues chosen for pairwise separation under deuteranopia and
  // protanopia as well as normal vision: the set alternates warm/cool and
  // never places two similar hues at similar lightness. Each entry carries a
  // deeper shade for the sphere's lower body and a lifted shade for the
  // bounce-light, so the ball is lit rather than flat-filled.
  static const List<BubbleHue> hues = <BubbleHue>[
    BubbleHue('Vermilion', Color(0xFFEE6A52), Color(0xFFAE3A28), Color(0xFFF79C87), HueGlyph.dot),
    BubbleHue('Amber', Color(0xFFE9AE2E), Color(0xFFA5740B), Color(0xFFF7CE76), HueGlyph.ring),
    BubbleHue('Lime', Color(0xFF9BCB55), Color(0xFF5C8836), Color(0xFFC5E492), HueGlyph.bar),
    BubbleHue('Jade', Color(0xFF2DB689), Color(0xFF14785A), Color(0xFF74D8B6), HueGlyph.triangle),
    BubbleHue('Azure', Color(0xFF4894DE), Color(0xFF2160A0), Color(0xFF8DC0EE), HueGlyph.diamond),
    BubbleHue('Iris', Color(0xFF8A76E4), Color(0xFF5540A8), Color(0xFFB4A6F7), HueGlyph.cross),
    // Pushed well into magenta so it never collides with Vermilion, which is
    // the only pair in this set close enough to be a problem.
    BubbleHue('Rose', Color(0xFFDD54A4), Color(0xFF9C2C6E), Color(0xFFF294CD), HueGlyph.chevron),
    BubbleHue('Slate', Color(0xFF7A88A4), Color(0xFF48536A), Color(0xFFAFBACF), HueGlyph.square),

    // --- second rank -------------------------------------------------------
    //
    // Only reached in later chapters, once the player is used to reading the
    // board. Twelve hues cannot all be separated by hue alone, so these four
    // are separated primarily by *lightness* and *chroma* against their
    // nearest neighbour above: Teal is pulled toward blue and away from Jade,
    // Cobalt sits darker than Azure, Sand is lighter and softer than Amber,
    // and Plum is a dark wine rather than a dark violet - a violet would sit
    // right on top of Iris, which was the weakest pair in the first cut of
    // this palette. Colour assist carries the rest of the load.
    BubbleHue('Teal', Color(0xFF2189A8), Color(0xFF0D5A72), Color(0xFF77C2D8), HueGlyph.arc),
    BubbleHue('Sand', Color(0xFFD9BC8E), Color(0xFF9A7C51), Color(0xFFF0DCBC), HueGlyph.dash),
    BubbleHue('Cobalt', Color(0xFF3C5FC4), Color(0xFF213A86), Color(0xFF8496E8), HueGlyph.star),
    BubbleHue('Plum', Color(0xFF7B3B5E), Color(0xFF491B33), Color(0xFFBA7C9B), HueGlyph.hex),
  ];


  // ------------------------------------------------------------------ spacing
  //
  // 4pt base. Using named steps rather than raw numbers is what stops the
  // layout drifting into "roughly 15px" territory.
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s56 = 56;
  static const double s72 = 72;

  // ------------------------------------------------------------------- radius
  static const double rXs = 6;
  static const double rSm = 10;
  static const double rMd = 16;
  static const double rLg = 22;
  static const double rXl = 30;
  static const double rPill = 999;

  // ------------------------------------------------------------------ shadows
  //
  // Shadows are tinted toward the background hue and kept wide + low opacity.
  // Two layers each: a tight contact shadow and a broad ambient one. Hard
  // black drop-shadows are the single fastest way to look like 2015.
  static List<BoxShadow> get e1 => const <BoxShadow>[
        BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
        BoxShadow(color: Color(0x24000814), blurRadius: 24, offset: Offset(0, 10)),
      ];

  static List<BoxShadow> get e2 => const <BoxShadow>[
        BoxShadow(color: Color(0x4D000000), blurRadius: 14, offset: Offset(0, 4)),
        BoxShadow(color: Color(0x33000814), blurRadius: 40, offset: Offset(0, 18)),
      ];

  static List<BoxShadow> glow(Color c, {double opacity = 0.34, double blur = 34, double y = 10}) =>
      <BoxShadow>[
        BoxShadow(color: c.withValues(alpha: opacity), blurRadius: blur, offset: Offset(0, y)),
        BoxShadow(color: c.withValues(alpha: opacity * 0.5), blurRadius: blur * 0.35, offset: Offset(0, y * 0.3)),
      ];

  // -------------------------------------------------------------- motion time
  //
  // Six durations, used everywhere.
  //
  // These are tuned for a *game*, which is a different budget from an app. In
  // an app a 300ms transition reads as considered; in a game, where the player
  // is making a move every second or so, the same 300ms is 300ms of the
  // controls not answering, and it is felt as the game being slow rather than
  // as the game being elegant. So everything here sits at the short end of its
  // band: the press response is at the perceptual floor so a button feels
  // wired to the finger, and nothing that stands between the player and their
  // next input is allowed past ~340ms.
  static const Duration tPress = Duration(milliseconds: 80);
  static const Duration tFast = Duration(milliseconds: 140);
  static const Duration tBase = Duration(milliseconds: 200);
  static const Duration tMove = Duration(milliseconds: 240);

  /// Screen-to-screen. Short on purpose — a level opening is the most common
  /// transition in the game and the one the player is most impatient through.
  static const Duration tRoute = Duration(milliseconds: 300);

  static const Duration tSlow = Duration(milliseconds: 340);

  /// Reserved for reward moments, which are the one place the player is
  /// content to watch rather than act.
  static const Duration tCelebrate = Duration(milliseconds: 620);
}

/// Optional shape marker drawn faintly inside a bubble when the player turns
/// on colour-blind assist — redundant encoding, so hue is never load-bearing.
enum HueGlyph { dot, ring, bar, triangle, diamond, cross, chevron, square, arc, dash, star, hex }

@immutable
class BubbleHue {
  const BubbleHue(this.name, this.base, this.deep, this.light, this.glyph);

  final String name;

  /// Mid-tone — the colour the ball reads as from across the room.
  final Color base;

  /// Lower body / core shadow.
  final Color deep;

  /// Upper hemisphere and bounce-light.
  final Color light;

  final HueGlyph glyph;
}

/// Named easings. Nothing in this game is allowed to move linearly.
class Ease {
  Ease._();

  /// Material 3 "emphasised" — a fast start that settles gently. The default
  /// for anything travelling across the screen.
  static const Cubic emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Entrances: decisive arrival, no overshoot.
  static const Cubic out = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Exits: accelerate away.
  static const Cubic inFast = Cubic(0.55, 0.0, 1.0, 0.45);

  /// Gentle two-sided ease for looping ambient motion.
  static const Cubic breathe = Cubic(0.45, 0.0, 0.55, 1.0);

  /// A restrained overshoot — used only on button release and bubble landing.
  static const Cubic overshoot = Cubic(0.18, 1.34, 0.4, 1.0);
}
