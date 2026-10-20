import 'dart:async';

import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _contexts = [
  ContextItem('work', 'Work', 'work'),
  ContextItem('gig', 'Side Gig', 'side_gig'),
  ContextItem('social', 'Social', 'social'),
  ContextItem('shop', 'Shopping', 'shopping'),
];

Reminder _reminder({
  String title = 'Original title',
  String? notes = 'Original notes',
  String status = 'open',
  DateTime? snoozedUntil,
  DateTime? dueAt,
  bool isOrder = false,
  List<String> channels = const ['push'],
}) => Reminder(
  id: 'r1',
  title: title,
  contextId: 'work',
  contextName: 'Work',
  contextSlug: 'work',
  notes: notes,
  status: status,
  snoozedUntil: snoozedUntil,
  dueAt: dueAt,
  isOrder: isOrder,
  channels: channels,
);

class FakeRepository implements ReminderRepository {
  FakeRepository(Reminder reminder) : item = reminder.copy();

  Reminder item;
  final stream = StreamController<void>.broadcast();
  Completer<void>? completeGate;
  bool failComplete = false;
  int completeCalls = 0;
  int restoreCalls = 0;
  Map<String, Object?>? saved;

  @override
  Stream<void> get changes => stream.stream;
  @override
  Future<List<ContextItem>> contexts() async => _contexts;
  @override
  Future<List<Reminder>> load() async =>
      item.status == 'done' ? [] : [item.copy()];
  @override
  Future<void> complete(String id) async {
    completeCalls++;
    if (completeGate != null) await completeGate!.future;
    if (failComplete) throw StateError('offline');
    item.status = 'done';
    item.snoozedUntil = null;
  }

  @override
  Future<void> restore(Reminder reminder) async {
    restoreCalls++;
    item.status = reminder.status;
    item.snoozedUntil = reminder.snoozedUntil;
  }

  @override
  Future<void> snooze(String id, DateTime until) async {}

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
    saved = {
      'id': id,
      'title': title,
      'notes': notes,
      'dueAt': dueAt,
      'contextId': contextId,
      'isOrder': isOrder,
      'channels': channels,
    };
    return id ?? 'r-created';
  }
}

Future<void> _showApp(WidgetTester tester, FakeRepository repo) async {
  await tester.pumpWidget(
    EzyApp(connected: false, preview: true, repository: repo),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('failed completion rolls back once and never duplicates row', (
    tester,
  ) async {
    final repo = FakeRepository(_reminder());
    repo.failComplete = true;
    await _showApp(tester, repo);

    await tester.tap(find.byKey(const ValueKey('ring-r1')));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(repo.completeCalls, 1);
    expect(find.text('Original title'), findsOneWidget);
    expect(
      find.text('Original title'),
      findsOneWidget,
      reason: 'rollback must restore exactly one visible row',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo waits for pending completion and restores snoozed state', (
    tester,
  ) async {
    final snooze = DateTime(2026, 10, 18, 9);
    final repo = FakeRepository(
      _reminder(status: 'snoozed', snoozedUntil: snooze),
    )..completeGate = Completer<void>();
    await _showApp(tester, repo);

    await tester.tap(find.byKey(const ValueKey('ring-r1')));
    await tester.pumpAndSettle();
    expect(repo.completeCalls, 1);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(repo.restoreCalls, 0, reason: 'Undo must wait for the write');

    repo.completeGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.restoreCalls, 1);
    expect(repo.item.status, 'snoozed');
    expect(repo.item.snoozedUntil, snooze);
    expect(find.text('Original title'), findsOneWidget);
  });

  testWidgets('sheet keeps dirty title and merges remote fields and channels', (
    tester,
  ) async {
    final initialDue = DateTime(2026, 10, 17, 11);
    final remoteDue = DateTime(2026, 10, 19, 15);
    final repo = FakeRepository(_reminder(dueAt: initialDue));
    await _showApp(tester, repo);

    await tester.tap(find.text('Original title'));
    await tester.pumpAndSettle();
    // The title field uses a hint, so locate it by its initial controller value.
    final title = tester.widgetList<TextField>(find.byType(TextField)).first;
    expect(title.controller!.text, 'Original title');
    await tester.enterText(find.byWidget(title), 'My local title');

    repo.item = _reminder(
      title: 'Remote title',
      notes: 'Remote notes',
      dueAt: remoteDue,
      isOrder: true,
      channels: const ['email', 'push'],
    );
    repo.stream.add(null);
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .first
          .controller!
          .text,
      'My local title',
    );
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .last
          .controller!
          .text,
      'Remote notes',
    );
    expect(find.text('Mon, Oct 19 · 3:00 PM'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await tester.pumpAndSettle();
    final orderSwitch = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(orderSwitch.value, isTrue);

    await tester.scrollUntilVisible(
      find.text('Save reminder'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Save reminder'), findsOneWidget);
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(repo.saved?['title'], 'My local title');
    expect(repo.saved?['notes'], 'Remote notes');
    expect(repo.saved?['dueAt'], remoteDue);
    expect(repo.saved?['isOrder'], isTrue);
    expect(repo.saved?['channels'], ['email', 'push']);
  });
}
