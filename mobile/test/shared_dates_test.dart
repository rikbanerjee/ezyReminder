import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:ezyreminder/core/util/dates.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final fixtures = (jsonDecode(
    File('../shared/fixtures/dates.json').readAsStringSync(),
  ) as List<dynamic>);

  for (final fixture in fixtures.cast<Map<String, dynamic>>()) {
    test(fixture['name'] as String, () {
      final location = tz.getLocation(fixture['timeZone'] as String);
      final now = _at(location, fixture['now'] as String);
      for (final testCase
          in (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final function = testCase['fn'] as String;
        switch (function) {
          case 'bucketFor':
            final due = testCase['due'] == null
                ? null
                : _at(location, testCase['due'] as String);
            expect(bucketFor(due, now: now), testCase['expected']);
            break;
          case 'relativeDue':
            final due = testCase['due'] == null
                ? null
                : _at(location, testCase['due'] as String);
            expect(relativeDue(due, now: now), testCase['expected']);
            break;
          case 'snoozeTarget':
            expect(
              snoozeTarget(
                testCase['preset'] as String,
                now: now,
              ).toUtc().toIso8601String(),
              testCase['expected'],
            );
            break;
          default:
            fail('Unknown fixture function $function');
        }
      }
    });
  }
}

tz.TZDateTime _at(tz.Location location, String iso) =>
    tz.TZDateTime.from(DateTime.parse(iso), location);
