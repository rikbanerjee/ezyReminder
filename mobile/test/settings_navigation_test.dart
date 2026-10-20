import 'package:ezyreminder/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Today and All open the same persistent settings', (
    tester,
  ) async {
    await tester.pumpWidget(const EzyApp(connected: false, preview: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final timezone = find.byKey(const ValueKey('settings-timezone'));
    expect(timezone, findsOneWidget);
    await tester.enterText(timezone, 'Europe/London');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-timezone')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('All'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(timezone).controller!.text,
      'Europe/London',
    );
    expect(tester.takeException(), isNull);
  });
}
