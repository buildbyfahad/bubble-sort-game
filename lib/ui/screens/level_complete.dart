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
      // The hint award, when there is one.
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

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DS.s16),
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: <Widget>[
              // Light and motes sit behind the card and are clipped by nothing,
              // so the celebration reads as coming from the card rather than
              // being drawn on top of it.
              Positioned(
                top: -300,
                child: IgnorePointer(
                  child: SizedBox(
                    width: 420,
                    height: 316,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (BuildContext context, _) =>
                          CustomPaint(painter: _CelebrationPainter(_c.value, grade.color)),
                    ),
                  ),
                ),
              ),
              SoftCard(
                radius: DS.rXl,
                tint: grade.color,
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s24, DS.s24, DS.s24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Text(
                        'LEVEL ${widget.level.id.toString().padLeft(2, '0')} CLEARED',
                        style: Type.label.copyWith(color: DS.textTertiary),
                      ),
                    ),
                    const SizedBox(height: DS.s12),
                    Center(
                      child: Text(
                        grade.label,
                        style: Type.titleLg.copyWith(color: grade.color),
                      ),
                    ),
                    const SizedBox(height: DS.s24),

                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _Stat(
                            label: 'MOVES',
                            value: widget.moves,
                            animation: _c,
                            start: 0.22,
                          ),
                        ),
                        _StatDivider(),
                        Expanded(
                          child: _Stat(
                            label: 'PAR',
                            value: widget.level.par,
                            animation: _c,
                            start: 0.30,
                            muted: true,
                          ),
                        ),
                        _StatDivider(),
                        Expanded(
                          child: _Stat(
                            label: widget.improved ? 'NEW BEST' : 'BEST',
                            value: widget.best,
                            animation: _c,
                            start: 0.38,
                            highlight: widget.improved,
                          ),
                        ),
                      ],
                    ),

                    if (widget.hintsAwarded > 0) ...<Widget>[
                      const SizedBox(height: DS.s20),
                      Center(child: _HintReward(count: widget.hintsAwarded, animation: _c)),
                    ],

                    const SizedBox(height: DS.s24),
                    Row(
                      children: <Widget>[
                        Text('PROGRESS', style: Type.label),
                        const Spacer(),
                        Text(
                          '${(widget.overallAfter * 100).round()}%',
                          style: Type.label.copyWith(color: DS.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: DS.s8),
                    // Begins at the previous value so the player watches the
                    // bar move, rather than arriving to find it already moved.
                    _DelayedProgress(
                      animation: _c,
                      from: widget.overallBefore,
                      to: widget.overallAfter,
                      start: 0.42,
                    ),

                    const SizedBox(height: DS.s24),
                    PrimaryButton(
                      label: widget.hasNext ? 'Next level' : 'Back to menu',
                      idlePulse: false,
                      onTap: widget.hasNext ? widget.onNext : widget.onHome,
                    ),
                    const SizedBox(height: DS.s12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        TextAction(icon: DIcons.restart, label: 'Replay', onTap: widget.onReplay),
                        const SizedBox(width: DS.s12),
                        TextAction(icon: DIcons.grid, label: 'Menu', onTap: widget.onHome),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single expanding ring plus a dozen slow motes. Twelve, not two hundred:
/// the eye reads a handful of drifting points as light and a swarm as noise.
class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter(this.t, this.color);

  final double t;
  final Color color;

  static const int _moteCount = 12;

  @override
  void paint(Canvas canvas, Size size) {
    // Seated on the card's top edge: the light appears to come from the
    // card, and the motes rise into open space instead of behind it.
    final Offset c = Offset(size.width / 2, size.height);

    // A single soft bloom seated on the card's top edge. An expanding stroked
    // ring was tried here and cut: against a dark ground it reads as a stray
    // hairline arc floating in space rather than as light.
    final double bloom = Curves.easeOutCubic.transform((t / 0.5).clamp(0.0, 1.0));
    final double bloomFade = 1 - (t / 0.8).clamp(0.0, 1.0);
    if (bloomFade > 0) {
      final double r = size.width * (0.16 + bloom * 0.42);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            r,
            <Color>[
              color.withValues(alpha: 0.22 * bloomFade),
              color.withValues(alpha: 0.07 * bloomFade),
              color.withValues(alpha: 0.0),
            ],
            <double>[0.0, 0.45, 1.0],
          )
          ..blendMode = BlendMode.plus,
      );
    }

    // Motes: each on its own phase, rising and fading. Deterministic offsets,
    // so the moment looks identical every time it plays.
    for (int i = 0; i < _moteCount; i++) {
      final double seed = i / _moteCount;
      // Every mote must complete its rise before the controller stops, or the
      // last few freeze mid-air as permanent dots.
      final double phase = ((t - 0.05 - seed * 0.24) / 0.60).clamp(0.0, 1.0);
      if (phase <= 0 || phase >= 1) continue;
      final double angle = seed * math.pi * 2 + 0.7;
      final double spread = size.width * (0.10 + 0.24 * ((i * 37) % 11) / 11);
      final double x = c.dx + math.cos(angle) * spread * (0.4 + phase * 0.8);
      final double y = c.dy - phase * size.height * (0.52 + 0.34 * ((i * 53) % 7) / 7);
      final double a = math.sin(phase * math.pi) * 0.8;
      final double r = size.width * 0.009 * (1 + ((i * 29) % 5) / 3);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = color.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) => old.t != t;
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

class _HintReward extends StatelessWidget {
  const _HintReward({required this.count, required this.animation});

  final int count;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, _) {
          final double t = ((animation.value - 0.5) / 0.35).clamp(0.0, 1.0);
          final double e = Ease.overshoot.transform(t);
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + e * 0.2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DS.rPill),
                  color: DS.gold.withValues(alpha: 0.10),
                  border: Border.all(color: DS.gold.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const DIcon(DIcons.hint, size: 15, color: DS.gold),
                    const SizedBox(width: DS.s8),
                    Text(
                      '+$count hint${count == 1 ? '' : 's'}',
                      style: Type.bodyStrong.copyWith(color: DS.gold, fontSize: 13),
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
