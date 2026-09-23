import 'package:flutter/widgets.dart';

import '../../data/level.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../engine/game_controller.dart';
import '../../data/cosmetics.dart';
import '../../data/daily_challenge.dart';
import '../../services/wallet_service.dart';
import '../app_scope.dart';
import '../transitions.dart';
import '../widgets/ambient_background.dart';
import '../widgets/board_view.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/surfaces.dart';
import 'level_complete.dart';
import 'shop_sheet.dart';
import 'settings_sheet.dart';

/// Gameplay.
///
/// The layout is three bands with a strict hierarchy: a thin identity strip at
/// the top, the board owning everything in between, and a floating control
/// dock at the bottom. The board gets all the remaining space and all of the
/// contrast — every other element on this screen is deliberately quieter than
/// the vessels.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.levelId, this.daily = false});

  final int levelId;

  /// Played as today's challenge rather than as a campaign level: pays the
  /// challenge reward, does not advance the road, and has no "next".
  final bool daily;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late AppScope _scope;
  late Chapter _chapter;
  late GameController _controller;
  bool _wired = false;

  /// 0 = teach selection, 1 = teach the pour, 2 = done.
  int _tutorialStep = 0;
  bool _tutorialActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    _scope = AppScope.of(context);
    _tutorialActive = widget.levelId == 1 && !_scope.progress.seenTutorial;
    _chapter = _scope.catalog.chapterOf(widget.levelId);
    _build();
  }

  void _build() {
    _controller = GameController(
      level: _scope.catalog.byId(widget.levelId),
      audio: _scope.audio,
      haptics: _scope.haptics,
    )
      ..onSolved = _handleSolved
      ..onFailed = _handleFailed;
    _controller
      ..addListener(_advanceTutorial)
      ..addListener(_driveMusic);
    // A fresh board starts the score from the top, in sync.
    _scope.audio
      ..resyncMusic()
      ..setMusicIntensity(0.0);
  }

  /// The score follows the board: each vessel sealed brings in more of it.
  void _driveMusic() {
    final int total = _controller.level.colorCount;
    if (total == 0) return;
    _scope.audio.setMusicIntensity(_controller.state.sealedCount / total);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_advanceTutorial)
      ..removeListener(_driveMusic)
      ..dispose();
    // Back to the menu mix.
    _scope.audio.setMusicIntensity(0.0);
    super.dispose();
  }

  // ---------------------------------------------------------------- tutorial

  /// The whole tutorial: two sentences that appear one at a time and are
  /// dismissed by playing, not by reading. Nothing is blocked, nothing is
  /// modal, and it never appears again.
  void _advanceTutorial() {
    if (!_tutorialActive) return;
    if (_tutorialStep == 0 && _controller.selected != null) {
      setState(() => _tutorialStep = 1);
    } else if (_tutorialStep >= 1 && _controller.moves > 0) {
      setState(() {
        _tutorialStep = 2;
        _tutorialActive = false;
      });
      _scope.progress.markTutorialSeen();
    }
  }

  /// The vessel the guide points at: a legal source first, then a legal
  /// destination for whatever the player picked up.
  int? get _guideTube {
    if (!_tutorialActive) return null;
    final int? sel = _controller.selected;
    if (sel == null) {
      for (int i = 0; i < _controller.state.tubeCount; i++) {
        for (int j = 0; j < _controller.state.tubeCount; j++) {
          if (_controller.state.canPour(i, j)) return i;
        }
      }
      return null;
    }
    for (int j = 0; j < _controller.state.tubeCount; j++) {
      if (_controller.state.canPour(sel, j)) return j;
    }
    return null;
  }

  String get _tutorialText => _tutorialStep == 0
      ? 'Tap a vessel to lift its top colour'
      : 'Now tap another vessel to pour it in';

  // ------------------------------------------------------------------- flow

  Future<void> _handleSolved() async {
    if (widget.daily) return _handleDailySolved();
    final Level level = _controller.level;
    final double before = _scope.progress.completion;
    final bool firstClear = !_scope.progress.isCleared(level.id);
    final bool improved = await _scope.progress.recordClear(level.id, _controller.moves);

    // Pay the board out. A replay pays a token amount rather than the full
    // rate — see WalletService.payoutFor for why the difference matters.
    final ClearGrade grade = gradeFor(_controller.moves, level.par);
    final int base = WalletService.payoutFor(
      flawless: grade == ClearGrade.flawless,
      great: grade == ClearGrade.great,
      firstClear: firstClear,
    );
    // The flow streak scales the payout; a finale pays double on top. A boss
    // that paid the same as the level before it would not be a boss.
    final double mult = _controller.flowMultiplier * (level.isBoss ? 2 : 1);
    final int coins = (base * mult).round();
    await _scope.wallet.grantCoins(coins);
    if (firstClear) await _scope.wallet.grantHints(1);

    // A finale can carry a cosmetic. Granted on the first clear only, and
    // only if the player does not already own it.
    Cosmetic? unlocked;
    if (level.isBoss && firstClear) {
      final Cosmetic? reward = Cosmetic.rewardFor(_chapter.number);
      if (reward != null && !_scope.cosmetics.owns(reward.id)) {
        await _scope.cosmetics.grant(reward.id);
        unlocked = reward;
      }
    }

    final double after = _scope.progress.completion;
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      sheetRoute<void>(
        dismissible: false,
        LevelCompleteSheet(
          level: level,
          moves: _controller.moves,
          best: _scope.progress.bestFor(level.id) ?? _controller.moves,
          improved: improved,
          hintsAwarded: firstClear ? 1 : 0,
          coinsAwarded: coins,
          bestFlow: _controller.bestFlow,
          unlocked: unlocked,
          overallBefore: before,
          overallAfter: after,
          hasNext: level.id < _scope.catalog.length,
          onNext: () {
            _scope.audio.whoosh();
            Navigator.of(context)
              ..pop()
              ..pushReplacement(riseRoute<void>(GameScreen(levelId: level.id + 1)));
          },
          onReplay: () {
            Navigator.of(context).pop();
            setState(() {
              _controller
                ..removeListener(_advanceTutorial)
                ..removeListener(_driveMusic)
                ..dispose();
              _build();
            });
          },
          onHome: () {
            // Back to the road — which is the home screen now, so this is a
            // single pop past the sheet rather than an unwind to a lobby.
            _scope.audio.whoosh();
            Navigator.of(context)
              ..pop()
              ..pop();
          },
        ),
      ),
    );
  }

  Future<void> _handleDailySolved() async {
    final Level level = _controller.level;
    final int day = _scope.wallet.today;
    final bool first = await _scope.progress.recordDailyClear(day, _controller.moves);
    final int coins = first ? DailyChallenge.reward : 5;
    await _scope.wallet.grantCoins(coins);
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      sheetRoute<void>(
        dismissible: false,
        LevelCompleteSheet(
          level: level,
          moves: _controller.moves,
          best: _controller.moves,
          improved: false,
          hintsAwarded: 0,
          coinsAwarded: coins,
          bestFlow: _controller.bestFlow,
          overallBefore: _scope.progress.completion,
          overallAfter: _scope.progress.completion,
          hasNext: false,
          daily: true,
          onNext: () {},
          onReplay: () {
            Navigator.of(context).pop();
            setState(() {
              _controller
                ..removeListener(_advanceTutorial)
                ..removeListener(_driveMusic)
                ..dispose();
              _build();
            });
          },
          onHome: () {
            // Back to the road — which is the home screen now, so this is a
            // single pop past the sheet rather than an unwind to a lobby.
            _scope.audio.whoosh();
            Navigator.of(context)
              ..pop()
              ..pop();
          },
        ),
      ),
    );
  }

  Future<void> _handleFailed() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      sheetRoute<void>(
        dismissible: false,
        _OutOfPoursSheet(
          level: _controller.level,
          onRetry: () {
            Navigator.of(context).pop();
            _controller.restart();
          },
          onHome: () => Navigator.of(context)
            ..pop()
            ..pop(),
        ),
      ),
    );
  }

  Future<void> _hint() async {
    if (_controller.hintPending) return;

    // Out of hints is the one moment the player actively wants what the shop
    // sells, so it opens the shop rather than buzzing at them. A dead button
    // at the exact point of need is the most annoying way to run an economy.
    if (_scope.wallet.hints <= 0) {
      // The dock button has already played its own tap; this is the *result*
      // of the tap, so it gets the navigation cue rather than a second click.
      _scope.audio.whoosh();
      await Navigator.of(context).push(sheetRoute<void>(const ShopSheet()));
      return;
    }

    final bool spent = await _scope.wallet.spendHint();
    if (!spent) {
      _scope.haptics.reject();
      _scope.audio.reject();
      return;
    }
    await _controller.requestHint();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final Level level = _controller.level;

    return AmbientBackground(
      // Dialled back so the board is unambiguously the brightest thing here.
      intensity: 0.55,
      atmosphere: Atmosphere.forChapter(_chapter.number),
      child: SafeArea(
        child: Observes(
          listenables: <Listenable>[
            _controller,
            _scope.settings,
            _scope.progress,
            _scope.wallet,
            _scope.cosmetics,
          ],
          builder: (BuildContext context) {
            final int sealed = _controller.state.sealedCount;

            return Column(
              children: <Widget>[
                _TopBar(
                  level: level,
                  chapter: _chapter,
                  sealed: sealed,
                  flow: _controller.flow,
                  daily: widget.daily,
                  onBack: () {
                    Navigator.of(context).pop();
                  },
                  onSettings: () {
                    Navigator.of(context).push(sheetRoute<void>(const SettingsSheet()));
                  },
                ),

                // --- board -------------------------------------------------
                //
                // Sat on a lit platform rather than floating in the sky. The
                // vessels had nothing to stand on, which is most of why the
                // board did not read as a *place* — and a play field that is
                // not a place is the difference between a game and a diagram.
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(DS.s12, DS.s8, DS.s12, DS.s8),
                    padding: const EdgeInsets.fromLTRB(DS.s12, DS.s16, DS.s12, DS.s16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(DS.rXl),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[DS.table, DS.tableEdge],
                      ),
                      // The board is the one object the whole game is about,
                      // and it was outlined in a 12%-white hairline — the
                      // lightest edge in the build. It gets the same drawn
                      // outline as everything else now, which is what makes it
                      // read as a tray the vessels are standing in rather than
                      // a rectangle they happen to be over.
                      border: Border.all(color: DS.outline, width: DS.stroke),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: DS.skyDeep.withValues(alpha: 0.5),
                          blurRadius: 30,
                          spreadRadius: -6,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: BoardView(
                      controller: _controller,
                      colorAssist: _scope.settings.colorAssist,
                      guideTube: _guideTube,
                      ballStyle: _scope.cosmetics.ballStyle,
                      vesselStyle: _scope.cosmetics.vesselStyle,
                    ),
                  ),
                ),

                // --- status line -------------------------------------------
                SizedBox(
                  height: 34,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: DS.tBase,
                      switchInCurve: Ease.out,
                      transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(a),
                          child: child,
                        ),
                      ),
                      child: _statusLine(level),
                    ),
                  ),
                ),

                // --- dock ---------------------------------------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(DS.s16, DS.s4, DS.s16, DS.s16),
                  child: Center(
                    child: SoftCard(
                      radius: DS.rXl,
                      onDark: true,
                      padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: DS.s8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          DockButton(
                            icon: DIcons.undo,
                            label: 'Undo',
                            enabled: _controller.canUndo,
                            onTap: _controller.undo,
                          ),
                          _DockDivider(),
                          DockButton(
                            icon: DIcons.hint,
                            label: 'Hint',
                            accent: DS.gold,
                            badge: _scope.wallet.hints,
                            busy: _controller.hintPending,
                            // Deliberately still enabled at zero hints: the
                            // tap opens the shop instead of spending.
                            enabled: _controller.status != GameStatus.solved,
                            onTap: _hint,
                          ),
                          _DockDivider(),
                          DockButton(
                            icon: DIcons.restart,
                            label: 'Restart',
                            enabled: _controller.moves > 0,
                            onTap: _controller.restart,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One line, one message. Priority order: teach, then warn, then report.
  Widget _statusLine(Level level) {
    if (_tutorialActive) {
      return Text(
        _tutorialText,
        key: ValueKey<String>('tut$_tutorialStep'),
        style: Type.bodyStrong.copyWith(color: DS.gold, fontSize: 13.5),
      );
    }
    if (_controller.hint != null) {
      final int left = _controller.hint!.remaining;
      return Text(
        left == 0 ? 'This pour finishes the board' : 'Solvable in $left more after this',
        key: const ValueKey<String>('hint'),
        style: Type.bodyStrong.copyWith(color: DS.gold, fontSize: 13.5),
      );
    }
    if (_controller.isStuck) {
      return Text(
        'No pours left — undo or restart',
        key: const ValueKey<String>('stuck'),
        style: Type.bodyStrong.copyWith(color: DS.hues[0].base, fontSize: 13.5),
      );
    }
    // An obstacle is taught the first time it appears and never again: the
    // status line already exists, so it costs no screen and nothing to
    // dismiss. A modal to explain a brass collar would be worse than the
    // collar being briefly puzzling.
    if (_controller.moves == 0 && level.hasObstacles) {
      final String teach = level.hasNarrow && level.hasColourLock
          ? 'Narrow necks pour one ball · tinted vessels take one colour'
          : (level.hasNarrow
              ? 'A narrow neck lets one ball out at a time'
              : 'A tinted vessel accepts only that colour');
      return Text(
        teach,
        key: const ValueKey<String>('obstacle'),
        textAlign: TextAlign.center,
        style: Type.bodyStrong.copyWith(color: DS.gold, fontSize: 12.5),
      );
    }

    final int? left = _controller.poursLeft;
    if (left != null) {
      // Precision: the budget is the whole point of the level, so it owns the
      // status line. Turns to the warning hue over the last three.
      final Color c = left <= 3 ? DS.hues[0].base : DS.gold;
      return Row(
        key: ValueKey<int>(left),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$left', style: Type.numeralSm.copyWith(fontSize: 15, color: c)),
          Text('  POURS LEFT', style: Type.label.copyWith(color: c.withValues(alpha: 0.7))),
          Container(
            width: 3,
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: DS.s12),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: DS.textTertiary),
          ),
          Text('BUDGET ${level.pourBudget}', style: Type.label),
        ],
      );
    }
    return Row(
      key: ValueKey<int>(_controller.moves),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('${_controller.moves}', style: Type.numeralSm.copyWith(fontSize: 15)),
        Text('  MOVES', style: Type.label),
        Container(
          width: 3,
          height: 3,
          margin: const EdgeInsets.symmetric(horizontal: DS.s12),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: DS.textTertiary),
        ),
        Text('PAR ${level.par}', style: Type.label),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.level,
    required this.chapter,
    required this.sealed,
    required this.flow,
    required this.daily,
    required this.onBack,
    required this.onSettings,
  });

  final Level level;
  final Chapter chapter;
  final int sealed;
  final int flow;
  final bool daily;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  String get _title {
    if (daily) return 'TODAY\'S CHALLENGE';
    // A finale or a precision level says so instead of its chapter — the
    // chapter is where you are, the mode is what is about to happen to you.
    if (level.isBoss) return 'LEVEL ${level.id} · FINALE';
    if (level.isPrecision) return 'LEVEL ${level.id} · PRECISION';
    return 'LEVEL ${level.id} · ${chapter.name.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, 0),
        child: Row(
          children: <Widget>[
            GhostIconButton(icon: DIcons.back, semanticLabel: 'Back', onTap: onBack),
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    _title,
                    style: Type.labelBright.copyWith(
                      color: daily || level.isBoss
                          ? DS.gold
                          : (level.isPrecision ? DS.hues[0].light : null),
                    ),
                  ),
                  const SizedBox(height: DS.s12),
                  // One pip per colour that still needs sealing. Reads faster
                  // than a fraction and animates for free.
                  PipRow(
                    total: level.colorCount,
                    filled: sealed,
                    color: level.isBoss ? DS.gold : DS.aqua,
                  ),
                ],
              ),
            ),
            // The flow chip sits where the settings button is until there is
            // a streak worth showing, then takes its place. Settings is one
            // tap away on the dock anyway; a streak is the thing that needs
            // the eye's attention during play.
            flow >= 2
                ? _FlowChip(flow: flow)
                : GhostIconButton(
                    icon: DIcons.settings,
                    semanticLabel: 'Settings',
                    onTap: onSettings,
                  ),
          ],
        ),
      );
}

/// The live streak: ×1.25, ×1.5 … up to ×2. Pops on each step.
class _FlowChip extends StatefulWidget {
  const _FlowChip({required this.flow});

  final int flow;

  @override
  State<_FlowChip> createState() => _FlowChipState();
}

class _FlowChipState extends State<_FlowChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 360))
      ..forward();
  }

  @override
  void didUpdateWidget(_FlowChip old) {
    super.didUpdateWidget(old);
    if (widget.flow != old.flow) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double mult = GameController.multiplierFor(widget.flow);
    final bool maxed = mult >= 2.0;
    return AnimatedBuilder(
      animation: _pop,
      builder: (BuildContext context, _) {
        final double t = Ease.overshoot.transform(_pop.value);
        return Transform.scale(
          scale: 0.7 + t * 0.3,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: DS.s12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DS.rPill),
              color: DS.gold.withValues(alpha: maxed ? 0.22 : 0.12),
              border: Border.all(color: DS.gold.withValues(alpha: maxed ? 0.8 : 0.45)),
              boxShadow: maxed ? DS.glow(DS.gold, opacity: 0.25, blur: 18, y: 4) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const DIcon(DIcons.flame, size: 14, color: DS.gold),
                const SizedBox(width: DS.s4),
                Text(
                  '×${mult == mult.roundToDouble() ? mult.toInt() : mult}',
                  style: Type.numeralSm.copyWith(fontSize: 14, color: DS.gold),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Precision level, budget spent. Two ways out and no lecture.
class _OutOfPoursSheet extends StatelessWidget {
  const _OutOfPoursSheet({
    required this.level,
    required this.onRetry,
    required this.onHome,
  });

  final Level level;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(DS.s16),
            child: SoftCard(
              radius: DS.rXl,
              tint: DS.hues[0].base,
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s24, DS.s24, DS.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(child: Text('PRECISION', style: Type.label)),
                  const SizedBox(height: DS.s12),
                  Center(
                    child: Text(
                      'Out of pours',
                      style: Type.titleLg.copyWith(color: DS.hues[0].light),
                    ),
                  ),
                  const SizedBox(height: DS.s12),
                  Center(
                    child: Text(
                      'This board has to be cleared in ${level.pourBudget} pours. '
                      'Undo still counts — plan before you pour.',
                      textAlign: TextAlign.center,
                      style: Type.body,
                    ),
                  ),
                  const SizedBox(height: DS.s24),
                  PrimaryButton(label: 'Try again', idlePulse: false, onTap: onRetry),
                  const SizedBox(height: DS.s12),
                  Center(child: TextAction(icon: DIcons.map, label: 'Menu', onTap: onHome)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DockDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 2,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DS.rPill),
          color: DS.outline.withValues(alpha: 0.5),
        ),
      );
}
