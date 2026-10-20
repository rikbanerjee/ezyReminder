import 'package:ezyreminder/main.dart';
import 'package:ezyreminder/features/home/home_page.dart';
import 'package:ezyreminder/features/home/home_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingHomeRepository extends DemoHouseholdRepository {
  bool fail = false;
  Map<String, dynamic>? lastSave;
  @override
  Future<String?> save(Map<String, dynamic> params) async {
    lastSave = params;
    if (fail) throw StateError('offline');
    return super.save(params);
  }
}

Future<void> editor(
  WidgetTester tester,
  RecordingHomeRepository repository, {
  HomeMaintenance? item,
  String category = 'car',
}) async {
  await tester.pumpWidget(const EzyApp(connected: false, preview: true));
  await tester.pumpAndSettle();
  final theme = Theme.of(tester.element(find.byType(TodayPage)));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: MaintenanceEditor(
          repository: repository,
          category: category,
          item: item,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Home navigation opens shopping checklist and persists checks', (
    tester,
  ) async {
    final repo = DemoRepository();
    await tester.pumpWidget(
      EzyApp(connected: false, preview: true, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.byType(HouseholdPage), findsOneWidget);
    expect(find.text('Car service & maintenance'), findsOneWidget);
    expect(find.text('HVAC & air filters'), findsOneWidget);
    expect(find.text('Filter changes'), findsNothing);
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    final lists = (await repo.load())
        .where((r) => r.contextSlug == 'shopping')
        .toList();
    expect(lists, isNotEmpty);
    await tester.tap(find.text(lists.first.title));
    await tester.pumpAndSettle();
    final before = await repo.loadShoppingItems(lists.first.id);
    expect(before, isNotEmpty);
    await tester.tap(find.text(before.first.label));
    await tester.pumpAndSettle();
    final after = await repo.loadShoppingItems(lists.first.id);
    expect(after.first.checked, !before.first.checked);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Maintenance validates date and keeps draft after failed save', (
    tester,
  ) async {
    final repo = RecordingHomeRepository()..fail = true;
    final item = HomeMaintenance({
      'reminder_id': 'car-1',
      'title': 'Oil change',
      'asset': 'Family car',
      'notes': '5W-30',
      'category': 'car',
      'status': 'open',
      'due_at': '2026-11-01T14:00:00Z',
      'channels': ['email'],
      'updated_at': '2026-10-18T12:00:00Z',
    });
    await editor(tester, repo, item: item);
    await tester.ensureVisible(find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(repo.lastSave?['p_asset'], 'Family car');
    expect(find.textContaining('Could not save.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Oil change'), findsOneWidget);
    expect(repo.items, isEmpty);
    await editor(tester, RecordingHomeRepository());
    await tester.ensureVisible(find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Choose the next service date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Car make and model are separate saved fields', (tester) async {
    final repo = RecordingHomeRepository()..fail = true;
    final item = HomeMaintenance({
      'reminder_id': 'car',
      'title': 'Oil change',
      'category': 'car',
      'asset': 'Family car',
      'notes': '',
      'status': 'open',
      'due_at': '2026-11-01T14:00:00Z',
      'channels': ['email'],
      'details': {'make': 'Toyota', 'model': 'Camry'},
    });
    await editor(tester, repo, item: item);
    expect(find.text('Car or appliance'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Car make'),
      'Honda',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Car model'),
      'Civic',
    );
    await tester.ensureVisible(find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(repo.lastSave?['p_details'], {'make': 'Honda', 'model': 'Civic'});
    expect(find.widgetWithText(TextFormField, 'Honda'), findsOneWidget);
  });

  testWidgets('Bill fields validate amounts and use payment terminology', (
    tester,
  ) async {
    final repo = RecordingHomeRepository()..fail = true;
    final item = HomeMaintenance({
      'reminder_id': 'bill',
      'title': 'Internet bill',
      'category': 'bill',
      'asset': 'Provider',
      'notes': '',
      'status': 'open',
      'due_at': '2026-11-01T14:00:00Z',
      'channels': ['email'],
      'repeat_months': 1,
      'details': {},
    });
    await editor(tester, repo, item: item, category: 'bill');
    expect(find.text('Car name'), findsNothing);
    expect(find.text('Car make'), findsNothing);
    expect(find.text('Biller or provider'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount due'),
      'abc',
    );
    await tester.ensureVisible(find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount such as 85.50'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount due'),
      '85.50',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Currency'),
      'usd',
    );
    await tester.ensureVisible(find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(repo.lastSave?['p_details'], {'amount': '85.50', 'currency': 'USD'});
    await tester.ensureVisible(find.text('Mark bill paid'));
    await tester.tap(find.text('Mark bill paid'));
    await tester.pumpAndSettle();
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Payment confirmation notes'), findsOneWidget);
    expect(find.text('Save payment record'), findsOneWidget);
    expect(find.text('Record completed service'), findsNothing);
  });

  testWidgets('Study uses student fields and a weekly repeat', (tester) async {
    final repo = RecordingHomeRepository()..fail = true;
    final item = HomeMaintenance({
      'reminder_id': 'study',
      'title': 'Math practice',
      'category': 'study',
      'asset': 'Alex',
      'notes': '',
      'status': 'open',
      'due_at': '2026-11-01T14:00:00Z',
      'channels': ['email'],
      'repeat_days': 7,
      'details': {'subject': 'Math', 'teacher': 'Ms Lee'},
    });
    await editor(tester, repo, item: item, category: 'study');
    expect(find.text('Student or family member'), findsOneWidget);
    expect(find.text('Subject or course'), findsOneWidget);
    expect(find.text('Car make'), findsNothing);
    await tester.ensureVisible(find.text('Save reminder'));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();
    expect(repo.lastSave?['p_repeat_days'], 7);
    expect(repo.lastSave?['p_repeat_months'], null);
    expect(repo.lastSave?['p_details'], {
      'subject': 'Math',
      'teacher': 'Ms Lee',
    });
  });

  testWidgets('Battery template names the device and battery type', (
    tester,
  ) async {
    await editor(tester, RecordingHomeRepository(), category: 'battery');
    expect(find.text('Device & location'), findsOneWidget);
    expect(find.text('Battery or charger type'), findsOneWidget);
    expect(find.text('Car make'), findsNothing);
    expect(find.text('Car or appliance'), findsNothing);
  });

  test(
    'Service history retains notes and one-time services complete',
    () async {
      final repo = DemoHouseholdRepository();
      await repo.save({
        'p_id': 'one',
        'p_title': 'Car inspection',
        'p_notes': '',
        'p_asset': 'Family car',
        'p_category': 'car',
        'p_repeat_months': null,
        'p_due_at': '2026-11-01T14:00:00Z',
        'p_channels': ['email'],
      });
      final item = (await repo.load()).single;
      final version = item.data['updated_at'];
      await repo.record({
        'p_id': 'one',
        'p_expected_updated_at': version,
        'p_serviced_at': '2026-10-01T12:00:00Z',
        'p_notes': 'Inspection at 50000 miles',
      });
      expect((await repo.load()).single.status, 'done');
      expect(
        (await repo.history()).single['notes'],
        'Inspection at 50000 miles',
      );
      await expectLater(
        repo.record({
          'p_id': 'one',
          'p_expected_updated_at': version,
          'p_serviced_at': '2026-10-01T12:00:00Z',
          'p_notes': 'duplicate',
        }),
        throwsStateError,
      );
      await repo.delete('one');
      expect(await repo.load(), isEmpty);
      expect(await repo.history(), hasLength(1));
    },
  );
}
