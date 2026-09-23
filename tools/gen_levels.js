#!/usr/bin/env node
/**
 * Bubble Sort level generator.
 *
 * Emits `assets/levels/levels.json` - 1000 levels across 25 chapters.
 *
 * Two guarantees:
 *   1. Every board that ships is solvable *under the game's own rules*, and
 *      that is verified, not assumed. Reverse-scrambling from the solved state
 *      is tempting to treat as a proof, but it is not one: the scramble moves
 *      single balls anywhere, while the game moves whole runs and forbids
 *      parking an already-pure stack in an empty vessel. A scrambled board can
 *      therefore be unreachable backwards through legal pours. Candidates that
 *      no search can finish are discarded.
 *   2. Every board's `par` is a real solution length that was actually found,
 *      never an estimate. Small boards are solved exactly with A*; larger ones
 *      use a beam search, where par is the best line found.
 *
 * Determinism: a seeded PRNG throughout, and no Date/Math.random anywhere, so
 * re-running produces a byte-identical file.
 *
 *   node tools/gen_levels.js [--levels 1000] [--out assets/levels/levels.json]
 */

'use strict';
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------- chapters
//
// Difficulty is shaped by three knobs, not one: how many colours are in play,
// how much spare room the player gets, and how deep the board is scrambled.
// Spare room matters most - dropping from two empty vessels to one is a bigger
// jump than adding a colour, so those chapters are used as deliberate steps up.
//
// `colors` is a range walked across the chapter's levels. `k` is vessel
// capacity; 5 is reserved for chapters with fewer colours, because a tall
// board and a wide board at the same time does not fit a phone.
const CHAPTERS = [
  // Difficulty here comes from FRAGMENTATION, not from taking spare vessels
  // away — which is the opposite of what the genre assumes, and is what the
  // numbers said.
  //
  // Measured across the previous catalogue, 18% of all balls started already
  // resting on an identical ball: roughly seven free pours per board, handed
  // over before the player thought about anything. Dealing under an adjacency
  // constraint instead (`deal: 'frag'`) makes every ball need moving at least
  // once, and lifts par from 0.66 pours per ball to about 0.85.
  //
  // The catch, and the reason the table looks like this: a fully fragmented
  // board with ONE spare vessel is essentially unsolvable past six colours —
  // zero boards in thirty at ten colours, however much the constraint is
  // relaxed. Fragmentation and spare vessels trade off directly. So the hard
  // boards here have TWO spares and no free pairs, which is harder than one
  // spare with seven of them, and the one-spare chapters are kept as variety
  // rather than as the difficulty ceiling — and early, because a one-spare
  // board now has a LOWER par than a fragmented two-spare one. Leaving them
  // at chapters 8 and 12 put a visible dip in the middle of the curve.
  { name: 'First Pours',   count: 12, colors: [2, 4],   empties: 2, k: 4, deal: 'scramble' },
  { name: 'Settling',      count: 18, colors: [4, 5],   empties: 2, k: 4, deal: 'frag' },
  { name: 'Narrow Room',   count: 20, colors: [4, 5],   empties: 1, k: 4, deal: 'scramble' },
  { name: 'Decanting',     count: 25, colors: [5, 6],   empties: 2, k: 4, deal: 'frag' },
  { name: 'Sediment',      count: 25, colors: [6, 6],   empties: 1, k: 4, deal: 'scramble' },
  { name: 'Meniscus',      count: 30, colors: [6, 7],   empties: 2, k: 4, deal: 'frag' },
  { name: 'Deep Vessels',  count: 30, colors: [6, 7],   empties: 2, k: 5, deal: 'frag' },
  { name: 'Suspension',    count: 35, colors: [7, 7],   empties: 2, k: 5, deal: 'frag' },
  { name: 'Titration',     count: 35, colors: [7, 8],   empties: 2, k: 4, deal: 'frag' },
  { name: 'Cascade',       count: 40, colors: [8, 8],   empties: 2, k: 4, deal: 'frag' },
  { name: 'Decant Deeper', count: 40, colors: [8, 9],   empties: 2, k: 5, deal: 'frag' },
  { name: 'Residue',       count: 40, colors: [9, 9],   empties: 2, k: 4, deal: 'frag' },
  { name: 'Emulsion',      count: 45, colors: [9, 10],  empties: 2, k: 4, deal: 'frag' },
  { name: 'Column',        count: 45, colors: [9, 10],  empties: 2, k: 5, deal: 'frag' },
  { name: 'Filtrate',      count: 45, colors: [10, 10], empties: 2, k: 4, deal: 'frag' },
  { name: 'Solvent',       count: 45, colors: [10, 11], empties: 2, k: 4, deal: 'frag' },
  { name: 'Reflux',        count: 45, colors: [10, 10], empties: 2, k: 5, deal: 'frag' },
  { name: 'Precipitate',   count: 45, colors: [11, 11], empties: 2, k: 4, deal: 'frag' },
  { name: 'Fractions',     count: 45, colors: [11, 12], empties: 2, k: 4, deal: 'frag' },
  { name: 'Saturation',    count: 45, colors: [12, 12], empties: 2, k: 4, deal: 'frag' },
  { name: 'Distillate',    count: 45, colors: [11, 11], empties: 2, k: 5, deal: 'frag' },
  { name: 'Supernatant',   count: 60, colors: [12, 12], empties: 2, k: 4, deal: 'frag' },
  { name: 'Crystalline',   count: 60, colors: [12, 12], empties: 2, k: 5, deal: 'frag' },
  { name: 'Azeotrope',     count: 60, colors: [11, 11], empties: 2, k: 5, deal: 'frag' },
  { name: 'Equilibrium',   count: 65, colors: [12, 12], empties: 2, k: 5, deal: 'frag' },
];

const PER_CHAPTER = 40; // legacy default, only used if a chapter omits `count`

/// Total levels the table asks for.
const PLANNED = CHAPTERS.reduce((n, c) => n + (c.count || PER_CHAPTER), 0);

// ------------------------------------------------------------------- prng
function rng(seed) {
  let s = seed >>> 0;
  return function () {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ------------------------------------------------------------ state helpers
const clone = (s) => s.map((t) => t.slice());

/**
 * Per-vessel obstacles for the board currently being generated or solved.
 *
 * Module-level rather than threaded through every function because the search
 * is recursive and hot, and a board's traits are fixed for its whole lifetime.
 * `withTraits` is the only way to set it, and it always restores — a leaked
 * trait array would silently solve the *next* board under the wrong rules.
 *
 * Packed exactly as lib/engine/board_state.dart packs them:
 *   bit 0     narrow neck
 *   bits 1..  colour lock as hue + 1
 */
let TRAITS = null;

function withTraits(traits, fn) {
  const prev = TRAITS;
  TRAITS = traits;
  try {
    return fn();
  } finally {
    TRAITS = prev;
  }
}

const traitAt = (i) => (TRAITS && TRAITS[i]) || 0;
const isNarrow = (i) => (traitAt(i) & 1) !== 0;
const lockedHue = (i) => (traitAt(i) >> 1) === 0 ? null : (traitAt(i) >> 1) - 1;

function key(s) {
  // Order-independent: two boards differing only in which vessel holds which
  // stack are the same search node — but only while the vessels themselves
  // behave alike, so the trait is folded in before the sort.
  const parts = new Array(s.length);
  for (let i = 0; i < s.length; i++) parts[i] = traitAt(i) + ':' + s[i].join('.');
  parts.sort();
  return parts.join('|');
}

function isDone(s, k) {
  for (const t of s) {
    if (t.length === 0) continue;
    if (t.length !== k) return false;
    const c = t[0];
    for (let i = 1; i < t.length; i++) if (t[i] !== c) return false;
  }
  return true;
}

/** Total number of maximal same-colour runs on the board. */
function runCount(s) {
  let r = 0;
  for (const t of s) {
    if (!t.length) continue;
    r++;
    for (let i = 1; i < t.length; i++) if (t[i] !== t[i - 1]) r++;
  }
  return r;
}

/**
 * Admissible lower bound on remaining pours.
 *
 * A pour moves one run onto a matching top (runs -1), onto an empty vessel
 * (runs unchanged), or partially (runs unchanged). So no pour ever reduces the
 * run count by more than one, and the goal has exactly one run per colour -
 * making `runs - colours` a floor on the pours still required. A* with this
 * bound returns a genuine optimum.
 */
const lowerBound = (s, colors) => Math.max(0, runCount(s) - colors);

/**
 * True while any vessel on the board pours one ball at a time.
 *
 * The A* bound above assumes a pour can carry a whole run. A narrow neck
 * breaks that assumption — the bound stays *admissible* (it still never
 * over-estimates) so A* remains correct, but it becomes much weaker, and the
 * exact search gets correspondingly slower. That is why boards with a narrow
 * neck are given a larger node budget below.
 */
const hasNarrow = () => TRAITS !== null && TRAITS.some((t) => (t & 1) !== 0);

function legalMoves(s, k) {
  const out = [];
  for (let i = 0; i < s.length; i++) {
    const from = s[i];
    if (!from.length) continue;
    const c = from[from.length - 1];
    let pure = true;
    for (let x = 0; x < from.length; x++) {
      if (from[x] !== c) { pure = false; break; }
    }
    if (pure && from.length === k) continue; // sealed
    for (let j = 0; j < s.length; j++) {
      if (i === j) continue;
      const to = s[j];
      if (to.length === k) continue;
      const lock = lockedHue(j);
      if (lock !== null && lock !== c) continue;
      if (to.length === 0) {
        // Pointless re-parking — unless the destination is locked to this
        // hue, where it is the only place the colour can ever be sealed.
        if (pure && lock !== c) continue;
        out.push((i << 8) | j);
      } else if (to[to.length - 1] === c) {
        out.push((i << 8) | j);
      }
    }
  }
  return out;
}

function apply(s, mv, k) {
  const i = mv >> 8;
  const j = mv & 255;
  const n = clone(s);
  const c = n[i][n[i].length - 1];
  let room = isNarrow(i) ? 1 : k - n[j].length;
  while (n[i].length && n[i][n[i].length - 1] === c && room > 0) {
    n[j].push(n[i].pop());
    room--;
  }
  return n;
}

// ------------------------------------------------------------------ search

/** Exact optimum via A*. Returns null if it exceeds the node budget. */
function solveExact(start, k, colors, nodeCap) {
  // The A* bound is much weaker with a narrow neck on the board, so the exact
  // search needs more room before it gives up and falls back to the beam.
  if (hasNarrow()) nodeCap *= 4;
  if (isDone(start, k)) return 0;

  // Buckets keyed by f = g + h. h is small and integral, so an array of
  // buckets beats a comparison heap here.
  const buckets = [];
  const push = (f, node) => (buckets[f] || (buckets[f] = [])).push(node);

  const seen = new Map([[key(start), 0]]);
  push(lowerBound(start, colors), { s: start, g: 0 });

  let expanded = 0;
  const MAX_F = 400;
  for (let f = 0; f <= MAX_F; f++) {
    const bucket = buckets[f];
    if (!bucket) continue;
    while (bucket.length) {
      const node = bucket.pop();
      if (++expanded > nodeCap) return null;
      for (const mv of legalMoves(node.s, k)) {
        const ns = apply(node.s, mv, k);
        const ng = node.g + 1;
        if (isDone(ns, k)) return ng;
        const nk = key(ns);
        const prev = seen.get(nk);
        if (prev !== undefined && prev <= ng) continue;
        seen.set(nk, ng);
        const nf = ng + lowerBound(ns, colors);
        if (nf <= MAX_F) push(nf, { s: ns, g: ng });
      }
    }
  }
  return null;
}

/**
 * Beam search, expanded one depth at a time. The first depth at which any
 * surviving node is solved is an upper bound on the optimum - with this
 * heuristic it lands on or very near it.
 */
function solveBeam(start, k, colors, width, maxDepth) {
  if (isDone(start, k)) return 0;
  let frontier = [start];
  const seen = new Set([key(start)]);

  for (let depth = 1; depth <= maxDepth; depth++) {
    const next = [];
    for (const s of frontier) {
      for (const mv of legalMoves(s, k)) {
        const ns = apply(s, mv, k);
        if (isDone(ns, k)) return depth;
        const nk = key(ns);
        if (seen.has(nk)) continue;
        seen.add(nk);
        next.push(ns);
      }
    }
    if (!next.length) return null;
    next.sort((a, b) => lowerBound(a, colors) - lowerBound(b, colors));
    frontier = next.slice(0, width);
  }
  return null;
}

/** Best line we can find, plus whether it is provably optimal. */
function solve(start, k, colors) {
  const exact = solveExact(start, k, colors, colors <= 6 ? 200000 : 50000);
  if (exact !== null) return { par: exact, exact: true };
  for (const width of [200, 600]) {
    const beam = solveBeam(start, k, colors, width, 260);
    if (beam !== null) return { par: beam, exact: false };
  }
  return null;
}

// ---------------------------------------------------------------- obstacles

/**
 * Which obstacle, if any, a level carries.
 *
 * Staggered deliberately: each is introduced alone, in its own chapter, and
 * only combined much later. Two new rules in one chapter is how a player
 * stops learning either of them. Ordinary levels stay the large majority
 * throughout — an obstacle is a change of question, and a change of question
 * every single level is just noise.
 *
 *   ch 6+   narrow neck
 *   ch 9+   colour lock
 *   ch 11+  either, and occasionally both on one board
 *
 * Precision levels and finales are exempt: a pour budget plus a narrow neck
 * is two rules fighting, and a finale should be the chapter's own game at its
 * hardest rather than a different one.
 */
function planTraits(ci, pos, count, tubeCount, colors, k, mode, rand, empties) {
  const traits = new Array(tubeCount).fill(0);
  if (mode !== 0) return traits;

  const chapter = ci + 1;
  const canNarrow = chapter >= 6;
  const canLock = chapter >= 9;
  if (!canNarrow && !canLock) return traits;

  // Roughly one level in four inside a chapter that has obstacles at all.
  if (pos % 4 !== 2) return traits;

  const both = chapter >= 11 && rand() < 0.25;
  const wantNarrow = canNarrow && (!canLock || both || rand() < 0.5);
  const wantLock = canLock && (both || !wantNarrow);

  // How many vessels are affected. Kept well under the spare count so the
  // board never loses all of its working room at once.
  const n = 1 + (chapter >= 14 && rand() < 0.5 ? 1 : 0);

  const used = new Set();
  const pick = (max) => {
    for (let tries = 0; tries < 30; tries++) {
      const i = (rand() * max) | 0;
      if (!used.has(i)) { used.add(i); return i; }
    }
    return -1;
  };

  if (wantNarrow) {
    // A filled vessel: narrow only bites on the way out, so it must have
    // something in it in the solved state to matter.
    for (let c = 0; c < n; c++) {
      const i = pick(colors);
      if (i >= 0) traits[i] |= 1;
    }
  }
  if (wantLock) {
    for (let c = 0; c < n; c++) {
      // Locking a *spare* is the sharper version — it takes away parking
      // space rather than merely constraining a vessel that already holds
      // that colour in the solution.
      //
      // But only when there is more than one spare. Locking the single spare
      // on a one-spare board leaves the player no unrestricted working room
      // at all, and at twelve colours that is not hard, it is impossible —
      // chapter 25 could not produce a solvable board until this guard
      // existed.
      const mayLockSpare = empties >= 2;
      const spare = colors + ((rand() * (tubeCount - colors)) | 0);
      const target = mayLockSpare && rand() < 0.65 ? spare : pick(colors);
      if (target < 0 || used.has(target) && target !== spare) continue;
      used.add(target);
      // In the solved state vessel `c` holds colour `c`; a spare holds
      // nothing, so it may be locked to any hue.
      // Two vessels locked to the same hue cannot both be filled with it in
      // any solution, so the board would be unsolvable by construction.
      const taken = new Set(
          traits.map((t) => (t >> 1) - 1).filter((h) => h >= 0));
      let hue = target < colors ? target : (rand() * colors) | 0;
      for (let g = 0; g < colors && taken.has(hue); g++) hue = (hue + 1) % colors;
      if (taken.has(hue)) continue;
      traits[target] = (traits[target] & 1) | ((hue + 1) << 1);
    }
  }
  return traits;
}

/** The compact per-vessel encoding written into levels.json. */
function encodeTraits(traits) {
  let out = '';
  let any = false;
  for (const t of traits) {
    if (t === 0) { out += '.'; continue; }
    any = true;
    if (t & 1) { out += 'n'; continue; }
    out += (((t >> 1) - 1)).toString(36);
  }
  return any ? out : null;
}

// -------------------------------------------------------------- generation

/**
 * Deals a board with no two identical balls touching.
 *
 * This replaces reverse-scrambling for everything past the opening chapters,
 * and it is the single most important change to how hard this game is.
 *
 * A random scramble leaves identical balls stacked on each other by chance —
 * measured across the old catalogue, 18% of all balls started already paired,
 * which is ~7.5 free pours handed to the player before they think about
 * anything. Every such pair is a move that makes itself. Dealing under an
 * adjacency constraint instead produces boards where *every* ball must be
 * moved at least once, which is the definition of the hardest board of a
 * given size.
 *
 * Solvability is not assumed — as with the scramble, the solver is still the
 * gate, and fragmented boards are rejected more often.
 */
function dealFragmented(colors, k, empties, rand, maxTries = 300) {
  for (let attempt = 0; attempt < maxTries; attempt++) {
    const pool = [];
    for (let c = 0; c < colors; c++) for (let i = 0; i < k; i++) pool.push(c);
    for (let i = pool.length - 1; i > 0; i--) {
      const j = (rand() * (i + 1)) | 0;
      const t = pool[i]; pool[i] = pool[j]; pool[j] = t;
    }

    const s = [];
    for (let i = 0; i < colors; i++) s.push([]);
    let ok = true;
    // Layer by layer rather than vessel by vessel, so no single vessel is
    // dealt from an already-depleted pool and forced into a pair at the end.
    for (let slot = 0; slot < k && ok; slot++) {
      for (let v = 0; v < colors && ok; v++) {
        let idx = -1;
        for (let p = 0; p < pool.length; p++) {
          if (!s[v].length || pool[p] !== s[v][s[v].length - 1]) { idx = p; break; }
        }
        if (idx < 0) { ok = false; break; }
        s[v].push(pool.splice(idx, 1)[0]);
      }
    }
    if (!ok || pool.length) continue;
    for (let e = 0; e < empties; e++) s.push([]);
    return s;
  }
  return null;
}

/** Fraction of balls that are NOT resting on an identical ball. 1 = hardest. */
const fragmentation = (s, balls) => runCount(s) / balls;

/**
 * Reverse-scramble from the solved state.
 *
 * This produces well-mixed boards cheaply, but it is only a *candidate*
 * generator - see the note at the top of this file on why it is not a proof of
 * solvability. Every board it returns is put through the solver before it is
 * allowed into the catalogue.
 *
 * The walk moves one ball at a time, which means it usually stops on a ragged
 * shape (half-filled vessels). Rejecting those outright is hopeless: exactly
 * -full shapes are a small slice of the space and random scrambles almost
 * never land on one. Instead the walk simply keeps going past `depth` until it
 * next passes through a well-formed shape, which costs a handful of extra
 * steps and preserves the solvability guarantee.
 */
function build(colors, empties, k, depth, rand) {
  const s = [];
  for (let c = 0; c < colors; c++) s.push(new Array(k).fill(c));
  for (let e = 0; e < empties; e++) s.push([]);

  const step = () => {
    const src = [];
    for (let i = 0; i < s.length; i++) if (s[i].length) src.push(i);
    const i = src[(rand() * src.length) | 0];
    const dst = [];
    for (let j = 0; j < s.length; j++) if (j !== i && s[j].length < k) dst.push(j);
    if (!dst.length) return;
    const j = dst[(rand() * dst.length) | 0];
    s[j].push(s[i].pop());
  };

  for (let n = 0; n < depth; n++) step();
  for (let extra = 0; extra < 4000 && !wellFormed(s, colors, k); extra++) step();
  return wellFormed(s, colors, k) ? s : null;
}

/**
 * Every vessel must end up either empty or exactly full, so the board reads as
 * a clean block rather than a ragged one, and so the opening state cannot leak
 * information about the solution.
 */
function wellFormed(s, colors, k) {
  let filled = 0;
  for (const t of s) {
    if (t.length === 0) continue;
    if (t.length !== k) return false;
    filled++;
  }
  return filled === colors;
}

/** How thoroughly mixed the board looks - guards against near-solved boards. */
function mixedness(s) {
  let m = 0;
  for (const t of s) if (t.length) m += new Set(t).size;
  return m;
}

// --------------------------------------------------------------------- run

const argv = process.argv.slice(2);
const argOf = (flag, fallback) => {
  const i = argv.indexOf(flag);
  return i >= 0 ? argv[i + 1] : fallback;
};
const TOTAL = parseInt(argOf('--levels', String(PLANNED)), 10);
const OUT = path.resolve(__dirname, '..', argOf('--out', 'assets/levels/levels.json'));

const levels = [];
const chapters = [];
let exactCount = 0;
let rejected = 0;
let droppedObstacles = 0;
let fragSum = 0;
let id = 0;

for (let ci = 0; ci < CHAPTERS.length && id < TOTAL; ci++) {
  const spec = CHAPTERS[ci];
  const count = Math.min(spec.count || PER_CHAPTER, TOTAL - id);
  const rand = rng((0x9e3779b9 ^ Math.imul(ci + 1, 2654435761)) >>> 0);
  const candidates = [];
  fragSum = 0;

  for (let n = 0; n < count; n++) {
    const t = count === 1 ? 0 : n / (count - 1);
    const isBoss = n === count - 1;
    // The finale carries one more colour than the rest of its chapter, so it
    // sorts to the end on its own and is a board the chapter has not shown
    // before. Capped at the palette.
    const colors = isBoss
        ? Math.min(12, spec.colors[1] + 1)
        : Math.round(spec.colors[0] + (spec.colors[1] - spec.colors[0]) * t);

    // Scramble depth ramps across the chapter, so difficulty rises inside a
    // chapter as well as between chapters.
    const balls = colors * spec.k;
    const minDepth = Math.round(balls * 0.75);
    const maxDepth = Math.round(balls * 2.9);
    const target = Math.round(minDepth + (maxDepth - minDepth) * t);

    // A floor on the solution length, walked up across the chapter.
    //
    // Scramble depth is a poor proxy for difficulty on its own: a deep
    // scramble can wander back to a nearly-sorted board, and those were
    // getting through and reading as filler. Par is the honest measure, so it
    // is now an acceptance criterion rather than only a label. The first few
    // levels of chapter 1 are exempt — they genuinely should be solvable in
    // three or four pours.
    // The finale must out-par everything before it in the chapter, so that
    // "last" and "hardest" are the same level. Generated last in the loop, so
    // every other candidate's par is known by now.
    const chapterMaxPar = candidates.reduce((m, c) => Math.max(m, c.par), 0);
    // Fragmentation floor. Dealt boards are 1.0 by construction; scrambled
    // ones are pushed as high as the scramble can reach, which measurement
    // puts a little above 0.9 for a one-spare board.
    const fragFloor = ci === 0
        ? 0.55 + 0.25 * t
        : (spec.deal === 'frag' ? 0.999 : 0.88);

    // Par floor, now measured against BALLS rather than colours — the old
    // floor was `colours * ~2`, which on a twelve-colour board asked for 24
    // pours when the board could sustain 40.
    // Measured ceilings differ sharply by dealer: a fragmented board reaches
    // about 0.85 pours per ball, a scrambled one about 0.66. One floor for
    // both asks the scramble for a board it cannot make.
    const parCeil = spec.deal === 'frag' ? 0.85 : 0.66;
    const parFloor = ci === 0 && n < 4
        ? 0
        : isBoss
            ? Math.max(chapterMaxPar, Math.round(balls * parCeil * 0.92))
            : Math.round(balls * parCeil * (0.72 + 0.20 * t));

    // Planned before the scramble so the solve runs under the same rules the
    // player will.
    const traits = planTraits(
        ci, n, count, colors + spec.empties, colors, spec.k,
        isBoss ? 2 : (ci >= 1 && (id + 1) % 5 === 0 ? 1 : 0), rand, spec.empties);

    let accepted = null;
    // For a finale the floor is a target, not a gate: at twelve colours and
    // capacity five the search space is deep enough that a board over the
    // chapter's max par may simply not turn up. Keep the hardest one seen.
    let bestSeen = null;

    // The fragmentation floor is a target too, relaxed in steps if the board
    // cannot meet it. A one-spare board at nine colours simply cannot be
    // scrambled to 88% and stay solvable — the two constraints fight, and
    // fragmentation is the one that has to give, because an unsolvable level
    // is not a hard level.
    let floor = fragFloor;
    let pf = parFloor;
    for (let relax = 0; relax < 8 && !accepted; relax++, floor -= 0.05, pf -= Math.max(1, Math.round(balls * 0.04))) {
    for (let attempt = 0; attempt < (isBoss ? 1200 : 260) && !accepted; attempt++) {
      const jitter = Math.round((rand() - 0.5) * 6);
      const cand = withTraits(traits, () => spec.deal === 'frag'
          ? dealFragmented(colors, spec.k, spec.empties, rand)
          : build(colors, spec.empties, spec.k, Math.max(3, target + jitter), rand));
      if (!cand) continue;
      if (isDone(cand, spec.k)) continue;
      if (mixedness(cand) < colors + Math.min(colors, 3)) continue;

      // Reject the boards that hand out free pours. A scrambled board has no
      // control over how many identical balls end up touching, so the floor
      // is applied after the fact; a dealt board is at 1.0 by construction
      // and passes trivially.
      if (fragmentation(cand, balls) < floor) { rejected++; continue; }

      // The acceptance test *is* the solve. A board nothing can finish never
      // reaches a player.
      const solved = withTraits(traits, () => solve(cand, spec.k, colors));
      if (!solved) { rejected++; continue; }
      const found = {
        board: cand, colors, par: solved.par, exact: solved.exact,
        boss: isBoss, traits,
      };
      if (solved.par < pf) {
        if (isBoss && (!bestSeen || found.par > bestSeen.par)) bestSeen = found;
        rejected++;
        continue;
      }
      accepted = found;
    }
    }
    if (!accepted && isBoss && bestSeen) accepted = bestSeen;

    // An obstacle that cannot be made to work on this board is dropped rather
    // than fatal. The alternative is a generator that fails outright because
    // one slot in one chapter got an unlucky combination — the level is worth
    // more than the obstacle.
    if (!accepted && traits.some((t) => t !== 0)) {
      const plain = new Array(traits.length).fill(0);
      for (let attempt = 0; attempt < 800 && !accepted; attempt++) {
        const jitter = Math.round((rand() - 0.5) * 6);
        const cand = withTraits(plain, () => spec.deal === 'frag'
            ? dealFragmented(colors, spec.k, spec.empties, rand)
            : build(colors, spec.empties, spec.k, Math.max(3, target + jitter), rand));
        if (!cand || isDone(cand, spec.k)) continue;
        if (mixedness(cand) < colors + Math.min(colors, 3)) continue;
        const solved = withTraits(plain, () => solve(cand, spec.k, colors));
        if (!solved || solved.par < pf) { rejected++; continue; }
        accepted = {
          board: cand, colors, par: solved.par, exact: solved.exact,
          boss: isBoss, traits: plain,
        };
        droppedObstacles++;
      }
    }
    if (!accepted) {
      console.error(`chapter ${ci + 1}: no solvable board for slot ${n}`);
      process.exit(1);
    }
    fragSum += fragmentation(accepted.board, accepted.colors * spec.k);
    candidates.push(accepted);
    if (process.env.GEN_VERBOSE) {
      process.stderr.write(`\r  ch${String(ci + 1).padStart(2)} ${n + 1}/${count}   `);
    }
  }

  // Order the chapter by its own difficulty, so the ramp inside a chapter is
  // smooth regardless of how the scrambles happened to land.
  candidates.sort((a, b) => (a.boss - b.boss) || a.colors - b.colors || a.par - b.par);

  const first = id + 1;
  for (let pos = 0; pos < candidates.length; pos++) {
    const c = candidates[pos];
    id++;
    if (c.exact) exactCount++;
    // Vessels ordered filled-first so the board reads as a solid block with
    // the spares grouped at the end.
    // Vessels are reordered filled-first for presentation, so their traits
    // have to travel with them — sorting the board and leaving the trait
    // array behind would silently move every obstacle to a different vessel.
    const order = c.board.map((t, i) => i).sort((x, y) => c.board[y].length - c.board[x].length);
    const ordered = order.map((i) => c.board[i]);
    c.traits = order.map((i) => c.traits[i]);

    // Mode. 2 = boss (the chapter finale), 1 = precision (a hard pour budget,
    // every fifth level from chapter 2), 0 = ordinary.
    const mode = c.boss ? 2 : (ci >= 1 && id % 5 === 0 ? 1 : 0);

    // Hidden vessels: from chapter 4, roughly every third level conceals
    // everything below the top ball in a few of its vessels. The count grows
    // slowly with the chapter and never covers every filled vessel, so there
    // is always something to reason from. Precision levels stay fully
    // visible — a pour budget and hidden information together is cruelty,
    // not difficulty.
    let hidden = 0;
    if (ci >= 3 && mode !== 1 && pos % 3 === 1) {
      hidden = Math.min(c.colors - 1, 2 + Math.floor(ci / 6));
    }

    levels.push({
      i: id,
      ch: ci + 1,
      c: c.colors,
      e: spec.empties,
      k: spec.k,
      p: c.par,
      x: c.exact ? 1 : 0,
      m: mode,
      h: hidden,
      ...(encodeTraits(c.traits) ? { v: encodeTraits(c.traits) } : {}),
      t: ordered.map((tube) => tube.map((v) => v.toString(36)).join('')).join(','),
    });
  }
  chapters.push({ n: ci + 1, name: spec.name, from: first, to: id });
  console.error(
    `chapter ${String(ci + 1).padStart(2)} ${spec.name.padEnd(14)} ` +
      `levels ${String(first).padStart(4)}-${String(id).padStart(4)}  ` +
      `colours ${spec.colors.join('-')} spare ${spec.empties} cap ${spec.k}  ` +
      `par ${candidates[0].par}-${candidates[candidates.length - 1].par}  ` +
      `frag ${(100 * fragSum / candidates.length).toFixed(0)}%`,
  );
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(
  OUT,
  JSON.stringify({ version: 1, generated: 'tools/gen_levels.js', chapters, levels }),
);

const bytes = fs.statSync(OUT).size;
console.error(
  `\n${levels.length} levels, ${chapters.length} chapters, ` +
    `${exactCount} with a proven-optimal par ` +
    `(${droppedObstacles} obstacles dropped as unsolvable) ` +
    `(${Math.round((exactCount / levels.length) * 100)}%), ` +
    `${rejected} candidates discarded as unsolvable  ` +
    `-> ${OUT} (${(bytes / 1024).toFixed(0)} KB)`,
);
