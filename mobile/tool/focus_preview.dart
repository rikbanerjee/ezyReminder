// Preview-only entry point: Focus planning with in-memory sample data.
//
//   flutter run -d <simulator> -t tool/focus_preview.dart \
//     --dart-define=EZY_PREVIEW=true --dart-define=FOCUS_TOUR=true
//
// Never connects to Supabase and never touches a real account. With FOCUS_TOUR
// it walks through the key Focus screens, printing `SHOT_READY <name>` when each
// is on screen so a script can capture it.
import 'dart:async';

import 'package:ezyreminder/features/focus/focus_controller.dart';
import 'package:ezyreminder/features/focus/focus_models.dart';
import 'package:ezyreminder/features/focus/focus_repository.dart';
import 'package:ezyreminder/features/focus/focus_widgets.dart';
import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';

const _tour = bool.fromEnvironment('FOCUS_TOUR');
const _tz = 'America/New_York';

final _reminders = <FocusReminder>[
  FocusReminder(
    id: 'fixture-1',
    title: 'Send the revised proposal',
    contextSlug: 'work',
    dueAt: DateTime.now().add(const Duration(hours: 2)),
  ),
  const FocusReminder(id: 'fixture-2', title: 'Photograph new listing', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r10', title: 'Write listing description', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r9', title: 'Choose photos for mug listing', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r11', title: 'Update shipping rates', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r12', title: 'Reply to buyer questions', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r5', title: 'Restock kraft mailers', contextSlug: 'sidegig'),
  const FocusReminder(id: 'r13', title: 'Draft the onboarding doc', contextSlug: 'work'),
];

const _times = [
  FocusTimeItem(id: 'ft1', label: 'Shop time', contextSlug: 'sidegig', weekdays: [4], startTime: '19:00:00', budgetMinutes: 30),
  FocusTimeItem(id: 'ft2', label: 'Saturday mornings', contextSlug: 'sidegig', weekdays: [6], startTime: '09:00:00', budgetMinutes: 60),
  FocusTimeItem(id: 'ft3', label: 'Lunch focus', contextSlug: 'work', weekdays: [1, 2, 3, 4, 5], startTime: '12:30:00', budgetMinutes: 30),
];

FocusAssignment _plan(String id, String rid, String title, String slug, String? ft, String date, String time, int min, int pos) =>
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

/// Moves the preview clock forward so a running session reaches "time is up".
Duration _skew = Duration.zero;

DemoFocusRepository _seed() {
  final now = DateTime.now().toUtc();
  String next(FocusTimeItem t) => nextFocusOccurrences(
    weekdays: t.weekdays,
    startTime: t.startTime,
    budgetMinutes: t.budgetMinutes,
    now: now,
    timeZone: _tz,
    count: 1,
  ).first.localDate;
  final today = focusLocalDate(now, _tz);
  return DemoFocusRepository(
    loadReminders: () async => _reminders,
    clock: () => DateTime.now().add(_skew),
    timezone: _tz,
    focusTimes: _times,
    nextSteps: const {
      'r10': 'Start with the title and first line.',
      'r9': 'Pick the best 4 from the Portland shoot.',
    },
    assignments: [
      _plan('a1', 'r10', 'Write listing description', 'sidegig', 'ft2', next(_times[1]), '09:00:00', 20, 0),
      _plan('a2', 'r13', 'Draft the onboarding doc', 'work', 'ft3', next(_times[2]), '12:30:00', 15, 0),
      _plan('a3', 'r9', 'Choose photos for mug listing', 'sidegig', 'ft1', next(_times[0]), '19:00:00', 15, 0),
      _plan('a4', 'r11', 'Update shipping rates', 'sidegig', 'ft1', next(_times[0]), '19:00:00', 10, 1),
      _plan('a5', 'r12', 'Reply to buyer questions', 'sidegig', 'ft1', next(_times[0]), '19:00:00', 10, 2),
      // Missed: earlier one-offs on a past day.
      _plan('m1', 'r5', 'Restock kraft mailers', 'sidegig', null, addLocalDays(today, -2), '09:00:00', 20, 0),
    ],
  );
}

void main() {
  final repo = _seed();
  runApp(EzyApp(connected: false, preview: true, focusRepository: repo));
  if (_tour) unawaited(_runTour(repo));
}

BuildContext? _scaffoldContext() {
  BuildContext? found;
  void visit(Element e) {
    if (found != null) return;
    if (e.widget is Scaffold) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<void> _runTour(DemoFocusRepository repo) async {
  final controller = FocusController(repo);
  await Future<void>.delayed(const Duration(seconds: 4));
  Future<void> shot(String name, {int dwell = 3}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    debugPrint('SHOT_READY $name');
    await Future<void>.delayed(Duration(seconds: dwell));
  }

  Future<void> open(Future<void> Function(BuildContext) opener, String name) async {
    final context = _scaffoldContext();
    if (context == null) return;
    unawaited(opener(context));
    await shot(name);
    if (context.mounted) Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  await shot('today-upnext');
  await open((c) => openFocusTimes(c, controller), 'times');
  final r6 = controller.reminderById('fixture-1')!;
  await open((c) => openWorkOnThis(c, controller, r6), 'plan');
  final occ = controller.upcoming.firstWhere((o) => o.tasks.length > 1);
  await open((c) => openFocusOccurrence(c, controller, occ), 'occurrence');
  await open((c) => openFocus(c, controller, reminder: controller.reminderById('r10')!), 'setup');
  await repo.start('tour-session', controller.reminderById('fixture-1')!, 25, 'Finish the headcount table.');
  await controller.reload();
  await shot('today-running');
  await open((c) => openFocus(c, controller), 'session');
  _skew = const Duration(minutes: 30);
  await controller.reload();
  await shot('today-timeup');
  await open((c) => openFocus(c, controller), 'review');
  debugPrint('SHOT_READY done');
}
