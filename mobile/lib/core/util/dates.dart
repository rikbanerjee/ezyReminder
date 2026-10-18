// Calendar and display helpers for the reminder list. These operate in the
// timezone carried by DateTime (device local or an explicit TZDateTime zone).
import 'package:timezone/timezone.dart';

DateTime _calendarDate(DateTime value, {int hour = 0, int minute = 0}) {
  if (value is TZDateTime) {
    return TZDateTime(
      value.location,
      value.year,
      value.month,
      value.day,
      hour,
      minute,
    );
  }
  return DateTime(value.year, value.month, value.day, hour, minute);
}

/// Which section an effective due time belongs to, relative to [now].
String bucketFor(DateTime? due, {DateTime? now}) {
  if (due == null) return 'nodate';
  final current = now ?? DateTime.now();
  final today = _calendarDate(current);
  final tomorrow = _addCalendarDays(today, 1);
  if (due.isBefore(current)) return 'overdue';
  if (due.isBefore(tomorrow)) return 'today';
  return 'upcoming';
}

/// Whether [date] falls on the local calendar day of [now].
bool isSameLocalDay(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  return _calendarDate(date).isAtSameMomentAs(_calendarDate(current));
}

/// Compact label such as “in 2h”, “2h overdue”, or “Tomorrow 9 AM”.
String relativeDue(DateTime? due, {DateTime? now}) {
  if (due == null) return '';
  final current = now ?? DateTime.now();
  final diffMinutes = (due.difference(current).inMilliseconds.abs() / 60000)
      .round();
  final past = due.isBefore(current);
  if (diffMinutes < 60) {
    final minutes = diffMinutes < 1 ? 1 : diffMinutes;
    return past
        ? '$minutes'
              'm overdue'
        : 'in ${minutes}m';
  }
  if (diffMinutes < 60 * 24 && isSameLocalDay(due, now: current)) {
    final hours = (diffMinutes / 60).round();
    return past
        ? '$hours'
              'h overdue'
        : 'in ${hours}h';
  }

  final dayDiff = _calendarDayOrdinal(due) - _calendarDayOrdinal(current);
  final time = _formatTime(due);
  if (dayDiff == 0) return time;
  if (dayDiff == 1) return 'Tomorrow $time';
  if (dayDiff == -1) return 'Yesterday $time';
  if (dayDiff > 1 && dayDiff < 7) return '${_weekdays[due.weekday - 1]} $time';
  return '${_months[due.month - 1]} ${due.day} $time';
}

/// Returns a snooze target, preserving local calendar wall time for day-based
/// presets across daylight-saving changes.
DateTime snoozeTarget(String preset, {DateTime? now}) {
  final current = now ?? DateTime.now();
  switch (preset) {
    case '1h':
      return _at(current, hour: current.hour + 1);
    case 'tonight':
      var target = _at(current, hour: 19);
      if (!target.isAfter(current)) target = _addCalendarDays(target, 1);
      return target;
    case 'tomorrow':
      return _at(_addCalendarDays(current, 1), hour: 9);
    case 'nextweek':
      return _at(_addCalendarDays(current, 7), hour: 9);
    default:
      throw ArgumentError.value(preset, 'preset', 'Unknown snooze preset');
  }
}

DateTime _at(DateTime value, {required int hour, int minute = 0}) =>
    _calendarDate(value, hour: hour, minute: minute);

DateTime _addCalendarDays(DateTime value, int days) {
  final date = DateTime.utc(value.year, value.month, value.day + days);
  if (value is TZDateTime) {
    return TZDateTime(
      value.location,
      date.year,
      date.month,
      date.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
  return DateTime(
    value.year,
    value.month,
    value.day + days,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}

int _calendarDayOrdinal(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

String _formatTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute == 0
      ? ''
      : ':${value.minute.toString().padLeft(2, '0')}';
  return '$hour$minute ${value.hour < 12 ? 'AM' : 'PM'}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
