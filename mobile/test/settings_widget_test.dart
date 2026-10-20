import 'dart:async';

import 'package:ezyreminder/core/util/device_timezone.dart';
import 'package:ezyreminder/core/util/quiet_hours.dart';
import 'package:ezyreminder/features/settings/settings_page.dart';
import 'package:ezyreminder/features/settings/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('timezone rejects invalid names and saves a trimmed IANA name', (
    tester,
  ) async {
    final repository = DemoSettingsRepository();
    var changed = 0;
    await _mount(tester, repository, onChanged: () => changed++);

    await tester.enterText(
      find.byKey(const ValueKey('settings-timezone')),
      'Not/AZone',
    );
    await _dismissKeyboard(tester);
    await _reveal(tester, find.byKey(const ValueKey('save-timezone')));
    await tester.tap(find.byKey(const ValueKey('save-timezone')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('settings-timezone')))
          .decoration
          ?.errorText,
      contains('valid IANA time zone'),
    );
    expect((await repository.load()).timezone, 'UTC');

    await tester.enterText(
      find.byKey(const ValueKey('settings-timezone')),
      '  America/Los_Angeles  ',
    );
    await _dismissKeyboard(tester);
    await _reveal(tester, find.byKey(const ValueKey('save-timezone')));
    await tester.tap(find.byKey(const ValueKey('save-timezone')));
    await tester.pumpAndSettle();
    expect((await repository.load()).timezone, 'America/Los_Angeles');
    expect(changed, 1);
  });

  testWidgets('follows the iPhone time zone until a zone is chosen by hand', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final read = DeviceTimezone.read;
    DeviceTimezone.read = () async => 'America/New_York';
    addTearDown(() => DeviceTimezone.read = read);
    final repository = DemoSettingsRepository(timezone: 'EST');
    await _mount(tester, repository);

    // On by default: the account catches up with the phone.
    expect((await repository.load()).timezone, 'America/New_York');
    final follow = find.byKey(const ValueKey('settings-follow-device'));
    expect(tester.widget<SwitchListTile>(follow).value, isTrue);
    expect(find.byKey(const ValueKey('save-timezone')), findsNothing);

    await tester.tap(follow);
    await tester.pumpAndSettle();
    expect(await DeviceTimezone.follows(), isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('settings-timezone')),
      'Europe/Paris',
    );
    await _dismissKeyboard(tester);
    await _reveal(tester, find.byKey(const ValueKey('save-timezone')));
    await tester.tap(find.byKey(const ValueKey('save-timezone')));
    await tester.pumpAndSettle();
    expect((await repository.load()).timezone, 'Europe/Paris');
    expect(await DeviceTimezone.follows(), isFalse);

    await tester.ensureVisible(follow);
    await tester.pumpAndSettle();
    await tester.tap(follow);
    await tester.pumpAndSettle();
    expect((await repository.load()).timezone, 'America/New_York');
    expect(await DeviceTimezone.follows(), isTrue);
  });

  testWidgets('timezone save failure retains the draft for retry', (
    tester,
  ) async {
    final repository = DemoSettingsRepository()..failTimezoneSave = true;
    await _mount(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('settings-timezone')),
      'Europe/Paris',
    );
    await _dismissKeyboard(tester);
    await _reveal(tester, find.byKey(const ValueKey('save-timezone')));
    await tester.tap(find.byKey(const ValueKey('save-timezone')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save time zone'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('settings-timezone')))
          .controller!
          .text,
      'Europe/Paris',
    );
    expect((await repository.load()).timezone, 'UTC');

    repository.failTimezoneSave = false;
    await tester.tap(find.byKey(const ValueKey('save-timezone')));
    await tester.pumpAndSettle();
    expect((await repository.load()).timezone, 'Europe/Paris');
  });

  testWidgets('timezone field is locked while its submitted draft saves', (
    tester,
  ) async {
    final repository = _GatedTimezoneRepository();
    await _mount(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('settings-timezone')),
      'Europe/Paris',
    );
    await _dismissKeyboard(tester);
    await _reveal(tester, find.byKey(const ValueKey('save-timezone')));
    await tester.tap(find.byKey(const ValueKey('save-timezone')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('settings-timezone')))
          .readOnly,
      isTrue,
    );
    repository.saveGate.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('settings-timezone')))
          .controller!
          .text,
      'Europe/Paris',
    );
  });

  testWidgets(
    'quiet-hours clear writes empty values and failed save keeps draft',
    (tester) async {
      final repository = DemoSettingsRepository(
        contexts: const [
          SettingsContext(
            id: 'work',
            name: 'Work',
            slug: 'work',
            quietHours: QuietHours(start: '21:00', end: '08:00'),
          ),
        ],
      )..failQuietHoursFor.add('work');
      await _mount(tester, repository);

      await _reveal(tester, find.byKey(const ValueKey('clear-quiet-work')));
      await tester.tap(find.byKey(const ValueKey('clear-quiet-work')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save quiet hours'), findsOneWidget);
      expect(find.text('Start · Not set'), findsOneWidget);
      expect(find.text('End · Not set'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(
        (await repository.load()).contexts.single.quietHours.start,
        '21:00',
      );

      repository.failQuietHoursFor.clear();
      await _reveal(tester, find.byKey(const ValueKey('save-quiet-work')));
      await tester.tap(find.byKey(const ValueKey('save-quiet-work')));
      await tester.pumpAndSettle();
      final saved = (await repository.load()).contexts.single.quietHours;
      expect(saved.start, '');
      expect(saved.end, '');
    },
  );

  testWidgets('equal quiet-hours endpoints are shown as inactive', (
    tester,
  ) async {
    final repository = DemoSettingsRepository(
      contexts: const [
        SettingsContext(
          id: 'work',
          name: 'Work',
          slug: 'work',
          quietHours: QuietHours(start: '08:30', end: '08:30'),
        ),
      ],
    );
    await _mount(tester, repository);
    expect(find.textContaining('Equal start and end times'), findsOneWidget);
  });

  testWidgets(
    'account deletion requires exact typed confirmation and reports failure',
    (tester) async {
      final repository = DemoSettingsRepository()..failDelete = true;
      var deleted = 0;
      await _mount(tester, repository, onDeleted: () async => deleted++);
      await _reveal(
        tester,
        find.byKey(const ValueKey('settings-delete-account')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const ValueKey('confirm-delete-account'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-confirmation')),
        'delete',
      );
      await _dismissKeyboard(tester);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-confirmation')),
        'DELETE',
      );
      await _dismissKeyboard(tester);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not delete account'), findsOneWidget);
      expect(repository.accountDeleted, isFalse);
      expect(deleted, 0);
      expect(find.text('Settings'), findsOneWidget);
    },
  );

  testWidgets('successful confirmed deletion invokes parent callback once', (
    tester,
  ) async {
    final repository = DemoSettingsRepository();
    var deleted = 0;
    await _mount(tester, repository, onDeleted: () async => deleted++);
    await _reveal(
      tester,
      find.byKey(const ValueKey('settings-delete-account')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-confirmation')),
      'DELETE',
    );
    await _dismissKeyboard(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('confirm-delete-account')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-delete-account')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.accountDeleted, isTrue);
    expect(deleted, 1);
  });

  testWidgets('settings remain usable at 1.5 text scale in dark mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DemoSettingsRepository();
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: SettingsPage(
            repository: repository,
            onSignOut: () async {},
            onDeleted: () async {},
            onChanged: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('CONTEXTS · QUIET HOURS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure has retry and does not show false settings', (
    tester,
  ) async {
    final repository = _FailingLoadRepository()..failLoad = true;
    await _mount(tester, repository);
    expect(find.textContaining('Could not load settings'), findsOneWidget);
    expect(find.text('CONTEXTS · QUIET HOURS'), findsNothing);

    repository.failLoad = false;
    await tester.tap(find.byKey(const ValueKey('retry-settings-load')));
    await tester.pumpAndSettle();
    expect(find.text('CONTEXTS · QUIET HOURS'), findsOneWidget);
  });
}

Future<void> _mount(
  WidgetTester tester,
  SettingsRepository repository, {
  Future<void> Function()? onSignOut,
  Future<void> Function()? onDeleted,
  VoidCallback? onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      home: SettingsPage(
        repository: repository,
        onSignOut: onSignOut ?? () async {},
        onDeleted: onDeleted ?? () async {},
        onChanged: onChanged ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final list = find.byKey(const ValueKey('settings-list'));
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(target, 220, scrollable: scrollable);
}

Future<void> _dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

class _FailingLoadRepository extends DemoSettingsRepository {
  bool failLoad = false;

  @override
  Future<SettingsData> load() async {
    if (failLoad) throw StateError('offline');
    return super.load();
  }
}

class _GatedTimezoneRepository extends DemoSettingsRepository {
  final Completer<void> saveGate = Completer<void>();

  @override
  Future<void> saveTimezone(String timezone) async {
    await saveGate.future;
    await super.saveTimezone(timezone);
  }
}
