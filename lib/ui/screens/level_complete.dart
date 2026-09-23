import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/cosmetics.dart';
import '../../data/level.dart';
import '../../design/tokens.dart';
import '../../engine/game_controller.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../widgets/buttons.dart';
import '../widgets/coin_flight.dart';
import '../widgets/icons.dart';
import '../widgets/surfaces.dart';

/// How well the board was solved. Three tiers, named rather than starred —
/// a row of stars is the most over-used reward device in the category, and it
/// implies an incomplete result whenever the player does not get three.
enum ClearGrade { clear, great, flawless }

ClearGrade gradeFor(int moves, int par) {
  if (moves <= par) return ClearGrade.flawless;
  if (moves <= (par * 1.4).ceil()) return ClearGrade.great;
  return ClearGrade.clear;
}

extension on ClearGrade {
  /// 0, 1, 2. Drives how much the crest is allowed to celebrate: how many
  /// rays it throws, how bright the burst is, how full the vessel reads.
  int get rank => switch (this) {
        ClearGrade.clear => 0,
        ClearGrade.great => 1,
        ClearGrade.flawless => 2,
      };

  String get note => switch (this) {
        ClearGrade.flawless => 'AT PAR OR BETTER',
        ClearGrade.great => 'CLOSE TO PAR',
        ClearGrade.clear => 'BOARD CLEARED',
      };

  String get label => switch (this) {
        ClearGrade.flawless => 'Flawless',
        ClearGrade.great => 'Great',
        ClearGrade.clear => 'Solved',
      };

  Color get color => switch (this) {
        ClearGrade.flawless => DS.gold,
        ClearGrade.great => DS.aqua,
        ClearGrade.clear => DS.textSecondary,
      };
}

/// The reward moment.
///
/// The brief was premium satisfaction rather than visual chaos, so the
/// celebration is three quiet things happening in sequence: a ring of light
/// opens behind the title, a small number of motes drift upward, and the stats
/// count themselves up. No confetti cannon, no screen shake, no fanfare that
/// outlasts the player's patience on the fortieth level.
class LevelCompleteSheet extends StatefulWidget {
  const LevelCompleteSheet({
    super.key,
    required this.level,
    required this.moves,
    required this.best,
    required this.improved,
    required this.hintsAwarded,
    required this.coinsAwarded,
    this.bestFlow = 0,
    this.unlocked,
    this.daily = false,
    required this.overallBefore,
    required this.overallAfter,
    required this.hasNext,
    required this.onNext,
    required this.onReplay,
    required this.onHome,
  });

  final Level level;
  final int moves;
  final int best;
  final bool improved;
  final int hintsAwarded;
  final int coinsAwarded;

  /// Longest run of seals without an undo. Shown when it earned a multiplier.
  final int bestFlow;

  /// A cosmetic this clear granted, if any. Finales only.
  final Cosmetic? unlocked;

  /// Today's challenge rather than a campaign level.
  final bool daily;
  final double overallBefore;
  final double overallAfter;
  final bool hasNext;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final VoidCallback onHome;

  @override
  State<LevelCompleteSheet> createState() => _LevelCompleteSheetState();
}

class _LevelCompleteSheetState extends State<LevelCompleteSheet>
    with SingleTickerProviderStateMixin {
  // 1500, not 2200. The celebration has to be over before the player wants it
  // to be over — on level four hundred they have seen it four hundred times,
  // and a reward the player is waiting out has stopped being a reward.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();

  /// Cues left to fire, as (point in the animation, what to play).
  ///
  /// Scored against the animation rather than against wall-clock timers, so
  /// the sound is locked to the picture: if a frame is dropped or the sheet is
  /// rebuilt, the cue still lands on the beat it belongs to.
  List<(double, VoidCallback)> _cues = const <(double, VoidCallback)>[];
  int _fired = 0;
  bool _cuesWired = false;

  final CoinFlightController _coins = CoinFlightController();
  final GlobalKey _crestKey = GlobalKey();
  final GlobalKey _purseKey = GlobalKey();
  bool _flown = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_playCues);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guarded: this runs again on any inherited-widget change, and rebuilding
    // the list would rewind cues that have already played.
    if (_cuesWired) return;
    _cuesWired = true;
    final AppScope scope = AppScope.of(context);
    _cues = <(double, VoidCallback)>[
      // The grade badge landing.
      (0.20, scope.audio.star),
      // Five ticks under the counters as they run.
      for (int i = 0; i < 5; i++) (0.26 + i * 0.035, scope.audio.tick),
      // The coin payout, and the hint a first clear grants.
      if (widget.coinsAwarded > 0) (0.46, scope.audio.star),
      if (widget.coinsAwarded > 0) (0.50, _flyCoins),
      if (widget.hintsAwarded > 0) (0.52, scope.audio.star),
      // Finishing the last level of a chapter is the game's only milestone
      // above a single board, and until now it sounded exactly like the
      // thirty-nine clears before it.
      if (widget.level.id == scope.catalog.chapterOf(widget.level.id).to)
        (0.68, scope.audio.unlock),
    ];
  }

  void _playCues() {
    while (_fired < _cues.length && _c.value >= _cues[_fired].$1) {
      _cues[_fired].$2();
      _fired++;
    }
  }

  @override
  void dispose() {
    _coins.dispose();
    _c
      ..removeListener(_playCues)
      ..dispose();
    super.dispose();
  }

  /// Throws the payout off the crest and into the coin pill on the card.
  ///
  /// Fired from the cue schedule rather than on a timer, so the coins leave
  /// on the same beat as the reward pill arrives.
  void _flyCoins() {
    if (_flown || widget.coinsAwarded <= 0) return;
    _flown = true;
    final RenderBox? root = context.findRenderObject() as RenderBox?;
    final RenderBox? crest = _crestKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? purse = _purseKey.currentContext?.findRenderObject() as RenderBox?;
    if (root == null || crest == null || purse == null) return;
    sendCoins(
      context,
      _coins,
      from: root.globalToLocal(crest.localToGlobal(crest.size.center(Offset.zero))),
      to: root.globalToLocal(purse.localToGlobal(purse.size.center(Offset.zero))),
      amount: widget.coinsAwarded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ClearGrade grade = gradeFor(widget.moves, widget.level.par);

    // A column, not a bottom sheet.
    //
    // The card used to sit on the bottom edge with two thirds of the screen
    // left black above it, which made the most-visited screen in the game read
    // as a form that had appeared over the board. The crest now occupies that
    // space and the result is a composition: mark, verdict, then the numbers.
    return SafeArea(
      child: Stack(
        children: <Widget>[
          // Paper, thrown once, behind everything.
          //
          // The top half of this screen was empty. The composition argument
          // for putting the crest there was right, but a mark alone in a void
          // is a *statement* about the result rather than a celebration of it,
          // and this is the screen the player sees more than any other. The
          // confetti costs one painter and is the difference between the game
          // announcing a win and the game reacting to one.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (BuildContext context, _) => CustomPaint(
                    painter: _ConfettiPainter(t: _c.value, rank: grade.rank, accent: grade.color),
                  ),
                ),
              ),
            ),
          ),
          Padding(
        padding: const EdgeInsets.fromLTRB(DS.s16, DS.s16, DS.s16, DS.s16),
        child: Column(
          children: <Widget>[
            Expanded(
              // Low-centred, not centred. Once the confetti and the rays have
              // gone the upper third is empty ground, and a mark floating in
              // the middle of it leaves that emptiness on both sides. Dropped
              // toward the card, the crest and the verdict read as one block
              // sitting on it, and the empty space collects at the top edge
              // where it works as air rather than as a gap.
              child: Align(
                alignment: const Alignment(0, 0.42),
                child: AnimatedBuilder(
                  key: _crestKey,
                  animation: _c,
                  builder: (BuildContext context, _) => _Crest(
                    grade: grade,
                    t: _c.value,
                  ),
                ),
              ),
            ),
            _ResultCard(
              grade: grade,
              animation: _c,
              level: widget.level,
              moves: widget.moves,
              best: widget.best,
              improved: widget.improved,
              hintsAwarded: widget.hintsAwarded,
              coinsAwarded: widget.coinsAwarded,
              bestFlow: widget.bestFlow,
              unlocked: widget.unlocked,
              daily: widget.daily,
              overallBefore: widget.overallBefore,
              overallAfter: widget.overallAfter,
              hasNext: widget.hasNext,
              onNext: widget.onNext,
              onReplay: widget.onReplay,
              onHome: widget.onHome,
              purseKey: _purseKey,
            ),
          ],
        ),
          ),
          Positioned.fill(child: CoinFlight(controller: _coins)),
        ],
      ),
    );
  }
}

/// The verdict, struck as a seal.
///
/// Deliberately not a row of stars. Stars are the most over-used reward device
/// in the category and they imply an incomplete result whenever the player
/// does not get three — on a puzzle where every clear is a real clear, that is
/// the wrong message forty levels in. This is one mark whose *weight* changes:
/// the ring gains a milled edge, the burst gains rays, and the vessel at the
/// centre fills, as the result improves.
class _Crest extends StatelessWidget {
  const _Crest({required this.grade, required this.t});

  final ClearGrade grade;
  final double t;

  @override
  Widget build(BuildContext context) {
    // Arrives with a single overshoot, like something set down hard.
    final double pop = Ease.overshoot.transform((t / 0.34).clamp(0.0, 1.0));
    final double label = Ease.out.transform(((t - 0.26) / 0.34).clamp(0.0, 1.0));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Transform.scale(
          scale: 0.6 + pop * 0.4,
          child: SizedBox(
            width: 188,
            height: 188,
            child: CustomPaint(painter: _CrestPainter(grade: grade, t: t)),
          ),
        ),
        const SizedBox(height: DS.s24),
        Opacity(
          opacity: label,
          child: Transform.translate(
            offset: Offset(0, (1 - label) * 12),
            child: Column(
              children: <Widget>[
                Text(grade.label, style: Type.titleLg.copyWith(color: grade.color)),
                const SizedBox(height: DS.s8),
                Text(
                  grade.note,
                  style: Type.labelInk.copyWith(
                    color: grade.color.withValues(alpha: 0.55),
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CrestPainter extends CustomPainter {
  _CrestPainter({required this.grade, required this.t});

  final ClearGrade grade;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width * 0.30;
    final Color accent = grade.color;
    final int rank = grade.rank;

    // --- rays -------------------------------------------------------------
    //
    // Only on a result worth them. A "Solved" clear gets the seal and nothing
    // else, so the difference between grades is felt before it is read.
    if (rank > 0) {
      final int rays = rank == 2 ? 16 : 10;
      final double sweep = Ease.out.transform(((t - 0.10) / 0.45).clamp(0.0, 1.0));
      final double fade = 1 - ((t - 0.55) / 0.45).clamp(0.0, 1.0);
      for (int i = 0; i < rays; i++) {
        final double a = (i / rays) * math.pi * 2 + t * 0.25;
        final double inner = r * 1.22;
        final double outer = inner + r * (0.30 + (i.isEven ? 0.34 : 0.14)) * sweep;
        canvas.drawLine(
          c + Offset(math.cos(a), math.sin(a)) * inner,
          c + Offset(math.cos(a), math.sin(a)) * outer,
          Paint()
            ..strokeWidth = i.isEven ? 2.4 : 1.2
            ..strokeCap = StrokeCap.round
            ..color = accent.withValues(alpha: 0.30 * fade * sweep),
        );
      }
    }

    // --- the burst behind the seal ----------------------------------------
    final double burst = Curves.easeOutCubic.transform((t / 0.5).clamp(0.0, 1.0));
    // Floors at 0.30 rather than fading to nothing. The burst is the only
    // light source behind the seal, and letting it go out entirely is what
    // left the settled screen looking like a mark on a flat wall.
    final double burstFade = 1 - 0.70 * (t / 0.85).clamp(0.0, 1.0);
    if (burstFade > 0) {
      final double br = r * (1.0 + burst * 1.5);
      canvas.drawCircle(
        c,
        br,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            br,
            <Color>[
              accent.withValues(alpha: (0.16 + rank * 0.06) * burstFade),
              accent.withValues(alpha: 0.05 * burstFade),
              accent.withValues(alpha: 0),
            ],
            <double>[0.0, 0.45, 1.0],
          )
          ..blendMode = BlendMode.plus,
      );
    }

    // --- the seal ---------------------------------------------------------
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, c.dy - r),
          Offset(c.dx, c.dy + r),
          // Was surfaceHigh barely tinted toward the accent, over surface:
          // a dark disc with a small gold glyph on it, which at a glance
          // reads as a clock face. The seal is the reward and has to be the
          // brightest object on the screen, so the face is the grade's own
          // colour and the vessel inside it is cut out dark.
          <Color>[
            Color.lerp(accent, const Color(0xFFFFFFFF), 0.34)!,
            Color.lerp(accent, DS.inkDeep, 0.18)!,
          ],
        ),
    );

    // A milled edge, the way a struck coin has. Only on the top two grades —
    // it is the detail that makes the mark feel minted rather than drawn.
    if (rank > 0) {
      const int teeth = 48;
      for (int i = 0; i < teeth; i++) {
        final double a = (i / teeth) * math.pi * 2;
        canvas.drawLine(
          c + Offset(math.cos(a), math.sin(a)) * (r * 1.02),
          c + Offset(math.cos(a), math.sin(a)) * (r * 1.08),
          Paint()
            ..strokeWidth = 1.4
            ..color = DS.outline.withValues(alpha: i.isEven ? 0.55 : 0.25),
        );
      }
    }

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = DS.stroke + rank * 0.6
        ..color = DS.outline,
    );
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = DS.outline.withValues(alpha: 0.30),
    );

    // --- the vessel at the centre -----------------------------------------
    //
    // The game's own mark rather than a tick or a star, filled to the grade:
    // brim-full for flawless, and lower as the result drops. The sealed vessel
    // is what the player has just spent the level making.
    // Proportioned from the ball, exactly as the board's own vessels are.
    // Picking a width and a height independently gave a vessel too wide for
    // the four balls in it, and they read as a column of dots rather than as
    // contents.
    final double ball = r * 0.255;
    final double vw = ball * 1.46;
    final double vh = ball * 4.16 + ball * 0.34;
    final Rect body = Rect.fromCenter(center: c, width: vw, height: vh);
    final RRect vessel = RRect.fromRectAndCorners(
      body,
      topLeft: Radius.circular(vw * 0.22),
      topRight: Radius.circular(vw * 0.22),
      bottomLeft: Radius.circular(vw * 0.46),
      bottomRight: Radius.circular(vw * 0.46),
    );

    canvas.drawRRect(vessel, Paint()..color = DS.inkDeep.withValues(alpha: 0.82));

    // Balls, not a flat fill.
    //
    // A gradient inside the silhouette reads as a pill or a zero at this size.
    // Drawing the actual contents — three or four spheres, lit from above like
    // every other ball in the game — makes the mark legible as *a vessel the
    // player just sealed* in the fraction of a second it is looked at.
    final int filled = <int>[2, 3, 4][rank];
    final double poured = Ease.out.transform(((t - 0.18) / 0.42).clamp(0.0, 1.0));
    final double pad = ball * 0.17;
    final double pitch = ball * 1.04;

    canvas.save();
    canvas.clipRRect(vessel);
    for (int i = 0; i < filled; i++) {
      // Poured in from the bottom up, staggered, so the crest fills rather
      // than appears.
      final double at = ((poured - i * 0.13) / (1 - i * 0.13)).clamp(0.0, 1.0);
      if (at <= 0) continue;
      final Offset bc = Offset(c.dx, body.bottom - pad - pitch * i - ball * 0.5);
      final double br = ball * 0.5 * at;
      canvas.drawCircle(
        bc,
        br,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(bc.dx - br * 0.3, bc.dy - br * 0.38),
            br * 1.25,
            <Color>[
              const Color(0xFFFFFFFF),
              Color.lerp(accent, const Color(0xFFFFFFFF), 0.55)!,
              Color.lerp(accent, DS.inkDeep, 0.30)!,
            ],
            <double>[0.0, 0.5, 1.0],
          ),
      );
    }
    canvas.restore();

    canvas.drawRRect(
      vessel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_CrestPainter old) => old.t != t || old.grade != grade;
}

String _fmt(double m) => m == m.roundToDouble() ? '${m.toInt()}' : '$m';

/// The numbers, and what to do next.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.grade,
    required this.animation,
    required this.level,
    required this.moves,
    required this.best,
    required this.improved,
    required this.hintsAwarded,
    required this.coinsAwarded,
    this.bestFlow = 0,
    this.unlocked,
    this.daily = false,
    required this.overallBefore,
    required this.overallAfter,
    required this.hasNext,
    required this.onNext,
    required this.onReplay,
    required this.onHome,
    required this.purseKey,
  });

  /// Where the coin flight lands.
  final GlobalKey purseKey;

  final ClearGrade grade;
  final Animation<double> animation;
  final Level level;
  final int moves;
  final int best;
  final bool improved;
  final int hintsAwarded;
  final int coinsAwarded;

  /// Longest run of seals without an undo. Shown when it earned a multiplier.
  final int bestFlow;
  final Cosmetic? unlocked;
  final bool daily;
  final double overallBefore;
  final double overallAfter;
  final bool hasNext;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      radius: DS.rXl,
      tint: grade.color,
      padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, DS.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Text(
              daily ? 'CHALLENGE CLEARED' : 'LEVEL ${level.id} CLEARED',
              style: Type.labelInk.copyWith(color: DS.inkSoft),
            ),
          ),
          const SizedBox(height: DS.s16),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(label: 'MOVES', value: moves, animation: animation, start: 0.22),
              ),
              _StatDivider(),
              Expanded(
                child: _Stat(
                  label: 'PAR',
                  value: level.par,
                  animation: animation,
                  start: 0.30,
                  muted: true,
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _Stat(
                  label: improved ? 'NEW BEST' : 'BEST',
                  value: best,
                  animation: animation,
                  start: 0.38,
                  highlight: improved,
                ),
              ),
            ],
          ),
          if (coinsAwarded > 0 || hintsAwarded > 0) ...<Widget>[
            const SizedBox(height: DS.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (coinsAwarded > 0)
                  _Reward(
                    key: purseKey,
                    icon: DIcons.coin,
                    label: '+$coinsAwarded',
                    accent: DS.gold,
                    animation: animation,
                    start: 0.46,
                  ),
                if (coinsAwarded > 0 && bestFlow >= 2) ...<Widget>[
                  const SizedBox(width: DS.s8),
                  _Reward(
                    icon: DIcons.flame,
                    label: '×${_fmt(GameController.multiplierFor(bestFlow))} flow',
                    accent: DS.gold,
                    animation: animation,
                    start: 0.49,
                  ),
                ],
                if (coinsAwarded > 0 && hintsAwarded > 0) const SizedBox(width: DS.s8),
                if (hintsAwarded > 0)
                  _Reward(
                    icon: DIcons.hint,
                    label: '+$hintsAwarded hint${hintsAwarded == 1 ? '' : 's'}',
                    accent: DS.aqua,
                    animation: animation,
                    start: 0.52,
                  ),
              ],
            ),
          ],
          if (unlocked != null) ...<Widget>[
            const SizedBox(height: DS.s12),
            Center(
              child: _Reward(
                icon: DIcons.grid,
                label: 'Unlocked · ${unlocked!.name}',
                accent: DS.gold,
                animation: animation,
                start: 0.56,
              ),
            ),
          ],
          // Chapter progress, not "2.8%".
          //
          // This row used to read PROGRESS / 2.8%, which is the same dashboard
          // number the menu led with until it was taken off there — and it is
          // worse here, because the moment the player has just won is the
          // moment the game chooses to tell them they have done almost none of
          // it. A thousand-level total can only ever produce a demoralising
          // fraction. The chapter they are actually in is forty levels long,
          // the bar visibly moves every single clear, and finishing one is a
          // real event with a cosmetic behind it.
          if (!daily) ...<Widget>[
            const SizedBox(height: DS.s20),
            Builder(
              builder: (BuildContext context) {
                final Chapter ch = AppScope.of(context).catalog.chapterOf(level.id);
                final int done = level.id - ch.from + 1;
                final int size = ch.to - ch.from + 1;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          'CHAPTER ${ch.number.toString().padLeft(2, '0')} · ${ch.name.toUpperCase()}',
                          style: Type.labelInk,
                        ),
                        const Spacer(),
                        Text(
                          '$done / $size',
                          style: Type.numeralSm.copyWith(fontSize: 13, color: DS.inkBody),
                        ),
                      ],
                    ),
                    const SizedBox(height: DS.s8),
                    _DelayedProgress(
                      animation: animation,
                      from: (done - 1) / size,
                      to: done / size,
                      start: 0.42,
                      // Gold, not the grade's colour. How far through the
                      // chapter the player is has nothing to do with how well
                      // they solved this board — and a "Solved" grade is
                      // silver, which on a white card made the bar disappear.
                      color: DS.gold,
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: DS.s20),
          PrimaryButton(
            label: hasNext ? 'Next level' : 'Back to menu',
            idlePulse: false,
            onTap: hasNext ? onNext : onHome,
          ),
          const SizedBox(height: DS.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextAction(icon: DIcons.restart, label: 'Replay', onTap: onReplay),
              const SizedBox(width: DS.s12),
              TextAction(icon: DIcons.map, label: 'Menu', onTap: onHome),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.animation,
    required this.start,
    this.muted = false,
    this.highlight = false,
  });

  final String label;
  final int value;
  final Animation<double> animation;
  final double start;
  final bool muted;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, _) {
        final double t = ((animation.value - start) / 0.30).clamp(0.0, 1.0);
        final double e = Ease.out.transform(t);
        // Counting up is what makes a number feel earned instead of printed.
        final int shown = (value * e).round();
        return Opacity(
          opacity: e,
          child: Column(
            children: <Widget>[
              Text(
                '$shown',
                style: Type.numeral.copyWith(
                  fontSize: 26,
                  color: highlight
                      ? DS.gold
                      // Ink, not textPrimary: this sits on a light card, and
                      // white-on-white made the headline number invisible.
                      : (muted ? DS.inkSoft : DS.inkStrong),
                ),
              ),
              const SizedBox(height: DS.s4),
              Text(
                label,
                style: Type.labelInk.copyWith(color: highlight ? DS.goldDeep : DS.inkSoft),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        color: DS.cardEdge,
      );
}

/// A reward pill — the coins a board paid out, or the hint a first clear
/// granted. Arrives late and with a small overshoot, after the stats have
/// finished counting, so it reads as a bonus on top of the result rather than
/// as another statistic.
class _Reward extends StatelessWidget {
  const _Reward({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.animation,
    required this.start,
  });

  final DIcons icon;
  final String label;
  final Color accent;
  final Animation<double> animation;
  final double start;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, _) {
          final double t = ((animation.value - start) / 0.30).clamp(0.0, 1.0);
          final double e = Ease.overshoot.transform(t);
          return Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.8 + e * 0.2,
              child: Container(
                // A 10%-alpha tint on a near-white card made the payout the
                // lowest-contrast thing on it. Solid, outlined and bevelled:
                // what the player won should look like something won.
                padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DS.rPill),
                  color: accent,
                  border: Border.all(color: DS.outline, width: 2),
                  boxShadow: DS.glow(accent, opacity: 0.30, blur: 14, y: 4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DIcon(icon, size: 15, color: DS.outline),
                    const SizedBox(width: DS.s8),
                    Text(
                      label,
                      style: Type.bodyStrong.copyWith(color: DS.outline, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _DelayedProgress extends StatelessWidget {
  const _DelayedProgress({
    required this.animation,
    required this.from,
    required this.to,
    required this.start,
    required this.color,
  });

  final Animation<double> animation;
  final double from;
  final double to;
  final double start;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, _) {
          final double t = ((animation.value - start) / 0.40).clamp(0.0, 1.0);
          return ProgressTrack(
            value: from + (to - from) * Ease.emphasized.transform(t),
            duration: Duration.zero,
            height: 7,
            color: color,
          );
        },
      );
}

/// Paper thrown once, at the top of the sheet.
///
/// Deterministic: every piece's position, tint, spin and drift come from its
/// index through a cheap hash, so there is no RNG to seed, no state to keep
/// between frames, and the golden tests render the same picture every run.
///
/// It behaves like paper rather than like particles. Each piece is a thin
/// rectangle spinning about its own horizontal axis, which is drawn by scaling
/// its height by `cos(spin)` — so a piece edge-on collapses to a line and
/// flashes, the way real confetti catches the light. Gravity is constant, drift
/// is a slow sine, and the whole thing fades out well before the animation
/// ends: the celebration has to be over before the player wants it to be.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.rank, required this.accent});

  final double t;

  /// Better results get more paper. It is the one reward signal on this screen
  /// that is felt without being read.
  final int rank;

  final Color accent;

  /// Cheap integer hash — deterministic, and good enough for scatter.
  static double _r(int i, int salt) {
    int h = i * 374761393 + salt * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return ((h ^ (h >> 16)) & 0x7FFFFFFF) / 0x7FFFFFFF;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Thrown from the moment the sheet opens and gone by 80%, so it never
    // competes with the button the player is reaching for.
    final double fade = 1 - ((t - 0.45) / 0.35).clamp(0.0, 1.0);
    if (fade <= 0) return;

    final int count = 26 + rank * 14;

    for (int i = 0; i < count; i++) {
      // Staggered launch, so the burst has a front edge rather than all
      // appearing on one frame.
      final double at = ((t - _r(i, 1) * 0.16) / 0.9).clamp(0.0, 1.0);
      if (at <= 0) continue;

      final double x0 = size.width * (0.08 + _r(i, 2) * 0.84);
      // Up first, then down: a throw, not a drip.
      final double vy = 0.55 + _r(i, 3) * 0.75;
      final double y = size.height * (-0.06 + (-0.42 * at + 1.30 * at * at) * vy);
      if (y > size.height) continue;

      final double drift = math.sin(at * 5.0 + _r(i, 4) * 6.28) * size.width * 0.05;
      final double spin = at * (7.0 + _r(i, 5) * 9.0) + _r(i, 6) * 6.28;

      // Mostly the grade's colour so the screen has one identity, with the
      // ball palette mixed through it so it still reads as confetti and not
      // as one colour of litter.
      final Color c = _r(i, 7) < 0.45
          ? accent
          : DS.hues[(i * 5 + 3) % DS.hues.length].base;

      final double w = 5.0 + _r(i, 8) * 4.0;
      final double h = w * (1.5 + _r(i, 9) * 1.1);

      canvas.save();
      canvas.translate(x0 + drift, y);
      canvas.rotate(_r(i, 10) * 6.28 + at * 1.4);
      // The spin. Collapsing the height by cos() turns the rectangle edge-on,
      // which is the whole reason paper twinkles as it falls.
      canvas.scale(1.0, math.cos(spin).abs().clamp(0.12, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          Radius.circular(w * 0.28),
        ),
        Paint()..color = c.withValues(alpha: fade * 0.9),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.t != t || old.rank != rank || old.accent != accent;
}
