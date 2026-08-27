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
  { name: 'First Pours',   colors: [2, 4],   empties: 2, k: 4 },
  { name: 'Settling',      colors: [4, 5],   empties: 2, k: 4 },
  { name: 'Decanting',     colors: [5, 6],   empties: 2, k: 4 },
  { name: 'Sediment',      colors: [6, 6],   empties: 2, k: 4 },
  { name: 'Meniscus',      colors: [6, 7],   empties: 2, k: 4 },
  { name: 'Narrow Room',   colors: [6, 7],   empties: 1, k: 4 },
  { name: 'Suspension',    colors: [7, 8],   empties: 2, k: 4 },
  { name: 'Deep Vessels',  colors: [7, 8],   empties: 2, k: 5 },
  { name: 'Titration',     colors: [8, 8],   empties: 1, k: 4 },
  { name: 'Cascade',       colors: [8, 9],   empties: 2, k: 4 },
  { name: 'Decant Deeper', colors: [8, 9],   empties: 2, k: 5 },
  { name: 'Residue',       colors: [9, 9],   empties: 1, k: 4 },
  { name: 'Emulsion',      colors: [9, 10],  empties: 2, k: 4 },
  { name: 'Column',        colors: [9, 10],  empties: 2, k: 5 },
  { name: 'Filtrate',      colors: [10, 10], empties: 1, k: 4 },
  { name: 'Solvent',       colors: [10, 11], empties: 2, k: 4 },
  { name: 'Reflux',        colors: [10, 10], empties: 2, k: 5 },
  { name: 'Precipitate',   colors: [11, 11], empties: 1, k: 4 },
  { name: 'Fractions',     colors: [11, 12], empties: 2, k: 4 },
  { name: 'Saturation',    colors: [12, 12], empties: 2, k: 4 },
  { name: 'Distillate',    colors: [11, 11], empties: 2, k: 5 },
  { name: 'Supernatant',   colors: [12, 12], empties: 1, k: 4 },
  { name: 'Crystalline',   colors: [12, 12], empties: 2, k: 5 },
  { name: 'Azeotrope',     colors: [11, 11], empties: 1, k: 5 },
  { name: 'Equilibrium',   colors: [12, 12], empties: 1, k: 5 },
];

const PER_CHAPTER = 40;

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

function key(s) {
  // Order-independent: two boards differing only in which vessel holds which
  // stack are the same search node.
  const parts = new Array(s.length);
  for (let i = 0; i < s.length; i++) parts[i] = s[i].join('.');
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
      if (to.length === 0) {
        if (pure) continue; // pointless re-parking
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
  let room = k - n[j].length;
  while (n[i].length && n[i][n[i].length - 1] === c && room > 0) {
    n[j].push(n[i].pop());
    room--;
  }
  return n;
}

// ------------------------------------------------------------------ search

/** Exact optimum via A*. Returns null if it exceeds the node budget. */
function solveExact(start, k, colors, nodeCap) {
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

// -------------------------------------------------------------- generation

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
const TOTAL = parseInt(argOf('--levels', String(CHAPTERS.length * PER_CHAPTER)), 10);
const OUT = path.resolve(__dirname, '..', argOf('--out', 'assets/levels/levels.json'));

const levels = [];
const chapters = [];
let exactCount = 0;
let rejected = 0;
let id = 0;

for (let ci = 0; ci < CHAPTERS.length && id < TOTAL; ci++) {
  const spec = CHAPTERS[ci];
  const count = Math.min(PER_CHAPTER, TOTAL - id);
  const rand = rng((0x9e3779b9 ^ Math.imul(ci + 1, 2654435761)) >>> 0);
  const candidates = [];

  for (let n = 0; n < count; n++) {
    const t = count === 1 ? 0 : n / (count - 1);
    const colors = Math.round(spec.colors[0] + (spec.colors[1] - spec.colors[0]) * t);

    // Scramble depth ramps across the chapter, so difficulty rises inside a
    // chapter as well as between chapters.
    const balls = colors * spec.k;
    const minDepth = Math.round(balls * 0.55);
    const maxDepth = Math.round(balls * 2.4);
    const target = Math.round(minDepth + (maxDepth - minDepth) * t);

    let accepted = null;
    for (let attempt = 0; attempt < 800 && !accepted; attempt++) {
      const jitter = Math.round((rand() - 0.5) * 6);
      const cand = build(colors, spec.empties, spec.k, Math.max(3, target + jitter), rand);
      if (!cand) continue;
      if (isDone(cand, spec.k)) continue;
      if (mixedness(cand) < colors + Math.min(colors, 3)) continue;

      // The acceptance test *is* the solve. A board nothing can finish never
      // reaches a player.
      const solved = solve(cand, spec.k, colors);
      if (!solved) { rejected++; continue; }
      accepted = { board: cand, colors, par: solved.par, exact: solved.exact };
    }
    if (!accepted) {
      console.error(`chapter ${ci + 1}: no solvable board for slot ${n}`);
      process.exit(1);
    }
    candidates.push(accepted);
  }

  // Order the chapter by its own difficulty, so the ramp inside a chapter is
  // smooth regardless of how the scrambles happened to land.
  candidates.sort((a, b) => a.colors - b.colors || a.par - b.par);

  const first = id + 1;
  for (const c of candidates) {
    id++;
    if (c.exact) exactCount++;
    // Vessels ordered filled-first so the board reads as a solid block with
    // the spares grouped at the end.
    const ordered = c.board.slice().sort((a, b) => b.length - a.length);
    levels.push({
      i: id,
      ch: ci + 1,
      c: c.colors,
      e: spec.empties,
      k: spec.k,
      p: c.par,
      x: c.exact ? 1 : 0,
      t: ordered.map((tube) => tube.map((v) => v.toString(36)).join('')).join(','),
    });
  }
  chapters.push({ n: ci + 1, name: spec.name, from: first, to: id });
  console.error(
    `chapter ${String(ci + 1).padStart(2)} ${spec.name.padEnd(14)} ` +
      `levels ${String(first).padStart(4)}-${String(id).padStart(4)}  ` +
      `colours ${spec.colors.join('-')} spare ${spec.empties} cap ${spec.k}  ` +
      `par ${candidates[0].par}-${candidates[candidates.length - 1].par}`,
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
    `(${Math.round((exactCount / levels.length) * 100)}%), ` +
    `${rejected} candidates discarded as unsolvable  ` +
    `-> ${OUT} (${(bytes / 1024).toFixed(0)} KB)`,
);
