import 'dart:math';

import 'focus_schedule.dart';

export 'focus_schedule.dart';

class FocusReminder {
  const FocusReminder({
    required this.id,
    required this.title,
    required String contextSlug,
    this.dueAt,
    this.status = 'open',
    this.isOrder = false,
    this.shipBy,
  }) : contextSlug = contextSlug == 'side_gig' || contextSlug == 'side-gig'
           ? 'sidegig'
           : contextSlug;
  final String id, title, status;

  /// 'work' or 'sidegig' (preview data uses 'side_gig'; normalised here).
  final String contextSlug;
  final DateTime? dueAt;

  /// Orders carry a ship-by DATE (YYYY-MM-DD, account calendar day).
  final String? shipBy;
  final bool isOrder;
  bool get eligible =>
      (contextSlug == 'work' || contextSlug == 'sidegig') &&
      (status == 'open' || status == 'snoozed');
  String get contextName => contextSlug == 'work' ? 'Work' : 'Side Gig';
  FocusDeadline get deadline =>
      FocusDeadline(dueAt: dueAt, shipBy: shipBy, isOrder: isOrder);
}

/// The reminder's real deadline. Focus planning never changes it; it only
/// drives the "Due ..." line and the "after the due time" warning.
class FocusDeadline {
  const FocusDeadline({this.dueAt, this.shipBy, this.isOrder = false});
  final DateTime? dueAt;
  final String? shipBy;
  final bool isOrder;
  bool get isShipBy => shipBy != null;
  bool get exists => isShipBy || dueAt != null;

  /// "Due Fri, Oct 23 · 4 PM", "Ship by Fri, Oct 23", or '' when none.
  String label(String timezone) {
    if (isShipBy) return 'Ship by ${focusShortDate(shipBy!)}';
    if (dueAt == null) return '';
    final parts = focusLocalParts(dueAt!, timezone);
    final dayOnly = parts.time == '23:59';
    return 'Due ${focusShortDate(parts.date)}${dayOnly ? '' : ' · ${focusTime12(parts.time)}'}';
  }

  /// True when an occurrence starting at [startsAt] is after the deadline.
  /// A ship-by date is the end of that calendar day in the account timezone.
  bool isBefore(DateTime startsAt, String timezone) {
    if (isShipBy) {
      return focusLocalDate(startsAt, timezone).compareTo(shipBy!) > 0;
    }
    return dueAt != null && startsAt.isAfter(dueAt!);
  }
}

class FocusHighlight {
  const FocusHighlight({
    required this.title,
    required this.contextSlug,
    this.reminderId,
  });
  final String? reminderId;
  final String title, contextSlug;
  factory FocusHighlight.fromMap(Map<String, dynamic> row) => FocusHighlight(
    reminderId: row['reminder_id'] as String?,
    title: row['reminder_title'] as String,
    contextSlug: row['context_slug'] as String,
  );
}

class FocusSession {
  const FocusSession({
    required this.id,
    required this.title,
    required this.contextSlug,
    required this.durationMinutes,
    required this.startedAt,
    required this.updatedAt,
    this.reminderId,
    this.lastResumedAt,
    this.pausedAt,
    this.finishedAt,
    this.intendedOutcome,
    this.outcome,
    this.nextStep,
    this.elapsedSeconds = 0,
  });
  final String id, title, contextSlug;
  final String? reminderId, intendedOutcome, outcome, nextStep;
  final int durationMinutes;
  final num elapsedSeconds;
  final DateTime startedAt, updatedAt;
  final DateTime? lastResumedAt, pausedAt, finishedAt;
  bool get paused => pausedAt != null;
  int remainingSeconds(DateTime serverNow) {
    final segment = !paused && finishedAt == null && lastResumedAt != null
        ? max(0, serverNow.difference(lastResumedAt!).inMilliseconds / 1000)
        : 0;
    final elapsed = (elapsedSeconds + segment).clamp(0, durationMinutes * 60);
    return (durationMinutes * 60 - elapsed).ceil();
  }

  bool awaitingFinish(DateTime serverNow) =>
      finishedAt == null && remainingSeconds(serverNow) == 0;
  factory FocusSession.fromMap(Map<String, dynamic> row) => FocusSession(
    id: row['id'] as String,
    reminderId: row['reminder_id'] as String?,
    title: row['reminder_title'] as String,
    contextSlug: row['context_slug'] as String,
    durationMinutes: row['duration_minutes'] as int,
    elapsedSeconds: row['elapsed_seconds'] as num? ?? 0,
    startedAt: DateTime.parse(row['started_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
    lastResumedAt: _date(row['last_resumed_at']),
    pausedAt: _date(row['paused_at']),
    finishedAt: _date(row['finished_at']),
    intendedOutcome: row['intended_outcome'] as String?,
    outcome: row['outcome'] as String?,
    nextStep: row['next_step'] as String?,
  );
  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
  Map<String, dynamic> toMap() => {
    'id': id,
    'reminder_id': reminderId,
    'reminder_title': title,
    'context_slug': contextSlug,
    'duration_minutes': durationMinutes,
    'elapsed_seconds': elapsedSeconds,
    'started_at': startedAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'last_resumed_at': lastResumedAt?.toIso8601String(),
    'paused_at': pausedAt?.toIso8601String(),
    'finished_at': finishedAt?.toIso8601String(),
    'intended_outcome': intendedOutcome,
    'outcome': outcome,
    'next_step': nextStep,
  };
}

class FocusTimeItem {
  const FocusTimeItem({
    required this.id,
    required this.contextSlug,
    required this.weekdays,
    required this.startTime,
    required this.budgetMinutes,
    this.label,
    this.enabled = true,
  });
  final String id, contextSlug, startTime;
  final String? label;
  final List<int> weekdays;
  final int budgetMinutes;
  final bool enabled;
  String get contextName => contextSlug == 'work' ? 'Work' : 'Side Gig';
  String get title => (label == null || label!.trim().isEmpty)
      ? focusDaysSummary(weekdays)
      : label!;
  String get summary =>
      '${focusDaysSummary(weekdays)} · ${focusTime12(startTime)} · $budgetMinutes min';
  factory FocusTimeItem.fromMap(Map<String, dynamic> row) => FocusTimeItem(
    id: row['id'] as String,
    label: row['label'] as String?,
    contextSlug: row['context_slug'] as String,
    weekdays: [
      for (final d in row['weekdays'] as List) (d as num).toInt(),
    ],
    startTime: row['start_time'] as String,
    budgetMinutes: (row['budget_minutes'] as num).toInt(),
    enabled: row['enabled'] as bool? ?? true,
  );
}

class FocusAssignment {
  const FocusAssignment({
    required this.id,
    required this.title,
    required this.contextSlug,
    required this.localDate,
    required this.startTime,
    required this.plannedMinutes,
    this.reminderId,
    this.focusTimeId,
    this.focusTimeLabel,
    this.position = 0,
    this.state = 'planned',
    this.dueAt,
    this.shipBy,
  });
  final String id, title, contextSlug, localDate, startTime, state;
  final String? reminderId, focusTimeId, focusTimeLabel, shipBy;
  final int plannedMinutes, position;
  final DateTime? dueAt;
  bool get planned => state == 'planned';
  FocusDeadline get deadline => FocusDeadline(dueAt: dueAt, shipBy: shipBy);
  factory FocusAssignment.fromMap(Map<String, dynamic> row) => FocusAssignment(
    id: row['id'] as String,
    reminderId: row['reminder_id'] as String?,
    title: row['reminder_title'] as String? ?? '',
    contextSlug: row['context_slug'] as String? ?? 'work',
    focusTimeId: row['focus_time_id'] as String?,
    focusTimeLabel: row['focus_time_label'] as String?,
    localDate: (row['local_date'] as String).substring(0, 10),
    startTime: row['start_time'] as String,
    plannedMinutes: (row['planned_minutes'] as num).toInt(),
    position: (row['position'] as num?)?.toInt() ?? 0,
    state: row['state'] as String? ?? 'planned',
    dueAt: row['due_at'] == null ? null : DateTime.parse(row['due_at'] as String),
    shipBy: row['ship_by'] == null
        ? null
        : (row['ship_by'] as String).substring(0, 10),
  );
}

/// Planned work that shares one derived occurrence: (focus time, date, time).
class FocusOccurrence {
  const FocusOccurrence({
    required this.key,
    required this.localDate,
    required this.startTime,
    required this.tasks,
    required this.budget,
    required this.contextSlug,
    required this.startsAt,
    this.time,
    required this.missed,
  });
  final String key, localDate, startTime, contextSlug;
  final FocusTimeItem? time;
  final List<FocusAssignment> tasks;
  final int budget;
  final DateTime startsAt;
  final bool missed;
  int get sum => tasks.fold(0, (s, a) => s + a.plannedMinutes);
  bool get overBudget => time != null && sum > budget;
  String get name => focusOccurrenceName(localDate, startTime);
  String get contextName => contextSlug == 'work' ? 'Work' : 'Side Gig';
  String get weekdayName => focusIsoDayName(focusIsoWeekday(localDate));
}

/// A selectable slot in "Work on this".
class FocusPlanOption {
  const FocusPlanOption({
    required this.time,
    required this.localDate,
    required this.startsAt,
  });
  final FocusTimeItem time;
  final String localDate;
  final DateTime startsAt;
  String get key => '${time.id}|$localDate';
  String get startTime => time.startTime;
  String get name => focusOccurrenceName(localDate, time.startTime);
  String get secondary =>
      '${focusShortDate(localDate)}${(time.label ?? '').trim().isEmpty ? '' : ' · ${time.label}'}';
}

class FocusState {
  const FocusState({
    required this.serverNow,
    required this.localDate,
    this.timezone = 'UTC',
    this.highlight,
    this.activeSession,
    this.preferredMinutes = 25,
    this.highlightNextStep,
    this.sessionNextStep,
    this.focusTimes = const [],
    this.assignments = const [],
    this.planning = false,
    this.preferences = false,
  });
  final DateTime serverNow;
  final String localDate, timezone;
  final FocusHighlight? highlight;
  final FocusSession? activeSession;

  /// Saved usual length. Always 25 on the pre-0015 fallback path.
  final int preferredMinutes;
  final String? highlightNextStep, sessionNextStep;
  final List<FocusTimeItem> focusTimes;
  final List<FocusAssignment> assignments;

  /// False when `get_focus_dashboard_v2` is not deployed yet (MVP behaviour:
  /// no Focus times or preference UI).
  final bool planning;

  /// True when the dashboard reports a saved/default usual length (0015).
  final bool preferences;

  List<FocusTimeItem> timesFor(String slug) => [
    for (final t in focusTimes)
      if (t.enabled && t.contextSlug == slug) t,
  ];

  factory FocusState.fromMap(Map<String, dynamic> row) {
    final v2 = row.containsKey('focus_times');
    return FocusState(
      serverNow: DateTime.parse(row['server_now'] as String),
      localDate: row['local_date'] as String,
      timezone: row['timezone'] as String? ?? 'UTC',
      highlight: row['highlight'] == null
          ? null
          : FocusHighlight.fromMap(
              Map<String, dynamic>.from(row['highlight'] as Map),
            ),
      activeSession: row['active_session'] == null
          ? null
          : FocusSession.fromMap(
              Map<String, dynamic>.from(row['active_session'] as Map),
            ),
      preferredMinutes: (row['preferred_minutes'] as num?)?.toInt() ?? 25,
      highlightNextStep: row['highlight_next_step'] as String?,
      sessionNextStep: row['session_next_step'] as String?,
      planning: v2,
      preferences: row.containsKey('preferred_minutes'),
      focusTimes: !v2
          ? const []
          : [
              for (final t in row['focus_times'] as List)
                FocusTimeItem.fromMap(Map<String, dynamic>.from(t as Map)),
            ],
      assignments: !v2
          ? const []
          : [
              for (final a in (row['assignments'] as List? ?? const []))
                FocusAssignment.fromMap(Map<String, dynamic>.from(a as Map)),
            ],
    );
  }

  /// Planned work grouped into derived occurrences, oldest start first.
  List<FocusOccurrence> occurrences(DateTime now) {
    final groups = <String, List<FocusAssignment>>{};
    for (final a in assignments) {
      if (!a.planned || a.reminderId == null) continue;
      final time = focusTimeHm(a.startTime);
      groups.putIfAbsent('${a.focusTimeId ?? 'one'}|${a.localDate}|$time', () => []).add(a);
    }
    final out = <FocusOccurrence>[];
    groups.forEach((key, list) {
      list.sort((x, y) => x.position.compareTo(y.position));
      final first = list.first;
      final time = focusTimes.where((t) => t.id == first.focusTimeId).firstOrNull;
      final budget = time?.budgetMinutes ?? 0;
      final start = focusTimeHm(first.startTime);
      out.add(
        FocusOccurrence(
          key: key,
          localDate: first.localDate,
          startTime: start,
          tasks: List.unmodifiable(list),
          budget: time?.budgetMinutes ?? list.fold(0, (s, a) => s + a.plannedMinutes),
          contextSlug: time?.contextSlug ?? first.contextSlug,
          time: time,
          startsAt: focusOccurrenceStart(first.localDate, start, timezone),
          missed: isOccurrenceMissed(
            localDate: first.localDate,
            startTime: start,
            budgetMinutes: budget,
            plannedMinutes: [for (final a in list) a.plannedMinutes],
            now: now,
            timeZone: timezone,
          ),
        ),
      );
    });
    out.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return out;
  }

  /// The next [limit] slots of enabled Focus times for a context.
  List<FocusPlanOption> planOptions(String slug, DateTime now, {int limit = 4}) {
    final out = <FocusPlanOption>[];
    for (final t in timesFor(slug)) {
      for (final w in nextFocusOccurrences(
        weekdays: t.weekdays,
        startTime: t.startTime,
        budgetMinutes: t.budgetMinutes,
        now: now,
        timeZone: timezone,
        count: limit,
      )) {
        out.add(FocusPlanOption(time: t, localDate: w.localDate, startsAt: w.startsAt));
      }
    }
    out.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return out.take(limit).toList();
  }
}

String newFocusId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
