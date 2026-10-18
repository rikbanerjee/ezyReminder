import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezyreminder/features/shipping/carrier_fields.dart';

Finder carrierDropdown() => find.byWidgetPredicate(
  (widget) => widget is DropdownButtonFormField<String>,
);

void main() {
  testWidgets(
    'carrier presets are case-insensitive and Other preserves custom names',
    (tester) async {
      final carrier = TextEditingController(text: 'uPs');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CarrierField(controller: carrier)),
        ),
      );

      expect(find.text('UPS'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        findsNothing,
      );

      await tester.tap(carrierDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      expect(carrier.text, '');

      await tester.enterText(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        'Local Courier',
      );
      expect(carrier.text, 'Local Courier');

      await tester.tap(carrierDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('USPS').last);
      await tester.pumpAndSettle();
      expect(carrier.text, 'USPS');
      expect(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'legacy custom carrier hydrates in Other without losing its name',
    (tester) async {
      final carrier = TextEditingController(text: 'Royal Mail');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CarrierField(controller: carrier)),
        ),
      );

      expect(find.text('Other'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        findsOneWidget,
      );
      expect(carrier.text, 'Royal Mail');
    },
  );

  testWidgets(
    'external updates sync while custom values matching presets stay custom',
    (tester) async {
      final carrier = TextEditingController(text: 'Acme Couriers');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CarrierField(controller: carrier)),
        ),
      );
      expect(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        findsOneWidget,
      );

      carrier.text = 'FedEx';
      await tester.pump();
      expect(find.text('FedEx'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        findsNothing,
      );

      await tester.tap(carrierDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        'UPS',
      );
      await tester.pump();
      expect(carrier.text, 'UPS');
      expect(
        find.byKey(const ValueKey('shipping-custom-carrier')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tracking blocks over-limit edits and validates loaded values by carrier',
    (tester) async {
      final tracking = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackingField(controller: tracking, carrier: 'ups'),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'A' * 34);
      expect(tracking.text, 'A' * 34);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${'A' * 34}B',
          selection: const TextSelection.collapsed(offset: 35),
        ),
      );
      expect(tracking.text, 'A' * 34);

      tracking.value = TextEditingValue(text: 'B' * 40);
      await tester.pump();
      expect(trackingError(tracking.text, 'UPS'), contains('34 characters'));
      expect(find.text('40/34'), findsOneWidget);

      tracking.value = TextEditingValue(text: 'C' * 40);
      await tester.pump();
      expect(tracking.text, 'C' * 40);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${'C' * 40}D',
          selection: const TextSelection.collapsed(offset: 41),
        ),
      );
      expect(tracking.text, 'C' * 40);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: 'C' * 39,
          selection: const TextSelection.collapsed(offset: 39),
        ),
      );
      expect(tracking.text, 'C' * 39);

      expect(trackingLimitForCarrier('dhl'), 39);
      expect(trackingLimitForCarrier('DoorDash'), 64);
      expect(trackingError('AB12CD', 'USPS'), isNull);
      expect(trackingError('A' * 39, 'DHL'), isNull);
    },
  );

  testWidgets('accepts parent-supplied paste suffix icon', (tester) async {
    final tracking = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackingField(
            controller: tracking,
            carrier: 'Other',
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste),
              onPressed: () => tracking.text = 'PASTED-TRACKING',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.paste));
    await tester.pump();
    expect(tracking.text, 'PASTED-TRACKING');
  });
}
