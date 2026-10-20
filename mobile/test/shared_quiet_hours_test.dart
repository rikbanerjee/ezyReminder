import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:ezyreminder/core/util/quiet_hours.dart';

void main() {
  setUpAll(initializeTimeZones);

  test('timezone database initialization is idempotent', () {
    expect(() => initializeTimeZones(), returnsNormally);
  });

  test('validates IANA timezone identifiers', () {
    expect(isValidTimeZone('America/New_York'), isTrue);
    expect(isValidTimeZone('Mars/Olympus_Mons'), isFalse);
  });

  test('clearing either endpoint disables quiet hours', () {
    final now = DateTime.utc(2026, 10, 17, 2);
    for (final hours in const [
      QuietHours(start: '', end: '08:00'),
      QuietHours(start: '22:00', end: ''),
    ]) {
      expect(isQuietNow(hours, 'UTC', now: now), isFalse);
    }
  });

  for (final fixture in (jsonDecode(
    File('../shared/fixtures/quiet-hours.json').readAsStringSync(),
  ) as List<dynamic>).cast<Map<String, dynamic>>()) {
    test(fixture['name'] as String, () {
      final location = tz.getLocation(fixture['timeZone'] as String);
      final now = tz.TZDateTime.from(
        DateTime.parse(fixture['now'] as String),
        location,
      );
      final rawHours = fixture['quietHours'] as Map<String, dynamic>?;
      final quietHours = rawHours == null
          ? null
          : QuietHours.fromJson(rawHours.cast<String, Object?>());

      if (fixture.containsKey('isQuiet')) {
        expect(
          isQuietNow(quietHours, fixture['timeZone'] as String, now: now),
          fixture['isQuiet'],
        );
      }
      if (fixture.containsKey('nextAllowed')) {
        expect(
          nextAllowedTime(
            quietHours!,
            fixture['timeZone'] as String,
            now: now,
          ).toIso8601String(),
          fixture['nextAllowed'],
        );
      }
    });
  }
}
