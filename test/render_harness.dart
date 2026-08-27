import 'dart:io';

import 'package:bubble_sort/data/level_catalog.dart';
import 'package:bubble_sort/services/audio_service.dart';
import 'package:bubble_sort/services/haptic_service.dart';
import 'package:bubble_sort/services/progress_service.dart';
import 'package:bubble_sort/services/settings_service.dart';
import 'package:bubble_sort/ui/app_scope.dart';
import 'package:bubble_sort/design/tokens.dart';
import 'package:bubble_sort/design/typography.dart';
import 'package:meta/meta.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Declares a golden test that renders with real shadow blur.
///
/// `flutter_test` sets [debugDisableShadows], which draws every shadow as a
/// solid, unblurred shape. That is fine for layout assertions and actively
/// misleading here — it turns every soft glow in this design into a hard bevel.
/// The flag has to be restored inside the test body, because the binding
/// asserts it is back to its default before the test's own teardown runs.
@isTest
void renderTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (WidgetTester tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

/// Loads the bundled variable fonts into the test renderer.
///
/// Without this every golden renders in the test framework's placeholder font
/// and the whole exercise — checking that the type, spacing and hierarchy
/// actually work — is worthless.
Future<void> loadAppFonts() async {
  for (final (String family, String path) in <(String, String)>[
    (Type.display, 'assets/fonts/Sora.ttf'),
    (Type.ui, 'assets/fonts/Inter.ttf'),
  ]) {
    final FontLoader loader = FontLoader(family)
      ..addFont(File(path).readAsBytes().then((Uint8List b) => b.buffer.asByteData()));
    await loader.load();
  }
}

/// The real level catalogue, read straight off disk.
///
/// Loaded once and shared: parsing a thousand levels per test would dominate
/// the suite's runtime for no benefit.
/// Read *synchronously* on purpose. `testWidgets` runs its body in a fake-async
/// zone where real I/O futures never complete, so an `await readAsString()`
/// here simply hangs the test.
LevelCatalog? _catalog;
LevelCatalog loadCatalog() =>
    _catalog ??= LevelCatalog.fromRaw(File(LevelCatalog.assetPath).readAsStringSync());

/// Builds a real [AppScope] over mocked preferences, so screens under test see
/// the same services they see in the app.
Future<AppScope> buildScope({
  required Widget child,
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final LevelCatalog catalog = loadCatalog();
  final SettingsService settings = await SettingsService.load();
  final ProgressService progress = await ProgressService.load(catalog.length);
  return AppScope(
    catalog: catalog,
    settings: settings,
    progress: progress,
    audio: AudioService(settings),
    haptics: HapticService(settings),
    child: child,
  );
}

/// Sizes the test surface to a real handset. Without this every golden renders
/// into the framework's 800x600 default, which is a landscape tablet — and a
/// portrait composition judged in landscape tells you nothing.
void useHandset(WidgetTester tester, {Size size = const Size(393, 852), double dpr = 2}) {
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = size * dpr
    ..padding = FakeViewPadding(top: 54 * dpr, bottom: 28 * dpr)
    ..viewPadding = FakeViewPadding(top: 54 * dpr, bottom: 28 * dpr);
  addTearDown(tester.view.reset);
}

/// Wraps a screen in the minimum app chrome a golden needs.
Widget harness(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: Type.body,
        child: Navigator(
          onGenerateRoute: (RouteSettings s) => PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => ColoredBox(color: DS.ink, child: child),
          ),
        ),
      ),
    );

/// Runs out any timer the app left armed — staggered entrance delays, and the
/// bounded timeout guarding audio initialisation, which never resolves in a
/// test because no platform is there to answer it. The binding asserts no
/// timers are pending when a test ends.
Future<void> drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pump();
}

/// Advances time in fixed steps. [WidgetTester.pumpAndSettle] never returns
/// here because the ambient background loops forever by design.
Future<void> settle(WidgetTester tester, {int steps = 24, int ms = 60}) async {
  for (int i = 0; i < steps; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}
