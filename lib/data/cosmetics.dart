import 'package:flutter/foundation.dart';

/// How a ball is drawn. Each is a different lighting model, not a recolour —
/// the palette stays the same across all of them so the puzzle reads
/// identically whatever the player has equipped.
enum BallStyle { classic, gem, planet, neon, ink, candy }

/// How a vessel is drawn.
enum VesselStyle { glass, brass, frost, obsidian }

enum CosmeticKind { ball, vessel }

/// One thing the player can own.
///
/// Two ways to get one: coins, or finishing a chapter. Never both for the
/// same item, and never real money. The chapter unlocks are the ones that
/// cannot be bought, which is what makes them worth having.
@immutable
class Cosmetic {
  const Cosmetic({
    required this.id,
    required this.name,
    required this.blurb,
    required this.kind,
    this.ball,
    this.vessel,
    this.price = 0,
    this.unlockChapter,
  }) : assert((kind == CosmeticKind.ball) == (ball != null));

  final String id;
  final String name;
  final String blurb;
  final CosmeticKind kind;
  final BallStyle? ball;
  final VesselStyle? vessel;

  /// Coins. Zero means free.
  final int price;

  /// Set when the item is a reward for finishing this chapter. Such items
  /// have no price.
  final int? unlockChapter;

  bool get isFree => price == 0 && unlockChapter == null;
  bool get isChapterReward => unlockChapter != null;

  static const List<Cosmetic> all = <Cosmetic>[
    // --- balls ---------------------------------------------------------
    Cosmetic(
      id: 'ball.classic',
      name: 'Satin',
      blurb: 'The original',
      kind: CosmeticKind.ball,
      ball: BallStyle.classic,
    ),
    Cosmetic(
      id: 'ball.candy',
      name: 'Candy',
      blurb: 'Hard shell, high gloss',
      kind: CosmeticKind.ball,
      ball: BallStyle.candy,
      price: 300,
    ),
    Cosmetic(
      id: 'ball.ink',
      name: 'Ink',
      blurb: 'Matte and quiet',
      kind: CosmeticKind.ball,
      ball: BallStyle.ink,
      price: 300,
    ),
    Cosmetic(
      id: 'ball.gem',
      name: 'Gemstone',
      blurb: 'Cut, not blown',
      kind: CosmeticKind.ball,
      ball: BallStyle.gem,
      price: 750,
    ),
    Cosmetic(
      id: 'ball.neon',
      name: 'Neon',
      blurb: 'Lit from within',
      kind: CosmeticKind.ball,
      ball: BallStyle.neon,
      unlockChapter: 3,
    ),
    Cosmetic(
      id: 'ball.planet',
      name: 'Planets',
      blurb: 'Every ball a world',
      kind: CosmeticKind.ball,
      ball: BallStyle.planet,
      unlockChapter: 6,
    ),

    // --- vessels -------------------------------------------------------
    Cosmetic(
      id: 'vessel.glass',
      name: 'Glass',
      blurb: 'The original',
      kind: CosmeticKind.vessel,
      vessel: VesselStyle.glass,
    ),
    Cosmetic(
      id: 'vessel.frost',
      name: 'Frost',
      blurb: 'Etched and cold',
      kind: CosmeticKind.vessel,
      vessel: VesselStyle.frost,
      price: 500,
    ),
    Cosmetic(
      id: 'vessel.brass',
      name: 'Brass',
      blurb: 'Warm, heavy, old',
      kind: CosmeticKind.vessel,
      vessel: VesselStyle.brass,
      unlockChapter: 2,
    ),
    Cosmetic(
      id: 'vessel.obsidian',
      name: 'Obsidian',
      blurb: 'Volcanic glass',
      kind: CosmeticKind.vessel,
      vessel: VesselStyle.obsidian,
      unlockChapter: 5,
    ),
  ];

  static Cosmetic byId(String id) => all.firstWhere((Cosmetic c) => c.id == id);

  static Iterable<Cosmetic> get balls => all.where((Cosmetic c) => c.kind == CosmeticKind.ball);
  static Iterable<Cosmetic> get vessels =>
      all.where((Cosmetic c) => c.kind == CosmeticKind.vessel);

  /// The reward for finishing [chapter], if there is one.
  static Cosmetic? rewardFor(int chapter) {
    for (final Cosmetic c in all) {
      if (c.unlockChapter == chapter) return c;
    }
    return null;
  }
}
