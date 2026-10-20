import 'dart:io';

import 'package:ezyreminder/core/util/quiet_hours.dart';
import 'package:ezyreminder/features/notifications/reminder_alerts.dart';
import 'package:ezyreminder/features/settings/settings_page.dart';
import 'package:ezyreminder/features/settings/settings_repository.dart';
import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final now = DateTime.utc(2026, 10, 19, 16); // 12:00 in New York

AlertReminder reminder(
  String id, {
  DateTime? due,
  DateTime? snoozed,
  String status = 'open',
  bool isOrder = false,
  List<String> tags = const [],
  QuietHours? quiet,
  String? notes,
}) => AlertReminder(
  id: id,
  title: 'Reminder $id',
  contextName: 'Work',
  contextSlug: 'work',
  notes: notes,
  status: status,
  dueAt: due,
  snoozedUntil: snoozed,
  isOrder: isOrder,
  tags: tags,
  quietHours: quiet,
);

class FakePlatform implements AlertPlatform {
  AlertPermission status = AlertPermission.allowed;
  AlertPermission afterRequest = AlertPermission.allowed;
  List<ReminderAlert>? pending;
  Set<String>? open;
  final added = <ReminderAlert>[];
  int tests = 0;
  String? opened;
  Future<Object?> Function(String method, Object? args)? handler;

  @override
  Future<AlertPermission> permission() async => status;
  @override
  Future<bool> requestPermission() async {
    status = afterRequest;
    return status == AlertPermission.allowed;
  }

  @override
  Future<void> replace(
    List<ReminderAlert> alerts, {
    required Set<String> open,
  }) async {
    pending = alerts;
    this.open = open;
  }

  @override
  Future<void> add(List<ReminderAlert> alerts) async => added.addAll(alerts);
  @override
  Future<void> sendTest() async => tests++;
  @override
  Future<void> openSettings() async {}
  @override
  Future<String?> takeOpened() async {
    final id = opened;
    opened = null;
    return id;
  }

  @override
  Future<void> attach(
    Future<Object?> Function(String method, Object? args) handler,
  ) async => this.handler = handler;
  @override
  Future<void> detach() async => handler = null;
}

class FakeSource implements AlertSource {
  FakeSource(this.reminders);
  List<AlertReminder>? reminders;
  bool offline = false;
  bool refuse = false;
  final completed = <String>[];
  final snoozed = <String, DateTime>{};

  void _check() {
    if (offline) throw const SocketException('offline');
    if (refuse) throw const PostgrestException(message: 'denied');
  }

  @override
  Future<AlertSnapshot?> load() async {
    _check();
    final rows = reminders;
    return rows == null
        ? null
        : AlertSnapshot(reminders: rows, timeZone: 'America/New_York');
  }

  @override
  Future<void> complete(String id) async {
    _check();
    completed.add(id);
  }

  @override
  Future<void> snooze(String id, DateTime until) async {
    _check();
    snoozed[id] = until;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('planReminderAlerts', () {
    List<ReminderAlert> plan(List<AlertReminder> rows, {int limit = 64}) =>
        planReminderAlerts(
          rows,
          timeZone: 'America/New_York',
          now: now,
          limit: limit,
        );

    test('schedules future open reminders at their effective time', () {
      final alerts = plan([
        reminder('due', due: now.add(const Duration(hours: 2))),
        reminder('past', due: now.subtract(const Duration(minutes: 1))),
        reminder('none'),
        reminder(
          'done',
          due: now.add(const Duration(hours: 1)),
          status: 'done',
        ),
        reminder(
          'snoozed',
          status: 'snoozed',
          due: now.subtract(const Duration(hours: 1)),
          snoozed: now.add(const Duration(minutes: 30)),
        ),
      ]);
      expect(alerts.map((a) => a.id), ['snoozed', 'due']);
      expect(alerts.first.fireAt, now.add(const Duration(minutes: 30)));
      expect(alerts.first.threadId, 'work');
    });

    test('a time inside quiet hours fires when the window ends', () {
      final alerts = plan([
        reminder(
          'late',
          // 23:00 in New York; quiet 21:00–08:00 → 08:00 the next morning.
          due: DateTime.utc(2026, 10, 20, 3),
          quiet: const QuietHours(start: '21:00', end: '08:00'),
        ),
        reminder(
          'day',
          due: DateTime.utc(2026, 10, 19, 18),
          quiet: const QuietHours(start: '21:00', end: '08:00'),
        ),
      ]);
      expect(alerts.map((a) => a.id), ['day', 'late']);
      expect(alerts.last.fireAt, DateTime.utc(2026, 10, 20, 12));
    });

    test('keeps only the soonest alerts iOS allows', () {
      final rows = [
        for (var i = 70; i > 0; i--)
          reminder('r$i', due: now.add(Duration(minutes: i))),
      ];
      final alerts = plan(rows);
      expect(alerts, hasLength(maxPendingAlerts));
      expect(alerts.first.id, 'r1');
      expect(alerts.last.id, 'r64');
    });

    test('orders, Side Gig work and Home tasks finish in their own forms', () {
      final due = now.add(const Duration(hours: 1));
      final alerts = {
        for (final a in plan([
          reminder('plain', due: due, notes: 'Bring the deck\nand notes'),
          reminder('order', due: due, isOrder: true),
          reminder('gig', due: due, tags: ['sidegig:work']),
          reminder('home', due: due, tags: ['home:hvac']),
        ]))
          a.id: a,
      };
      expect(alerts['plain']!.category, 'REMINDER');
      expect(alerts['plain']!.body, 'Work · Bring the deck');
      expect(alerts['order']!.category, 'REMINDER_OPEN');
      expect(alerts['order']!.body, 'Work · Order');
      expect(alerts['gig']!.category, 'REMINDER_OPEN');
      expect(alerts['home']!.category, 'REMINDER_OPEN');
    });

    test('an unknown account zone falls back to UTC instead of failing', () {
      final alerts = planReminderAlerts(
        [
          reminder(
            'x',
            due: now.add(const Duration(hours: 1)),
            quiet: const QuietHours(start: '00:00', end: '23:59'),
          ),
        ],
        timeZone: 'Not/AZone',
        now: now,
      );
      expect(alerts.single.fireAt, DateTime.utc(2026, 10, 19, 23, 59));
    });
  });

  group('ReminderAlerts', () {
    late FakePlatform platform;
    late FakeSource source;
    late ReminderAlerts alerts;
    setUp(() {
      platform = FakePlatform();
      source = FakeSource([
        reminder('soon', due: now.add(const Duration(hours: 1))),
        reminder('undated'),
      ]);
      alerts = ReminderAlerts(
        source: source,
        platform: platform,
        clock: () => now,
      );
    });

    test(
      'sync replaces the pending set and keeps open reminders delivered',
      () async {
        await alerts.sync();
        expect(platform.pending!.map((a) => a.id), ['soon']);
        expect(platform.open, {'soon', 'undated'});
      },
    );

    test('nothing is scheduled without permission', () async {
      platform.status = AlertPermission.denied;
      await alerts.sync();
      expect(platform.pending, isNull);
    });

    test('a signed-out sync clears every alert', () async {
      source.reminders = null;
      await alerts.sync();
      expect(platform.pending, isEmpty);
      expect(platform.open, isEmpty);
    });

    test('enable asks iOS once, then schedules', () async {
      platform.status = AlertPermission.notDetermined;
      expect(await alerts.enable(), AlertPermission.allowed);
      expect(platform.pending!.map((a) => a.id), ['soon']);
    });

    test('Done completes the reminder and reschedules', () async {
      await alerts.run({'kind': 'action', 'action': doneAction, 'id': 'soon'});
      expect(source.completed, ['soon']);
      expect(platform.pending, isNotNull);
    });

    test('Snooze offline still alerts in an hour and replays later', () async {
      source.offline = true;
      final alert = ReminderAlert(
        id: 'soon',
        title: 'Reminder soon',
        body: 'Work',
        fireAt: now,
        threadId: 'work',
        canComplete: true,
      );
      await alerts.run({
        'kind': 'action',
        'action': snoozeAction,
        'id': 'soon',
        'alert': alert.toMap(),
      });
      expect(platform.added.single.fireAt, now.add(snoozeFor));
      expect(platform.added.single.category, 'REMINDER');
      expect(source.snoozed, isEmpty);

      source.offline = false;
      await alerts.sync();
      expect(source.snoozed, {'soon': now.add(snoozeFor)});
      await alerts.sync();
      expect(source.snoozed, hasLength(1), reason: 'replayed once');
    });

    test('a refused write is not retried forever', () async {
      source.refuse = true;
      await alerts.act('soon', doneAction);
      source.refuse = false;
      await alerts.sync();
      expect(source.completed, isEmpty);
    });
  });

  testWidgets('Settings turns on iPhone notifications from a tap', (
    tester,
  ) async {
    final platform = FakePlatform()..status = AlertPermission.notDetermined;
    final alerts = ReminderAlerts(
      source: FakeSource([]),
      platform: platform,
      clock: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          repository: DemoSettingsRepository(),
          onSignOut: () async {},
          onDeleted: () async {},
          onChanged: () {},
          alerts: alerts,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-iphone-notifications'));
    await tester.scrollUntilVisible(
      row,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CHANNELS'), findsOneWidget);
    expect(
      platform.status,
      AlertPermission.notDetermined,
      reason: 'no prompt on open',
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-enable-notifications')),
    );
    await tester.pumpAndSettle();
    expect(find.text('On ✓'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-test-notification')));
    await tester.pumpAndSettle();
    expect(platform.tests, 1);
  });

  testWidgets('tapping an alert opens its reminder', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = FakePlatform();
    await tester.pumpWidget(
      EzyApp(
        connected: false,
        preview: true,
        repository: DemoRepository(),
        alerts: ReminderAlerts(source: FakeSource([]), platform: platform),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.handler, isNotNull);
    expect(find.byType(BottomSheet), findsNothing);
    platform.opened = 'fixture-1';
    await platform.handler!('opened', null);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Send the revised proposal'),
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
