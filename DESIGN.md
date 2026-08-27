# Bubble Sort — Design System

A colour-sorting puzzle. Familiar mechanic, entirely original product identity:
name, mark, palette, typography, vessel and ball rendering, motion, icon set and
sound are all authored here and reference no existing game.

---

## 1. Visual direction

**Warm light in a cool dark room.**

Almost every game in this category is bright candy on white. Bubble Sort inverts
that: a deep blue-black ground, one warm gold accent, and jewel-toned contents
that are the only saturated things on screen. The result reads closer to a
well-made utility app than to a casual game — which is exactly the intent.

Three rules the whole product follows:

1. **One light source, from above.** Every surface — card, vessel, ball, button,
   switch knob — is lit from the top. Highlights sit on top edges, shadows fall
   below and are tinted toward the background hue, never pure black.
2. **One obvious action per screen.** The home screen has exactly one gold
   element. The game screen has exactly one bright object: the board.
3. **Nothing moves linearly, and nothing moves without reason.** Motion either
   confirms a touch, carries an object between two places, or signals a state
   change. There is no decorative animation anywhere except the ambient
   background and the logo's pour loop.

---

## 2. The design system

All tokens live in [`lib/design/tokens.dart`](lib/design/tokens.dart) and
[`lib/design/typography.dart`](lib/design/typography.dart). No screen is
permitted to invent a colour, radius, duration or gap.

### Colour

| Role | Token | Value |
|---|---|---|
| Ground | `ink` | `#0A0C12` |
| Deepest (vignette, scrims) | `inkDeep` | `#06070B` |
| Surface | `surface` | `#11141C` |
| Raised (cards, dock) | `surfaceRaised` | `#171B25` |
| High (vessel interior top) | `surfaceHigh` | `#1E2330` |
| Hairline / strong hairline | `hairline` | `#FFFFFF` @ 8% / 14% |

The ground is a deep blue-black, not `#000`. Pure black flattens shadows and is
the single fastest way to make a dark UI look cheap.

**Brand.** Gold `#F3C56B`, deep `#D9A03F`, soft `#FFE0A6` — the primary action,
progress, and hints. Cool counterpoint: aqua `#5FD6C4` for success and
completion. Nothing else in the product is allowed to be an accent colour.

**Text.** Primary `#F2F4F8`, secondary `#9BA6BC`, tertiary `#5F6979`, on-gold
`#231A08`. Three greys, used strictly by hierarchy level.

### Bubble palette

Eight hues, each carrying three tones (mid / deep / light) so a ball can be lit
rather than flat-filled.

| # | Name | Base | Glyph |
|---|---|---|---|
| 0 | Vermilion | `#EE6A52` | dot |
| 1 | Amber | `#E9AE2E` | ring |
| 2 | Lime | `#9BCB55` | bar |
| 3 | Jade | `#2DB689` | triangle |
| 4 | Azure | `#4894DE` | diamond |
| 5 | Iris | `#8A76E4` | cross |
| 6 | Rose | `#DD54A4` | chevron |
| 7 | Slate | `#7A88A4` | square |
| 8 | Teal | `#2189A8` | arc |
| 9 | Sand | `#D9BC8E` | dash |
| 10 | Cobalt | `#3C5FC4` | star |
| 11 | Plum | `#7B3B5E` | hex |

The first eight carry the game on their own and are all the player sees for the
first several hundred levels. The last four only appear in later chapters, once
the board is a familiar object.

Twelve hues cannot all be separated by hue alone, and pretending otherwise is
how palettes in this genre end up with three indistinguishable purples. The
second rank is therefore separated from its nearest neighbour primarily by
**lightness and chroma**: Teal is pulled toward blue and away from Jade, Cobalt
sits darker than Azure, Sand is lighter and softer than Amber, and Plum is a
dark wine rather than a dark violet - a violet would sit directly on top of
Iris, which was the weakest pair in the first cut of this palette.

The set alternates warm and cool and never places two similar hues at similar
lightness. Rose is pushed well into magenta specifically so it cannot collide
with Vermilion — the only pair in the set close enough to be a problem.

**Colour-blind support** is a first-class setting, not an afterthought: turning
on *Colour assist* draws each hue's glyph faintly inside its balls, so hue is
never the only thing distinguishing one stack from another.

### Spacing

4pt base, used as named steps only: `2, 4, 8, 12, 16, 20, 24, 32, 40, 56, 72`.

### Radius

`6 / 10 / 16 / 22 / 30 / pill`. Vessels are a special case: a `0.20 × width`
radius at the mouth and `0.46 × width` at the base, so the silhouette has a
direction — you can tell at a glance which end things pour out of.

### Shadows

Two elevations, each two layers: a tight contact shadow plus a broad ambient
one, both tinted toward the background and kept at low opacity. Glows use
negative spread so they sit *under* an element rather than haloing around it.

> A saturated colour at high opacity with a small blur and a downward offset is
> not a glow, it is a bevel — and a bevel dates a button by a decade.

### Typography

Two bundled variable faces, used with intent:

- **Sora** — geometric, wide-aperture, distinctive numerals. Wordmark, level
  numbers, titles, counters.
- **Inter** — workhorse UI face with excellent small-size legibility. Everything
  else.

Weights are set through `FontVariation` as well as `FontWeight`, so the engine
uses real optical weights rather than faux-bolding. The wordmark is *light* at a
large size with generous tracking — that is what separates a considered
logotype from a bold-sans app title.

### Iconography

Fourteen icons, drawn in [`icons.dart`](lib/ui/widgets/icons.dart) rather than
imported. One 24-unit grid, one stroke weight, round caps and joins. A stock
icon font would bring someone else's optical weight into the product and make it
read like a business app. Notable choices: settings is *sliders*, not a cog
(these are preferences, not configuration); hint is a *sparkle*, not a lightbulb.

### Motion

| Token | Duration | Used for |
|---|---|---|
| `tPress` | 80ms | button down |
| `tFast` | 140ms | opacity, small state |
| `tBase` | 200ms | switches, status line |
| `tMove` | 240ms | in-screen travel |
| `tRoute` | 300ms | screen transitions |
| `tSlow` | 340ms | the longest ordinary move |
| `tCelebrate` | 620ms | the vessel shatter |

These are a game's budget, not an app's. In an app a 300ms transition reads as
considered; in a game, where the player makes a move every second or so, the
same 300ms is 300ms of the controls not answering. Two numbers sit outside the
table because they are the ones the player actually feels:

- **A pour's flight is 190ms** (`GameController.flightDuration`), down from
  340. It is the most load-bearing duration in the product: chained moves
  cannot start until the previous arc lands, so every millisecond here is a
  millisecond of input latency.
- **Lifting a stack is 150ms**, shorter than `tBase`. It is a direct response
  to a touch, and a direct response is the one thing that must never be seen
  to travel.

Named easings: `emphasized` (0.2, 0, 0, 1) for travel, `out` for entrances,
`inFast` for exits, `breathe` for ambient loops, `overshoot` for release and
landing. Linear is never used.

---

## 3. Home screen

```
      ┌──────────────────────────── ⚙ ┐   utility row, one control
      │                                │
      │            ▮▯▮  ●               │   animated mark (pour loop)
      │          D E C A N T A          │   wordmark
      │       POUR · SORT · SETTLE      │   tagline
      │                                │
      │  ┌──────────────────────────┐  │
      │  │ PROGRESS                 │  │   state card
      │  │ 4 / 10              ✦ 5  │  │
      │  │ ▬▬▬▬▬▬▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭▭  │  │
      │  └──────────────────────────┘  │
      │  ┌──────────────────────────┐  │
      │  │        CONTINUE          │  │   the one gold element
      │  │  LEVEL 05 · SUSPENSION   │  │
      │  └──────────────────────────┘  │
      │          ▯ The road             │   quiet secondary
      └────────────────────────────────┘
```

Weighted 4:6 rather than centred, so the identity block lands in the optical
upper third and the action block owns the bottom. Everything a home screen
usually accumulates — a shop, a daily reward, four badges, a spinning coin — is
absent, and the resulting hierarchy is what makes it read as expensive.

The ambient background is pushed hardest here (`intensity: 1.9`). The menu is
mostly negative space by design, and unlit negative space reads as an empty
container; a visible warm/cool wash turns the same emptiness into atmosphere.

**The PLAY button** carries a slow pulse in its *glow*, never in its geometry.
Press drops it 3.8% in 90ms; release runs an elastic curve past zero so it
settles with a hair of overshoot — a much better approximation of a physical key
than a symmetric ease, and the interaction the player performs most often.

---

## 4. Game screen

```
   ‹        LEVEL 03 · DECANT        ⚙     thin identity strip
                 ▬▬ ▬▬ ▭ ▭                one pip per vessel to seal

              ▮  ▮  ▯  ▯                  the board owns everything
              ▮  ▮  ▯  ▯                  in between, and all the
              ▮  ▮  ▯  ▯                  contrast on screen
              ▮  ▮  ▯  ▯

             8  MOVES  ·  PAR 8           one status line, one message
        ┌────────────────────────┐
        │  ↶      ✦³      ↻      │        floating dock, three controls
        │ UNDO   HINT  RESTART   │
        └────────────────────────┘
```

Three bands with a strict hierarchy. The ambient background is dialled back to
`0.55` so the board is unambiguously the brightest thing on the display.

The status line shows exactly one message, by priority: teach → warn (no pours
left) → report (moves and par).

### Vessel

Not a plain U-tube, and drawn in three passes:

1. **Back glass** — cast shadow, interior gradient (darker at the base), a
   single soft specular band down the left, the outer edge (brightest at the
   mouth, fading toward the base), and a short bright cap across the rim.
2. **Contents.**
3. **Front glass** — inner shadow falling from the rim, a broad diagonal sheen,
   and a right-hand rim light.

Drawing the balls *between* two glass layers is the whole trick: the front sheen
falls across them, which is what sells the contents as being inside something
rather than as circles stacked in front of a tube-shaped picture.

Balls are given generous wall clearance (`0.23 × diameter` each side). Balls
that touch the glass make the vessel disappear behind its contents — the most
common reason boards in this genre look cheap.

### Ball

Five stacked passes describing a real lighting setup:

1. a soft contact shadow, tinted with the ball's own deep tone
2. a body gradient lit from the upper left, its centre off-axis
3. a **bounce-light crescent** along the lower edge — light coming back up off
   the vessel floor. This is the pass that makes it read as three-dimensional
4. a terminator darkening only the outermost few percent
5. one small, soft specular highlight — deliberately understated

All of it is gradients; there is not a single blur filter. Visually the
difference is negligible, and with 28 balls on screen on a mid-range Android
phone it is the difference between a smooth board and a stuttering one.

---

## 5. Animation principles

| Moment | What happens |
|---|---|
| **Select** | Vessel rises `0.20 × ball` and scales 2.8%; rim brightens to gold; the top run peels out of the mouth on a staggered overshoot |
| **Press** | Vessel dips slightly — separate from selection, so a touch always answers |
| **Pour** | Three-phase arc: rise (easeOutCubic), cross (emphasized), fall (easeInCubic). Vertical and horizontal are eased *separately* and overlap only in the middle |
| **Land** | Volume-preserving squash — 16% flatter, 13% wider — staggered per ball |
| **Seal** | The vessel shatters — see below |
| **Reject** | Three diminishing swings, `0.20 × ball` amplitude. Soft, informative, not punishing |
| **Clear** | Bloom on the card's top edge, twelve slow motes, counters counting up |

A ball that slides diagonally across the board is the single most common tell of
a prototype, which is why the pour path is neither a straight line nor one
curve. And a ball is never in two places at once: while a pour is in the air the
destination's arriving balls are withheld from the board and drawn by the flight
overlay instead.

### The seal

The completion of a vessel is the game's reward beat, and it is the one place
the design spends. Five things fire on overlapping schedules rather than one
animation playing:

1. a **flash**, over in two frames, that marks the instant of impact;
2. a **fracture that propagates** — cracks race down from the rim, branch into
   splinters, and are crossed by two concentric rings;
3. **shards** thrown off the mouth, each with its own spin and gravity;
4. a **shockwave** ring tracing the vessel's own outline; and
5. **glints** running along the cracks once they have stopped growing.

The propagation is the part that matters. A crack texture that fades in reads
as a decal; a crack that *travels* reads as something breaking. The concentric
rings are the second half of that: struck glass cracks both outward from the
impact and around it, and without the rings a radial-only network reads as a
firework however much the angles are jittered.

The fracture is generated from a seed, cached, and keyed on the vessel index
and the level id — so no two vessels on a board crack alike, and no level
repeats the last one. It then **stays**, at about a quarter of its peak
brightness, so a finished vessel is marked as finished by its own history
rather than by a badge stuck on top of it.

**Screen transitions** never slide laterally. A lateral slide implies a spatial
relationship between screens that this game does not have, and it is the default
that makes an app feel like a stack of forms. Instead the outgoing screen
recedes and fades while the incoming one rises.

---

## 6. The levels

### The road

The level picker is a **map, not a menu**. A grid of numbered tiles tells the
player how much is left and nothing else; a map tells them where they are, and
in a thousand-level puzzle game progress is most of the product.

- **A road.** Nodes sit on a serpentine path with a drawn track between them,
  lit gold behind the player and dashed and unlit ahead, so position is
  readable at a glance from across a room.
- **A horizon.** The map stops eight levels past the furthest unlocked one
  rather than running to level 1000. Scrolling past nine hundred padlocks is
  demoralising and says nothing; a handful of nodes ahead, fading into three
  pips and the name of the next chapter, is an invitation.
- **Chapters as gates.** Each chapter opens with a banner that breaks the road,
  so a run of forty levels has a beginning and an end.
- **Cleared nodes carry their grade** — gold for flawless, aqua for great —
  rather than a uniform tick, so the road behind the player is not flat.

It is one flat list of fixed-height rows, one per level and one per banner, so
only the dozen rows on screen are ever built. Every node's position is a pure
function of its index, which is what lets "scroll to where the player is" be
computed arithmetically rather than by measuring anything.

### The catalogue

**1000 levels across 25 chapters**, all generated and verified by
[`tools/gen_levels.js`](tools/gen_levels.js), which emits
`assets/levels/levels.json` (~103 KB) in about 30 seconds.

Difficulty is shaped by three knobs, not one:

- **Hues in play** - 2 through 12.
- **Spare vessels** - two, or one. This matters more than an extra colour, so
  single-spare chapters are used as deliberate steps up.
- **Vessel capacity** - 4 or 5. Reserved for chapters with fewer hues; a board
  that is both tall and wide does not fit a phone.

| Ch | Name | Hues | Spare | Cap | Par range |
|---|---|---|---|---|---|
| 1 | First Pours | 2-4 | 2 | 4 | 3-14 |
| 2 | Settling | 4-5 | 2 | 4 | 4-17 |
| 3 | Decanting | 5-6 | 2 | 4 | 6-20 |
| 4 | Sediment | 6 | 2 | 4 | 9-22 |
| 5 | Meniscus | 6-7 | 2 | 4 | 12-25 |
| 6 | Narrow Room | 6-7 | **1** | 4 | 7-20 |
| 7 | Suspension | 7-8 | 2 | 4 | 12-28 |
| 8 | Deep Vessels | 7-8 | 2 | **5** | 21-35 |
| ... | | | | | |
| 23 | Crystalline | 12 | 2 | 5 | 33-53 |
| 24 | Azeotrope | 11 | 1 | 5 | 18-38 |
| 25 | Equilibrium | 12 | 1 | 5 | 18-41 |

Par is **not** comparable across chapters, and is not meant to be. A
single-spare board needs *fewer* pours than a two-spare one at the same hue
count - there is less room to shuffle - while being considerably harder to
think through. Par is a target for the level in front of you, not a difficulty
ranking of the catalogue.

### Two guarantees

**Every board is solvable, and that is verified rather than assumed.**
Reverse-scrambling from the solved state is tempting to treat as a proof of
solvability. It is not one: the scramble moves single balls anywhere, while the
game moves whole *runs* and forbids parking an already-pure stack in an empty
vessel. A scrambled board can therefore be unreachable backwards through legal
pours. Roughly 5900 candidates were discarded on exactly these grounds during
generation - almost all of them from the single-spare chapters, where about
four in ten scrambles produce a board no legal sequence can finish.

**Every par is a solution length that was actually found**, never an estimate.
Boards small enough are solved exactly by A*, using the admissible bound below;
the rest fall back to a beam search, where par is the best line found. 978 of
the 1000 pars are provably optimal, and `Level.parIsOptimal` records which.

> *The bound:* a pour merges one run onto a matching top (runs -1), moves it to
> an empty vessel (runs unchanged), or moves part of it (runs unchanged). No
> pour ever removes more than one run, and the goal holds exactly one run per
> hue - so `runs - hues` is a floor on the pours still required. A test asserts
> no level's par falls below its own floor.

### The opening run

Chapter 1 opens at two hues and three pours. **Level 1 is the tutorial**: two
colours, two spare vessels. The teaching is two sentences that appear one at a
time and are dismissed by *playing*, not by reading - "Tap a vessel to lift its
top colour", then "Now tap another vessel to pour it in" - with a gold halo
tracing the vessel to touch. Nothing is blocked, nothing is modal, and it never
appears again.

### Storage

Levels are an **asset, not source**. A `const` list in Dart stops being the
right shape somewhere in the low hundreds: a thousand entries would be ~8000
lines of generated code compiled into the binary and re-reviewed on every diff.
As JSON it is ~103 KB, decoded once on a background isolate at boot, and
replacing the catalogue is a file copy.

## Rules that shape the feel

Two rules exist purely to stop the game feeling hostile:

- **Sealed vessels are locked.** Once a vessel holds a full set of one hue it
  cannot be poured out of, which removes a whole class of accidental
  self-sabotage.
- **A pure stack cannot be moved into an empty vessel.** It achieves nothing and
  only pads the move counter.

And one in the input layer: if you tap a vessel that is not a legal destination
but *is* a legal source, that is treated as changing your mind, not as an error.
Punishing a reasonable intention is what makes a puzzle game feel unfriendly.
