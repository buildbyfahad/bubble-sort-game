import 'package:flutter/widgets.dart';

import '../data/level_catalog.dart';
import '../services/ads_service.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../services/progress_service.dart';
import '../services/settings_service.dart';
import '../services/wallet_service.dart';

/// The long-lived services, handed down the tree.
///
/// Deliberately not a state-management framework: this game has exactly one
/// player, no server, and a handful of singletons. An inherited widget over
/// [ChangeNotifier]s is the whole requirement, and keeping it that small is
/// what keeps the frame budget for the board.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.catalog,
    required this.settings,
    required this.progress,
    required this.wallet,
    required this.audio,
    required this.haptics,
    required this.ads,
    required super.child,
  });

  final LevelCatalog catalog;
  final SettingsService settings;
  final ProgressService progress;
  final WalletService wallet;
  final AudioService audio;
  final HapticService haptics;
  final AdsService ads;

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
      wallet != old.wallet ||
      audio != old.audio ||
      haptics != old.haptics ||
      ads != old.ads;
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
