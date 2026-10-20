import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:ezyreminder/features/focus/focus_schedule.dart';

/// Shared with lib/focus.ts: design/focus-time-fixtures.json defines the outcomes.
Map<String, dynamic> _fixtures() {
  final file = File('../design/focus-time-fixtures.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

DateTime _t(String iso) => DateTime.parse(iso);

void main() {
  test('legacy account timezone names resolve like Postgres, not as UTC', () {
    // user_settings.timezone is free text; 'EST' is fixed UTC-5 in Postgres.
    expect(
      focusOccurrenceStart('2026-10-19', '21:00', 'EST').toUtc(),
      DateTime.utc(2026, 10, 20, 2),
    );
    expect(
      focusOccurrenceStart('2026-10-19', '21:00', 'US/Eastern').toUtc(),
      DateTime.utc(2026, 10, 20, 1),
    );
  });
  setUpAll(tzdata.initializeTimeZones);
  final f = _fixtures();

  group('occurrenceStart fixtures', () {
    for (final c
        in (f['occurrenceStart'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final got = focusOccurrenceStart(
          c['localDate'] as String,
          c['startTime'] as String,
          c['timeZone'] as String,
        );
        expect(
          got.isAtSameMomentAs(_t(c['expected'] as String)),
          isTrue,
          reason: '${c['description']} got ${got.toIso8601String()}',
        );
      });
    }
  });

  group('nextOccurrences fixtures', () {
    for (final c
        in (f['nextOccurrences'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final time = c['time'] as Map<String, dynamic>;
        final got = nextFocusOccurrences(
          weekdays: (time['weekdays'] as List).cast<int>(),
          startTime: time['start_time'] as String,
          budgetMinutes: time['budget_minutes'] as int,
          now: _t(c['now'] as String),
          timeZone: c['timeZone'] as String,
          count: c['count'] as int,
        );
        final expected = (c['expected'] as List).cast<Map<String, dynamic>>();
        expect(got.length, expected.length, reason: c['description'] as String);
        for (var i = 0; i < expected.length; i++) {
          expect(got[i].localDate, expected[i]['localDate']);
          expect(
            got[i].startsAt.isAtSameMomentAs(
              _t(expected[i]['startsAt'] as String),
            ),
            isTrue,
            reason: 'start $i got ${got[i].startsAt}',
          );
          expect(
            got[i].endsAt.isAtSameMomentAs(_t(expected[i]['endsAt'] as String)),
            isTrue,
            reason: 'end $i got ${got[i].endsAt}',
          );
        }
      });
    }
  });

  group('missed fixtures', () {
    for (final c in (f['missed'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final o = c['occurrence'] as Map<String, dynamic>;
        expect(
          isOccurrenceMissed(
            localDate: o['localDate'] as String,
            startTime: o['startTime'] as String,
            budgetMinutes: o['budgetMinutes'] as int,
            plannedMinutes: (c['plannedMinutes'] as List).cast<int>(),
            now: _t(c['now'] as String),
            timeZone: c['timeZone'] as String,
          ),
          c['expected'] as bool,
          reason: c['description'] as String,
        );
      });
    }
  });

  group('nextWeekdayAfter fixtures', () {
    for (final c
        in (f['nextWeekdayAfter'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        expect(
          nextWeekdayAfter(c['localDate'] as String, c['isoWeekday'] as int),
          c['expected'],
        );
      });
    }
  });

  test('fixture groups are all exercised', () {
    expect(
      f.keys.toSet().containsAll([
        'occurrenceStart',
        'nextOccurrences',
        'missed',
        'nextWeekdayAfter',
      ]),
      isTrue,
    );
  });

  test('display helpers match the prototype', () {
    expect(focusOccurrenceName('2026-10-29', '19:00:00'), 'Thursday · 7 PM');
    expect(focusOccurrenceName('2026-10-27', '12:30:00'), 'Tuesday · 12:30 PM');
    expect(focusShortDate('2026-10-24'), 'Sat, Oct 24');
    expect(focusDaysSummary([5, 3, 4, 2, 1]), 'Weekdays');
    expect(focusDaysSummary([4]), 'Thursday');
    expect(focusDaysSummary([1, 3]), 'Mon, Wed');
    expect(addLocalDays('2026-12-31', 1), '2027-01-01');
    expect(focusIsoWeekday('2026-11-01'), 7);
  });
}
