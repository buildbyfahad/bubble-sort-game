import 'package:flutter/widgets.dart';

import '../data/level_catalog.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../services/progress_service.dart';
import '../services/settings_service.dart';

/// The four long-lived services, handed down the tree.
///
/// Deliberately not a state-management framework: this game has exactly one
/// player, no server, and four singletons. An inherited widget over
/// [ChangeNotifier]s is the whole requirement, and keeping it that small is
/// what keeps the frame budget for the board.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.catalog,
    required this.settings,
    required this.progress,
    required this.audio,
    required this.haptics,
    required super.child,
  });

  final LevelCatalog catalog;
  final SettingsService settings;
  final ProgressService progress;
  final AudioService audio;
  final HapticService haptics;

  static AppScope of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      catalog != old.catalog ||
      settings != old.settings ||
      progress != old.progress ||
      audio != old.audio ||
      haptics != old.haptics;
}

/// Rebuilds [builder] whenever any of the given notifiers fire. Saves wiring
/// an AnimatedBuilder by hand at half a dozen call sites.
class Observes extends StatelessWidget {
  const Observes({super.key, required this.listenables, required this.builder});

  final List<Listenable> listenables;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge(listenables),
        builder: (BuildContext context, _) => builder(context),
      );
}
