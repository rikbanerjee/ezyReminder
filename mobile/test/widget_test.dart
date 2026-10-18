import 'dart:async';

import 'package:ezyreminder/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> revealTodayReminder(WidgetTester tester, Finder reminder) async {
  final scrollable = find
      .descendant(
        of: find.byType(CustomScrollView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(reminder, 160, scrollable: scrollable);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preview shows fixture reminders and context filters', (
    tester,
  ) async {
    await tester.pumpWidget(const EzyApp(connected: false, preview: true));
    await tester.pumpAndSettle();
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    await revealTodayReminder(tester, find.text('Send the revised proposal'));
    expect(find.text('Send the revised proposal'), findsOneWidget);
  });

  testWidgets('All searches titles and groups Someday rows by context', (
    tester,
  ) async {
    final repo = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    expect(find.text('Search reminders'), findsOneWidget);
    expect(find.text('SOMEDAY'), findsWidgets);
    final search = find.byKey(const ValueKey('all-search'));
    await tester.enterText(search, 'oat milk');
    await tester.pumpAndSettle();
    expect(find.text('Pick up oat milk'), findsOneWidget);
    expect(find.text('Send the revised proposal'), findsNothing);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side Gig').first);
    await tester.pumpAndSettle();
    expect(find.text('Ship handmade mug'), findsOneWidget);
    expect(find.text('Send the revised proposal'), findsNothing);
  });

  testWidgets('All completes and reopens the same reminder in place', (
    tester,
  ) async {
    final repo = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    final ring = find.byKey(const ValueKey('ring-fixture-1'));
    await tester.tap(ring);
    await tester.pumpAndSettle();
    expect(
      (await repo.loadAll()).firstWhere((r) => r.id == 'fixture-1').status,
      'done',
    );
    expect(find.text('Send the revised proposal'), findsOneWidget);
    await tester.tap(ring);
    await tester.pumpAndSettle();
    expect(
      (await repo.loadAll()).firstWhere((r) => r.id == 'fixture-1').status,
      'open',
    );
    expect(find.text('Send the revised proposal'), findsOneWidget);
  });

  testWidgets('All realtime refresh preserves a pending completion state', (
    tester,
  ) async {
    final repo = DemoRepository();
    final gate = Completer<void>();
    repo.browseWriteGates['complete'] = gate;
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ring-fixture-1')));
    await tester.pumpAndSettle();
    repo.notifyRemoteChange();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ring-fixture-1')),
        matching: find.byIcon(CupertinoIcons.checkmark),
      ),
      findsOneWidget,
    );
    gate.complete();
    repo.browseWriteGates.remove('complete');
    await tester.pumpAndSettle();
    expect(
      (await repo.loadAll()).firstWhere((r) => r.id == 'fixture-1').status,
      'done',
    );
  });

  testWidgets('permanent delete confirms and rolls back a failed write', (
    tester,
  ) async {
    final repo = DemoRepository()..failBrowseWrites.add('delete');
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Send the revised proposal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete reminder?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Send the revised proposal'), findsOneWidget);
    repo.failBrowseWrites.clear();
    await tester.longPress(find.text('Send the revised proposal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Send the revised proposal'), findsNothing);
  });

  testWidgets(
    'Shopping list adds, checks, deletes, and rolls failed writes back',
    (tester) async {
      final repo = DemoRepository();
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping').first);
      await tester.pumpAndSettle();
      await revealTodayReminder(tester, find.text('Pick up oat milk'));
      await tester.tap(find.text('Pick up oat milk'));
      await tester.pumpAndSettle();
      expect(find.text('Coffee beans'), findsOneWidget);
      final add = find.byKey(const ValueKey('shopping-add-input'));
      await tester.enterText(add, 'Apples');
      await tester.tap(find.byTooltip('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('Apples'), findsOneWidget);
      expect(tester.widget<TextField>(add).controller!.text, isEmpty);

      repo.failShoppingWrites.add('toggle');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isFalse,
      );
      repo.failShoppingWrites.clear();

      repo.failShoppingWrites.add('delete');
      await tester.ensureVisible(find.text('Apples'));
      await tester.tap(find.byType(IconButton).last);
      await tester.pumpAndSettle();
      expect(
        find.text('Apples'),
        findsOneWidget,
        reason: 'failed delete restores the item',
      );
      repo.failShoppingWrites.clear();
      await tester.tap(find.byType(IconButton).last);
      await tester.pumpAndSettle();
      expect(find.text('Apples'), findsNothing);
    },
  );

  testWidgets(
    'Shopping realtime refresh merges remote items and created lists reopen',
    (tester) async {
      final repo = DemoRepository();
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping').first);
      await tester.pumpAndSettle();
      await revealTodayReminder(tester, find.text('Pick up oat milk'));
      await tester.tap(find.text('Pick up oat milk'));
      await tester.pumpAndSettle();
      repo.remoteShoppingUpdate('fixture-3', const [
        ShoppingItem(
          id: 'remote-item',
          label: 'Remote item',
          checked: false,
          position: 0,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Remote item'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Shopping failed in-flight toggle reconciles a remote deletion', (
    tester,
  ) async {
    final repo = DemoRepository();
    final gate = Completer<void>();
    repo.shoppingWriteGates['toggle'] = gate;
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopping').first);
    await tester.pumpAndSettle();
    await revealTodayReminder(tester, find.text('Pick up oat milk'));
    await tester.tap(find.text('Pick up oat milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    repo.remoteShoppingUpdate('fixture-3', const [
      ShoppingItem(
        id: 'shop-2',
        label: 'Coffee beans',
        checked: false,
        position: 1,
      ),
      ShoppingItem(
        id: 'shop-3',
        label: 'Dish soap',
        checked: true,
        position: 2,
      ),
    ]);
    await tester.pump();
    repo.failShoppingWrites.add('toggle');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Oat milk'), findsNothing);
  });

  testWidgets(
    'same-label Shopping item remains visible while an add is pending',
    (tester) async {
      final repo = DemoRepository();
      final gate = Completer<void>();
      repo.shoppingWriteGates['add'] = gate;
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping').first);
      await tester.pumpAndSettle();
      await revealTodayReminder(tester, find.text('Pick up oat milk'));
      await tester.tap(find.text('Pick up oat milk'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('shopping-add-input'));
      await tester.enterText(input, 'Oat milk');
      await tester.tap(find.byTooltip('Add item'));
      await tester.pump();
      expect(find.text('Oat milk'), findsNWidgets(2));
      gate.complete();
      repo.shoppingWriteGates.remove('add');
      await tester.pumpAndSettle();
      expect(find.text('Oat milk'), findsNWidgets(2));
    },
  );

  testWidgets('Shopping Done waits for rename and keeps newer title drafts', (
    tester,
  ) async {
    final repo = DemoRepository();
    final gate = Completer<void>();
    repo.shoppingWriteGates['rename'] = gate;
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopping').first);
    await tester.pumpAndSettle();
    await revealTodayReminder(tester, find.text('Pick up oat milk'));
    await tester.tap(find.text('Pick up oat milk'));
    await tester.pumpAndSettle();
    final name = find.byType(TextField).first;
    await tester.enterText(name, 'First name');
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(
      find.text('Done'),
      findsOneWidget,
      reason: 'sheet stays open until save completes',
    );
    await tester.enterText(name, 'Final name');
    gate.complete();
    repo.shoppingWriteGates.remove('rename');
    await tester.pumpAndSettle();
    expect(await repo.loadShoppingListTitle('fixture-3'), 'Final name');
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('create sheet reports missing title and context', (tester) async {
    final repo = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me to…'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save reminder'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Title required'), findsOneWidget);
    expect(find.text('Choose a context'), findsOneWidget);
  });

  testWidgets(
    'Ship Queue expands tracking then confirms and offers one follow-up',
    (tester) async {
      final repo = DemoRepository();
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Ship Queue'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Etsy #1042 · Sarah M.'), findsOneWidget);
      expect(find.text('Ship by tomorrow'), findsOneWidget);
      await tester.tap(find.text('Mark shipped'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm'), findsOneWidget);
      final trackingField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Tracking # (optional)',
      );
      await tester.enterText(trackingField, 'TRACK-1042');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Shipped ✓'), findsOneWidget);
      expect((await repo.loadOrders()).single.trackingNumber, 'TRACK-1042');
      await tester.tap(find.text('+3d follow-up'));
      await tester.pumpAndSettle();
      expect(repo.followUpCalls, 1);
    },
  );

  testWidgets(
    'editing an order merges untouched metadata after remote completion',
    (tester) async {
      final repo = DemoRepository();
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Ship Queue'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit order'));
      await tester.pumpAndSettle();
      expect(find.text('Reminder'), findsOneWidget);
      final ref = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Order ref',
      );
      final recipient = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Recipient',
      );
      await tester.scrollUntilVisible(
        ref,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(ref, 'Local edit');
      repo.remoteUpdateOrder(
        OrderDetails(
          reminderId: 'fixture-order',
          title: 'Ship handmade mug',
          contextName: 'Side Gig',
          contextSlug: 'side_gig',
          orderRef: 'Remote ref',
          recipientName: 'Remote buyer',
          shipBy: '2026-10-18',
          carrier: 'USPS',
          trackingNumber: 'EXISTING-TRACK',
          shippedAt: '2026-10-16T10:00:00Z',
        ),
        completeReminder: true,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(ref).controller!.text, 'Local edit');
      expect(
        tester.widget<TextField>(recipient).controller!.text,
        'Remote buyer',
      );
      await tester.ensureVisible(find.text('Tracking · EXISTING-TRACK'));
      expect(find.textContaining('Shipped ·'), findsOneWidget);
      expect(find.text('Tracking · EXISTING-TRACK'), findsOneWidget);
    },
  );

  testWidgets('order edit sheet marks shipped and offers follow-up', (
    tester,
  ) async {
    final repo = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Ship Queue'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit order'));
    await tester.pumpAndSettle();
    final markShipped = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.text('Mark shipped'),
    );
    await tester.scrollUntilVisible(
      markShipped,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(markShipped);
    await tester.pumpAndSettle();
    await tester.tap(markShipped);
    await tester.pumpAndSettle();
    expect(find.textContaining('Shipped ✓'), findsOneWidget);
    await tester.tap(find.text('+3d follow-up'));
    await tester.pumpAndSettle();
    expect(repo.followUpCalls, 1);
  });

  testWidgets('Ship Queue expanded controls fit at 1.5x on a 393px screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EzyApp(
        connected: false,
        preview: true,
        repository: DemoRepository(),
        textScale: 1.5,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Ship Queue'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark shipped'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row opens edit sheet and ring completes the reminder', (
    tester,
  ) async {
    final repo = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await revealTodayReminder(tester, find.text('Send the revised proposal'));
    await tester.tap(find.text('Send the revised proposal'));
    await tester.pumpAndSettle();
    expect(find.text('Reminder'), findsOneWidget);
    await tester.tapAt(const Offset(190, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ring-fixture-1')));
    await tester.pumpAndSettle();
    expect(find.text('Completed “Send the revised proposal”'), findsOneWidget);
    expect(
      (await repo.load()).any((r) => r.title == 'Send the revised proposal'),
      isFalse,
    );
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('Today and sheet fit at ${scale}x text scale', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, textScale: scale),
      );
      await tester.pumpAndSettle();
      final screenException = tester.takeException();
      expect(screenException, isNull, reason: '$screenException');
      await tester.tap(find.text('Remind me to…'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
