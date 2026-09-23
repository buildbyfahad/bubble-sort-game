
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
  // Dark ground, low chroma, bright glass.
  //
  // Three directions were tried before this one. Near-black with a single gold
  // accent read as cold — a finance app containing a puzzle. Bright violet
  // spent the whole contrast budget on scenery, leaving nothing for twelve
  // saturated ball hues. Dark saturated violet was the compromise, and it had
  // a problem neither of the others did.
  //
  // Short wavelengths focus at a different depth from the rest of the
  // spectrum, so a large field of saturated deep blue-violet gives the eye a
  // focus it can never quite settle on. The last ground was hue 268 at 75%
  // saturation across the entire screen, which is that exact colour, in a
  // game people play in the dark before sleeping.
  //
  // So the base keeps its darkness and gives up its chroma: a cool slate that
  // the eye can rest on. The colour is not gone, it has moved to where it
  // costs nothing — the per-chapter [Atmosphere] washes, which are broad and
  // soft and make no demand on focus, and the gold, which is small, warm and
  // the only thing on screen asking to be pressed.
  //
  // Every value here is matched to the luminance of the colour it replaced,
  // to within 1%. That was not the first attempt: dropping the saturation
  // while keeping the same hex lightness produced a ground a third brighter
  // than the old one, which quietly cost almost every ball 10% of its
  // contrast — a palette that was easier to look at and harder to play on.
  //
  // Held at equal luminance, the change is free. Contrast against the balls
  // is what it always was, and what the game gains is chroma separation: the
  // ground moved from hue 256 at 75% saturation to hue 230 at 53%, so it is
  // no longer sitting in the same colour family as Iris, Cobalt and Plum.
  static const Color skyTop = Color(0xFF222841);
  static const Color skyMid = Color(0xFF161A30);
  static const Color skyDeep = Color(0xFF0C0E1A);

  /// The lit surface the vessels stand on. Without it they float in a void,
  /// which is most of why the board did not read as a place.
  static const Color table = Color(0xFF181D32);
  static const Color tableEdge = Color(0xFF0E1122);

  /// `ink` is the darkest ground — used for panels and vessels rather than
  /// for the whole screen.
  static const Color ink = Color(0xFF191E33);
  static const Color inkDeep = Color(0xFF0D1020);
  static const Color surface = Color(0xFF1F2540);
  static const Color surfaceRaised = Color(0xFF2C3352);
  static const Color surfaceHigh = Color(0xFF3C4670);

  /// Hairline used on card and vessel edges.
  static const Color hairline = Color(0x1FFFFFFF);
  static const Color hairlineStrong = Color(0x33FFFFFF);

  // ------------------------------------------------------------------- brand
  //
  // Candy accents, each with a deeper twin used as the bevel under a button.
  // The bevel is what makes a control look pressable rather than painted on,
  // and it is the single most recognisable piece of casual-game furniture.
  static const Color gold = Color(0xFFFFC93C);
  static const Color goldDeep = Color(0xFFD99413);
  static const Color goldSoft = Color(0xFFFFE9A8);

  static const Color aqua = Color(0xFF3FD9C8);
  static const Color aquaDeep = Color(0xFF17A092);

  /// A third accent, for the things gold and aqua should not both carry.
  static const Color punch = Color(0xFFFF5E9C);
  static const Color punchDeep = Color(0xFFD1307A);

  // -------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFD3DAEE);
  // Lifted from #9585D8: a dim tertiary reads as "quiet" on near-black and
  // as "broken" on anything brighter. This sits above the ground by enough
  // to be legible at 12pt without competing with the primary.
  static const Color textTertiary = Color(0xFFA4AECB);
  static const Color textOnGold = Color(0xFF4A3000);

  // ---------------------------------------------------------------- on light
  //
  // Cards are light now, and the sky spans the middle of the value range —
  // a panel can only read as a panel by being clearly darker or clearly
  // lighter than it, with nothing usable in between. Dark panels were the
  // first choice; these are the inks for the other one.
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSoft = Color(0xFFF2F4FB);
  static const Color cardEdge = Color(0xFFDCE1EF);

  /// The body a card's face sits on, showing as a thick bottom edge. Same
  /// idea as a button's bevel: it is what makes a surface read as an object
  /// rather than a rectangle of colour.
  static const Color cardUnder = Color(0xFFBCC4DE);

  static const Color inkStrong = Color(0xFF1C2340);
  static const Color inkBody = Color(0xFF414A6B);
  static const Color inkSoft = Color(0xFF7C86A5);

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
    BubbleHue('Slate', Color(0xFF94A3BE), Color(0xFF5A6780), Color(0xFFC6D0E0), HueGlyph.square),

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
    //
    // Slate, Cobalt and Plum were all lifted when the ground lost its chroma.
    // Slate is a desaturated blue-grey and Cobalt a dark blue, which is the
    // ground's own family now; Plum was the darkest ball in the set and was
    // disappearing into it. All three are lighter than the ground by a clear
    // margin rather than a narrow one.
    BubbleHue('Teal', Color(0xFF2189A8), Color(0xFF0D5A72), Color(0xFF77C2D8), HueGlyph.arc),
    BubbleHue('Sand', Color(0xFFD9BC8E), Color(0xFF9A7C51), Color(0xFFF0DCBC), HueGlyph.dash),
    BubbleHue('Cobalt', Color(0xFF4A6BD4), Color(0xFF26409A), Color(0xFF8FA1EE), HueGlyph.star),
    BubbleHue('Plum', Color(0xFF9B4A75), Color(0xFF5E2445), Color(0xFFCB8CAE), HueGlyph.hex),
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
  // Rounder than before across the board. Chunky radii are the other half of
  // reading as a game; a 16pt card corner is an app, a 24pt one is a toy.
  static const double rXs = 8;
  static const double rSm = 14;
  static const double rMd = 22;
  static const double rLg = 28;
  static const double rXl = 36;
  static const double rPill = 999;

  /// How deep a pressable control's bevel sits. Buttons are drawn as a face
  /// over a darker body; pressing sinks the face into it.
  static const double bevel = 5;

  /// The dark stroke around every element.
  ///
  /// This is the construction the whole category is built on and the thing
  /// this UI was missing: a sticker is a fill plus an outline, and without
  /// the outline it is just a coloured rectangle. Thick enough to read as a
  /// drawn edge rather than a border.
  static const double stroke = 2.5;
  static const Color outline = Color(0xFF0D1124);

  // ------------------------------------------------------------------ shadows
  //
  // Shadows are tinted toward the background hue and kept wide + low opacity.
  // Two layers each: a tight contact shadow and a broad ambient one. Hard
  // black drop-shadows are the single fastest way to look like 2015.
  // Tinted toward the ground rather than pure black, which on a coloured
  // background is the fastest way to look muddy.
  static List<BoxShadow> get e1 => const <BoxShadow>[
        BoxShadow(color: Color(0x3D080B18), blurRadius: 10, offset: Offset(0, 4)),
        BoxShadow(color: Color(0x26060812), blurRadius: 28, offset: Offset(0, 12)),
      ];

  static List<BoxShadow> get e2 => const <BoxShadow>[
        BoxShadow(color: Color(0x52080B18), blurRadius: 18, offset: Offset(0, 8)),
        BoxShadow(color: Color(0x38060812), blurRadius: 44, offset: Offset(0, 20)),
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

/// The three colour fields behind a screen.
///
/// Each chapter gets its own, so forty levels do not all look like one room.
/// The pairs are chosen the way the hue palette was: a warm and a cool that
/// sit apart, with a deep third to anchor. The defaults are the menu's.
@immutable
class Atmosphere {
  const Atmosphere(this.name, this.warm, this.cool, this.deep);

  final String name;
  final Color warm;
  final Color cool;
  final Color deep;

  /// The warm field is orange rather than gold.
  ///
  /// A yellow glow over a desaturated blue-slate ground mixes to olive, which
  /// is the one thing the menu's top corner must not look like. Pushed toward
  /// orange it reads as warm light instead. The deep field moved with the
  /// ground, from violet to indigo.
  static const Atmosphere menu =
      Atmosphere('Menu', Color(0xFFFF9E4D), DS.aqua, Color(0xFF5B6BD8));

  /// Cycled by chapter. Six is enough that neighbouring chapters never
  /// share one and a returning player can still place a chapter by its light.
  static const List<Atmosphere> chapters = <Atmosphere>[
    Atmosphere('Ochre', Color(0xFFE0A84A), Color(0xFF3E8F9E), Color(0xFF5E4AA8)),
    Atmosphere('Teal', Color(0xFF3AA79A), Color(0xFF4A7BD0), Color(0xFF2E4C8C)),
    Atmosphere('Rose', Color(0xFFD86A8C), Color(0xFF6A5BD8), Color(0xFF7A2E58)),
    Atmosphere('Ember', Color(0xFFE2703C), Color(0xFF9A4A9E), Color(0xFF4C2A3E)),
    Atmosphere('Frost', Color(0xFF7FB8E8), Color(0xFF4FD0C0), Color(0xFF3A4A9C)),
    Atmosphere('Violet', Color(0xFFB07AE8), Color(0xFF3F9AD8), Color(0xFF3E2A7C)),
  ];

  static Atmosphere forChapter(int number) => chapters[(number - 1) % chapters.length];
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
