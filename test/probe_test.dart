import 'package:bubble_sort/ui/widgets/buttons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_harness.dart';

/// Isolated render of the primary button on the app ground, used to judge the
/// shadow treatment on its own rather than through a full screen.
void main() {
  setUpAll(loadAppFonts);

  renderTest('button probe', (WidgetTester tester) async {
    useHandset(tester, size: const Size(360, 260));
    await tester.pumpWidget(harness(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            PrimaryButton(label: 'Continue', sublabel: 'LEVEL 05 · SUSPENSION', onTap: () {}),
          ],
        ),
      ),
    ));
    await settle(tester, steps: 6);
    await expectLater(find.byType(Navigator), matchesGoldenFile('goldens/probe_button.png'));
  });
}
