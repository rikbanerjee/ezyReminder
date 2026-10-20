import 'dart:async';

import 'package:ezyreminder/features/add/today_add_flow.dart';
import 'package:ezyreminder/features/focus/focus_widgets.dart';
import 'package:ezyreminder/features/home/home_page.dart';
import 'package:ezyreminder/features/shopping/shopping_list_sheet.dart';
import 'package:ezyreminder/features/sidegig/sidegig_page.dart';
import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails the first save, and can hold a save open to test repeat taps.
class _FlakyRepository extends DemoRepository {
  int failures = 0;
  Completer<void>? gate;
  int attempts = 0;

  @override
  Future<String?> save({
    String? id,
    required String title,
    required String? notes,
    required DateTime? dueAt,
    required String contextId,
    required bool isOrder,
    required List<String> channels,
    String? orderRef,
    String? recipientName,
    String? shipBy,
    String? carrier,
  }) async {
    attempts++;
    await gate?.future;
    if (failures > 0) {
      failures--;
      throw StateError('offline');
    }
    return super.save(
      id: id,
      title: title,
      notes: notes,
      dueAt: dueAt,
      contextId: contextId,
      isOrder: isOrder,
      channels: channels,
      orderRef: orderRef,
      recipientName: recipientName,
      shipBy: shipBy,
      carrier: carrier,
    );
  }
}

Future<void> _pump(WidgetTester tester, DemoRepository repository) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    EzyApp(connected: false, preview: true, repository: repository),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAdd(WidgetTester tester) async {
  await tester.tap(find.text('Remind me to…'));
  await tester.pumpAndSettle();
  expect(find.text('What would you like to add?'), findsOneWidget);
}

Future<void> _choose(WidgetTester tester, String step) async {
  await tester.tap(find.byKey(ValueKey('add-choice-$step')));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  // A focused field would scroll itself back into view first.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(BottomSheet), matching: matching);

Future<void> _revealToday(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Today Add lists every destination and keeps Focus on Today', (
    tester,
  ) async {
    await _pump(tester, DemoRepository());
    expect(find.byType(FocusCard), findsWidgets);
    await _openAdd(tester);
    for (final d in addDestinations) {
      expect(find.text(d.label), findsWidgets);
      expect(find.text(d.description), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to add?'), findsNothing);
    expect(find.byType(FocusCard), findsWidgets);
  });

  testWidgets(
    'Today → Side Gig → Task saves one record seen in Today and Side Gig, '
    'then edits and completes that same reminder',
    (tester) async {
      final repository = DemoRepository();
      await _pump(tester, repository);
      await _openAdd(tester);
      await _choose(tester, 'sidegig');
      expect(find.text('Add to Side Gig'), findsOneWidget);
      for (final kind in sideGigAddKinds.values) {
        expect(find.text(kind[0]), findsOneWidget);
      }
      await _choose(tester, 'gig:work');
      await tester.enterText(
        find.byKey(const ValueKey('gig-field-title')),
        'Draft client proposal',
      );
      await _tapVisible(tester, find.widgetWithText(OutlinedButton, 'Save'));

      expect(find.text('Task added to Side Gig'), findsOneWidget);
      expect(repository.reminderCreateCalls, 1);
      final id = repository.lastCreatedReminderId!;
      expect(find.byType(FocusCard), findsWidgets);
      // Visible in Today before any optional details are added.
      await _revealToday(tester, find.text('Draft client proposal'));
      expect(find.text('Draft client proposal'), findsOneWidget);

      // View opens Side Gig's Tasks section with the saved item.
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      final gig = find.byType(SideGigPage);
      expect(
        find.descendant(of: gig, matching: find.text('Draft client proposal')),
        findsWidgets,
      );
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();

      // Editing from Today opens the canonical Side Gig editor on the same ID.
      await _tab(tester, 'Today');
      await _revealToday(tester, find.text('Draft client proposal'));
      await tester.tap(find.text('Draft client proposal'));
      await tester.pumpAndSettle();
      expect(find.byType(GigFormSheet), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('gig-field-title')),
        'Send client proposal',
      );
      await _tapVisible(tester, find.widgetWithText(OutlinedButton, 'Save'));
      final saved = (await repository.loadAll())
          .where((r) => r.id == id)
          .toList();
      expect(saved.single.title, 'Send client proposal');
      expect(repository.reminderCreateCalls, 1);

      // Completing from Today removes it from Side Gig's open Tasks too.
      await _revealToday(tester, find.text('Send client proposal'));
      await tester.tap(find.byKey(ValueKey('ring-$id')));
      await tester.pumpAndSettle();
      expect(
        (await repository.loadAll()).singleWhere((r) => r.id == id).status,
        'done',
      );
      await _tab(tester, 'Side Gig');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Tasks'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: gig, matching: find.text('Send client proposal')),
        findsNothing,
      );
    },
  );

  testWidgets('Today → Side Gig → Order appears in Ship Queue', (tester) async {
    final repository = DemoRepository();
    await _pump(tester, repository);
    await _openAdd(tester);
    await _choose(tester, 'sidegig');
    await _choose(tester, 'gig:order');
    expect(find.text('New order'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('gig-field-title')),
      'Ship mug to Sam',
    );
    await tester.enterText(
      find.byKey(const ValueKey('gig-field-reference')),
      '123',
    );
    await _tapVisible(tester, find.widgetWithText(OutlinedButton, 'Save'));

    expect(find.text('Order added to Ship Queue'), findsOneWidget);
    final id = repository.lastCreatedReminderId!;
    expect(
      (await repository.loadOrders()).where((o) => o.reminderId == id),
      hasLength(1),
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('To ship'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SideGigPage),
        matching: find.text('Ship mug to Sam'),
      ),
      findsOneWidget,
      reason: 'the row leads with the title, not the order reference',
    );
    expect(
      find.descendant(
        of: find.byType(SideGigPage),
        matching: find.textContaining('Ref 123 · '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Today → Home → Bill pay saves into the Bill pay section', (
    tester,
  ) async {
    await _pump(tester, DemoRepository());
    await _openAdd(tester);
    await _choose(tester, 'home');
    expect(find.text('Add to Home'), findsOneWidget);
    expect(find.text('Bill pay'), findsOneWidget);
    await _choose(tester, 'task:bill');
    expect(find.byType(MaintenanceEditor), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bill name'),
      'Electricity',
    );
    await _tapVisible(tester, find.textContaining('Payment due:'));
    await tester.tap(find.byKey(const ValueKey('date-time-ok')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Save reminder'));

    expect(find.text('Bill added to Home'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(HouseholdPage), findsOneWidget);
    expect(find.text('BILLS & PAYMENTS'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Electricity'),
      findsOneWidget,
      reason: 'View opens the saved bill',
    );
  });

  testWidgets('Today → Home → Home care offers its categories first', (
    tester,
  ) async {
    await _pump(tester, DemoRepository());
    await _openAdd(tester);
    await _choose(tester, 'home');
    await _choose(tester, 'home:care');
    expect(find.text('Car service & maintenance'), findsOneWidget);
    expect(find.text('Smart-home batteries'), findsOneWidget);
    await _choose(tester, 'task:car');
    expect(find.text('Car service & maintenance'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Home care'), findsOneWidget);
  });

  testWidgets('Shopping creates a list and continues into its checklist', (
    tester,
  ) async {
    final repository = DemoRepository();
    await _pump(tester, repository);
    await _openAdd(tester);
    await _choose(tester, 'list:shopping');
    expect(find.text('New shopping list'), findsOneWidget);
    await tester.enterText(
      _inSheet(find.byType(TextField)).first,
      'Costco run',
    );
    await _tapVisible(tester, find.text('Save reminder'));
    expect(find.byType(ShoppingListSheet), findsOneWidget);
    expect(
      (await repository.load()).where(
        (r) => r.title == 'Costco run' && r.contextSlug == 'shopping',
      ),
      hasLength(1),
    );
  });

  testWidgets('Back keeps the draft and Close guards unsaved input', (
    tester,
  ) async {
    final repository = DemoRepository();
    await _pump(tester, repository);
    await _openAdd(tester);
    await _choose(tester, 'sidegig');
    await _choose(tester, 'gig:work');
    final title = find.byKey(const ValueKey('gig-field-title'));
    await tester.enterText(title, 'Half-written estimate');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Side Gig'), findsOneWidget);
    await _choose(tester, 'gig:work');
    expect(
      tester.widget<TextField>(title).controller!.text,
      'Half-written estimate',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to add?'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard what you’ve entered?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to add?'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to add?'), findsNothing);
    expect(repository.reminderCreateCalls, 0);
  });

  testWidgets(
    'a failed save keeps the draft inline and a repeat tap saves once',
    (tester) async {
      final repository = _FlakyRepository()..failures = 1;
      await _pump(tester, repository);
      await _openAdd(tester);
      await _choose(tester, 'form:work');
      expect(find.text('New Work reminder'), findsOneWidget);
      expect(find.byKey(const ValueKey('flow-context')), findsOneWidget);
      final title = _inSheet(find.byType(TextField)).first;
      await tester.enterText(title, 'Prepare quarterly review');
      await _tapVisible(tester, find.text('Save reminder'));
      expect(find.textContaining('offline'), findsOneWidget);
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Prepare quarterly review',
      );

      repository.gate = Completer<void>();
      await tester.tap(find.text('Save reminder'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(find.text('Saving…'), warnIfMissed: false);
      await tester.pump();
      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(repository.attempts, 2);
      expect(repository.reminderCreateCalls, 1);
      expect(find.text('Work reminder added to Today'), findsOneWidget);
      expect(
        (await repository.load()).where(
          (r) => r.title == 'Prepare quarterly review',
        ),
        hasLength(1),
      );
    },
  );
}
