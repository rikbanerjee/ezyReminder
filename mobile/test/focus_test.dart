import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezyreminder/features/focus/focus_controller.dart';
import 'package:ezyreminder/features/focus/focus_models.dart';
import 'package:ezyreminder/features/focus/focus_repository.dart';
import 'package:ezyreminder/features/focus/focus_widgets.dart';

const reminder = FocusReminder(
  id: 'one',
  title: 'Publish the mug listing',
  contextSlug: 'sidegig',
);
void main() {
  test(
    'timestamp timer survives background time and paused intervals',
    () async {
      var now = DateTime.utc(2026, 10, 18, 12);
      final repo = DemoFocusRepository(
        loadReminders: () async => [reminder],
        clock: () => now,
      );
      await repo.start('s', reminder, 25, 'Choose the photos');
      now = now.add(const Duration(minutes: 10, milliseconds: 250));
      final running = (await repo.load()).activeSession!;
      expect(running.remainingSeconds(now), 900);
      await repo.pause(running);
      final paused = (await repo.load()).activeSession!;
      expect(paused.lastResumedAt, isNull);
      now = now.add(const Duration(hours: 2));
      expect(paused.remainingSeconds(now), 900);
      await repo.resume(paused);
      now = now.add(const Duration(minutes: 20));
      final expired = (await repo.load()).activeSession!;
      expect(expired.awaitingFinish(now), isTrue);
      expect(expired.finishedAt, isNull);
      await repo.finish(expired, 'progress', 'Write the description');
      expect((await repo.load()).activeSession, isNull);
      expect(repo.sessions['s']!.elapsedSeconds, 1500);
      expect(await repo.latestNextStep(reminder.id), 'Write the description');
      await repo.finish(expired, 'interrupted', 'Overwrite');
      expect(await repo.latestNextStep(reminder.id), 'Write the description');
      repo.dispose();
    },
  );

  test('single session, uncertain-start retry, stale writes and latest blank next step', () async {
    var now = DateTime.utc(2026, 10, 18, 12);
    final repo = DemoFocusRepository(
      loadReminders: () async => [reminder],
      clock: () => now,
    );
    await repo.start('s', reminder, 10, null);
    final first = (await repo.load()).activeSession!;
    await repo.start('s', reminder, 10, null);
    expect(repo.sessions.length, 1);
    await expectLater(
      repo.start('another', reminder, 25, null),
      throwsStateError,
    );
    now = now.add(const Duration(minutes: 1));
    await repo.pause(first);
    final paused = (await repo.load()).activeSession!;
    now = now.add(const Duration(minutes: 1));
    await repo.resume(paused);
    await expectLater(repo.pause(first), throwsStateError);
    await repo.finish(
      (await repo.load()).activeSession!,
      'progress',
      'Old next step',
    );
    now = now.add(const Duration(minutes: 1));
    await repo.start('next', reminder, 25, null);
    await repo.finish((await repo.load()).activeSession!, 'finished', null);
    expect(await repo.latestNextStep(reminder.id), isNull);
    repo.dispose();
  });

  test('account date and fractional pause time match web semantics', () {
    expect(
      focusLocalDate(DateTime.utc(2026, 10, 18, 0, 30), 'America/New_York'),
      '2026-10-17',
    );
    expect(
      focusLocalDate(DateTime.utc(2026, 11, 1, 5, 30), 'America/New_York'),
      '2026-11-01',
    );
    expect(
      focusLocalDate(DateTime.utc(2026, 11, 1, 6, 30), 'America/New_York'),
      '2026-11-01',
    );
    final s = FocusSession(
      id: 's',
      title: reminder.title,
      contextSlug: 'sidegig',
      durationMinutes: 25,
      startedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      lastResumedAt: DateTime.utc(2026),
      elapsedSeconds: 60.5,
    );
    expect(
      s.remainingSeconds(
        DateTime.utc(2026).add(const Duration(minutes: 10, milliseconds: 250)),
      ),
      840,
    );
    expect(s.remainingSeconds(DateTime.utc(2025)), 1440);
  });

  testWidgets(
    'focus flow validates, preserves failed outcome draft, and restores next step',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DemoFocusRepository(loadReminders: () async => [reminder]);
      final controller = FocusController(repo, tick: false);
      await controller.reload();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: Column(
                  children: [
                    FocusCard(controller: controller),
                    TextButton(
                      onPressed: () =>
                          openFocus(context, controller, reminder: reminder),
                      child: const Text('Focus on this'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Focus on this'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Minutes (1–180)'),
        '0',
      );
      await tester.pump();
      expect(find.text('Choose a whole number from 1 to 180.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Minutes (1–180)'),
        '10',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Start now'));
      await tester.tap(find.text('Start now'));
      await tester.pumpAndSettle();
      expect(controller.session, isNotNull, reason: controller.error);
      expect(find.text('End session'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(controller.session!.paused, isTrue);
      await tester.tap(find.byTooltip('Close focus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open session'));
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save session'));
      await tester.tap(find.text('Save session'));
      await tester.pumpAndSettle();
      expect(find.text('Choose how your session went.'), findsOneWidget);
      await tester.ensureVisible(find.text('Made progress'));
      await tester.tap(find.text('Made progress'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Next step for next time (optional)'),
        'Write the description',
      );
      repo.failWrites = true;
      await tester.ensureVisible(find.text('Save session'));
      await tester.tap(find.text('Save session'));
      await tester.pumpAndSettle();
      expect(controller.session, isNotNull);
      expect(find.text('Write the description'), findsOneWidget);
      repo.failWrites = false;
      await tester.ensureVisible(find.text('Save session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save session'));
      await tester.pumpAndSettle();
      expect(controller.session, isNull);
      expect(repo.sessions.values.single.outcome, 'progress');
      await tester.tap(find.text('Focus on this'));
      await tester.pumpAndSettle();
      expect(find.text('Last next step'), findsOneWidget);
      expect(find.text('Write the description'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
