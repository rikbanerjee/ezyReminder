import 'dart:async';

import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Today and All both open the organized Add flow; this adds from All.
Future<void> addFromAll(
  WidgetTester tester,
  String destination,
  String title,
) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('All'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remind me to…'));
  await tester.pumpAndSettle();
  expect(find.text('What would you like to add?'), findsOneWidget);
  await tester.tap(find.byKey(ValueKey('add-choice-form:$destination')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        )
        .first,
    title,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await revealSheetControl(tester, find.text('Save reminder'));
  await tester.pumpAndSettle();
}

/// The Add flow confirms with a toast; clear it so later snackbars show.
Future<void> clearToast(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .clearSnackBars();
  await tester.pumpAndSettle();
}

Future<void> revealSheetControl(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).last;
  await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
}

Future<void> revealTodayReminder(WidgetTester tester, Finder reminder) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Today'),
    ),
  );
  await tester.pumpAndSettle();
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
  testWidgets('new Work reminder creates once then saves follow-up details', (
    tester,
  ) async {
    final repository = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await addFromAll(tester, 'work', 'Prepare launch brief');
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    await clearToast(tester);
    await revealTodayReminder(tester, find.text('Prepare launch brief'));
    await tester.tap(find.text('Prepare launch brief'));
    await tester.pumpAndSettle();
    await revealSheetControl(
      tester,
      find.byKey(const ValueKey('work-details-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('work-details-toggle')));
    await tester.pumpAndSettle();
    await revealSheetControl(
      tester,
      find.byKey(const ValueKey('work-manager')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('work-manager')),
      'Morgan',
    );
    await tester.enterText(
      find.byKey(const ValueKey('work-department-resource')),
      'People Ops',
    );
    await tester.enterText(
      find.byKey(const ValueKey('work-project')),
      'Launch',
    );
    await revealSheetControl(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();

    expect(repository.reminderCreateCalls, 1);
    final id = repository.lastCreatedReminderId!;
    expect(repository.workDetails[id]?.managerName, 'Morgan');
    expect(repository.workDetails[id]?.departmentResource, 'People Ops');
    expect(repository.workDetails[id]?.projectName, 'Launch');
  });

  testWidgets(
    'Work detail retry updates the captured reminder without duplicating it',
    (tester) async {
      final repository = DemoRepository()..failContextDetailWrites.add('work');
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repository),
      );
      await tester.pumpAndSettle();
      await addFromAll(tester, 'work', 'Review budget');
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();
      await clearToast(tester);
      await revealTodayReminder(tester, find.text('Review budget'));
      await tester.tap(find.text('Review budget'));
      await tester.pumpAndSettle();
      await revealSheetControl(
        tester,
        find.byKey(const ValueKey('work-details-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('work-details-toggle')));
      await tester.pumpAndSettle();
      await revealSheetControl(
        tester,
        find.byKey(const ValueKey('work-manager')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('work-manager')),
        'Taylor',
      );
      await revealSheetControl(tester, find.text('Save reminder'));
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();

      expect(find.textContaining('follow-up details failed'), findsOneWidget);
      expect(repository.reminderCreateCalls, 1);
      expect(repository.lastCreatedReminderId, isNotNull);
      repository.failContextDetailWrites.clear();
      await revealSheetControl(tester, find.text('Save reminder'));
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();
      expect(repository.reminderCreateCalls, 1);
      expect(repository.reminderUpdateCalls, 2);
      expect(
        repository.workDetails[repository.lastCreatedReminderId]?.managerName,
        'Taylor',
      );
    },
  );

  testWidgets(
    'missing capture ID keeps the draft visible and prevents duplicate retry',
    (tester) async {
      final repository = _NullCreateIdRepository();
      await tester.pumpWidget(
        EzyApp(connected: false, preview: true, repository: repository),
      );
      await tester.pumpAndSettle();
      await addFromAll(tester, 'work', 'Review renewal');
      await revealSheetControl(tester, find.text('Save reminder'));
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('server did not return a reminder ID'),
        findsOneWidget,
      );
      await revealSheetControl(tester, find.text('Save reminder'));
      expect(find.text('Save reminder'), findsOneWidget);
      expect(repository.reminderCreateCalls, 1);

      await revealSheetControl(tester, find.text('Save reminder'));
      await tester.tap(find.text('Save reminder'));
      await tester.pumpAndSettle();
      expect(repository.reminderCreateCalls, 1);
      // Shown inline (the kept error) and as the retry's snackbar.
      expect(find.textContaining('Refresh before retrying'), findsWidgets);
    },
  );

  testWidgets('the destination stays fixed during an in-flight save', (
    tester,
  ) async {
    final repository = _GatedSaveRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await addFromAll(tester, 'work', 'Prepare handoff');
    await revealSheetControl(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pump();

    expect(find.text('Saving…'), findsOneWidget);
    // Chosen in the Add flow, so there is no context control to change.
    expect(find.byKey(const ValueKey('flow-context')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    repository.saveGate.complete();
    await tester.pumpAndSettle();
    final saved = (await repository.load()).last;
    expect(saved.contextId, 'work');
    expect(repository.workDetails[saved.id], isNull);
    expect(repository.sideGigDetails[saved.id], isNull);
  });

  testWidgets('Side Gig panel saves initiative and client fields', (
    tester,
  ) async {
    // A plain Side Gig reminder, as older clients and agents create them.
    final repository = DemoRepository();
    await repository.save(
      title: 'Photograph new products',
      notes: null,
      dueAt: null,
      contextId: 'gig',
      isOrder: false,
      channels: const [],
    );
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await revealTodayReminder(tester, find.text('Photograph new products'));
    await tester.tap(find.text('Photograph new products'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gig-details-toggle')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('gig-details-toggle')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gig-field-initiative')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const ValueKey('gig-field-initiative')),
      'Spring catalog',
    );
    await tester.enterText(
      find.byKey(const ValueKey('gig-field-person')),
      'Avery',
    );
    await tester.scrollUntilVisible(
      find.text('Save'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.reminderCreateCalls, 1);
    final details = repository.sideGigDetails[repository.lastCreatedReminderId];
    expect(details?.initiativeName, 'Spring catalog');
    expect(details?.clientName, 'Avery');
  });

  testWidgets('editing preserves panel details when panel is hidden', (
    tester,
  ) async {
    final repository = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await revealTodayReminder(tester, find.text('Send the revised proposal'));
    await tester.tap(find.text('Send the revised proposal'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('work-details-toggle'));
    await revealSheetControl(tester, toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await revealSheetControl(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(repository.workDetails['fixture-1']?.managerName, 'Jordan Lee');
    expect(repository.workDetails['fixture-1']?.projectName, 'Q4 launch');
  });

  testWidgets('realtime merges untouched panel fields but preserves draft', (
    tester,
  ) async {
    final repository = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await revealTodayReminder(tester, find.text('Send the revised proposal'));
    await tester.tap(find.text('Send the revised proposal'));
    await tester.pumpAndSettle();
    await revealSheetControl(
      tester,
      find.byKey(const ValueKey('work-manager')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('work-manager')),
      'My draft',
    );
    repository.remoteWorkDetailsUpdate(
      'fixture-1',
      const WorkDetails(
        managerName: 'Remote manager',
        departmentResource: 'Remote department',
        projectName: 'Remote project',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('work-manager')))
          .controller!
          .text,
      'My draft',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('work-department-resource')),
          )
          .controller!
          .text,
      'Remote department',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('work-project')))
          .controller!
          .text,
      'Remote project',
    );
  });

  testWidgets('realtime does not reopen an explicitly hidden panel', (
    tester,
  ) async {
    final repository = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await revealTodayReminder(tester, find.text('Send the revised proposal'));
    await tester.tap(find.text('Send the revised proposal'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('work-details-toggle'));
    await revealSheetControl(tester, toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    repository.remoteWorkDetailsUpdate(
      'fixture-1',
      const WorkDetails(
        managerName: 'Remote manager',
        departmentResource: 'Remote department',
        projectName: 'Remote project',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.byKey(const ValueKey('work-manager')), findsNothing);
    expect(repository.workDetails['fixture-1']?.managerName, 'Remote manager');
  });
}

class _NullCreateIdRepository extends DemoRepository {
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
    await super.save(
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
    return null;
  }
}

class _GatedSaveRepository extends DemoRepository {
  final Completer<void> saveGate = Completer<void>();

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
    await saveGate.future;
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
