import 'dart:math';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Dart port of the occurrence rules in lib/focus.ts. Both implementations must
// pass design/focus-time-fixtures.json. Occurrences are derived, never stored:
// an occurrence is (focus_time_id, local_date) and its UTC start comes from the
// ACCOUNT timezone (user_settings.timezone), never the device zone.

bool _zonesReady = false;

/// Account timezone lookup with the tz database initialised on first use.
/// Unknown names fall back to UTC so a bad setting never crashes Focus.
tz.Location focusLocation(String timezone) {
  if (!_zonesReady) {
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }
  try {
    return tz.getLocation(timezone);
  } catch (_) {
    return tz.UTC;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _dateKey(int y, int m, int d) => '$y-${_two(m)}-${_two(d)}';

/// Calendar key in the account timezone, independent of the device timezone.
String focusLocalDate(DateTime now, String timezone) {
  final local = tz.TZDateTime.from(now, focusLocation(timezone));
  return _dateKey(local.year, local.month, local.day);
}

/// Account-local date key and "HH:MM" of an instant.
({String date, String time}) focusLocalParts(DateTime instant, String timezone) {
  final local = tz.TZDateTime.from(instant, focusLocation(timezone));
  return (
    date: _dateKey(local.year, local.month, local.day),
    time: '${_two(local.hour)}:${_two(local.minute)}',
  );
}

List<int> _parseDate(String localDate) {
  final parts = localDate.split('-').map(int.parse).toList();
  return [parts[0], parts[1], parts[2]];
}

/// Calendar arithmetic on a YYYY-MM-DD key (no timezone involved).
String addLocalDays(String localDate, int days) {
  final p = _parseDate(localDate);
  final d = DateTime.utc(p[0], p[1], p[2] + days);
  return _dateKey(d.year, d.month, d.day);
}

/// ISO weekday of a YYYY-MM-DD key: 1 = Monday .. 7 = Sunday.
int focusIsoWeekday(String localDate) {
  final p = _parseDate(localDate);
  return DateTime.utc(p[0], p[1], p[2]).weekday;
}

/// First date strictly after [localDate] that falls on [isoWeekday].
String nextWeekdayAfter(String localDate, int isoWeekday) {
  final delta = ((isoWeekday - focusIsoWeekday(localDate) + 6) % 7) + 1;
  return addLocalDays(localDate, delta);
}

int _offsetMs(int instantMs, tz.Location location) =>
    location.timeZone(instantMs).offset.inMilliseconds;

/// UTC instant of a wall-clock time on an account-local date. A time inside a
/// spring-forward gap shifts forward by the gap (02:30 -> 03:30); a repeated
/// autumn time resolves to its first instance.
DateTime focusOccurrenceStart(
  String localDate,
  String startTime,
  String timeZone,
) {
  final location = focusLocation(timeZone);
  final p = _parseDate(localDate);
  final t = startTime.split(':').map((s) => int.tryParse(s) ?? 0).toList();
  final hh = t.isNotEmpty ? t[0] : 0;
  final mm = t.length > 1 ? t[1] : 0;
  final ss = t.length > 2 ? t[2] : 0;
  final wall = DateTime.utc(p[0], p[1], p[2], hh, mm, ss).millisecondsSinceEpoch;
  const day = 86400000;
  final before = _offsetMs(wall - day, location);
  final after = _offsetMs(wall + day, location);
  final valid = <int>{wall - before, wall - after}
      .where((utc) => _offsetMs(utc, location) == wall - utc)
      .toList();
  if (valid.isNotEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(valid.reduce(min), isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(wall - before, isUtc: true);
}

class FocusOccurrenceWindow {
  const FocusOccurrenceWindow({
    required this.localDate,
    required this.startsAt,
    required this.endsAt,
  });
  final String localDate;
  final DateTime startsAt, endsAt;
}

/// Upcoming weekly occurrences on or after today's account-local date whose
/// start has not yet passed its budget (listed until `start + budget`).
List<FocusOccurrenceWindow> nextFocusOccurrences({
  required List<int> weekdays,
  required String startTime,
  required int budgetMinutes,
  required DateTime now,
  required String timeZone,
  required int count,
}) {
  final out = <FocusOccurrenceWindow>[];
  if (count <= 0 || weekdays.isEmpty) return out;
  final today = focusLocalDate(now, timeZone);
  for (var i = 0; i < count * 7 + 7 && out.length < count; i++) {
    final localDate = addLocalDays(today, i);
    if (!weekdays.contains(focusIsoWeekday(localDate))) continue;
    final startsAt = focusOccurrenceStart(localDate, startTime, timeZone);
    final endsAt = startsAt.add(Duration(minutes: budgetMinutes));
    if (endsAt.isAfter(now)) {
      out.add(
        FocusOccurrenceWindow(
          localDate: localDate,
          startsAt: startsAt,
          endsAt: endsAt,
        ),
      );
    }
  }
  return out;
}

/// Missed = still has planned work and `start + max(budget, sum(planned))` has
/// passed. Use `budgetMinutes: 0` for one-off assignments. Not a failure; it
/// only drives the recovery card.
bool isOccurrenceMissed({
  required String localDate,
  required String startTime,
  required int budgetMinutes,
  required List<int> plannedMinutes,
  required DateTime now,
  required String timeZone,
}) {
  if (plannedMinutes.isEmpty) return false;
  final total = plannedMinutes.fold<int>(0, (sum, m) => sum + m);
  final startsAt = focusOccurrenceStart(localDate, startTime, timeZone);
  final end = startsAt.add(Duration(minutes: max(budgetMinutes, total)));
  return !now.isBefore(end);
}

// ---------------------------------------------------------------------------
// Display helpers (account timezone; names match the prototype exactly).
// ---------------------------------------------------------------------------

const focusDayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const focusMonthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// ISO 1..7 to a full weekday name.
String focusIsoDayName(int iso) => focusDayNames[iso % 7];

/// "HH:MM[:SS]" to "7 PM" / "12:30 PM".
String focusTime12(String time) {
  final t = time.split(':').map((s) => int.tryParse(s) ?? 0).toList();
  final h = t[0];
  final m = t.length > 1 ? t[1] : 0;
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour${m == 0 ? '' : ':${_two(m)}'} ${h < 12 ? 'AM' : 'PM'}';
}

/// "HH:MM:SS" to "HH:MM" for pickers and RPC params.
String focusTimeHm(String time) {
  final p = time.split(':');
  return '${_two(int.tryParse(p[0]) ?? 0)}:${_two(p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0)}';
}

/// "Thursday · 7 PM" for a local date and start time.
String focusOccurrenceName(String localDate, String startTime) =>
    '${focusIsoDayName(focusIsoWeekday(localDate))} · ${focusTime12(startTime)}';

/// "Thu, Oct 29".
String focusShortDate(String localDate) {
  final p = _parseDate(localDate);
  final iso = focusIsoWeekday(localDate);
  return '${focusIsoDayName(iso).substring(0, 3)}, ${focusMonthNames[p[1] - 1]} ${p[2]}';
}

/// "Oct 29".
String focusMonthDay(String localDate) {
  final p = _parseDate(localDate);
  return '${focusMonthNames[p[1] - 1]} ${p[2]}';
}

/// "Weekdays", "Weekends", "Saturday" or "Mon, Wed".
String focusDaysSummary(List<int> days) {
  final sorted = [...days]..sort();
  final key = sorted.join(',');
  if (key == '1,2,3,4,5') return 'Weekdays';
  if (key == '6,7') return 'Weekends';
  if (sorted.length == 1) return focusIsoDayName(sorted.first);
  return sorted.map((n) => focusIsoDayName(n).substring(0, 3)).join(', ');
}
