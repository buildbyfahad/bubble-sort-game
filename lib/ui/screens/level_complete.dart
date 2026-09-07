import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/level.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../widgets/buttons.dart';
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
    _c
      ..removeListener(_playCues)
      ..dispose();
    super.dispose();
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DS.s16, DS.s16, DS.s16, DS.s16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: AnimatedBuilder(
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
              overallBefore: widget.overallBefore,
              overallAfter: widget.overallAfter,
              hasNext: widget.hasNext,
              onNext: widget.onNext,
              onReplay: widget.onReplay,
              onHome: widget.onHome,
            ),
          ],
        ),
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
                  style: Type.label.copyWith(
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
    final double burstFade = 1 - (t / 0.85).clamp(0.0, 1.0);
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
          <Color>[
            Color.lerp(DS.surfaceHigh, accent, 0.20)!,
            DS.surface,
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
            ..color = accent.withValues(alpha: i.isEven ? 0.34 : 0.14),
        );
      }
    }

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + rank * 0.6
        ..color = accent.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = accent.withValues(alpha: 0.28),
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

    canvas.drawRRect(vessel, Paint()..color = DS.inkDeep.withValues(alpha: 0.55));

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
              Color.lerp(accent, const Color(0xFFFFFFFF), 0.45)!,
              accent,
              Color.lerp(accent, DS.inkDeep, 0.55)!,
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
        ..color = accent.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_CrestPainter old) => old.t != t || old.grade != grade;
}

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
    required this.overallBefore,
    required this.overallAfter,
    required this.hasNext,
    required this.onNext,
    required this.onReplay,
    required this.onHome,
  });

  final ClearGrade grade;
  final Animation<double> animation;
  final Level level;
  final int moves;
  final int best;
  final bool improved;
  final int hintsAwarded;
  final int coinsAwarded;
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
              'LEVEL ${level.id} CLEARED',
              style: Type.label.copyWith(color: DS.textTertiary),
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
                    icon: DIcons.coin,
                    label: '+$coinsAwarded',
                    accent: DS.gold,
                    animation: animation,
                    start: 0.46,
                  ),
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
          const SizedBox(height: DS.s20),
          Row(
            children: <Widget>[
              Text('PROGRESS', style: Type.label),
              const Spacer(),
              Text(
                '${(overallAfter * 100).toStringAsFixed(1)}%',
                style: Type.label.copyWith(color: DS.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: DS.s8),
          _DelayedProgress(
            animation: animation,
            from: overallBefore,
            to: overallAfter,
            start: 0.42,
          ),
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
                      : (muted ? DS.textTertiary : DS.textPrimary),
                ),
              ),
              const SizedBox(height: DS.s4),
              Text(
                label,
                style: Type.label.copyWith(color: highlight ? DS.gold : DS.textTertiary),
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
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
      );
}

/// A reward pill — the coins a board paid out, or the hint a first clear
/// granted. Arrives late and with a small overshoot, after the stats have
/// finished counting, so it reads as a bonus on top of the result rather than
/// as another statistic.
class _Reward extends StatelessWidget {
  const _Reward({
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
                padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DS.rPill),
                  color: accent.withValues(alpha: 0.10),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DIcon(icon, size: 15, color: accent),
                    const SizedBox(width: DS.s8),
                    Text(
                      label,
                      style: Type.bodyStrong.copyWith(color: accent, fontSize: 13),
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
  });

  final Animation<double> animation;
  final double from;
  final double to;
  final double start;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, _) {
          final double t = ((animation.value - start) / 0.40).clamp(0.0, 1.0);
          return ProgressTrack(
            value: from + (to - from) * Ease.emphasized.transform(t),
            duration: Duration.zero,
          );
        },
      );
}
