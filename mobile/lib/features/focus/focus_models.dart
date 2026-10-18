import 'dart:math';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class FocusReminder {
  const FocusReminder({
    required this.id,
    required this.title,
    required this.contextSlug,
    this.dueAt,
    this.status = 'open',
  });
  final String id, title, contextSlug, status;
  final DateTime? dueAt;
  bool get eligible =>
      (contextSlug == 'work' ||
          contextSlug == 'sidegig' ||
          contextSlug == 'side-gig') &&
      (status == 'open' || status == 'snoozed');
  String get contextName => contextSlug == 'work' ? 'Work' : 'Side Gig';
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

class FocusState {
  const FocusState({
    required this.serverNow,
    required this.localDate,
    this.timezone = 'UTC',
    this.highlight,
    this.activeSession,
  });
  final DateTime serverNow;
  final String localDate, timezone;
  final FocusHighlight? highlight;
  final FocusSession? activeSession;
  factory FocusState.fromMap(Map<String, dynamic> row) => FocusState(
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
  );
}

bool _zonesReady = false;
String focusLocalDate(DateTime now, String timezone) {
  if (!_zonesReady) {
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }
  tz.Location location;
  try {
    location = tz.getLocation(timezone);
  } catch (_) {
    location = tz.UTC;
  }
  final local = tz.TZDateTime.from(now, location);
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String newFocusId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
