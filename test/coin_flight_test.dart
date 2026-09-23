import 'package:bubble_sort/ui/widgets/coin_flight.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collecting a reward has to *show* something moving. These check the flight
/// actually runs and reports every arrival, because the counter it drives is
/// wired to those callbacks — a flight that silently dropped a coin would
/// leave the displayed total short.
void main() {
  testWidgets('coins fly, land, and report every arrival', (WidgetTester tester) async {
    final CoinFlightController c = CoinFlightController();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoinFlight(controller: c),
      ),
    );

    int landed = 0;
    c.send(
      from: const Offset(40, 400),
      to: const Offset(300, 60),
      count: 9,
      onArrive: () => landed++,
    );
    expect(c.isEmpty, isFalse, reason: 'the flight should be in the air');

    // Long enough for the last coin's stagger plus its own life.
    for (int i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(landed, 9, reason: 'every coin must report its arrival');
    expect(c.isEmpty, isTrue, reason: 'the flight should have cleared itself');
  });

  testWidgets('a payout never throws more coins than it is worth',
      (WidgetTester tester) async {
    final CoinFlightController c = CoinFlightController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: CoinFlight(controller: c)),
    );

    // Three coins for a payout of three — not a dozen.
    int landed = 0;
    c.send(from: Offset.zero, to: const Offset(10, 10), count: 3, onArrive: () => landed++);
    for (int i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(landed, 3);
  });
}
