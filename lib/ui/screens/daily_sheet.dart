import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../services/wallet_service.dart';
import '../app_scope.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/surfaces.dart';

/// The daily reward.
///
/// This is the game's day-2 return mechanism, and it is built on one idea: the
/// player should always be able to see the rung they are on *and* the rung
/// they lose by not coming back. A reward that simply appears and says "+40"
/// teaches nothing about tomorrow; a seven-rung ladder with today lit and
/// Sunday's prize visible at the end of it is an argument for opening the app
/// again.
///
/// Everything is local — a claim is a date written to disk. There is no
/// server, so a player who changes their device clock can claim early. That is
/// a fair trade for a single-player game with nothing to protect.
class DailyRewardSheet extends StatefulWidget {
  const DailyRewardSheet({super.key});

  @override
  State<DailyRewardSheet> createState() => _DailyRewardSheetState();
}

class _DailyRewardSheetState extends State<DailyRewardSheet>
    with SingleTickerProviderStateMixin {
  // Built in initState, not as a `late final` initialiser.
  //
  // A lazy field here is a crash waiting for a player who opens the sheet and
  // closes it without claiming: nothing would ever have read `_c`, so
  // `dispose()` would be the first access, constructing an AnimationController
  // against a vsync whose element is already deactivated.
  late final AnimationController _c;

  DailyReward? _claimed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _claim(AppScope scope) async {
    if (_busy) return;
    setState(() => _busy = true);

    final DailyReward? reward = await scope.wallet.claimDaily();
    if (!mounted) return;

    if (reward == null) {
      // Claimed on another screen, or the day turned over mid-tap.
      setState(() => _busy = false);
      return;
    }
    scope.audio.unlock();
    scope.haptics.celebrate();
    setState(() {
      _claimed = reward;
      _busy = false;
    });
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DS.s16),
          child: Observes(
            listenables: <Listenable>[scope.wallet],
            builder: (BuildContext context) {
              final WalletService w = scope.wallet;
              final bool claimable = w.canClaimDaily;

              // The rung being offered right now, or the one just taken.
              final int shownStreak = claimable ? w.streakIfClaimed : w.streak;
              final int cycleDay = WalletService.cycleDayFor(shownStreak);

              return SoftCard(
                radius: DS.rXl,
                tint: DS.gold,
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, DS.s24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('DAILY REWARD', style: Type.label),
                              const SizedBox(height: DS.s8),
                              Row(
                                children: <Widget>[
                                  DIcon(
                                    DIcons.flame,
                                    size: 17,
                                    color: shownStreak > 0 ? DS.gold : DS.textTertiary,
                                  ),
                                  const SizedBox(width: DS.s8),
                                  Text(
                                    shownStreak <= 1
                                        ? 'Day one'
                                        : '$shownStreak day streak',
                                    style: Type.titleMd.copyWith(fontSize: 19),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        GhostIconButton(
                          icon: DIcons.close,
                          size: 38,
                          semanticLabel: 'Close',
                          onTap: () {
                            scope.audio.tap();
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: DS.s20),

                    // --- the ladder ------------------------------------------
                    Row(
                      children: <Widget>[
                        for (int d = 1; d <= 7; d++) ...<Widget>[
                          if (d > 1) const SizedBox(width: DS.s4),
                          Expanded(
                            child: _Rung(
                              day: d,
                              reward: WalletService.rewardFor(d),
                              // Rungs behind today are taken; today is either
                              // on offer or just claimed.
                              taken: d < cycleDay || (d == cycleDay && !claimable),
                              current: d == cycleDay,
                              pulse: d == cycleDay && claimable,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: DS.s20),

                    if (_claimed != null)
                      _ClaimedBanner(reward: _claimed!, animation: _c)
                    else if (claimable)
                      PrimaryButton(
                        label: _busy ? 'Claiming…' : 'Claim',
                        sublabel: _sublabelFor(WalletService.rewardFor(cycleDay)),
                        idlePulse: false,
                        onTap: () => _claim(scope),
                      )
                    else
                      Center(
                        child: Text(
                          'Claimed. Come back tomorrow for '
                          '${WalletService.rewardFor(WalletService.cycleDayFor(w.streak + 1)).coins}.',
                          textAlign: TextAlign.center,
                          style: Type.caption,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _sublabelFor(DailyReward r) =>
      r.hints > 0 ? '${r.coins} COINS · ${r.hints} HINT${r.hints == 1 ? '' : 'S'}' : '${r.coins} COINS';
}

/// One rung of the ladder.
class _Rung extends StatefulWidget {
  const _Rung({
    required this.day,
    required this.reward,
    required this.taken,
    required this.current,
    required this.pulse,
  });

  final int day;
  final DailyReward reward;
  final bool taken;
  final bool current;
  final bool pulse;

  @override
  State<_Rung> createState() => _RungState();
}

class _RungState extends State<_Rung> with SingleTickerProviderStateMixin {
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _breathe.repeat();
  }

  @override
  void didUpdateWidget(_Rung old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_breathe.isAnimating) {
      _breathe.repeat();
    } else if (!widget.pulse && _breathe.isAnimating) {
      _breathe
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sunday is the payoff, and it is drawn larger than the rest so the shape
    // of the week is legible before a single word is read.
    final bool finale = widget.day == 7;
    final Color accent = widget.taken
        ? DS.aqua
        : (widget.current ? DS.gold : DS.textTertiary);

    return AnimatedBuilder(
      animation: _breathe,
      builder: (BuildContext context, _) {
        final double glow =
            widget.pulse ? 0.5 + 0.5 * math.sin(_breathe.value * math.pi * 2) : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: DS.s8, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DS.rSm),
            color: widget.current
                ? DS.gold.withValues(alpha: 0.10 + glow * 0.06)
                : const Color(0x08FFFFFF),
            border: Border.all(
              color: widget.current
                  ? DS.gold.withValues(alpha: 0.45 + glow * 0.35)
                  : (widget.taken ? DS.aqua.withValues(alpha: 0.24) : DS.hairline),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${widget.day}',
                style: Type.label.copyWith(
                  color: accent,
                  fontSize: 9,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: DS.s4),
              if (widget.taken)
                DIcon(DIcons.check, size: finale ? 14 : 12, color: DS.aqua)
              else
                DIcon(
                  widget.reward.hints > 0 ? DIcons.hint : DIcons.coin,
                  size: finale ? 15 : 12,
                  color: accent,
                ),
              const SizedBox(height: DS.s4),
              Text(
                '${widget.reward.coins}',
                style: Type.label.copyWith(
                  color: accent,
                  fontSize: finale ? 10 : 9,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What the player just took, counted up rather than stated.
class _ClaimedBanner extends StatelessWidget {
  const _ClaimedBanner({required this.reward, required this.animation});

  final DailyReward reward;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, _) {
          final double t = Ease.out.transform(animation.value.clamp(0.0, 1.0));
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _Pill(
                    icon: DIcons.coin,
                    label: '+${(reward.coins * t).round()}',
                    accent: DS.gold,
                  ),
                  if (reward.hints > 0) ...<Widget>[
                    const SizedBox(width: DS.s8),
                    _Pill(
                      icon: DIcons.hint,
                      label: '+${reward.hints}',
                      accent: DS.aqua,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.accent});

  final DIcons icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DS.rPill),
          color: accent.withValues(alpha: 0.10),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DIcon(icon, size: 16, color: accent),
            const SizedBox(width: DS.s8),
            Text(label, style: Type.bodyStrong.copyWith(color: accent)),
          ],
        ),
      );
}
