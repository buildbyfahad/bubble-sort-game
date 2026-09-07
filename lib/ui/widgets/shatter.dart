import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// The completion effect: a vessel of glass fracturing the moment its last
/// ball lands.
///
/// This is the game's reward beat, and it is built out of five things firing on
/// overlapping schedules rather than one animation:
///
///   1. a flash, over almost immediately, that marks the instant of impact;
///   2. a fracture network that *propagates* — cracks race down from the rim
///      and branch, rather than appearing all at once;
///   3. shards thrown off the rim, each with its own spin and gravity;
///   4. a shockwave ring; and
///   5. glints that run along the cracks after they have stopped growing.
///
/// The propagation is the part that matters. A crack texture that fades in
/// reads as a decal; a crack that travels reads as something breaking, and the
/// difference is most of why this feels like a reward at all.
///
/// The network then *stays*, at a fraction of its peak brightness, so a sealed
/// vessel is permanently marked as finished by its own history rather than by
/// a badge stuck on top of it.

/// One branch of the fracture: a polyline in the vessel's normalised space
/// (0..1 on both axes), plus when it starts growing and how long it takes.
class _Branch {
  const _Branch(this.points, this.delay, this.span, this.width);

  final List<Offset> points;
  final double delay;
  final double span;
  final double width;
}

/// A thrown piece of glass, in normalised space, with a velocity in units of
/// vessel-widths per unit of animation time.
class _Shard {
  const _Shard(this.origin, this.velocity, this.spin, this.size, this.delay);

  final Offset origin;
  final Offset velocity;
  final double spin;
  final double size;
  final double delay;
}

/// The generated fracture for one vessel.
///
/// Deterministic from a seed and cached, so a given vessel cracks the same way
/// every time it is painted — a pattern that reshuffles between frames would
/// strobe — while two vessels on the same board never crack alike.
class Fracture {
  Fracture._(this._branches, this._shards);

  static final Map<int, Fracture> _cache = <int, Fracture>{};

  // Private because their element types are: the generated geometry is an
  // implementation detail of this file, and only ShatterPainter reads it.
  final List<_Branch> _branches;
  final List<_Shard> _shards;

  factory Fracture.forSeed(int seed) =>
      _cache.putIfAbsent(seed & 0xFF, () => Fracture._generate(seed & 0xFF));

  static Fracture _generate(int seed) {
    final math.Random r = math.Random(seed * 7919 + 13);
    final List<_Branch> branches = <_Branch>[];

    // Impact point: near the rim, where the last ball came in, offset a little
    // so the star of cracks is never symmetrical. Symmetry is the tell that a
    // fracture was drawn rather than propagated.
    final Offset impact = Offset(0.34 + r.nextDouble() * 0.32, 0.10 + r.nextDouble() * 0.08);

    // --- primaries: long runs from the impact toward the base --------------
    final int primaries = 6 + r.nextInt(3);
    for (int i = 0; i < primaries; i++) {
      // Fan biased downward — glass under a rim strike fractures with the
      // blow, not back up out of it.
      final double angle =
          math.pi * (0.16 + 0.68 * (i + r.nextDouble() * 0.6) / primaries);
      final double reach = 0.34 + r.nextDouble() * 0.38;

      final List<Offset> pts = <Offset>[impact];
      Offset p = impact;
      double a = angle;
      // Many short segments rather than a few long ones. A crack drawn in
      // three strokes reads as a scratch however much you jitter the angles;
      // it needs enough joints to visibly hunt for the weakest path.
      final int segs = 5 + r.nextInt(3);
      for (int s = 0; s < segs; s++) {
        a += (r.nextDouble() - 0.5) * 1.15;
        final double step = reach / segs;
        p = Offset(p.dx + math.cos(a) * step * 0.62, p.dy + math.sin(a) * step);
        pts.add(p);
      }
      branches.add(_Branch(pts, 0.0, 0.30 + r.nextDouble() * 0.14, 1.6));

      // --- secondaries: short splinters off a primary's midpoint -----------
      if (r.nextDouble() < 0.75) {
        final int from = 1 + r.nextInt(pts.length - 1);
        final Offset root = pts[from];
        double sa = a + (r.nextBool() ? 1 : -1) * (0.5 + r.nextDouble() * 0.7);
        final List<Offset> sp = <Offset>[root];
        Offset q = root;
        for (int s = 0; s < 2; s++) {
          sa += (r.nextDouble() - 0.5) * 0.5;
          final double step = 0.10 + r.nextDouble() * 0.13;
          q = Offset(q.dx + math.cos(sa) * step * 0.7, q.dy + math.sin(sa) * step);
          sp.add(q);
        }
        // Delayed: a splinter cannot start before the crack it grows out of
        // has reached the point it grows from.
        branches.add(_Branch(sp, 0.12 + r.nextDouble() * 0.16, 0.24, 0.9));
      }
    }

    // --- concentric rings, crossing the radials ----------------------------
    //
    // The piece that turns a starburst into a fracture. Struck glass cracks
    // both outward from the impact and *around* it; without the rings this
    // looks like a firework, and no amount of work on the radials fixes that.
    for (int ring = 0; ring < 2; ring++) {
      final double radius = 0.20 + ring * 0.19 + r.nextDouble() * 0.06;
      final double from = math.pi * (0.14 + r.nextDouble() * 0.2);
      final double to = math.pi * (0.86 - r.nextDouble() * 0.2);
      final List<Offset> arc = <Offset>[];
      const int steps = 5;
      for (int k = 0; k <= steps; k++) {
        // Deliberately not a circle: each vertex is pushed in or out a little,
        // so the ring is a chain of straight chords between radials rather
        // than a drawn curve.
        final double ang = from + (to - from) * (k / steps);
        final double rad = radius * (0.86 + r.nextDouble() * 0.28);
        arc.add(Offset(impact.dx + math.cos(ang) * rad * 0.66,
            impact.dy + math.sin(ang) * rad));
      }
      branches.add(_Branch(arc, 0.16 + ring * 0.10, 0.26, 1.0));
    }

    // --- a couple of rim cracks, running across rather than down -----------
    for (int i = 0; i < 2; i++) {
      final double y = 0.06 + r.nextDouble() * 0.05;
      final double x0 = r.nextDouble() * 0.4;
      branches.add(_Branch(
        <Offset>[
          Offset(x0, y),
          Offset(x0 + 0.22, y + (r.nextDouble() - 0.5) * 0.05),
          Offset(x0 + 0.44, y + (r.nextDouble() - 0.5) * 0.06),
        ],
        0.04 + r.nextDouble() * 0.10,
        0.22,
        0.8,
      ));
    }

    // --- shards ------------------------------------------------------------
    final List<_Shard> shards = <_Shard>[];
    final int count = 17 + r.nextInt(6);
    for (int i = 0; i < count; i++) {
      // Thrown from around the mouth, since that is where the vessel is open.
      final double x = 0.10 + r.nextDouble() * 0.80;
      final double y = 0.04 + r.nextDouble() * 0.22;
      // Outward from the centre line, and up: an ejection, not a spill.
      final double lateral = (x - 0.5) * (2.4 + r.nextDouble() * 2.2);
      shards.add(_Shard(
        Offset(x, y),
        Offset(lateral * 0.34, -(0.75 + r.nextDouble() * 1.15)),
        (r.nextDouble() - 0.5) * 18,
        0.055 + r.nextDouble() * 0.105,
        r.nextDouble() * 0.10,
      ));
    }

    return Fracture._(branches, shards);
  }
}

/// Paints [fracture] over a vessel.
///
/// [t] runs 0→1 across the seal animation. [settled] switches to the quiet
/// permanent etch used for a vessel that was already finished when the board
/// was built — after an undo, or on a rebuild — so a completed vessel looks
/// completed without replaying its celebration.
class ShatterPainter extends CustomPainter {
  ShatterPainter({
    required this.t,
    required this.fracture,
    required this.hue,
    required this.shape,
    this.settled = false,
  });

  final double t;
  final Fracture fracture;
  final BubbleHue hue;

  /// The vessel silhouette, so the cracks are clipped to the glass and the
  /// shockwave traces the real outline.
  final RRect Function(Size) shape;

  final bool settled;

  /// How bright the fracture stays once the celebration is over.
  static const double _etch = 0.26;

  @override
  void paint(Canvas canvas, Size size) {
    if (settled) {
      canvas.save();
      canvas.clipRRect(shape(size));
      _paintBranches(canvas, size, progress: 1.0, intensity: _etch);
      canvas.restore();
      return;
    }
    if (t <= 0) return;

    final RRect body = shape(size);

    // --- 1. impact flash ---------------------------------------------------
    //
    // Two frames of light. Long enough to register as the moment of contact,
    // short enough that it is never seen as a fade.
    final double flash = (1 - (t / 0.13)).clamp(0.0, 1.0);
    if (flash > 0) {
      final double f = flash * flash;
      canvas.drawRRect(
        body,
        Paint()
          ..color = Color.lerp(hue.light, const Color(0xFFFFFFFF), 0.45)!
              .withValues(alpha: 0.78 * f)
          ..blendMode = BlendMode.plus,
      );
    }

    // --- 2. cracks ---------------------------------------------------------
    canvas.save();
    canvas.clipRRect(body);
    // Full brightness while growing, easing back to the permanent etch once
    // the celebration is over.
    final double bright =
        t < 0.55 ? 1.0 : 1.0 - (1 - _etch) * ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    _paintBranches(canvas, size, progress: t, intensity: bright);

    // --- 5. glints ---------------------------------------------------------
    //
    // A highlight running along the fracture after it has stopped growing —
    // the light catching a fresh edge.
    if (t > 0.34 && t < 0.92) {
      _paintGlints(canvas, size, ((t - 0.34) / 0.58).clamp(0.0, 1.0));
    }
    canvas.restore();

    // --- 4. shockwave ------------------------------------------------------
    if (t < 0.62) {
      final double p = Curves.easeOutCubic.transform((t / 0.62).clamp(0.0, 1.0));
      final double fade = (1 - p) * (1 - p);
      canvas.drawRRect(
        body.inflate(p * size.width * 0.52),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 * (1 - p * 0.7)
          ..color = hue.light.withValues(alpha: 0.6 * fade),
      );
    }

    // --- 3. shards ---------------------------------------------------------
    _paintShards(canvas, size);
  }

  void _paintBranches(
    Canvas canvas,
    Size size, {
    required double progress,
    required double intensity,
  }) {
    if (intensity <= 0.001) return;
    final double w = size.width;

    for (final _Branch b in fracture._branches) {
      final double local =
          ((progress - b.delay) / b.span).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final double grown = Curves.easeOutCubic.transform(local);

      final Path? path = _grow(b.points, size, grown);
      if (path == null) continue;

      // Tapered, drawn segment by segment: wide at the impact and closing to
      // nothing at the tip.
      //
      // A constant-width stroke is the single thing that made the first
      // version of this read as white scribble rather than as broken glass.
      // A real fracture is widest where it was struck and vanishes where it
      // ran out of energy, and the eye knows that even when it cannot say why.
      _taperedStroke(
        canvas,
        b.points,
        size,
        grown,
        width: b.width * w * 0.075,
        color: DS.inkDeep.withValues(alpha: 0.60 * intensity),
      );
      _taperedStroke(
        canvas,
        b.points,
        size,
        grown,
        width: b.width * w * 0.030,
        color: Color.lerp(hue.light, const Color(0xFFFFFFFF), 0.22)!
            .withValues(alpha: 0.92 * intensity),
      );

      // A bloom at the growing tip while it is still travelling.
      if (local < 1 && intensity > 0.5) {
        final Offset tip = _pointAt(b.points, size, grown);
        canvas.drawCircle(
          tip,
          w * 0.05 * (1 - local),
          Paint()
            ..color = hue.light.withValues(alpha: 0.5 * (1 - local) * intensity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03)
            ..blendMode = BlendMode.plus,
        );
      }
    }
  }

  void _paintGlints(Canvas canvas, Size size, double p) {
    final double w = size.width;
    final double fade = math.sin(p * math.pi);
    for (int i = 0; i < fracture._branches.length; i += 2) {
      final _Branch b = fracture._branches[i];
      // Each glint starts at a different point along its crack, so they read
      // as light moving rather than as one synchronised sweep.
      final double at = ((p + i * 0.17) % 1.0);
      final Offset c = _pointAt(b.points, size, at);
      canvas.drawCircle(
        c,
        w * 0.035,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5 * fade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.025)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  void _paintShards(Canvas canvas, Size size) {
    final double w = size.width;
    for (final _Shard s in fracture._shards) {
      final double local = ((t - s.delay) / (1 - s.delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;

      // Ballistic: constant lateral velocity, gravity on the vertical. The
      // shard therefore slows, turns over and falls, which is what makes a
      // handful of triangles read as debris.
      final double px = s.origin.dx + s.velocity.dx * local;
      final double py =
          s.origin.dy + s.velocity.dy * local + 1.5 * local * local;

      final Offset c = Offset(px * w, py * size.height);
      final double fade = (1 - local) * (1 - local);
      final double side = s.size * w * (0.75 + 0.25 * (1 - local));

      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(s.spin * local);

      final Path tri = Path()
        ..moveTo(0, -side)
        ..lineTo(side * 0.86, side * 0.5)
        ..lineTo(-side * 0.86, side * 0.5)
        ..close();

      canvas.drawPath(
        tri,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, -side),
            Offset(0, side),
            <Color>[
              Color.lerp(const Color(0xFFFFFFFF), hue.light, 0.35)!
                  .withValues(alpha: 0.95 * fade),
              hue.base.withValues(alpha: 0.8 * fade),
            ],
          ),
      );
      canvas.drawPath(
        tri,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85 * fade),
      );
      canvas.restore();
    }
  }

  /// Strokes the first [grown] fraction of a polyline with a width that falls
  /// to zero along its length.
  ///
  /// Flutter has no variable-width stroke, so this walks the line and draws
  /// each short segment with its own paint. At these lengths that is a handful
  /// of draw calls and cheaper than building a polygon per crack.
  static void _taperedStroke(
    Canvas canvas,
    List<Offset> pts,
    Size size,
    double grown, {
    required double width,
    required Color color,
  }) {
    if (pts.length < 2 || grown <= 0) return;
    final List<Offset> px = <Offset>[
      for (final Offset p in pts) Offset(p.dx * size.width, p.dy * size.height),
    ];
    final double total = _length(px);
    if (total <= 0) return;

    const int steps = 14;
    final double end = total * grown;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    for (int i = 0; i < steps; i++) {
      final double a = end * (i / steps);
      final double b = end * ((i + 1) / steps);
      // Taper against position along the *whole* crack, not the grown part,
      // so the profile does not rescale as the fracture travels.
      final double at = (b / total).clamp(0.0, 1.0);
      paint.strokeWidth = width * (1 - at * 0.88);
      canvas.drawLine(
        _walk(px, a),
        _walk(px, b),
        paint,
      );
    }
  }

  /// The point [d] pixels along a polyline.
  static Offset _walk(List<Offset> px, double d) {
    double want = d;
    for (int i = 1; i < px.length; i++) {
      final double seg = (px[i] - px[i - 1]).distance;
      if (want <= seg) {
        return Offset.lerp(px[i - 1], px[i], seg == 0 ? 0 : want / seg)!;
      }
      want -= seg;
    }
    return px.last;
  }

  // ------------------------------------------------------------- polyline maths

  /// The first [grown] fraction of a polyline, by arc length, in pixels.
  static Path? _grow(List<Offset> pts, Size size, double grown) {
    if (pts.length < 2 || grown <= 0) return null;
    final List<Offset> px = <Offset>[
      for (final Offset p in pts) Offset(p.dx * size.width, p.dy * size.height),
    ];
    final double total = _length(px);
    if (total <= 0) return null;

    double want = total * grown;
    final Path path = Path()..moveTo(px.first.dx, px.first.dy);
    for (int i = 1; i < px.length; i++) {
      final double seg = (px[i] - px[i - 1]).distance;
      if (want >= seg) {
        path.lineTo(px[i].dx, px[i].dy);
        want -= seg;
      } else {
        final Offset p = Offset.lerp(px[i - 1], px[i], seg == 0 ? 0 : want / seg)!;
        path.lineTo(p.dx, p.dy);
        break;
      }
    }
    return path;
  }

  /// The point at [at] along a polyline, by arc length, in pixels.
  static Offset _pointAt(List<Offset> pts, Size size, double at) {
    final List<Offset> px = <Offset>[
      for (final Offset p in pts) Offset(p.dx * size.width, p.dy * size.height),
    ];
    double want = _length(px) * at.clamp(0.0, 1.0);
    for (int i = 1; i < px.length; i++) {
      final double seg = (px[i] - px[i - 1]).distance;
      if (want <= seg) {
        return Offset.lerp(px[i - 1], px[i], seg == 0 ? 0 : want / seg)!;
      }
      want -= seg;
    }
    return px.last;
  }

  static double _length(List<Offset> px) {
    double n = 0;
    for (int i = 1; i < px.length; i++) {
      n += (px[i] - px[i - 1]).distance;
    }
    return n;
  }

  @override
  bool shouldRepaint(ShatterPainter old) =>
      old.t != t ||
      old.settled != settled ||
      old.hue != hue ||
      !identical(old.fracture, fracture);
}
