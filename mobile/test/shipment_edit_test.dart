import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezyreminder/main.dart' as app;

Future<void> openShipQueue(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Side Gig'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Ship Queue'));
  await tester.tap(find.widgetWithText(OutlinedButton, 'Ship Queue'));
  await tester.pumpAndSettle();
}

Future<void> openShippedOrderEditor(WidgetTester tester) async {
  await tester.tap(find.text('Shipped'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byTooltip('Edit order').first);
  await tester.tap(find.byTooltip('Edit order').first);
  await tester.pumpAndSettle();
}

Future<void> openPendingOrderEditor(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Edit order').first);
  await tester.tap(find.byTooltip('Edit order').first);
  await tester.pumpAndSettle();
}

Future<void> scrollSheetTo(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(target, 250, scrollable: scrollable);
}

void main() {
  test(
    'Demo save preserves shipment timestamp unless status changes',
    () async {
      final repo = app.DemoRepository();
      await repo.markShipped('fixture-order', '1' * 34, 'UPS');
      final reminder = (await repo.loadAll()).singleWhere(
        (item) => item.id == 'fixture-order',
      );
      final shippedOrder = (await repo.loadOrders()).singleWhere(
        (item) => item.reminderId == 'fixture-order',
      );
      final originalShippedAt = shippedOrder.shippedAt;

      await (repo as app.ShipmentEditingRepository).saveOrderReminder(
        reminder: reminder,
        order: app.OrderDetails(
          reminderId: shippedOrder.reminderId,
          orderRef: shippedOrder.orderRef,
          recipientName: 'Updated recipient',
          shipBy: shippedOrder.shipBy,
          carrier: shippedOrder.carrier,
          trackingNumber: '2' * 34,
          shippedAt: shippedOrder.shippedAt,
          title: shippedOrder.title,
          contextName: shippedOrder.contextName,
          contextSlug: shippedOrder.contextSlug,
        ),
      );
      var savedOrder = (await repo.loadOrders()).singleWhere(
        (item) => item.reminderId == 'fixture-order',
      );
      var savedReminder = (await repo.loadAll()).singleWhere(
        (item) => item.id == 'fixture-order',
      );
      expect(savedOrder.recipientName, 'Updated recipient');
      expect(savedOrder.trackingNumber, '2' * 34);
      expect(savedOrder.shippedAt, originalShippedAt);
      expect(savedReminder.status, 'done');

      await (repo as app.ShipmentEditingRepository).saveOrderReminder(
        reminder: savedReminder,
        order: savedOrder,
        shipped: false,
      );
      savedOrder = (await repo.loadOrders()).singleWhere(
        (item) => item.reminderId == 'fixture-order',
      );
      savedReminder = (await repo.loadAll()).singleWhere(
        (item) => item.id == 'fixture-order',
      );
      expect(savedOrder.shipped, isFalse);
      expect(savedOrder.trackingNumber, '2' * 34);
      expect(savedReminder.status, 'open');

      await (repo as app.ShipmentEditingRepository).saveOrderReminder(
        reminder: savedReminder,
        order: savedOrder,
        shipped: true,
      );
      savedOrder = (await repo.loadOrders()).singleWhere(
        (item) => item.reminderId == 'fixture-order',
      );
      savedReminder = (await repo.loadAll()).singleWhere(
        (item) => item.id == 'fixture-order',
      );
      expect(savedOrder.shipped, isTrue);
      expect(savedOrder.shippedAt, isNotNull);
      expect(savedReminder.status, 'done');
    },
  );

  testWidgets('shipped order tracking and recipient remain editable', (
    tester,
  ) async {
    final repo = app.DemoRepository();
    await repo.markShipped('fixture-order', '1' * 34, 'UPS');
    await tester.pumpWidget(
      app.EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await openShipQueue(tester);
    await openShippedOrderEditor(tester);

    final recipientField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Recipient',
    );
    final trackingField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Tracking # (optional)',
    );
    await scrollSheetTo(tester, recipientField);
    await tester.enterText(recipientField, 'Updated recipient');
    await scrollSheetTo(tester, trackingField);
    await tester.enterText(trackingField, '2' * 34);
    await scrollSheetTo(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();

    final order = (await repo.loadOrders()).singleWhere(
      (item) => item.reminderId == 'fixture-order',
    );
    final reminder = (await repo.loadAll()).singleWhere(
      (item) => item.id == 'fixture-order',
    );
    expect(order.recipientName, 'Updated recipient');
    expect(order.trackingNumber, '2' * 34);
    expect(order.shipped, isTrue);
    expect(reminder.status, 'done');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching Shipped off reopens reminder and returns it to queue',
    (tester) async {
      final repo = app.DemoRepository();
      await repo.markShipped('fixture-order', '1' * 34, 'UPS');
      await tester.pumpWidget(
        app.EzyApp(connected: false, preview: true, repository: repo),
      );
      await tester.pumpAndSettle();
      await openShipQueue(tester);
      await openShippedOrderEditor(tester);

      final shippedSwitch = find.byKey(
        const ValueKey('shipment-status-switch'),
      );
      await scrollSheetTo(tester, shippedSwitch);
      expect(shippedSwitch, findsOneWidget);
      await tester.tap(shippedSwitch);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Saving returns this order to Ship Queue and reopens its reminder.',
        ),
        findsOneWidget,
      );
      await scrollSheetTo(tester, find.text('Save reminder'));
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();

      var order = (await repo.loadOrders()).singleWhere(
        (item) => item.reminderId == 'fixture-order',
      );
      var reminder = (await repo.loadAll()).singleWhere(
        (item) => item.id == 'fixture-order',
      );
      expect(order.shipped, isFalse);
      expect(reminder.status, 'open');
      await tester.tap(find.text('To ship'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit order'), findsOneWidget);

      await openPendingOrderEditor(tester);
      final pendingStatusSwitch = find.byKey(
        const ValueKey('shipment-status-switch'),
      );
      await scrollSheetTo(tester, pendingStatusSwitch);
      await tester.tap(pendingStatusSwitch);
      await tester.pumpAndSettle();
      await scrollSheetTo(tester, find.text('Save reminder'));
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();

      order = (await repo.loadOrders()).singleWhere(
        (item) => item.reminderId == 'fixture-order',
      );
      reminder = (await repo.loadAll()).singleWhere(
        (item) => item.id == 'fixture-order',
      );
      expect(order.shipped, isTrue);
      expect(reminder.status, 'done');
      expect(tester.takeException(), isNull);
    },
  );
}
