import 'package:ezyreminder/shared/widgets/compact_date_time_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OK preserves the initial date and exact minute', (tester) async {
    final initial = DateTime(2026, 10, 17, 14, 37);
    await _showPicker(tester, initial);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('2:37 PM'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('date-time-ok')));
    await tester.pumpAndSettle();
    expect(_picked, initial);
  });

  testWidgets('changing the calendar date keeps the selected time', (
    tester,
  ) async {
    final initial = DateTime(2026, 10, 17, 9, 6);
    await _showPicker(tester, initial);
    await tester.tap(find.byKey(const ValueKey('date-day-22')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('date-time-ok')));
    await tester.pumpAndSettle();

    expect(_picked, DateTime(2026, 10, 22, 9, 6));
  });

  testWidgets('quick time preset updates selection and keeps chosen date', (
    tester,
  ) async {
    await _showPicker(tester, DateTime(2026, 10, 17, 14, 37));
    await tester.tap(find.byKey(const ValueKey('time-preset-evening')));
    await tester.pumpAndSettle();
    expect(find.text('6:00 PM'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('date-day-22')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('date-time-ok')));
    await tester.pumpAndSettle();
    expect(_picked, DateTime(2026, 10, 22, 18));
  });

  testWidgets('midnight initializes correctly and noon preset returns noon', (
    tester,
  ) async {
    await _showPicker(tester, DateTime(2026, 10, 17));
    expect(find.text('12:00 AM'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('time-preset-noon')));
    await tester.pumpAndSettle();
    expect(find.text('12:00 PM'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('date-time-ok')));
    await tester.pumpAndSettle();
    expect(_picked, DateTime(2026, 10, 17, 12));
  });

  testWidgets('time wheel accepts a direct minute adjustment', (tester) async {
    await _showPicker(tester, DateTime(2026, 10, 17, 14, 37));
    final minute = find.text('37');
    expect(minute, findsOneWidget);
    await tester.drag(minute, const Offset(0, -42));
    await tester.pumpAndSettle();
    final changedLabel = tester
        .widget<Text>(find.byKey(const ValueKey('selected-date-time-label')))
        .data;
    expect(changedLabel, isNot('2:37 PM'));
  });

  testWidgets('Cancel returns null without changing the initial value', (
    tester,
  ) async {
    await _showPicker(tester, DateTime(2026, 4, 3, 18, 42));
    await tester.tap(find.byKey(const ValueKey('date-time-cancel')));
    await tester.pumpAndSettle();
    expect(_picked, isNull);
  });

  testWidgets('compact dialog fits small screen at 1.5 scale in dark mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(1.5),
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => CompactDateTimePicker.show(
                  context,
                  initial: DateTime(2026, 10, 17, 21, 5),
                ).then((value) => _picked = value),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('selected-date-time-label')))
          .data,
      '21:05',
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('date-time-cancel')));
    await tester.pumpAndSettle();
  });
}

DateTime? _picked;

Future<void> _showPicker(WidgetTester tester, DateTime initial) async {
  _picked = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => CompactDateTimePicker.show(
                context,
                initial: initial,
              ).then((value) => _picked = value),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
