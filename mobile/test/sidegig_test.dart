import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezyreminder/main.dart';
import 'package:ezyreminder/features/focus/focus_controller.dart';
import 'package:ezyreminder/features/focus/focus_repository.dart';
import 'package:ezyreminder/features/sidegig/sidegig_repository.dart';
import 'package:ezyreminder/features/sidegig/sidegig_page.dart';

Future<void> chooseCaptureContext(WidgetTester tester, String name) async {
  final dropdown = find.byType(DropdownButtonFormField<String>).last;
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

/// Today opens the organized Add flow; All keeps the minimal capture sheet.
Future<void> openQuickCapture(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('All'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remind me to…'));
  await tester.pumpAndSettle();
}

Future<void> revealCapture(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  final fixture = Map<String, dynamic>.from(
    jsonDecode(File('../design/sidegig-fixtures.json').readAsStringSync())
        as Map,
  );
  test('shared attention and exact currency fixtures', () {
    final d = GigDashboard.fromMap(fixture);
    expect(d.attention.map((r) => r.id).toList(), fixture['attention_ids']);
    expect(
      gigMoney(d.items.where((r) => r.kind == 'payment')).totals,
      fixture['money_totals'],
    );
  });
  testWidgets(
    'All captures simply then edits the same Side Gig task in its full form',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = DemoRepository();
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repository),
      );
      await tester.pumpAndSettle();
      await openQuickCapture(tester);
      final title = find.byKey(const ValueKey('capture-title'));
      await tester.enterText(title, 'Write the client estimate');
      for (final context in ['Side Gig', 'Work', 'Side Gig']) {
        await chooseCaptureContext(tester, context);
        expect(find.byType(GigFormSheet), findsNothing);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(title).controller!.text,
          'Write the client estimate',
        );
        expect(find.byKey(const ValueKey('gig-field-next_step')), findsNothing);
        expect(find.text('Order details'), findsNothing);
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        title,
        findsOneWidget,
        reason: 'the scrim cannot discard a capture',
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this reminder?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Write the client estimate',
      );
      await revealCapture(tester, find.text('Save reminder'));
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();
      final original = (await repository.loadAll()).singleWhere(
        (r) => r.title == 'Write the client estimate',
      );
      expect(original.isOrder, isFalse);
      expect(original.dueAt, isNull);
      expect(original.notes, isNull);
      expect(repository.reminderCreateCalls, 1);
      // The tab was mounted before capture. It must show the new plain task
      // without first editing/enriching it in the Side Gig form.
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Side Gig'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Work'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Write the client estimate'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SideGigPage),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(find.text('Write the client estimate'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Today'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Write the client estimate'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write the client estimate'));
      await tester.pumpAndSettle();
      expect(find.byType(GigFormSheet), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('gig-field-title')))
            .controller!
            .text,
        'Write the client estimate',
      );
      await revealCapture(tester, find.text('This is an order'));
      await tester.tap(find.text('This is an order'));
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('gig-field-next_step'));
      await revealCapture(tester, next);
      await tester.enterText(next, 'Compare the two pricing options.');
      final save = find.widgetWithText(OutlinedButton, 'Save');
      await revealCapture(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final saved = (await repository.loadAll())
          .where((r) => r.title == 'Write the client estimate')
          .toList();
      expect(saved, hasLength(1));
      expect(saved.single.id, original.id);
      expect(saved.single.isOrder, isTrue);
      expect(
        (await repository.loadOrders()).where(
          (o) => o.reminderId == original.id,
        ),
        hasLength(1),
      );
      expect(repository.reminderCreateCalls, 1);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Side Gig'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Work'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Write the client estimate'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SideGigPage),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Write the client estimate'), findsOneWidget);
      expect(
        find.textContaining('Compare the two pricing options.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Side Gig destination has full sections and creates a basic task',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: DemoRepository()),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Side Gig'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your work. Your own pace.'), findsOneWidget);
      expect(find.text('Ship Queue'), findsWidgets);
      await tester.tap(find.text('Add to Side Gig'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'What do you need to remember?'),
        'Draft the estimate',
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Save'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(GigFormSheet), findsNothing);
      expect(find.text('Draft the estimate'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'payment recording preserves order and displays received history',
    (tester) async {
      final repo = MemoryGigRepository(
        items: [
          GigItem({
            'id': 'pay',
            'kind': 'payment',
            'title': 'Client balance',
            'status': 'open',
            'context_slug': 'sidegig',
            'amount': '20.10',
            'currency': 'USD',
            'due_at': '2026-10-22T14:00:00Z',
          }),
          GigItem({
            'id': 'order',
            'kind': 'order',
            'title': 'Ship order',
            'status': 'open',
            'context_slug': 'sidegig',
            'ship_by': '2026-10-23',
          }),
        ],
      );
      final f = FocusController(
        DemoFocusRepository(loadReminders: () async => []),
        tick: false,
      );
      final theme = ThemeData(
        extensions: [
          const Palette(
            Colors.white,
            Colors.black,
            Colors.grey,
            Color(0xffE5E4E0),
            [Colors.blue, Colors.orange, Colors.green, Colors.purple],
            BoxShadow(),
            BoxShadow(),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SideGigPage(repository: repo, focus: f, openId: 'pay'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Record received'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Confirm received'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Confirm received'));
      await tester.pumpAndSettle();
      final d = await repo.load();
      expect(d.items.firstWhere((r) => r.id == 'pay').status, 'received');
      expect(d.items.firstWhere((r) => r.id == 'order').status, 'open');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      repo.dispose();
    },
  );
}
