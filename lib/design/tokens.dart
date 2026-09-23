
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
  // Dark ground, bright glass.
  //
  // This went bright violet for a while, on an instruction to take it "full
  // casual-bright". The reference the brief finally supplied says the
  // opposite: the games in this specific genre — ball sort, water sort — are
  // near-black with *clear* glass tubes and very glossy balls on top. The
  // contrast is the whole product. Twelve saturated hues need somewhere dark
  // to sit, and a bright ground spends the contrast budget on scenery.
  //
  // So the ground is a deep indigo-black again. What survives from the bright
  // pass is everything that was not the colour: the rounded face, the sunk
  // buttons, the outlines, the sticker construction.
  //
  // The original palette was near-black with a single gold accent, argued for
  // on the grounds that the whole category is candy-on-white. It produced
  // something genuinely sophisticated and, in play-testing, something that
  // read as cold: a premium finance app that happened to contain a puzzle.
  // A player who downloads a colour-sorting game to relax is not looking for
  // restraint.
  //
  // So: a bright violet ground, and dark panels floating on it. Panels stay
  // dark deliberately — twelve ball hues have to stay separable, and every
  // one of them reads more cleanly against a dark vessel than a light one.
  // The brightness goes into the world behind the board, where it costs the
  // puzzle nothing.
  // Darkened from #8E6CFF. A gradient sky means text contrast varies by
  // where on the screen it sits, and screen titles live at the very top —
  // which was the lightest part of it.
  static const Color skyTop = Color(0xFF2E1B5E);
  static const Color skyMid = Color(0xFF1F1145);
  static const Color skyDeep = Color(0xFF120926);

  /// The lit surface the vessels stand on. Without it they float in a void,
  /// which is most of why the board did not read as a place.
  static const Color table = Color(0xFF241542);
  static const Color tableEdge = Color(0xFF160C2C);

  /// `ink` is still the darkest ground — now used for panels and vessels
  /// rather than for the whole screen.
  static const Color ink = Color(0xFF231447);
  static const Color inkDeep = Color(0xFF160B30);
  static const Color surface = Color(0xFF2C1A5C);
  static const Color surfaceRaised = Color(0xFF3A2472);
  static const Color surfaceHigh = Color(0xFF4A3090);

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
  static const Color textSecondary = Color(0xFFDCD2FF);
  // Lifted from #9585D8: on a near-black ground a dim grey-violet reads as
  // "quiet"; on a bright violet one it reads as "broken".
  static const Color textTertiary = Color(0xFFB9ABF2);
  static const Color textOnGold = Color(0xFF4A3000);

  // ---------------------------------------------------------------- on light
  //
  // Cards are light now, and the sky spans the middle of the value range —
  // a panel can only read as a panel by being clearly darker or clearly
  // lighter than it, with nothing usable in between. Dark panels were the
  // first choice; these are the inks for the other one.
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSoft = Color(0xFFF3EFFF);
  static const Color cardEdge = Color(0xFFE2D9FF);

  /// The body a card's face sits on, showing as a thick bottom edge. Same
  /// idea as a button's bevel: it is what makes a surface read as an object
  /// rather than a rectangle of colour.
  static const Color cardUnder = Color(0xFFC3B2F0);

  static const Color inkStrong = Color(0xFF241557);
  static const Color inkBody = Color(0xFF4B3A8C);
  static const Color inkSoft = Color(0xFF8577C4);

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
  static const Color outline = Color(0xFF1B0E3D);

  // ------------------------------------------------------------------ shadows
  //
  // Shadows are tinted toward the background hue and kept wide + low opacity.
  // Two layers each: a tight contact shadow and a broad ambient one. Hard
  // black drop-shadows are the single fastest way to look like 2015.
  // Tinted toward the violet ground rather than black. A black shadow on a
  // coloured background is the fastest way to make a bright palette look
  // muddy.
  static List<BoxShadow> get e1 => const <BoxShadow>[
        BoxShadow(color: Color(0x381A0A45), blurRadius: 10, offset: Offset(0, 4)),
        BoxShadow(color: Color(0x22140538), blurRadius: 28, offset: Offset(0, 12)),
      ];

  static List<BoxShadow> get e2 => const <BoxShadow>[
        BoxShadow(color: Color(0x4A1A0A45), blurRadius: 18, offset: Offset(0, 8)),
        BoxShadow(color: Color(0x33140538), blurRadius: 44, offset: Offset(0, 20)),
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

  static const Atmosphere menu = Atmosphere('Menu', DS.gold, DS.aqua, Color(0xFF6B5BD8));

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
