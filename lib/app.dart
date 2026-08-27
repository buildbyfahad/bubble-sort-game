import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/level_catalog.dart';
import 'design/tokens.dart';
import 'design/typography.dart';
import 'services/audio_service.dart';
import 'services/haptic_service.dart';
import 'services/progress_service.dart';
import 'services/settings_service.dart';
import 'ui/app_scope.dart';
import 'ui/screens/home_screen.dart';
import 'ui/widgets/ambient_background.dart';
import 'ui/widgets/brand_mark.dart';
import 'ui/widgets/logo.dart';

/// Root. Built on [WidgetsApp] rather than MaterialApp on purpose: this game
/// uses none of Material's components, and inheriting its theme, ripples,
/// default fonts and page transitions would drag in exactly the generic
/// look the design is trying to avoid.
class BubbleSortApp extends StatefulWidget {
  const BubbleSortApp({super.key, this.loadCatalog});

  /// How the level catalogue is obtained. Defaults to reading and decoding the
  /// bundled asset on a worker isolate.
  ///
  /// Overridable because `testWidgets` runs inside a fake-async zone where an
  /// isolate hop never resolves - a test can pass an already-parsed catalogue
  /// instead of the production path being compromised to suit it.
  final Future<LevelCatalog> Function()? loadCatalog;

  @override
  State<BubbleSortApp> createState() => _BubbleSortAppState();
}

class _BubbleSortAppState extends State<BubbleSortApp> {
  /// Backgrounding has to stop the score. A puzzle game still humming to
  /// itself from the app switcher is the kind of thing that gets a one-star
  /// review with the word "battery" in it.
  AppLifecycleListener? _lifecycle;

  LevelCatalog? _catalog;
  SettingsService? _settings;
  ProgressService? _progress;
  AudioService? _audio;
  HapticService? _haptics;

  /// Held true until both the services are ready *and* a minimum display time
  /// has passed, so the opening frame is always a composed brand moment rather
  /// than a flash of logo on fast devices.
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final Future<void> minimumHold =
        Future<void>.delayed(const Duration(milliseconds: 900));

    final LevelCatalog catalog = await (widget.loadCatalog ?? LevelCatalog.load)();
    final SettingsService settings = await SettingsService.load();
    final ProgressService progress = await ProgressService.load(catalog.length);
    final AudioService audio = AudioService(settings);
    final HapticService haptics = HapticService(settings);

    // Warm the audio pool alongside the splash rather than in front of it.
    // Cues are silent until it reports ready, and the player reaching the menu
    // must never be gated on the platform's audio stack answering.
    unawaited(audio.init().then((_) => audio.startMusic()));

    _lifecycle = AppLifecycleListener(
      onHide: audio.suspend,
      onPause: audio.suspend,
      onRestart: audio.resumeAll,
      onShow: audio.resumeAll,
    );

    await minimumHold;
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _settings = settings;
      _progress = progress;
      _audio = audio;
      _haptics = haptics;
      _booting = false;
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Bubble Sort',
      color: DS.ink,
      debugShowCheckedModeBanner: false,
      textStyle: Type.body,
      // Routes are pushed imperatively with the game's own transitions; this
      // is only the root page.
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: DS.tSlow,
        pageBuilder: (BuildContext c, Animation<double> a, Animation<double> s) =>
            FadeTransition(opacity: a, child: builder(c)),
      ),
      // AppScope is installed here, in `builder`, rather than around `home`.
      // `builder` wraps the Navigator; `home` is only its first route. Anything
      // pushed on top of `home` is a sibling of it, not a descendant — so a
      // scope placed around `home` would be invisible to every screen the
      // player navigates to.
      builder: (BuildContext context, Widget? child) {
        // Lock text scaling to a sane band: the board is a fixed-geometry
        // composition, and a 2× system font would break its balance.
        final MediaQueryData mq = MediaQuery.of(context);
        final Widget scaled = MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(
              mq.textScaler.scale(1).clamp(0.9, 1.15),
            ),
          ),
          child: child!,
        );

        final SettingsService? settings = _settings;
        if (settings == null) return scaled; // still booting; nothing needs it

        return AppScope(
          catalog: _catalog!,
          settings: settings,
          progress: _progress!,
          audio: _audio!,
          haptics: _haptics!,
          child: scaled,
        );
      },
      home: AnimatedSwitcher(
        duration: DS.tSlow,
        switchInCurve: Ease.out,
        switchOutCurve: Ease.inFast,
        child: _booting || _settings == null
            ? const _BootScreen(key: ValueKey<String>('boot'))
            : const HomeScreen(key: ValueKey<String>('home')),
      ),
    );
  }
}

/// The opening frame.
///
/// A splash exists to buy time for disk I/O, and most of them look it. This one
/// is the same composition the home screen opens with — same mark, same ground,
/// same light — so the transition into the menu reads as the page settling
/// rather than as one screen being replaced by another.
class _BootScreen extends StatefulWidget {
  const _BootScreen({super.key});

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, _) {
            final double mark = Ease.out.transform((_c.value / 0.55).clamp(0.0, 1.0));
            final double word =
                Ease.out.transform(((_c.value - 0.30) / 0.60).clamp(0.0, 1.0));

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Opacity(
                  opacity: mark,
                  child: Transform.scale(
                    scale: 0.90 + mark * 0.10,
                    child: const BrandMark(size: 116, animate: true),
                  ),
                ),
                const SizedBox(height: DS.s24),
                Opacity(
                  opacity: word,
                  child: Transform.translate(
                    offset: Offset(0, (1 - word) * 10),
                    child: const Wordmark(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// System chrome: fully transparent bars over the ambient ground, with light
/// icons. Called once at startup.
void configureSystemChrome() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarDividerColor: Color(0x00000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}
