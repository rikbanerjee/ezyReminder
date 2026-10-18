import 'dart:async';

import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> chooseContext(WidgetTester tester, String label) async {
  final option = switch (label) {
    'Work' => 'work',
    'Side Gig' => 'gig',
    _ => throw ArgumentError.value(label),
  };
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await revealSheetControl(tester, dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  final item = find.byKey(ValueKey('context-option-$option'));
  expect(item, findsOneWidget);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> revealSheetControl(WidgetTester tester, Finder target) async {
  final sheet = find.byType(DraggableScrollableSheet).last;
  final scrollable = find
      .descendant(of: sheet, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
}

Future<void> revealTodayReminder(WidgetTester tester, Finder reminder) async {
  final scrollable = find.descendant(of: find.byType(CustomScrollView).first, matching: find.byType(Scrollable)).first;
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
    await tester.tap(find.text('Remind me to…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Prepare launch brief',
    );
    await chooseContext(tester, 'Work');
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

  testWidgets('partial Work panel failure retains created ID for retry', (
    tester,
  ) async {
    final repository = DemoRepository()..failContextDetailWrites.add('work');
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me to…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Review budget');
    await chooseContext(tester, 'Work');
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
    expect(repository.reminderUpdateCalls, 1);
    expect(
      repository.workDetails[repository.lastCreatedReminderId]?.managerName,
      'Taylor',
    );
  });

  testWidgets('missing create ID keeps panel data visible and prevents retry', (
    tester,
  ) async {
    final repository = _NullCreateIdRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me to…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Review renewal');
    await chooseContext(tester, 'Work');
    await revealSheetControl(
      tester,
      find.byKey(const ValueKey('work-details-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('work-details-toggle')));
    await tester.pumpAndSettle();
    await revealSheetControl(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('server did not return a reminder ID'),
      findsOneWidget,
    );
    expect(find.text('Save reminder'), findsOneWidget);
    expect(repository.reminderCreateCalls, 1);

    await revealSheetControl(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(repository.reminderCreateCalls, 1);
    expect(find.textContaining('Refresh before retrying'), findsOneWidget);
  });

  testWidgets('context controls cannot change during an in-flight save', (
    tester,
  ) async {
    final repository = _GatedSaveRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me to…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Prepare handoff');
    await chooseContext(tester, 'Work');
    await revealSheetControl(
      tester,
      find.byKey(const ValueKey('work-details-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('work-details-toggle')));
    await tester.pumpAndSettle();
    await revealSheetControl(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pump();

    expect(find.text('Saving…'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AbsorbPointer && widget.absorbing,
      ),
      findsOneWidget,
    );

    repository.saveGate.complete();
    await tester.pumpAndSettle();
    final saved = (await repository.load()).last;
    expect(saved.contextId, 'work');
    expect(repository.workDetails[saved.id], isNotNull);
    expect(repository.sideGigDetails[saved.id], isNull);
  });

  testWidgets('Side Gig panel saves initiative and client fields', (
    tester,
  ) async {
    final repository = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me to…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Photograph new products',
    );
    await chooseContext(tester, 'Side Gig');
    await revealSheetControl(
      tester,
      find.byKey(const ValueKey('sidegig-details-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('sidegig-details-toggle')));
    await tester.pumpAndSettle();
    await revealSheetControl(
      tester,
      find.byKey(const ValueKey('sidegig-initiative')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('sidegig-initiative')),
      'Spring catalog',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sidegig-client')),
      'Avery',
    );
    await revealSheetControl(tester, find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
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
