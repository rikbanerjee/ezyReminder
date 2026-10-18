import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Wall-clock quiet-hours window. An absent or partial window is inactive.
class QuietHours {
  const QuietHours({this.start, this.end});

  final String? start;
  final String? end;

  factory QuietHours.fromJson(Map<String, Object?> json) =>
      QuietHours(start: json['start'] as String?, end: json['end'] as String?);
}

bool _timeZoneDatabaseInitialized = false;

/// Initializes the bundled IANA database once before timezone operations.
void initializeTimeZones() {
  if (_timeZoneDatabaseInitialized) return;
  tzdata.initializeTimeZones();
  _timeZoneDatabaseInitialized = true;
}

/// True when [timeZone] is a recognized IANA timezone identifier.
bool isValidTimeZone(String timeZone) {
  initializeTimeZones();
  try {
    tz.getLocation(timeZone);
    return true;
  } catch (_) {
    return false;
  }
}

/// True when [now] falls inside the configured wall-clock quiet window.
bool isQuietNow(QuietHours? quietHours, String timeZone, {DateTime? now}) {
  if (quietHours?.start?.isNotEmpty != true ||
      quietHours?.end?.isNotEmpty != true) {
    return false;
  }
  final start = _parseHm(quietHours!.start!);
  final end = _parseHm(quietHours.end!);
  final startMinute = start.$1 * 60 + start.$2;
  final endMinute = end.$1 * 60 + end.$2;
  if (startMinute == endMinute) return false;
  final local = _localParts(now ?? DateTime.now(), timeZone);
  final currentMinute = local.$4 * 60 + local.$5;
  if (startMinute < endMinute) {
    return currentMinute >= startMinute && currentMinute < endMinute;
  }
  return currentMinute >= startMinute || currentMinute < endMinute;
}

/// Resolves the next end wall time to a UTC instant.
///
/// During fall-back, use the first still-future occurrence of the ambiguous
/// wall time. If both occurrences have passed, advance to tomorrow. During a
/// spring-forward gap, shift the requested time forward by the gap duration.
DateTime nextAllowedTime(
  QuietHours quietHours,
  String timeZone, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final end = _parseHm(quietHours.end ?? '00:00');
  final local = _localParts(current, timeZone);
  var candidate = _localToUtc(
    local.$1,
    local.$2,
    local.$3,
    end.$1,
    end.$2,
    timeZone,
    after: current,
  );
  if (!candidate.isAfter(current)) {
    final tomorrow = DateTime.utc(local.$1, local.$2, local.$3 + 1);
    candidate = _localToUtc(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      end.$1,
      end.$2,
      timeZone,
    );
  }
  return candidate.toUtc();
}

(int, int) _parseHm(String value) {
  final parts = value.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return (hour, minute);
}

(int, int, int, int, int) _localParts(DateTime instant, String timeZone) {
  initializeTimeZones();
  final local = tz.TZDateTime.from(instant, tz.getLocation(timeZone));
  return (local.year, local.month, local.day, local.hour, local.minute);
}

DateTime _localToUtc(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  String timeZone, {
  DateTime? after,
}) {
  initializeTimeZones();
  final location = tz.getLocation(timeZone);
  final wallTime = DateTime.utc(year, month, day, hour, minute);
  final offsets = <int>{};
  for (var hours = -48; hours <= 48; hours += 6) {
    offsets.add(
      tz.TZDateTime.from(
        wallTime.add(Duration(hours: hours)),
        location,
      ).timeZoneOffset.inMilliseconds,
    );
  }

  final candidates = offsets
      .map((offset) => wallTime.subtract(Duration(milliseconds: offset)))
      .toList();
  final matches = candidates.where((candidate) {
    final local = tz.TZDateTime.from(candidate, location);
    return local.year == year &&
        local.month == month &&
        local.day == day &&
        local.hour == hour &&
        local.minute == minute;
  }).toList()..sort();

  if (matches.isNotEmpty) {
    final future = after == null
        ? matches
        : matches.where((candidate) => candidate.isAfter(after)).toList();
    return (future.isNotEmpty ? future : matches).first;
  }

  final afterGap =
      candidates
          .map(
            (candidate) => (candidate, tz.TZDateTime.from(candidate, location)),
          )
          .where((entry) {
            final local = entry.$2;
            return DateTime.utc(
              local.year,
              local.month,
              local.day,
              local.hour,
              local.minute,
            ).isAfter(wallTime);
          })
          .toList()
        ..sort((a, b) {
          final aLocal = a.$2;
          final bLocal = b.$2;
          final wallCompare =
              DateTime.utc(
                aLocal.year,
                aLocal.month,
                aLocal.day,
                aLocal.hour,
                aLocal.minute,
              ).compareTo(
                DateTime.utc(
                  bLocal.year,
                  bLocal.month,
                  bLocal.day,
                  bLocal.hour,
                  bLocal.minute,
                ),
              );
          return wallCompare != 0 ? wallCompare : a.$1.compareTo(b.$1);
        });
  return afterGap.isNotEmpty ? afterGap.first.$1 : candidates.first;
}
