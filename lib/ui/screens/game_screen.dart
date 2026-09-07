import 'package:flutter/widgets.dart';

import '../../data/level.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../engine/game_controller.dart';
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
  const GameScreen({super.key, required this.levelId});

  final int levelId;

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
    )..onSolved = _handleSolved;
    _controller.addListener(_advanceTutorial);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_advanceTutorial)
      ..dispose();
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
    final Level level = _controller.level;
    final double before = _scope.progress.completion;
    final bool firstClear = !_scope.progress.isCleared(level.id);
    final bool improved = await _scope.progress.recordClear(level.id, _controller.moves);

    // Pay the board out. A replay pays a token amount rather than the full
    // rate — see WalletService.payoutFor for why the difference matters.
    final ClearGrade grade = gradeFor(_controller.moves, level.par);
    final int coins = WalletService.payoutFor(
      flawless: grade == ClearGrade.flawless,
      great: grade == ClearGrade.great,
      firstClear: firstClear,
    );
    await _scope.wallet.grantCoins(coins);
    if (firstClear) await _scope.wallet.grantHints(1);

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
            _scope.audio.tap();
            Navigator.of(context).pop();
            setState(() {
              _controller
                ..removeListener(_advanceTutorial)
                ..dispose();
              _build();
            });
          },
          onHome: () {
            _scope.audio.whoosh();
            Navigator.of(context)
              ..pop()
              ..pop();
          },
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
      _scope.haptics.reject();
      _scope.audio.tap();
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
      child: SafeArea(
        child: Observes(
          listenables: <Listenable>[
            _controller,
            _scope.settings,
            _scope.progress,
            _scope.wallet,
          ],
          builder: (BuildContext context) {
            final int sealed = _controller.state.sealedCount;

            return Column(
              children: <Widget>[
                _TopBar(
                  level: level,
                  chapter: _chapter,
                  sealed: sealed,
                  onBack: () {
                    _scope.audio.tap();
                    Navigator.of(context).pop();
                  },
                  onSettings: () {
                    _scope.audio.tap();
                    Navigator.of(context).push(sheetRoute<void>(const SettingsSheet()));
                  },
                ),

                // --- board -------------------------------------------------
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(DS.s24, DS.s8, DS.s24, DS.s8),
                    child: BoardView(
                      controller: _controller,
                      colorAssist: _scope.settings.colorAssist,
                      guideTube: _guideTube,
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
    required this.onBack,
    required this.onSettings,
  });

  final Level level;
  final Chapter chapter;
  final int sealed;
  final VoidCallback onBack;
  final VoidCallback onSettings;

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
                    'LEVEL ${level.id} · ${chapter.name.toUpperCase()}',
                    style: Type.labelBright,
                  ),
                  const SizedBox(height: DS.s12),
                  // One pip per colour that still needs sealing. Reads faster
                  // than a fraction and animates for free.
                  PipRow(total: level.colorCount, filled: sealed),
                ],
              ),
            ),
            GhostIconButton(icon: DIcons.settings, semanticLabel: 'Settings', onTap: onSettings),
          ],
        ),
      );
}

class _DockDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.055),
      );
}
