import 'package:ezyreminder/features/focus/focus_controller.dart';
import 'package:ezyreminder/features/focus/focus_models.dart';
import 'package:ezyreminder/features/focus/focus_repository.dart';
import 'package:ezyreminder/features/focus/focus_widgets.dart';
import 'package:ezyreminder/features/settings/settings_page.dart';
import 'package:ezyreminder/features/settings/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Prototype clock: Fri Oct 23, 2026 1:10 PM in the account timezone.
final _now = DateTime.utc(2026, 10, 23, 17, 10);
const _tz = 'America/New_York';

final _reminders = <FocusReminder>[
  FocusReminder(
    id: 'r3',
    title: 'Send Q3 capacity plan to Priya',
    contextSlug: 'work',
    dueAt: DateTime.utc(2026, 10, 23, 20), // 4 PM
  ),
  const FocusReminder(id: 'r10', title: 'Write listing description', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r13', title: 'Draft onboarding doc', contextSlug: 'work'),
  const FocusReminder(id: 'r9', title: 'Choose photos for mug listing', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r11', title: 'Update shipping rates', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r12', title: 'Reply to buyer questions', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r5', title: 'Restock kraft mailers', contextSlug: 'sidegig'),
  const FocusReminder(
    id: 'r8',
    title: 'Pack the Hendricks order',
    contextSlug: 'sidegig',
    isOrder: true,
    shipBy: '2026-10-23',
  ),
  FocusReminder(
    id: 'r6',
    title: 'Submit monthly timesheet',
    contextSlug: 'work',
    dueAt: DateTime.utc(2026, 10, 27, 14), // Tue 10 AM
  ),
];

const _times = [
  FocusTimeItem(id: 'ft1', label: 'Shop time', contextSlug: 'sidegig', weekdays: [4], startTime: '19:00:00', budgetMinutes: 30),
  FocusTimeItem(id: 'ft2', label: 'Saturday mornings', contextSlug: 'sidegig', weekdays: [6], startTime: '09:00:00', budgetMinutes: 60),
  FocusTimeItem(id: 'ft3', label: 'Lunch focus', contextSlug: 'work', weekdays: [1, 2, 3, 4, 5], startTime: '12:30:00', budgetMinutes: 30),
];

FocusAssignment _a(String id, String rid, String title, String slug, String? ft, String date, String time, int min, int pos) =>
    FocusAssignment(
      id: id,
      reminderId: rid,
      title: title,
      contextSlug: slug,
      focusTimeId: ft,
      localDate: date,
      startTime: time,
      plannedMinutes: min,
      position: pos,
    );

List<FocusAssignment> _planned() => [
  _a('a1', 'r10', 'Write listing description', 'sidegig', 'ft2', '2026-10-24', '09:00:00', 20, 0),
  _a('a2', 'r13', 'Draft onboarding doc', 'work', 'ft3', '2026-10-27', '12:30:00', 15, 0),
  _a('a3', 'r9', 'Choose photos for mug listing', 'sidegig', 'ft1', '2026-10-29', '19:00:00', 15, 0),
  _a('a4', 'r11', 'Update shipping rates', 'sidegig', 'ft1', '2026-10-29', '19:00:00', 10, 1),
  _a('a5', 'r12', 'Reply to buyer questions', 'sidegig', 'ft1', '2026-10-29', '19:00:00', 10, 2),
];

List<FocusAssignment> _missed() => [
  _a('m1', 'r5', 'Restock kraft mailers', 'sidegig', 'ft2', '2026-10-17', '09:00:00', 20, 0),
  _a('m2', 'r8', 'Pack the Hendricks order', 'sidegig', 'ft1', '2026-10-22', '19:00:00', 10, 0),
];

DateTime _clockValue = _now;
DemoFocusRepository _repo({
  bool times = true,
  bool planned = true,
  bool missed = false,
  bool planning = true,
  bool intents = true,
  int preferred = 25,
}) => DemoFocusRepository(
  loadReminders: () async => _reminders,
  clock: () => _clockValue,
  timezone: _tz,
  planning: planning,
  intents: intents,
  preferredMinutes: preferred,
  focusTimes: times ? _times : const [],
  assignments: [if (planned) ..._planned(), if (missed) ..._missed()],
  nextSteps: const {'r10': 'Start with the title and first line.', 'r3': 'Add the Q4 headcount table.'},
);

Future<FocusController> _controller(DemoFocusRepository repo) async {
  _clockValue = _now;
  final c = FocusController(repo, clock: () => _clockValue, tick: false);
  await c.reload();
  return c;
}

class _Host extends StatelessWidget {
  const _Host(this.controller, {this.actions = const {}});
  final FocusController controller;
  final Map<String, void Function(BuildContext)> actions;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        FocusCard(controller: controller),
        for (final e in actions.entries)
          TextButton(onPressed: () => e.value(context), child: Text(e.key)),
      ],
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  FocusController c, {
  bool dark = false,
  double scale = 1,
  Map<String, void Function(BuildContext)> actions = const {},
}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: _Host(c, actions: actions)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester, FocusController c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  group('model', () {
    test('planned work groups into derived occurrences with budgets and missed state', () async {
      final repo = _repo(missed: true);
      final state = await repo.load();
      final occ = state.occurrences(_now);
      expect(occ.map((o) => o.name).toList(), [
        'Saturday · 9 AM', // missed 10-17
        'Thursday · 7 PM', // missed 10-22
        'Saturday · 9 AM', // 10-24
        'Tuesday · 12:30 PM',
        'Thursday · 7 PM', // 10-29
      ]);
      expect(occ.map((o) => o.missed).toList(), [true, true, false, false, false]);
      final thursday = occ.last;
      expect(thursday.tasks.map((a) => a.id), ['a3', 'a4', 'a5'], reason: 'ordered by position');
      expect(thursday.sum, 35);
      expect(thursday.budget, 30);
      expect(thursday.overBudget, isTrue);
      repo.dispose();
    });

    test('a one-off uses its planned minutes as the window and groups by slot', () async {
      final repo = DemoFocusRepository(
        loadReminders: () async => _reminders,
        clock: () => _now,
        timezone: _tz,
        assignments: [
          _a('o1', 'r10', 'Write listing description', 'sidegig', null, '2026-10-23', '12:00:00', 30, 0),
          _a('o2', 'r9', 'Choose photos for mug listing', 'sidegig', null, '2026-10-23', '12:00:00', 20, 1),
        ],
      );
      final occ = (await repo.load()).occurrences(_now);
      expect(occ, hasLength(1));
      expect(occ.single.time, isNull);
      expect(occ.single.sum, 50);
      expect(occ.single.overBudget, isFalse);
      // 12:00 EDT + 50 min = 12:50 EDT, before 1:10 PM: missed.
      expect(occ.single.missed, isTrue);
      repo.dispose();
    });

    test('plan options are the next four enabled slots in the context, soonest first', () async {
      final state = await _repo().load();
      final options = state.planOptions('work', _now);
      expect(options.map((o) => o.name).toList(), [
        'Monday · 12:30 PM', // Friday's lunch window already ended at 1:00 PM
        'Tuesday · 12:30 PM',
        'Wednesday · 12:30 PM',
        'Thursday · 12:30 PM',
      ]);
      expect(options.first.secondary, 'Mon, Oct 26 · Lunch focus');
    });

    test('deadline label, day-only due and after-deadline checks use the account timezone', () {
      final due = FocusDeadline(dueAt: DateTime.utc(2026, 10, 23, 20));
      expect(due.label(_tz), 'Due Fri, Oct 23 · 4 PM');
      expect(FocusDeadline(dueAt: DateTime.utc(2026, 10, 24, 3, 59)).label(_tz), 'Due Fri, Oct 23');
      const ship = FocusDeadline(shipBy: '2026-10-23', isOrder: true);
      expect(ship.label(_tz), 'Ship by Fri, Oct 23');
      // 11:30 PM EDT on the ship-by day is not after it; 12:30 AM the next day is.
      expect(ship.isBefore(DateTime.utc(2026, 10, 24, 3, 30), _tz), isFalse);
      expect(ship.isBefore(DateTime.utc(2026, 10, 24, 4, 30), _tz), isTrue);
      expect(due.isBefore(DateTime.utc(2026, 10, 23, 20, 1), _tz), isTrue);
      expect(due.isBefore(DateTime.utc(2026, 10, 23, 19, 59), _tz), isFalse);
    });
  });

  group('fallback when 0015/0016 are not applied', () {
    test('missing v2 RPC falls back to get_focus_state without throwing', () async {
      final called = <String>[];
      final gate = FocusDashboardGate(clock: () => _now);
      Future<Object?> rpc(String fn) async {
        called.add(fn);
        if (fn == 'get_focus_dashboard_v2') {
          throw const PostgrestException(message: 'Could not find the function', code: 'PGRST202');
        }
        return {'server_now': '2026-10-23T17:10:00Z', 'local_date': '2026-10-23', 'timezone': _tz};
      }

      final state = await loadFocusDashboard(rpc, gate);
      expect(called, ['get_focus_dashboard_v2', 'get_focus_state']);
      expect(state.planning, isFalse);
      expect(state.preferences, isFalse);
      expect(state.preferredMinutes, 25);
      expect(state.focusTimes, isEmpty);
      // Not probed again within a minute.
      called.clear();
      await loadFocusDashboard(rpc, gate);
      expect(called, ['get_focus_state']);
    });

    test('Postgres 42883 also falls back, other errors do not', () async {
      final gate = FocusDashboardGate(clock: () => _now);
      final ok = {'server_now': '2026-10-23T17:10:00Z', 'local_date': '2026-10-23'};
      var calls = 0;
      final state = await loadFocusDashboard((fn) async {
        calls++;
        if (fn == 'get_focus_dashboard_v2') {
          throw const PostgrestException(message: 'function does not exist', code: '42883');
        }
        return ok;
      }, gate);
      expect(state.planning, isFalse);
      expect(calls, 2);
      await expectLater(
        loadFocusDashboard(
          (fn) async => throw const PostgrestException(message: 'boom', code: '500'),
          FocusDashboardGate(clock: () => _now),
        ),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('v2 payload with planning keys parses times, assignments and preference', () async {
      final state = await loadFocusDashboard(
        (fn) async => {
          'server_now': '2026-10-23T17:10:00Z',
          'local_date': '2026-10-23',
          'timezone': _tz,
          'preferred_minutes': 40,
          'highlight_next_step': 'Write the intro',
          'session_next_step': null,
          'focus_times': [
            {'id': 'ft1', 'label': null, 'context_slug': 'work', 'weekdays': [1, 3], 'start_time': '12:30:00', 'budget_minutes': 30, 'enabled': true, 'updated_at': '2026-10-01T00:00:00Z'},
          ],
          'assignments': [
            {'id': 'a1', 'reminder_id': 'r1', 'reminder_title': 'T', 'context_slug': 'work', 'focus_time_id': 'ft1', 'focus_time_label': null, 'local_date': '2026-10-26', 'start_time': '12:30:00', 'planned_minutes': 15, 'position': 3, 'state': 'planned', 'moved_to': null, 'updated_at': '2026-10-01T00:00:00Z', 'due_at': null, 'ship_by': '2026-10-30'},
          ],
        },
        FocusDashboardGate(clock: () => _now),
      );
      expect(state.planning && state.preferences, isTrue);
      expect(state.intents, isFalse, reason: 'no focus_api: 0016 without 0017');
      expect(state.preferredMinutes, 40);
      expect(state.highlightNextStep, 'Write the intro');
      expect(state.focusTimes.single.title, 'Mon, Wed');
      expect(state.assignments.single.shipBy, '2026-10-30');
    });

    testWidgets('card shows MVP behaviour: 25 min default, no planning UI, no error', (tester) async {
      final repo = _repo(planning: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(find.text('Start 25 min'), findsOneWidget);
      expect(find.text('Your focus times'), findsNothing);
      expect(find.text('YOUR FOCUS TIMES'), findsNothing);
      expect(find.text("Didn't get to this?"), findsNothing);
      expect(c.error, isNull);
      // Duration chip opens setup, which does not claim a saved preference.
      await _tap(tester, _key('focus-card-duration'));
      await tester.tap(find.text('10 min'));
      await tester.pump();
      expect(find.textContaining('saves it as your usual length'), findsNothing);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('empty card without planning hides Set my focus times', (tester) async {
      final repo = _repo(planning: false, planned: false);
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(find.text('What would you like to move forward?'), findsOneWidget);
      expect(find.text('Choose a reminder'), findsOneWidget);
      expect(find.text('Set my focus times'), findsNothing);
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('Today card priority', () {
    testWidgets('empty: choose a reminder or set focus times', (tester) async {
      final repo = _repo(times: false, planned: false);
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(c.cardKind, FocusCardKind.empty);
      expect(find.text('What would you like to move forward?'), findsOneWidget);
      expect(find.text('Choose one Work or Side Gig reminder.'), findsOneWidget);
      expect(find.text('Choose a reminder'), findsOneWidget);
      expect(find.text('Set my focus times'), findsOneWidget);
      // The empty card already offers Set my focus times; no duplicate section.
      expect(find.text('YOUR FOCUS TIMES'), findsNothing);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('planned work becomes "Up next" and never pins itself', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(c.cardKind, FocusCardKind.upNext);
      expect(find.text('Up next · Saturday · 9 AM'), findsOneWidget);
      expect(find.text('Write listing description'), findsWidgets);
      expect(find.text('Side Gig · 20 min planned · Sat, Oct 24'), findsOneWidget);
      expect(find.text('Next step from last time'), findsOneWidget);
      expect(find.text('Start with the title and first line.'), findsOneWidget);
      expect(find.text('Start 20 min'), findsOneWidget);
      expect(find.text("Make today's focus"), findsOneWidget);
      expect(repo.highlights, isEmpty);
      await _tap(tester, _key('focus-make-today'));
      expect(c.cardKind, FocusCardKind.highlight);
      expect(repo.highlights.values.single.reminderId, 'r10');
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('highlight beats up next; running beats highlight; time up asks to review', (tester) async {
      final repo = _repo(preferred: 40);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(c.cardKind, FocusCardKind.highlight);
      expect(find.text('Send Q3 capacity plan to Priya'), findsOneWidget);
      expect(find.text('Due Fri, Oct 23 · 4 PM'), findsOneWidget);
      expect(find.text('Add the Q4 headcount table.'), findsOneWidget);
      expect(find.text('Start 40 min'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Up next · Saturday · 9 AM'), findsNothing);
      await repo.start('s', _reminders.first, 25, null);
      await c.reload();
      await tester.pumpAndSettle();
      expect(c.cardKind, FocusCardKind.running);
      expect(find.text('Work · In focus'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Open session'), findsOneWidget);
      await repo.pause(c.session!);
      await c.reload();
      await tester.pumpAndSettle();
      expect(find.text('Work · Paused'), findsOneWidget);
      await repo.resume(c.session!);
      _clockValue = _now.add(const Duration(minutes: 26));
      await c.reload();
      expect(c.cardKind, FocusCardKind.timeUp);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('time up card is calm and offers Review session', (tester) async {
      final repo = _repo(planned: false, times: false);
      final c = await _controller(repo);
      await repo.start('s', _reminders.first, 1, null);
      _clockValue = _now.add(const Duration(minutes: 2));
      await c.reload();
      await _pump(tester, c);
      expect(find.text('Work · Time is up'), findsOneWidget);
      expect(find.text('How did it go?'), findsOneWidget);
      expect(find.text('Review session'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('Your focus times', () {
    testWidgets('lists the next three populated occurrences with plan summaries', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(find.text('YOUR FOCUS TIMES'), findsOneWidget);
      expect(find.text('Manage ›'), findsOneWidget);
      expect(find.text('Saturday · 9 AM'), findsOneWidget);
      expect(find.text('Tuesday · 12:30 PM'), findsOneWidget);
      expect(find.text('Thursday · 7 PM'), findsOneWidget);
      expect(find.text('Choose photos for mug listing · 15 min'), findsOneWidget);
      expect(find.text('3 tasks · 35 min planned'), findsOneWidget);
      expect(find.text('35 min planned for 30 min available'), findsOneWidget);
      expect(find.text('Oct 29 ›'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('times with nothing planned, and none set, collapse to one row', (tester) async {
      final repo = _repo(planned: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(find.text('Nothing planned yet'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();

      final none = _repo(times: false, planned: false);
      await none.highlight('r3');
      final c2 = await _controller(none);
      await _pump(tester, c2);
      expect(find.text('Set my focus times'), findsOneWidget);
      expect(find.text('Manage ›'), findsNothing);
      await _teardown(tester, c2);
      none.dispose();
    });

    testWidgets('occurrence sheet: ordered tasks, Start per task, Skip leaves the reminder', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, find.text('Thursday · 7 PM'));
      expect(find.text('Side Gig · Thu, Oct 29 · Shop time'), findsOneWidget);
      expect(find.text('3 tasks · 35 min planned'), findsWidgets);
      expect(find.text('Start 15 min'), findsOneWidget);
      expect(find.text('Start 10 min'), findsNWidgets(2));
      expect(find.text('Skip leaves the reminder as it is. Nothing starts on its own.'), findsOneWidget);
      await tester.tap(_key('occ-skip-a4'));
      await tester.pumpAndSettle();
      expect(repo.assignments['a4']!.state, 'skipped');
      expect(c.reminderById('r11'), isNotNull, reason: 'skip never touches the reminder');
      expect(find.text('Update shipping rates'), findsNothing);
      await tester.tap(_key('occ-start-a3'));
      await tester.pumpAndSettle();
      expect(repo.sessions.values.single.durationMinutes, 15);
      expect(repo.assignments['a3']!.state, 'in_progress');
      expect(find.text('One thing at a time.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('start is disabled with an explanation while a session runs', (tester) async {
      final repo = _repo();
      await repo.start('s', _reminders.first, 25, null);
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, find.text('Thursday · 7 PM'));
      expect(find.text('A session is already in progress. '), findsOneWidget);
      final start = tester.widget<TextButton>(find.descendant(of: _key('occ-start-a3'), matching: find.byType(TextButton)).first);
      expect(start.onPressed, isNull);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('Missed recovery card', () {
    testWidgets('shows the oldest first with +N more; acting reveals the next', (tester) async {
      final repo = _repo(missed: true);
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(find.text("Didn't get to this?"), findsOneWidget);
      expect(find.text('+1 more'), findsOneWidget);
      expect(find.text('Restock kraft mailers'), findsOneWidget);
      expect(find.text('Saturday · 9 AM · Sat, Oct 17 · 20 min planned'), findsOneWidget);
      expect(find.text('Next Saturday'), findsOneWidget);
      expect(find.text('Start now'), findsOneWidget);
      expect(find.text('Choose another time'), findsOneWidget);
      expect(find.text('Leave unscheduled'), findsOneWidget);
      await _tap(tester, _key('missed-leave'));
      expect(repo.assignments['m1']!.state, 'skipped');
      expect(find.text('Pack the Hendricks order'), findsOneWidget);
      expect(find.text('+1 more'), findsNothing);
      expect(find.text('Next Thursday'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Next Saturday moves the plan one week later in the same focus time', (tester) async {
      final repo = _repo(missed: true);
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('missed-next'));
      expect(repo.assignments['m1']!.state, 'moved');
      final replacement = repo.assignments.values.firstWhere(
        (a) => a.reminderId == 'r5' && a.planned,
      );
      expect(replacement.localDate, '2026-10-24');
      expect(replacement.focusTimeId, 'ft2');
      expect(replacement.plannedMinutes, 20);
      expect(repo.assignments.values.where((a) => a.reminderId == 'r5' && a.planned), hasLength(1));
      expect(find.text('Planned for Saturday · 9 AM (Sat, Oct 24)'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Next weekday keeps the slot as a one-off if the focus time no longer runs that day', (tester) async {
      final repo = DemoFocusRepository(
        loadReminders: () async => _reminders,
        clock: () => _now,
        timezone: _tz,
        focusTimes: const [
          FocusTimeItem(id: 'ft2', contextSlug: 'sidegig', weekdays: [1], startTime: '09:00:00', budgetMinutes: 60),
        ],
        assignments: [_a('m1', 'r5', 'Restock kraft mailers', 'sidegig', 'ft2', '2026-10-17', '09:00:00', 20, 0)],
      );
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('missed-next'));
      final replacement = repo.assignments.values.firstWhere((a) => a.planned);
      expect(replacement.focusTimeId, isNull);
      expect(replacement.localDate, '2026-10-24');
      expect(replacement.startTime, '09:00:00');
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Start now starts the planned work with its minutes and opens the session', (tester) async {
      final repo = _repo(missed: true);
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('missed-start'));
      expect(repo.sessions.values.single.durationMinutes, 20);
      expect(repo.assignments['m1']!.state, 'in_progress');
      expect(find.text('One thing at a time.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Choose another time opens Work on this for that reminder', (tester) async {
      final repo = _repo(missed: true);
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('missed-other'));
      expect(find.text('Work on this'), findsOneWidget);
      expect(find.text('Restock kraft mailers'), findsWidgets);
      expect(find.text('Currently planned'), findsOneWidget, reason: 'the missed plan is still the outstanding one; choosing moves it');
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('Work on this', () {
    Map<String, void Function(BuildContext)> actions(FocusController c, String id) => {
      'plan $id': (context) => openWorkOnThis(context, c, c.reminderById(id)!),
    };

    testWidgets('moves an existing plan atomically and says so', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c, actions: actions(c, 'r13'));
      await _tap(tester, find.text('plan r13'));
      expect(find.text('Currently planned'), findsOneWidget);
      expect(find.text('Tuesday · 12:30 PM · 15 min. Choosing another time moves it.'), findsOneWidget);
      expect(find.text('Monday · 12:30 PM'), findsOneWidget);
      expect(find.text('Mon, Oct 26 · Lunch focus'), findsOneWidget);
      expect(find.text('Pick another day'), findsOneWidget);
      expect(find.text('Keep unscheduled'), findsOneWidget);
      await _tap(tester, find.text('Wednesday · 12:30 PM'));
      expect(find.text('Planned minutes'), findsOneWidget);
      expect(find.text('1 task · 15 min planned'), findsOneWidget);
      await _tap(tester, _key('plan-min-25'));
      await _tap(tester, _key('plan-save'));
      expect(repo.assignments['a2']!.state, 'moved');
      final now = repo.assignments.values.where((a) => a.reminderId == 'r13' && a.planned).single;
      expect(now.localDate, '2026-10-28');
      expect(now.plannedMinutes, 25);
      expect(now.focusTimeId, 'ft3');
      expect(find.text('Planned for Wednesday · 12:30 PM (moved)'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('warns when the slot is after the due time; deadline never changes', (tester) async {
      final repo = _repo(planned: false);
      final c = await _controller(repo);
      await _pump(tester, c, actions: actions(c, 'r6'));
      await _tap(tester, find.text('plan r6'));
      expect(find.text('Due Tue, Oct 27 · 10 AM'), findsOneWidget);
      await _tap(tester, find.text('Tuesday · 12:30 PM'));
      expect(find.text('This is after the due time'), findsOneWidget);
      expect(find.text('Due Tue, Oct 27 · 10 AM. Your deadline stays the same.'), findsOneWidget);
      expect(find.text('Choose an earlier time'), findsOneWidget);
      expect(find.text('Plan it anyway'), findsOneWidget);
      expect(find.text('Save plan'), findsNothing, reason: 'the warning replaces Save plan');
      // Choose an earlier time clears the choice.
      await _tap(tester, _key('plan-earlier'));
      expect(find.text('This is after the due time'), findsNothing);
      expect(find.text('Save plan'), findsOneWidget);
      await _tap(tester, find.text('Monday · 12:30 PM'));
      expect(find.text('This is after the due time'), findsNothing);
      // Back to the late slot and plan anyway.
      await _tap(tester, find.text('Tuesday · 12:30 PM'));
      await _tap(tester, _key('plan-anyway'));
      final planned = repo.assignments.values.where((a) => a.reminderId == 'r6' && a.planned).single;
      expect(planned.localDate, '2026-10-27');
      expect(planned.plannedMinutes, 15, reason: '15 is the default');
      expect(c.reminderById('r6')!.dueAt, DateTime.utc(2026, 10, 27, 14), reason: 'deadline untouched');
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('ship-by deadlines warn on the next calendar day, not that evening', (tester) async {
      final repo = DemoFocusRepository(
        loadReminders: () async => _reminders,
        clock: () => _now,
        timezone: _tz,
        // Shop time Thursday 7 PM on Oct 29 is after the 10-23 ship-by date.
        focusTimes: _times,
      );
      final c = await _controller(repo);
      await _pump(tester, c, actions: actions(c, 'r8'));
      await _tap(tester, find.text('plan r8'));
      expect(find.text('Ship by Fri, Oct 23'), findsOneWidget);
      await _tap(tester, find.text('Thursday · 7 PM').first);
      expect(find.text('This is after the ship-by time'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('keep unscheduled skips the current plan; no focus time offers setup', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c, actions: actions(c, 'r13'));
      await _tap(tester, find.text('plan r13'));
      await _tap(tester, _key('plan-none'));
      await _tap(tester, _key('plan-save'));
      expect(repo.assignments['a2']!.state, 'skipped');
      await _teardown(tester, c);
      repo.dispose();

      final empty = _repo(times: false, planned: false);
      final c2 = await _controller(empty);
      await _pump(tester, c2, actions: actions(c2, 'r6'));
      await _tap(tester, find.text('plan r6'));
      expect(find.textContaining("You haven't set up a Work focus time yet."), findsOneWidget);
      await _tap(tester, _key('plan-set-times'));
      expect(find.text('Your focus times'), findsOneWidget);
      await _teardown(tester, c2);
      empty.dispose();
    });

    testWidgets('validation: nothing chosen shows a visible message, never a disabled button', (tester) async {
      final repo = _repo(planned: false);
      final c = await _controller(repo);
      await _pump(tester, c, actions: actions(c, 'r6'));
      await _tap(tester, find.text('plan r6'));
      await _tap(tester, _key('plan-save'));
      expect(find.text("Choose when you'd like to work on this."), findsOneWidget);
      await _tap(tester, _key('plan-other'));
      await _tap(tester, _key('plan-picker-ok'));
      expect(find.text('Choose a day first.'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Pick another day plans a one-off with date and time', (tester) async {
      final repo = _repo(planned: false);
      final c = await _controller(repo);
      await _pump(tester, c, actions: actions(c, 'r13'));
      await _tap(tester, find.text('plan r13'));
      await _tap(tester, _key('plan-other'));
      // Past days are disabled; tomorrow is selectable.
      expect(tester.widget<InkWell>(_key('plan-day-2026-10-22')).onTap, isNull);
      await _tap(tester, _key('plan-day-2026-10-31'));
      await _tap(tester, _key('plan-picker-ok'));
      expect(find.text('Sat, Oct 31 · 6:30 PM'), findsOneWidget);
      await _tap(tester, _key('plan-save'));
      final one = repo.assignments.values.single;
      expect(one.focusTimeId, isNull);
      expect(one.localDate, '2026-10-31');
      expect(one.startTime, '18:30:00');
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('a failed save keeps the draft and retries with the same operation id', (tester) async {
      final repo = _repo(planned: false);
      final c = await _controller(repo);
      await _pump(tester, c, actions: actions(c, 'r6'));
      await _tap(tester, find.text('plan r6'));
      await _tap(tester, find.text('Monday · 12:30 PM'));
      repo.failWrites = true;
      await _tap(tester, _key('plan-save'));
      expect(find.text('Connection lost'), findsNothing); // mapped to a friendly message
      expect(find.textContaining('Could not confirm the change'), findsWidgets);
      expect(find.text('Save plan'), findsOneWidget, reason: 'draft and sheet are still here');
      repo.failWrites = false;
      await _tap(tester, _key('plan-save'));
      final attempts = repo.calls.where((x) => x.startsWith('assign:')).toList();
      expect(attempts, hasLength(2));
      expect(attempts.first, attempts.last, reason: 'same intent keeps its idempotency id');
      expect(repo.assignments.values.where((a) => a.planned), hasLength(1));
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('one-tap start', () {
    testWidgets('uses the assignment minutes on Up next and the saved preference on a highlight', (tester) async {
      final repo = _repo(preferred: 40);
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('focus-card-start'));
      expect(repo.sessions.values.single.durationMinutes, 20);
      expect(repo.assignments['a1']!.state, 'in_progress');
      expect(find.text('One thing at a time.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();

      final repo2 = _repo(preferred: 40, planned: false);
      await repo2.highlight('r3');
      final c2 = await _controller(repo2);
      await _pump(tester, c2);
      expect(find.text('Start 40 min'), findsOneWidget);
      await _tap(tester, _key('focus-card-start'));
      expect(repo2.sessions.values.single.durationMinutes, 40);
      expect(repo2.sessions.values.single.intendedOutcome, isNull);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c2);
      repo2.dispose();
    });

    testWidgets('the length chip opens setup; starting with another length saves it as the usual one', (tester) async {
      final repo = _repo(preferred: 25, planned: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(tester.getSize(_key('focus-card-duration')).height, greaterThanOrEqualTo(44));
      await _tap(tester, _key('focus-card-duration'));
      expect(find.text('Focus on this'), findsOneWidget);
      expect(find.text('Next step from last time'), findsNWidgets(2), reason: 'card + setup sheet');
      expect(find.textContaining('What could you finish in 10–15 minutes?'), findsOneWidget);
      expect(find.textContaining('saves it as your usual length'), findsNothing);
      await _tap(tester, _key('focus-setup-10'));
      expect(find.text('Starting with 10 min saves it as your usual length.'), findsOneWidget);
      await _tap(tester, _key('focus-setup-start'));
      expect(repo.sessions.values.single.durationMinutes, 10);
      expect(repo.preferredMinutes, 10);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      expect(find.text('Start 10 min'), findsNothing, reason: 'session is running, card shows it');
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('planned setup asks what you could finish and saves it on the session', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('focus-card-duration'));
      expect(find.text('Focus on this'), findsOneWidget);
      await tester.enterText(_key('focus-intent'), '  Draft the first paragraph  ');
      await _tap(tester, _key('focus-setup-start'));
      final session = repo.sessions.values.single;
      expect(session.intendedOutcome, 'Draft the first paragraph');
      expect(repo.assignments['a1']!.state, 'in_progress');
      expect(find.text('Draft the first paragraph'), findsOneWidget, reason: 'session sheet shows Your focus');
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('without 0017 planned setup hides the outcome field', (tester) async {
      final repo = _repo(intents: false);
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('focus-card-duration'));
      expect(find.text('Focus on this'), findsOneWidget);
      expect(_key('focus-intent'), findsNothing);
      await _tap(tester, _key('focus-setup-start'));
      expect(repo.sessions.values.single.intendedOutcome, isNull);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('a failed start keeps the same session id for the retry', (tester) async {
      final repo = _repo(planned: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c);
      repo.failWrites = true;
      await tester.tap(_key('focus-card-start'));
      await tester.pumpAndSettle();
      expect(repo.sessions, isEmpty);
      repo.failWrites = false;
      await tester.tap(_key('focus-card-start'));
      await tester.pumpAndSettle();
      final ids = repo.calls.where((x) => x.startsWith('start:')).toSet();
      expect(ids, hasLength(1), reason: 'both attempts used one id');
      expect(repo.sessions, hasLength(1));
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('review follow-ups', () {
    Future<void> runToReview(WidgetTester tester, FocusController c, DemoFocusRepository repo, String outcome, String next) async {
      await _tap(tester, _key('focus-card-start'));
      await _tap(tester, _key('focus-end'));
      expect(find.text('How did it go?'), findsWidgets);
      expect(find.text('Where will you start next time?'), findsOneWidget);
      expect(find.text('Optional. It appears on your card when you come back.'), findsOneWidget);
      expect(find.text('This saves your session. Your reminder stays as it is.'), findsOneWidget);
      await _tap(tester, _key('focus-outcome-$outcome'));
      if (next.isNotEmpty) await tester.enterText(_key('focus-next-step'), next);
      await _tap(tester, _key('focus-save-session'));
    }

    testWidgets('Finished: continue, choose another focus time, done, and a separate Mark reminder done', (tester) async {
      final repo = _repo(planned: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      final marked = <String>[];
      c.onMarkDone = (id) async => marked.add(id);
      await _pump(tester, c);
      await runToReview(tester, c, repo, 'finished', 'Send the draft to Priya');
      expect(find.text('Session saved'), findsOneWidget);
      expect(find.text('Finished what I planned · 1 min'), findsOneWidget);
      expect(find.text('Next time'), findsOneWidget);
      expect(find.text('Send the draft to Priya'), findsWidgets);
      expect(find.text('Continue for 10 min'), findsOneWidget);
      expect(find.text('Choose another focus time'), findsOneWidget);
      expect(find.text("I'm done for now"), findsOneWidget);
      expect(find.text('Your reminder is still open. Finishing it is a separate step.'), findsOneWidget);
      expect(find.text('Mark reminder done'), findsOneWidget);
      expect(marked, isEmpty, reason: 'finishing a session never completes the reminder');
      expect(c.reminderById('r3')!.status, 'open');
      await _tap(tester, find.text('Mark reminder done'));
      expect(marked, ['r3']);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Made progress has no completion block; no focus times hides Choose another', (tester) async {
      final repo = _repo(planned: false, times: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c);
      await runToReview(tester, c, repo, 'progress', '');
      expect(find.text('Session saved'), findsOneWidget);
      expect(find.text('Next time'), findsNothing, reason: 'blank note shows no inset');
      expect(find.text('Choose another focus time'), findsNothing);
      expect(find.text('Mark reminder done'), findsNothing);
      expect(find.text('Continue for 10 min'), findsOneWidget);
      await _tap(tester, find.text('Continue for 10 min'));
      expect(repo.sessions.values.where((s) => s.finishedAt == null).single.durationMinutes, 10);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('assigned work that finishes is reviewed; the latest blank note clears the old one', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c);
      expect(find.text('Start with the title and first line.'), findsOneWidget);
      await _tap(tester, _key('focus-card-start'));
      await _tap(tester, _key('focus-end'));
      await _tap(tester, _key('focus-outcome-finished'));
      await _tap(tester, _key('focus-save-session'));
      expect(repo.assignments['a1']!.state, 'reviewed');
      await _tap(tester, find.text("I'm done for now"));
      expect(c.nextStepFor('r10'), isNull, reason: 'latest saved note is blank');
      expect(find.text('Start with the title and first line.'), findsNothing);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('a failed save keeps the answers and shows a retry block', (tester) async {
      final repo = _repo(planned: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c);
      await _tap(tester, _key('focus-card-start'));
      await _tap(tester, _key('focus-end'));
      await _tap(tester, _key('focus-save-session'));
      expect(find.text('Choose how the session went.'), findsOneWidget);
      await _tap(tester, _key('focus-outcome-interrupted'));
      await tester.enterText(_key('focus-next-step'), 'Call back at 3');
      repo.failWrites = true;
      await _tap(tester, _key('focus-save-session'));
      expect(find.text("Couldn't save your session"), findsOneWidget);
      expect(find.textContaining('Your answers are still here.'), findsOneWidget);
      expect(find.text('Call back at 3'), findsOneWidget);
      repo.failWrites = false;
      await _tap(tester, _key('focus-retry-save'));
      expect(find.text('Session saved'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('Focus times editor', () {
    testWidgets('validates visibly, saves, and keeps drafts across Realtime refreshes', (tester) async {
      final repo = _repo(times: false, planned: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c, actions: {'times': (context) => openFocusTimes(context, c)});
      await _tap(tester, find.text('times'));
      expect(find.text('Your focus times'), findsWidgets);
      expect(find.text('Pick the weekly times you can focus, then plan reminders into them. Nothing starts on its own.'), findsOneWidget);
      expect(find.text('Times use your account timezone, America/New_York. '), findsOneWidget);
      await _tap(tester, _key('focus-add-time'));
      expect(find.text('New focus time'), findsOneWidget);
      await _tap(tester, _key('focus-time-save'));
      expect(find.text('Choose at least one day.'), findsOneWidget);
      expect(find.text('Choose Work or Side Gig.'), findsOneWidget);
      await tester.enterText(_key('focus-time-name'), 'Shop time');
      await _tap(tester, _key('focus-day-4'));
      await _tap(tester, _key('focus-day-6'));
      await _tap(tester, _key('focus-for-sidegig'));
      await _tap(tester, _key('focus-have-60'));
      // A Realtime refresh rebuilds everything but never touches the draft.
      repo.notifyRemoteChange();
      await tester.pumpAndSettle();
      expect(find.text('Shop time'), findsOneWidget);
      expect(tester.widget<TextField>(_key('focus-time-name')).controller!.text, 'Shop time');
      await _tap(tester, _key('focus-time-save'));
      expect(find.text('Focus time saved'), findsWidgets);
      final saved = repo.times.values.single;
      expect(saved.label, 'Shop time');
      expect(saved.weekdays, [4, 6]);
      expect(saved.contextSlug, 'sidegig');
      expect(saved.budgetMinutes, 60);
      expect(saved.startTime, '09:00:00');
      expect(find.text('Shop time'), findsWidgets);
      expect(find.text('Thu, Sat · 9 AM · 60 min'), findsOneWidget);
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('custom minutes are validated and Archive offers Undo that restores the same time', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await _pump(tester, c, actions: {'times': (context) => openFocusTimes(context, c)});
      await _tap(tester, find.text('times'));
      await _tap(tester, _key('focus-time-ft1'));
      expect(find.text('Edit focus time'), findsOneWidget);
      await _tap(tester, _key('focus-have-custom'));
      await tester.enterText(
        find.descendant(of: _key('focus-have-custom'), matching: find.byType(TextField)),
        '0',
      );
      await _tap(tester, _key('focus-time-save'));
      expect(find.text('Choose a whole number from 1 to 180 minutes.'), findsOneWidget);
      await _tap(tester, _key('focus-time-archive'));
      expect(repo.times.containsKey('ft1'), isFalse);
      expect(find.text('Focus time archived · planned work stays'), findsOneWidget);
      await _tap(tester, _key('focus-notice-undo'));
      expect(repo.times.values.where((t) => t.label == 'Shop time'), hasLength(1));
      expect(repo.times['ft1']!.enabled, isTrue, reason: 'same id, same on/off as before');
      expect(repo.calls.where((x) => x.startsWith('time:')), isEmpty, reason: 'Undo never creates a new time');
      expect(c.state!.assignments.where((a) => a.focusTimeId == 'ft1'), hasLength(3), reason: 'planned work stays attached');
      expect(find.text('Focus time restored'), findsOneWidget);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('without 0017 Archive offers no Undo', (tester) async {
      final repo = _repo(planned: false, intents: false);
      final c = await _controller(repo);
      await _pump(tester, c, actions: {'times': (context) => openFocusTimes(context, c)});
      await _tap(tester, find.text('times'));
      await _tap(tester, _key('focus-time-ft1'));
      await _tap(tester, _key('focus-time-archive'));
      expect(find.text('Focus time archived · planned work stays'), findsOneWidget);
      expect(_key('focus-notice-undo'), findsNothing);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Settings → Focus shows the count and opens the same sheet', (tester) async {
      final repo = _repo();
      final c = await _controller(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            repository: DemoSettingsRepository(timezone: _tz),
            onSignOut: () async {},
            onDeleted: () async {},
            onChanged: () {},
            focusController: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(_key('settings-focus-times'), find.byKey(const ValueKey('settings-list')), const Offset(0, -200));
      expect(find.text('FOCUS'), findsOneWidget);
      expect(find.text('3 set up ›'), findsOneWidget);
      await tester.tap(_key('settings-focus-times'));
      await tester.pumpAndSettle();
      expect(find.text('Your focus times'), findsOneWidget);
      expect(find.text('Saturday mornings'), findsOneWidget);
      expect(find.text('Add a focus time'), findsOneWidget);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });

    testWidgets('Settings hides Focus when the planning migrations are not applied', (tester) async {
      final repo = _repo(planning: false);
      final c = await _controller(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            repository: DemoSettingsRepository(timezone: _tz),
            onSignOut: () async {},
            onDeleted: () async {},
            onChanged: () {},
            focusController: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('ACCOUNT'), find.byKey(const ValueKey('settings-list')), const Offset(0, -200));
      expect(find.text('Focus times'), findsNothing);
      await _teardown(tester, c);
      repo.dispose();
    });
  });

  group('large text and dark mode', () {
    for (final dark in [false, true]) {
      testWidgets('card, missed card and sheets fit at 1.5x text (${dark ? 'dark' : 'light'})', (tester) async {
        final repo = _repo(missed: true);
        final c = await _controller(repo);
        await _pump(
          tester,
          c,
          dark: dark,
          scale: 1.5,
          actions: {
            'plan': (context) => openWorkOnThis(context, c, c.reminderById('r6')!),
            'times': (context) => openFocusTimes(context, c),
          },
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_key('focus-card-start')).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(_key('missed-start')).height, greaterThanOrEqualTo(44));
        await _tap(tester, find.text('Thursday · 7 PM'));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_key('occ-start-a3')).height, greaterThanOrEqualTo(44));
        await tester.tap(find.byTooltip('Close focus'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('plan'));
        await _tap(tester, _key('plan-opt-ft3|2026-10-27'));
        expect(find.text('This is after the due time'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close focus'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('times'));
        await _tap(tester, _key('focus-add-time'));
        await _tap(tester, _key('focus-time-chip'));
        expect(tester.takeException(), isNull);
        for (final day in [1, 7]) {
          expect(tester.getSize(_key('focus-day-$day')).height, greaterThanOrEqualTo(44));
        }
        await tester.tap(find.byTooltip('Close focus'));
        await tester.pumpAndSettle();
        await _teardown(tester, c);
        repo.dispose();
      });
    }

    testWidgets('session and review sheets fit at 1.5x text in dark mode', (tester) async {
      final repo = _repo(planned: false);
      await repo.highlight('r3');
      final c = await _controller(repo);
      await _pump(tester, c, dark: true, scale: 1.5);
      await _tap(tester, _key('focus-card-start'));
      expect(find.text('In focus'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _tap(tester, _key('focus-end'));
      await _tap(tester, _key('focus-outcome-finished'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await _teardown(tester, c);
      repo.dispose();
    });
  });
}
