import 'package:bubble_sort/ui/widgets/brand_mark.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_harness.dart';

/// Renders the brand artwork straight out of the app's own widgets into
/// `assets/branding/`, which `flutter_launcher_icons` and
/// `flutter_native_splash` then slice into platform assets.
///
/// On a normal `flutter test` run this is a **guard**, not a generator: it
/// fails if the committed artwork no longer matches what the code draws, which
/// is exactly what should happen when a brand colour or the mark's geometry
/// moves and nobody re-cut the icons. The fix for a failure here is to
/// regenerate, not to edit a PNG:
///
///   flutter test --update-goldens test/brand_assets_test.dart
///   dart run flutter_launcher_icons
///   dart run flutter_native_splash:create
///
/// Drawing the icon in a design tool would mean maintaining the mark twice and
/// watching the two drift apart the first time a brand colour moves. Rendering
/// it from the same [BrandMark] the menu uses makes that impossible: change a
/// token, re-run this, and the launcher icon follows.
///
///   flutter test --update-goldens test/brand_assets_test.dart
void main() {
  setUpAll(loadAppFonts);

  Future<void> paint(
    WidgetTester tester,
    Widget child,
    double side,
    String path,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(side, side);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(child: SizedBox(width: side, height: side, child: child)),
      ),
    );
    await tester.pump();
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(path));
  }

  renderTest('icon - full bleed, for iOS and legacy Android', (WidgetTester tester) async {
    await paint(
      tester,
      const BrandPlate(size: 1024, child: BrandMark(size: 840)),
      1024,
      '../assets/branding/icon.png',
    );
  });

  renderTest('icon - adaptive foreground', (WidgetTester tester) async {
    // Android crops adaptive icons to an arbitrary mask and animates them, so
    // only the middle ~66% is guaranteed visible. The mark is inset well
    // inside that safe zone; artwork sized to the full canvas gets its edges
    // shaved off on round-mask launchers.
    await paint(
      tester,
      const Center(child: BrandMark(size: 720)),
      1024,
      '../assets/branding/icon_foreground.png',
    );
  });

  renderTest('splash - mark on transparency', (WidgetTester tester) async {
    // Transparent, because the splash background is a flat colour supplied to
    // the platform. Baking the ground into the image would show a visible
    // seam wherever the system's own background peeked out.
    await paint(
      tester,
      const Center(child: BrandMark(size: 480)),
      640,
      '../assets/branding/splash.png',
    );
  });

  renderTest('splash - Android 12 icon', (WidgetTester tester) async {
    // Android 12+ masks the splash icon to a circle and draws it at a fixed
    // size, so this variant is inset harder than the one above.
    await paint(
      tester,
      const Center(child: BrandMark(size: 560)),
      1152,
      '../assets/branding/splash_android12.png',
    );
  });
}
