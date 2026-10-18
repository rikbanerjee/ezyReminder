import 'package:ezyreminder/features/focus/focus_models.dart';
import 'package:ezyreminder/features/focus/focus_repository.dart';
import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DemoFocusRepository _repo({bool planning = true}) => DemoFocusRepository(
  planning: planning,
  loadReminders: () async => [
    const FocusReminder(id: 'fixture-1', title: 'Send the revised proposal', contextSlug: 'work'),
    const FocusReminder(id: 'fixture-2', title: 'Photograph new listing', contextSlug: 'side_gig'),
  ],
  focusTimes: const [
    FocusTimeItem(id: 'ft', label: 'Lunch focus', contextSlug: 'work', weekdays: [1, 2, 3, 4, 5, 6, 7], startTime: '12:30:00', budgetMinutes: 30),
  ],
);

Future<void> _pumpApp(WidgetTester tester, DemoFocusRepository focus) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    EzyApp(
      connected: false,
      preview: true,
      repository: DemoRepository(),
      focusRepository: focus,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openReminder(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reminder sheet offers Focus on this and Work on this with the plan state', (tester) async {
    final focus = _repo();
    await _pumpApp(tester, focus);
    expect(find.text("TODAY'S FOCUS"), findsOneWidget);
    expect(find.text('What would you like to move forward?'), findsOneWidget);
    await _openReminder(tester, 'Send the revised proposal');
    await tester.ensureVisible(find.byKey(const ValueKey('work-on-this')));
    expect(find.text('FOCUS'), findsOneWidget);
    expect(find.text('Focus on this'), findsOneWidget);
    expect(find.text('Work on this'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-note')), findsOneWidget);
    expect(find.text('Not planned yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('work-on-this')));
    await tester.pumpAndSettle();
    // The planning sheet opens for this reminder, without having saved the reminder.
    expect(find.text('Work on this'), findsOneWidget);
    expect(find.text('Send the revised proposal'), findsWidgets);
    final option = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('plan-opt-'),
    );
    await tester.tap(option.first);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('plan-save'));
    final anyway = find.byKey(const ValueKey('plan-anyway'));
    await tester.ensureVisible(save.evaluate().isNotEmpty ? save : anyway);
    await tester.tap(save.evaluate().isNotEmpty ? save : anyway);
    await tester.pumpAndSettle();
    expect(focus.assignments.values.where((a) => a.planned), hasLength(1));
    expect(find.text("TODAY'S FOCUS"), findsOneWidget);
    expect(find.textContaining('Up next'), findsOneWidget, reason: 'planned work becomes the Up next card');
    // Reopening shows the plan and offers to move it.
    await _openReminder(tester, 'Send the revised proposal');
    await tester.ensureVisible(find.byKey(const ValueKey('plan-note')));
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-note'))).data, startsWith('Planned: '));
    expect(tester.widget<Text>(find.byKey(const ValueKey('plan-note'))).data, endsWith('· 15 min'));
  });

  testWidgets('without the planning migrations the sheet keeps only Focus on this', (tester) async {
    await _pumpApp(tester, _repo(planning: false));
    await _openReminder(tester, 'Send the revised proposal');
    await tester.ensureVisible(find.text('Focus on this'));
    expect(find.text('Focus on this'), findsOneWidget);
    expect(find.text('Work on this'), findsNothing);
    expect(find.byKey(const ValueKey('plan-note')), findsNothing);
    expect(find.text('Set my focus times'), findsNothing);
  });

  testWidgets('Today card is not filtered by the context pills', (tester) async {
    await _pumpApp(tester, _repo());
    await tester.drag(find.text('Work').first, const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Social').first);
    await tester.pumpAndSettle();
    expect(find.text("TODAY'S FOCUS"), findsOneWidget);
    expect(find.text('Choose a reminder'), findsOneWidget);
  });
}
