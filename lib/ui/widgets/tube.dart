import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'bubble.dart';
import 'shatter.dart';

/// Geometry for one vessel, derived from a single input: the ball diameter.
///
/// Everything else — wall thickness, inner padding, how far a selected stack
/// lifts — is a ratio of that, so the board scales cleanly from a small phone
/// to a tablet without a single hard-coded pixel value.
class TubeMetrics {
  const TubeMetrics(this.ball, this.capacity);

  final double ball;
  final int capacity;

  /// Clearance between a ball and the vessel wall. Generous on purpose: balls
  /// that touch the glass make the vessel disappear behind its contents, which
  /// is the single most common reason boards in this genre look cheap.
  double get sidePad => ball * 0.23;
  double get innerPad => ball * 0.20;
  double get width => ball + sidePad * 2;

  /// Vertical pitch between stacked balls — a hair over one diameter, so the
  /// stack reads as separate objects resting on each other rather than as one
  /// continuous bar of colour.
  double get pitch => ball * 1.04;

  double get bodyHeight => pitch * capacity + innerPad * 2;

  /// Headroom above the rim for a lifted stack.
  ///
  /// Must be at least a full ball plus the hover gap, or a lifted stack pokes
  /// out of the top of its own layout box - which on a multi-row board makes it
  /// look like it belongs to the vessel in the row above.
  double get liftZone => ball * 1.20;

  double get totalHeight => bodyHeight + liftZone;

  /// Centre of slot [k] (0 = resting on the base) in widget coordinates.
  Offset ballCenter(int k) => Offset(
        width / 2,
        liftZone + bodyHeight - innerPad - pitch * k - ball * 0.5,
      );

  /// Where a lifted ball hovers, [k] counted from the bottom of the lifted run.
  Offset liftCenter(int k) => Offset(width / 2, liftZone * 0.50 - ball * k * 0.94);

  /// The point a pour is thrown from and arrives at — just above the rim.
  double get rimY => liftZone;
}

/// The vessel silhouette, shared by everything that has to trace it.
///
/// Not a plain U-tube. The mouth is slightly flared and squared off while the
/// base is a deep bowl, which gives the silhouette a direction — you can tell
/// at a glance which end things pour out of.
RRect vesselShape(Size s) => RRect.fromRectAndCorners(
      Offset.zero & s,
      topLeft: Radius.circular(s.width * 0.20),
      topRight: Radius.circular(s.width * 0.20),
      bottomLeft: Radius.circular(s.width * 0.46),
      bottomRight: Radius.circular(s.width * 0.46),
    );

/// A vessel: back glass, contents, front glass.
///
/// The three-pass structure is the whole trick. Balls are drawn *between* two
/// glass layers, so the front sheen and the rim's inner shadow fall across
/// them — that is what sells the contents as being inside something, rather
/// than as circles stacked in front of a tube-shaped picture.
class Tube extends StatefulWidget {
  const Tube({
    super.key,
    required this.contents,
    required this.metrics,
    required this.selected,
    required this.liftCount,
    required this.sealed,
    required this.colorAssist,
    required this.rejectToken,
    required this.settleToken,
    required this.settleCount,
    required this.sealToken,
    required this.hinted,
    required this.dim,
    required this.onTap,
    this.fractureSeed = 0,
  });

  /// Chooses which of the generated fracture patterns this vessel breaks
  /// along. Two vessels sealing on the same board must not crack identically.
  final int fractureSeed;

  /// Visible contents, bottom-up, as hue indices.
  final List<int> contents;
  final TubeMetrics metrics;

  final bool selected;

  /// How many balls at the top are hovering out of the mouth.
  final int liftCount;

  final bool sealed;
  final bool colorAssist;

  /// Bumping this plays the refusal shake.
  final int rejectToken;

  /// Bumping this plays the landing squash on the top [settleCount] balls.
  final int settleToken;
  final int settleCount;

  /// Bumping this plays the seal bloom.
  final int sealToken;

  /// Marked as the destination the hint is pointing at.
  final bool hinted;

  /// Pushes the vessel back while another one holds the player's attention.
  final double dim;

  final VoidCallback onTap;

  @override
  State<Tube> createState() => _TubeState();
}

class _TubeState extends State<Tube> with TickerProviderStateMixin {
  late final AnimationController _select;
  late final AnimationController _shake;
  late final AnimationController _settle;
  late final AnimationController _seal;
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    // Deliberately shorter than DS.tBase. Lifting a stack is a direct
    // response to a touch, and a direct response is the one thing in the game
    // that must never be seen to travel.
    _select = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 150),
        value: widget.selected ? 1 : 0);
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _seal = AnimationController(vsync: this, duration: DS.tCelebrate, value: widget.sealed ? 1 : 0);
    _press = AnimationController(vsync: this, duration: DS.tPress);
  }

  @override
  void didUpdateWidget(Tube old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) {
      widget.selected ? _select.forward() : _select.reverse();
    }
    if (widget.rejectToken != old.rejectToken) {
      _shake.forward(from: 0);
    }
    if (widget.settleToken != old.settleToken && widget.settleCount > 0) {
      _settle.forward(from: 0);
    }
    // Guarded on the token being a real one. The board hands back -1 once the
    // celebration beat is over, and that is a *change* to the token — without
    // this check it restarts the shatter from zero halfway through, and the
    // vessel breaks twice.
    if (widget.sealToken != old.sealToken && widget.sealToken >= 0) {
      _seal.forward(from: 0);
    } else if (widget.sealed && _seal.value == 0 && !_seal.isAnimating) {
      _seal.value = 1; // restored mid-board (undo, rebuild) — no replay
    } else if (!widget.sealed && _seal.value != 0 && !_seal.isAnimating) {
      _seal.value = 0;
    }
  }

  @override
  void dispose() {
    _select.dispose();
    _shake.dispose();
    _settle.dispose();
    _seal.dispose();
    _press.dispose();
    super.dispose();
  }

  /// Damped oscillation: three diminishing swings, not a buzzing rectangle.
  double _shakeOffset(double t) {
    if (t == 0) return 0;
    return math.sin(t * math.pi * 5) * (1 - t) * (1 - t) * widget.metrics.ball * 0.22;
  }

  @override
  Widget build(BuildContext context) {
    final TubeMetrics m = widget.metrics;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press.forward(),
      onTapCancel: () => _press.reverse(),
      onTapUp: (_) => _press.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_select, _shake, _settle, _seal, _press]),
        builder: (BuildContext context, _) {
          final double sel = Curves.easeOutCubic.transform(_select.value);
          final double sealT = _seal.value;
          final double press = Curves.easeOut.transform(_press.value);

          // A selected vessel rises and scales a touch; a pressed one dips.
          // Both are small enough to feel like a response rather than an event.
          final double lift = sel * m.ball * 0.20 - press * m.ball * 0.05;

          // The seal punch: one hard swell in the first fifth of the
          // celebration, gone by the time the shards are in the air. An
          // impact the whole object registers is what stops a completion
          // reading as a colour change.
          final double punchT = (sealT / 0.22).clamp(0.0, 1.0);
          final double punch =
              punchT > 0 && punchT < 1 ? math.sin(punchT * math.pi) * (1 - punchT) * 0.26 : 0.0;

          final double scale = 1 + sel * 0.028 - press * 0.022 + punch;

          return Transform.translate(
            offset: Offset(_shakeOffset(_shake.value), -lift),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: m.width,
                height: m.totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    // --- back glass + cast shadow ---------------------------
                    Positioned(
                      left: 0,
                      top: m.liftZone,
                      width: m.width,
                      height: m.bodyHeight,
                      child: CustomPaint(
                        painter: _VesselBackPainter(
                          metrics: m,
                          selection: sel,
                          seal: sealT,
                          sealed: widget.sealed,
                          sealHue: widget.sealed && widget.contents.isNotEmpty
                              ? DS.hues[widget.contents.first]
                              : null,
                          hinted: widget.hinted,
                          dim: widget.dim,
                        ),
                        isComplex: true,
                        willChange: sel > 0 && sel < 1,
                      ),
                    ),

                    // --- contents -------------------------------------------
                    ..._buildResting(m),

                    // --- front glass ----------------------------------------
                    Positioned(
                      left: 0,
                      top: m.liftZone,
                      width: m.width,
                      height: m.bodyHeight,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _VesselFrontPainter(metrics: m, selection: sel, dim: widget.dim),
                        ),
                      ),
                    ),

                    // --- fracture, above both glass layers ------------------
                    //
                    // Drawn last of the vessel's own layers on purpose: the
                    // cracks are in the *near* face of the glass, so they must
                    // sit over the contents and over the sheen. Putting them
                    // behind either one immediately reads as a texture printed
                    // on the back wall.
                    if ((sealT > 0 || widget.sealed) && widget.contents.isNotEmpty)
                      Positioned(
                        left: 0,
                        top: m.liftZone,
                        width: m.width,
                        height: m.bodyHeight,
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: ShatterPainter(
                              t: sealT,
                              // Once the celebration is over the network stays
                              // as a quiet etch, so a finished vessel carries
                              // the mark of having been finished.
                              settled: widget.sealed && sealT >= 1 && !_seal.isAnimating,
                              fracture: Fracture.forSeed(widget.fractureSeed),
                              hue: DS.hues[widget.contents.first],
                              shape: vesselShape,
                            ),
                            isComplex: true,
                            willChange: _seal.isAnimating,
                          ),
                        ),
                      ),

                    // --- lifted stack, above the glass ----------------------
                    ..._buildLifted(m, sel),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildResting(TubeMetrics m) {
    final int restingCount = widget.contents.length - (widget.selected ? widget.liftCount : 0);
    final List<Widget> out = <Widget>[];
    for (int k = 0; k < restingCount; k++) {
      final Offset c = m.ballCenter(k);

      // Landing squash, applied only to the balls that just arrived. Volume is
      // preserved (wider as it flattens), which is what makes it read as a
      // soft object settling rather than a sprite being scaled.
      double sx = 1, sy = 1;
      final int fromTop = restingCount - 1 - k;
      if (_settle.isAnimating && fromTop < widget.settleCount) {
        final double delay = fromTop * 0.12;
        final double t = ((_settle.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        final double squash = math.sin(t * math.pi) * (1 - t) * 0.9;
        sy = 1 - squash * 0.16;
        sx = 1 + squash * 0.13;
      }

      out.add(Positioned(
        left: c.dx - m.ball / 2,
        top: c.dy - m.ball / 2,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(sx, sy, 1),
          child: Bubble(
            hue: DS.hues[widget.contents[k]],
            size: m.ball,
            colorAssist: widget.colorAssist,
            dim: widget.dim,
          ),
        ),
      ));
    }
    return out;
  }

  List<Widget> _buildLifted(TubeMetrics m, double sel) {
    if (!widget.selected || widget.liftCount == 0) return const <Widget>[];
    final List<Widget> out = <Widget>[];
    final int start = widget.contents.length - widget.liftCount;
    for (int k = 0; k < widget.liftCount; k++) {
      final Offset rest = m.ballCenter(start + k);
      final Offset up = m.liftCenter(widget.liftCount - 1 - k);
      // Staggered so the run peels out of the mouth instead of teleporting as
      // a block.
      final double delay = k * 0.10;
      final double t = Ease.overshoot.transform(((sel - delay) / (1 - delay)).clamp(0.0, 1.0));
      final Offset c = Offset.lerp(rest, up, t)!;
      out.add(Positioned(
        left: c.dx - m.ball / 2,
        top: c.dy - m.ball / 2,
        child: Bubble(
          hue: DS.hues[widget.contents[start + k]],
          size: m.ball,
          colorAssist: widget.colorAssist,
          elevation: 1 + t * 1.4,
        ),
      ));
    }
    return out;
  }
}

/// The vessel silhouette: outer shape, interior glass, side specular, and the
/// state treatments (selection ring, seal bloom, hint ring).
class _VesselBackPainter extends CustomPainter {
  _VesselBackPainter({
    required this.metrics,
    required this.selection,
    required this.seal,
    required this.sealed,
    required this.sealHue,
    required this.hinted,
    required this.dim,
  });

  final TubeMetrics metrics;
  final double selection;
  final double seal;
  final bool sealed;
  final BubbleHue? sealHue;
  final bool hinted;
  final double dim;

  static RRect shape(Size s) => vesselShape(s);

  @override
  void paint(Canvas canvas, Size size) {
    final RRect body = shape(size);
    final double w = size.width;

    // Ground contact shadow, tightening as the vessel lifts on selection.
    final Rect ground = Rect.fromCenter(
      center: Offset(w / 2, size.height + w * 0.10 + selection * w * 0.14),
      width: w * (1.5 - selection * 0.24),
      height: w * (0.40 - selection * 0.08),
    );
    canvas.drawOval(
      ground,
      Paint()
        ..shader = ui.Gradient.radial(
          ground.center,
          ground.width / 2,
          <Color>[
            const Color(0xFF000000).withValues(alpha: 0.46 - selection * 0.10),
            const Color(0x00000000),
          ],
          <double>[0.0, 1.0],
          TileMode.clamp,
          Matrix4.diagonal3Values(1, ground.height / ground.width, 1).storage,
        ),
    );

    // Interior. Darker than the page so contents pop, with a slight warm lift
    // near the mouth where ambient light would actually reach.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          <Color>[
            Color.lerp(DS.surfaceHigh, DS.inkDeep, 0.42 + dim * 0.25)!.withValues(alpha: 0.94),
            Color.lerp(DS.inkDeep, DS.surface, 0.16 - dim * 0.1)!.withValues(alpha: 0.97),
          ],
        ),
    );

    // Left-hand specular streak — a single soft vertical band. The classic
    // two hard white stripes read as clip-art; one soft band reads as glass.
    final Rect streak = Rect.fromLTWH(w * 0.14, size.height * 0.06, w * 0.16, size.height * 0.80);
    canvas.drawRRect(
      RRect.fromRectAndRadius(streak, Radius.circular(w * 0.09)),
      Paint()
        ..shader = ui.Gradient.linear(
          streak.topCenter,
          streak.bottomCenter,
          <Color>[
            const Color(0xFFFFFFFF).withValues(alpha: 0.11 * (1 - dim * 0.6)),
            const Color(0xFFFFFFFF).withValues(alpha: 0.022 * (1 - dim * 0.6)),
            const Color(0x00FFFFFF),
          ],
          <double>[0.0, 0.55, 1.0],
        ),
    );

    // Seal bloom — a colour wash that floods up from the base, then a ring
    // that expands once and fades. One gesture, no particle storm.
    if (sealHue != null && (seal > 0 || sealed)) {
      final double t = sealed && seal == 0 ? 1 : seal;
      final double wash = sealed ? 0.16 : math.sin(t * math.pi).clamp(0.0, 1.0) * 0.22 + 0.16 * t;
      canvas.drawRRect(
        body,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, size.height),
            Offset(0, 0),
            <Color>[
              sealHue!.base.withValues(alpha: wash),
              sealHue!.base.withValues(alpha: wash * 0.15),
            ],
          )
          ..blendMode = BlendMode.plus,
      );

      if (t < 1) {
        final double ring = Curves.easeOutCubic.transform(t);
        final double fade = (1 - t) * (1 - t);
        canvas.drawRRect(
          body.inflate(ring * w * 0.34),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 * (1 - ring * 0.6)
            ..color = sealHue!.light.withValues(alpha: 0.55 * fade),
        );
      }
    }

    // Edge. Brightest at the mouth, fading toward the base — a rim catching a
    // light source that lives above the board.
    final Color edgeTop = sealed && sealHue != null
        ? Color.lerp(DS.hairlineStrong, sealHue!.light.withValues(alpha: 0.5), 0.75)!
        : Color.lerp(DS.hairlineStrong, DS.gold.withValues(alpha: 0.85), selection)!;
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25 + selection * 0.6
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          <Color>[edgeTop, edgeTop.withValues(alpha: edgeTop.a * 0.22)],
        ),
    );

    // The rim itself: a short bright cap across the mouth.
    canvas.drawLine(
      Offset(w * 0.24, 1.0),
      Offset(w * 0.76, 1.0),
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          const Color(0xFFFFFFFF).withValues(alpha: 0.34 * (1 - dim * 0.6)),
          DS.gold,
          selection * 0.8,
        )!,
    );

    // Hint ring — a slow gold pulse on the vessel the solver is pointing at.
    if (hinted) {
      canvas.drawRRect(
        body.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = DS.gold.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_VesselBackPainter old) =>
      old.selection != selection ||
      old.seal != seal ||
      old.sealed != sealed ||
      old.sealHue != sealHue ||
      old.hinted != hinted ||
      old.dim != dim;
}

/// Drawn on top of the contents: the inner shadow under the rim and a broad
/// diagonal sheen. Both are near-invisible in isolation and do most of the
/// work of making the balls look enclosed.
class _VesselFrontPainter extends CustomPainter {
  _VesselFrontPainter({required this.metrics, required this.selection, required this.dim});

  final TubeMetrics metrics;
  final double selection;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect body = _VesselBackPainter.shape(size);
    canvas.save();
    canvas.clipRRect(body);

    // Inner shadow falling from the rim.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.22),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height * 0.22),
          <Color>[
            const Color(0xFF000000).withValues(alpha: 0.34),
            const Color(0x00000000),
          ],
        ),
    );

    // Diagonal sheen across the glass face.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.1, 0),
          Offset(size.width * 0.95, size.height * 0.75),
          <Color>[
            const Color(0xFFFFFFFF).withValues(alpha: 0.05 * (1 - dim * 0.7)),
            const Color(0x00FFFFFF),
            const Color(0x00FFFFFF),
            const Color(0xFFFFFFFF).withValues(alpha: 0.022 * (1 - dim * 0.7)),
          ],
          <double>[0.0, 0.32, 0.72, 1.0],
        ),
    );

    // Right-hand rim light, so the vessel has a lit side and a dark side.
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.86, size.height * 0.05, size.width * 0.05, size.height * 0.88),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.05),
          Offset(0, size.height * 0.93),
          <Color>[
            const Color(0x00FFFFFF),
            const Color(0xFFFFFFFF).withValues(alpha: 0.055 * (1 - dim * 0.7)),
            const Color(0x00FFFFFF),
          ],
          <double>[0.0, 0.4, 1.0],
        ),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_VesselFrontPainter old) =>
      old.selection != selection || old.dim != dim;
}
