import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../transitions.dart';
import '../widgets/ambient_background.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/brand_mark.dart';
import '../widgets/logo.dart';
import '../widgets/surfaces.dart';
import 'game_screen.dart';
import 'levels_screen.dart';
import 'settings_sheet.dart';

/// The first three seconds.
///
/// The composition is deliberately sparse: an identity block that owns the
/// upper half, one card of state, one gold button, and one quiet secondary
/// action. Everything else a home screen usually accumulates — a shop, a
/// daily reward, four badges, a spinning coin — is absent, and the resulting
/// hierarchy is what makes it read as expensive.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    // Pushed harder here than anywhere else in the game. The menu is mostly
    // negative space by design, and unlit negative space reads as an empty
    // container; a visible warm/cool wash turns the same emptiness into
    // atmosphere.
    return AmbientBackground(
      intensity: 1.9,
      child: SafeArea(
        child: Observes(
          listenables: <Listenable>[scope.progress],
          builder: (BuildContext context) {
            final int total = scope.catalog.length;
            final int cleared = scope.progress.clearedCount;
            final int nextId = scope.progress.currentLevelId;
            final bool finishedAll = cleared == total;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // --- utility row ------------------------------------------
                  Padding(
                    padding: const EdgeInsets.only(top: DS.s8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        RiseIn(
                          index: 0,
                          child: GhostIconButton(
                            icon: DIcons.settings,
                            semanticLabel: 'Settings',
                            onTap: () {
                              scope.audio.tap();
                              Navigator.of(context).push(sheetRoute<void>(const SettingsSheet()));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- identity ---------------------------------------------
                  // Weighted 3:7 rather than centred, so the identity block
                  // lands in the optical upper third and the action block owns
                  // the bottom. A centred logo with equal air above and below
                  // is what makes a menu feel like a placeholder.
                  const Spacer(flex: 4),
                  RiseIn(
                    index: 1,
                    distance: 26,
                    child: Column(
                      children: <Widget>[
                        const BrandMark(size: 124, animate: true),
                        const SizedBox(height: DS.s20),
                        const Wordmark(),
                        const SizedBox(height: DS.s16),
                        Text(
                          'POUR · SETTLE · SOLVE',
                          textAlign: TextAlign.center,
                          style: Type.label.copyWith(color: DS.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 6),

                  // --- state ------------------------------------------------
                  RiseIn(
                    index: 2,
                    child: SoftCard(
                      padding: const EdgeInsets.fromLTRB(DS.s20, DS.s16, DS.s20, DS.s20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text('PROGRESS', style: Type.label),
                                    const SizedBox(height: DS.s8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: <Widget>[
                                        Text('$cleared', style: Type.numeral),
                                        Text(
                                          ' / $total',
                                          style: Type.numeralSm.copyWith(color: DS.textTertiary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: DS.s4),
                                child: Row(
                                  children: <Widget>[
                                    const DIcon(DIcons.hint, size: 15, color: DS.gold),
                                    const SizedBox(width: DS.s8),
                                    Text(
                                      '${scope.progress.hints}',
                                      style: Type.numeralSm.copyWith(color: DS.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: DS.s16),
                          ProgressTrack(value: scope.progress.completion),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: DS.s20),

                  // --- the one obvious thing to press -----------------------
                  RiseIn(
                    index: 3,
                    child: PrimaryButton(
                      label: cleared == 0 ? 'Play' : (finishedAll ? 'Play again' : 'Continue'),
                      sublabel: 'LEVEL $nextId · '
                          '${scope.catalog.chapterOf(nextId).name.toUpperCase()}',
                      onTap: () {
                        scope.audio.whoosh();
                        Navigator.of(context).push(
                          riseRoute<void>(GameScreen(levelId: nextId)),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: DS.s16),

                  RiseIn(
                    index: 4,
                    child: Center(
                      child: TextAction(
                        icon: DIcons.map,
                        label: 'The road',
                        onTap: () {
                          scope.audio.whoosh();
                          Navigator.of(context).push(riseRoute<void>(const LevelsScreen()));
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: DS.s32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
