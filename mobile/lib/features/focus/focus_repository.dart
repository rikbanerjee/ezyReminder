import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'focus_models.dart';

abstract interface class FocusRepository {
  Stream<void> get changes;
  Future<FocusState> load();
  Future<List<FocusReminder>> reminders();
  Future<String?> latestNextStep(String reminderId);
  Future<void> highlight(String? reminderId);
  Future<void> start(
    String id,
    FocusReminder reminder,
    int minutes,
    String? intent,
  );
  /// [intent] needs 0017; pass null when [FocusState.intents] is false.
  Future<void> startAssigned(
    String sessionId,
    FocusAssignment assignment,
    int minutes,
    String? intent,
  );
  Future<void> pause(FocusSession session);
  Future<void> resume(FocusSession session);
  Future<void> finish(FocusSession session, String outcome, String? nextStep);
  Future<void> savePreferredMinutes(int minutes);
  Future<void> saveFocusTime(FocusTimeDraft draft);
  Future<void> archiveFocusTime(String id);

  /// Undo for archive (0017): same id, so its planned work stays attached.
  Future<void> restoreFocusTime(String id, {required bool enabled});
  Future<void> assign(FocusAssignRequest request);
  Future<void> skip(String assignmentId);
  void dispose();
}

/// Values for `save_focus_time`. [id] is a client UUID kept across retries.
class FocusTimeDraft {
  const FocusTimeDraft({
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
}

/// Values for `assign_focus_work`. [id] is the idempotency id of this intent.
/// A null [focusTimeId] is a one-off "Pick another day" with [startTime].
class FocusAssignRequest {
  const FocusAssignRequest({
    required this.id,
    required this.reminder,
    required this.localDate,
    required this.startTime,
    required this.plannedMinutes,
    this.focusTimeId,
  });
  final String id, localDate, startTime;
  final FocusReminder reminder;
  final String? focusTimeId;
  final int plannedMinutes;
}

/// Remembers that `get_focus_dashboard_v2` is not deployed, so a project that
/// has not applied 0015/0016 is probed at most once a minute.
class FocusDashboardGate {
  FocusDashboardGate({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  DateTime? _missingSince;
  bool get shouldProbe =>
      _missingSince == null ||
      _clock().difference(_missingSince!) > const Duration(minutes: 1);
  void markMissing() => _missingSince = _clock();
  void markPresent() => _missingSince = null;
}

/// Loads the dashboard, falling back to the pre-0015 `get_focus_state` (MVP
/// behaviour, no Focus times or preference UI, no error) when v2 is missing.
Future<FocusState> loadFocusDashboard(
  Future<Object?> Function(String function) rpc,
  FocusDashboardGate gate,
) async {
  if (gate.shouldProbe) {
    try {
      final row = await rpc('get_focus_dashboard_v2');
      gate.markPresent();
      return FocusState.fromMap(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (e) {
      if (!focusFunctionMissing(e)) rethrow;
      gate.markMissing();
    }
  }
  return FocusState.fromMap(
    Map<String, dynamic>.from(await rpc('get_focus_state') as Map),
  );
}

/// PostgREST reports an undeployed function as PGRST202 (or 42883 from
/// Postgres). Used to fall back to the pre-0015 Focus MVP without an error.
bool focusFunctionMissing(Object error) =>
    error is PostgrestException &&
    (error.code == 'PGRST202' || error.code == '42883');

class SupabaseFocusRepository implements FocusRepository {
  SupabaseFocusRepository(this.client) {
    final user = client.auth.currentUser?.id;
    PostgresChangeFilter? filter() => user == null
        ? null
        : PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user,
          );
    // Core channel: unchanged tables that exist on every deployment.
    _channel = client.channel('focus-${user ?? 'signed-out'}');
    for (final table in ['focus_sessions', 'focus_highlights', 'user_settings']) {
      _channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: filter(),
        callback: (_) => _emit(),
      );
    }
    _channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) _emit();
    });
    // Planning tables get their own channel: before migrations 0015/0016 are
    // applied they do not exist, and a failed subscription must never take
    // down the core channel.
    _planning = client.channel('focus-planning-${user ?? 'signed-out'}');
    for (final table in ['focus_times', 'focus_assignments', 'focus_preferences']) {
      _planning.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: filter(),
        callback: (_) => _emit(),
      );
    }
    _planning.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) _emit();
    });
  }
  final SupabaseClient client;
  final _changes = StreamController<void>.broadcast();
  late final RealtimeChannel _channel, _planning;
  final _gate = FocusDashboardGate();
  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<FocusState> load() => loadFocusDashboard(
    (function) async => await client.rpc(function),
    _gate,
  );

  @override
  Future<List<FocusReminder>> reminders() async {
    final rows = await client
        .from('reminders')
        .select('id,title,status,due_at,is_order,contexts!inner(slug),orders(ship_by)')
        .inFilter('status', ['open', 'snoozed'])
        .inFilter('contexts.slug', ['work', 'sidegig', 'side-gig'])
        .order('due_at', nullsFirst: false);
    return rows
        .map(
          (r) => FocusReminder(
            id: r['id'] as String,
            title: r['title'] as String,
            contextSlug: (r['contexts'] as Map)['slug'] as String,
            status: r['status'] as String,
            dueAt: r['due_at'] == null
                ? null
                : DateTime.parse(r['due_at'] as String),
            isOrder: r['is_order'] as bool? ?? false,
            shipBy: _shipBy(r['orders']),
          ),
        )
        .toList();
  }

  /// `orders` embeds as an object (1:1) but tolerate a list.
  static String? _shipBy(Object? orders) {
    final row = orders is List ? orders.firstOrNull : orders;
    final value = row is Map ? row['ship_by'] : null;
    return value is String && value.length >= 10 ? value.substring(0, 10) : null;
  }

  @override
  Future<String?> latestNextStep(String reminderId) async {
    final user = client.auth.currentUser?.id;
    if (user == null) throw StateError('Sign in to load your next step.');
    final rows = await client
        .from('focus_sessions')
        .select('next_step')
        .eq('user_id', user)
        .eq('reminder_id', reminderId)
        .not('finished_at', 'is', null)
        .order('finished_at', ascending: false)
        .order('id', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : rows.first['next_step'] as String?;
  }

  @override
  Future<void> highlight(String? reminderId) async {
    await client.rpc(
      'set_focus_highlight',
      params: {'p_reminder_id': reminderId},
    );
  }

  @override
  Future<void> start(
    String id,
    FocusReminder reminder,
    int minutes,
    String? intent,
  ) async {
    await client.rpc(
      'start_focus_session',
      params: {
        'p_id': id,
        'p_reminder_id': reminder.id,
        'p_duration_minutes': minutes,
        'p_intended_outcome': intent,
      },
    );
  }

  @override
  Future<void> startAssigned(
    String sessionId,
    FocusAssignment assignment,
    int minutes,
    String? intent,
  ) async {
    await client.rpc(
      'start_assigned_focus',
      params: {
        'p_session_id': sessionId,
        'p_assignment_id': assignment.id,
        'p_duration_minutes': minutes,
        // Before 0017 the RPC has no p_intended_outcome, so only send it when set.
        'p_intended_outcome': ?intent,
      },
    );
  }

  @override
  Future<void> savePreferredMinutes(int minutes) async {
    await client.rpc(
      'save_focus_preferences',
      params: {'p_preferred_minutes': minutes},
    );
  }

  @override
  Future<void> saveFocusTime(FocusTimeDraft d) async {
    await client.rpc(
      'save_focus_time',
      params: {
        'p_id': d.id,
        'p_label': (d.label ?? '').trim().isEmpty ? null : d.label!.trim(),
        'p_context_slug': d.contextSlug,
        'p_weekdays': d.weekdays,
        'p_start_time': d.startTime,
        'p_budget_minutes': d.budgetMinutes,
        'p_enabled': d.enabled,
      },
    );
  }

  @override
  Future<void> archiveFocusTime(String id) async {
    await client.rpc('archive_focus_time', params: {'p_id': id});
  }

  @override
  Future<void> restoreFocusTime(String id, {required bool enabled}) async {
    await client.rpc(
      'restore_focus_time',
      params: {'p_id': id, 'p_enabled': enabled},
    );
  }

  @override
  Future<void> assign(FocusAssignRequest r) async {
    await client.rpc(
      'assign_focus_work',
      params: {
        'p_id': r.id,
        'p_reminder_id': r.reminder.id,
        'p_focus_time_id': r.focusTimeId,
        'p_local_date': r.localDate,
        'p_start_time': r.startTime,
        'p_planned_minutes': r.plannedMinutes,
      },
    );
  }

  @override
  Future<void> skip(String assignmentId) async {
    await client.rpc('skip_focus_work', params: {'p_id': assignmentId});
  }

  Map<String, dynamic> _transition(FocusSession session) => {
    'p_id': session.id,
    'p_expected_updated_at': session.updatedAt.toIso8601String(),
  };
  @override
  Future<void> pause(FocusSession session) async {
    await client.rpc('pause_focus_session', params: _transition(session));
  }

  @override
  Future<void> resume(FocusSession session) async {
    await client.rpc('resume_focus_session', params: _transition(session));
  }

  @override
  Future<void> finish(
    FocusSession session,
    String outcome,
    String? nextStep,
  ) async {
    await client.rpc(
      'finish_focus_session',
      params: {
        ..._transition(session),
        'p_outcome': outcome,
        'p_next_step': nextStep,
      },
    );
  }

  @override
  void dispose() {
    unawaited(client.removeChannel(_channel));
    unawaited(client.removeChannel(_planning));
    unawaited(_changes.close());
  }
}

/// Preview data is kept separate from reminders: ending focus cannot complete a
/// reminder or ship an order. Supply the same repository to retain preview state.
/// It mirrors the server rules of 0015/0016 (one outstanding assignment per
/// reminder, atomic moves, review-on-finish) so widgets can be tested offline.
class DemoFocusRepository implements FocusRepository {
  DemoFocusRepository({
    required this.loadReminders,
    DateTime Function()? clock,
    this.timezone = 'UTC',
    this.planning = true,
    this.intents = true,
    List<FocusTimeItem> focusTimes = const [],
    List<FocusAssignment> assignments = const [],
    Map<String, String> nextSteps = const {},
    this.preferredMinutes = 25,
  }) : clock = clock ?? DateTime.now {
    for (final t in focusTimes) {
      times[t.id] = t;
    }
    for (final a in assignments) {
      this.assignments[a.id] = a;
    }
    seededNextSteps.addAll(nextSteps);
  }
  final Future<List<FocusReminder>> Function() loadReminders;
  final DateTime Function() clock;
  final String timezone;

  /// False simulates a project where 0015/0016 are not applied yet.
  final bool planning;

  /// False simulates 0016 without 0017 (no planned intents, no restore).
  final bool intents;
  int preferredMinutes;
  final _changes = StreamController<void>.broadcast();
  final Map<String, FocusHighlight> highlights = {};
  final Map<String, FocusSession> sessions = {};
  final Map<String, FocusTimeItem> times = {};
  final Map<String, FocusTimeItem> archivedTimes = {};
  final Map<String, FocusAssignment> assignments = {};
  final Map<String, String> sessionAssignment = {};
  final Map<String, String> seededNextSteps = {};

  /// Idempotency ledger: the ids each write received, so tests can assert that
  /// retries reuse the same id.
  final List<String> calls = [];
  bool failWrites = false;
  FocusSession? get active =>
      sessions.values.where((s) => s.finishedAt == null).firstOrNull;
  @override
  Stream<void> get changes => _changes.stream;
  void notifyRemoteChange() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _write() {
    if (failWrites) throw StateError('Connection lost');
  }

  @override
  Future<FocusState> load() async {
    final all = await loadReminders();
    final eligible = {for (final r in all.where((r) => r.eligible)) r.id: r};
    final rows = <FocusAssignment>[];
    for (final a in assignments.values) {
      if (a.state != 'planned' && a.state != 'in_progress') continue;
      final r = eligible[a.reminderId];
      // Mirrors the cancel trigger: planned work for an ineligible reminder disappears.
      if (a.state == 'planned' && r == null) continue;
      rows.add(
        FocusAssignment(
          id: a.id,
          reminderId: a.reminderId,
          title: r?.title ?? a.title,
          contextSlug: r?.contextSlug ?? a.contextSlug,
          focusTimeId: a.focusTimeId,
          focusTimeLabel: (times[a.focusTimeId] ?? archivedTimes[a.focusTimeId])?.label,
          localDate: a.localDate,
          startTime: a.startTime,
          plannedMinutes: a.plannedMinutes,
          position: a.position,
          state: a.state,
          dueAt: r?.dueAt,
          shipBy: r?.shipBy,
        ),
      );
    }
    rows.sort((a, b) {
      final c = '${a.localDate}${a.startTime}'.compareTo('${b.localDate}${b.startTime}');
      return c != 0 ? c : a.position.compareTo(b.position);
    });
    final date = focusLocalDate(clock(), timezone);
    final hi = highlights[date];
    final session = active;
    return FocusState(
      serverNow: clock().toUtc(),
      localDate: date,
      timezone: timezone,
      highlight: hi,
      activeSession: session,
      preferredMinutes: preferredMinutes,
      preferences: planning,
      planning: planning,
      intents: planning && intents,
      highlightNextStep: hi?.reminderId == null ? null : _latestStep(hi!.reminderId!),
      sessionNextStep: session?.reminderId == null ? null : _latestStep(session!.reminderId!),
      focusTimes: planning ? (times.values.toList()..sort((a, b) => a.startTime.compareTo(b.startTime))) : const [],
      assignments: planning ? rows : const [],
    );
  }

  @override
  Future<List<FocusReminder>> reminders() async =>
      (await loadReminders()).where((r) => r.eligible).toList();
  String? _latestStep(String reminderId) {
    final rows =
        sessions.values
            .where((s) => s.reminderId == reminderId && s.finishedAt != null)
            .toList()
          ..sort((a, b) {
            final time = b.finishedAt!.compareTo(a.finishedAt!);
            return time == 0 ? b.id.compareTo(a.id) : time;
          });
    return rows.isEmpty ? seededNextSteps[reminderId] : rows.first.nextStep;
  }

  @override
  Future<String?> latestNextStep(String reminderId) async => _latestStep(reminderId);

  Future<FocusReminder> _eligible(String id) async =>
      (await reminders()).firstWhere(
        (r) => r.id == id,
        orElse: () =>
            throw StateError('Choose an open Work or Side Gig reminder.'),
      );
  @override
  Future<void> highlight(String? reminderId) async {
    _write();
    final date = focusLocalDate(clock(), timezone);
    if (reminderId == null) {
      highlights.remove(date);
    } else {
      final r = await _eligible(reminderId);
      highlights[date] = FocusHighlight(
        title: r.title,
        contextSlug: r.contextSlug,
        reminderId: r.id,
      );
    }
    notifyRemoteChange();
  }

  FocusSession _newSession(
    String id,
    FocusReminder eligible,
    int minutes,
    String? intent,
  ) {
    final now = clock().toUtc();
    return FocusSession(
      id: id,
      reminderId: eligible.id,
      title: eligible.title,
      contextSlug: eligible.contextSlug,
      durationMinutes: minutes,
      intendedOutcome: intent,
      startedAt: now,
      updatedAt: now,
      lastResumedAt: now,
    );
  }

  @override
  Future<void> start(
    String id,
    FocusReminder reminder,
    int minutes,
    String? intent,
  ) async {
    calls.add('start:$id');
    _write();
    if (sessions.containsKey(id)) return;
    if (active != null) {
      throw StateError('Finish your current focus session first.');
    }
    final eligible = await _eligible(reminder.id);
    if (minutes < 1 || minutes > 180 || (intent?.length ?? 0) > 500) {
      throw ArgumentError('Invalid focus duration or intent');
    }
    sessions[id] = _newSession(id, eligible, minutes, intent);
    notifyRemoteChange();
  }

  @override
  Future<void> startAssigned(
    String sessionId,
    FocusAssignment assignment,
    int minutes,
    String? intent,
  ) async {
    calls.add('startAssigned:$sessionId');
    _write();
    if (sessions.containsKey(sessionId)) return;
    if (active != null) {
      throw StateError('Finish your current focus session first.');
    }
    final stored = assignments[assignment.id];
    if (stored == null) throw StateError('Assignment not found.');
    if (!stored.planned) {
      throw StateError('This plan is no longer available. Refresh and try again.');
    }
    if (minutes < 1 || minutes > 180) {
      throw ArgumentError('Use a duration of 1–180 minutes');
    }
    if (intent != null && (!intents || intent.length > 500)) {
      throw ArgumentError('Keep the outcome to 500 characters');
    }
    final eligible = await _eligible(stored.reminderId ?? '');
    final text = intent?.trim();
    sessions[sessionId] = _newSession(sessionId, eligible, minutes, text == null || text.isEmpty ? null : text);
    sessionAssignment[sessionId] = stored.id;
    assignments[stored.id] = _copy(stored, state: 'in_progress');
    notifyRemoteChange();
  }

  FocusAssignment _copy(
    FocusAssignment a, {
    String? state,
    String? localDate,
    int? position,
  }) => FocusAssignment(
    id: a.id,
    reminderId: a.reminderId,
    title: a.title,
    contextSlug: a.contextSlug,
    localDate: localDate ?? a.localDate,
    startTime: a.startTime,
    plannedMinutes: a.plannedMinutes,
    focusTimeId: a.focusTimeId,
    focusTimeLabel: a.focusTimeLabel,
    position: position ?? a.position,
    state: state ?? a.state,
    dueAt: a.dueAt,
    shipBy: a.shipBy,
  );

  void _change(
    FocusSession session, {
    bool? paused,
    String? outcome,
    String? nextStep,
  }) {
    _write();
    final stored = sessions[session.id];
    if (stored == null) throw StateError('Session no longer exists.');
    if (stored.finishedAt != null) return;
    if (outcome == null && stored.paused == paused) return;
    if (stored.updatedAt != session.updatedAt) {
      throw StateError('Session changed on another device. Refresh and retry.');
    }
    final now = clock().toUtc();
    if (paused == false && stored.remainingSeconds(now) == 0) {
      throw StateError('Time is up. Review this session.');
    }
    final segment = stored.lastResumedAt == null || stored.paused
        ? 0
        : now.difference(stored.lastResumedAt!).inMicroseconds / 1000000;
    final elapsed = (stored.elapsedSeconds + (segment < 0 ? 0 : segment)).clamp(
      0,
      stored.durationMinutes * 60,
    );
    sessions[stored.id] = FocusSession.fromMap({
      ...stored.toMap(),
      'elapsed_seconds': elapsed,
      'updated_at': now.isAfter(stored.updatedAt)
          ? now.toIso8601String()
          : stored.updatedAt
                .add(const Duration(microseconds: 1))
                .toIso8601String(),
      'last_resumed_at': outcome == null && paused == false
          ? now.toIso8601String()
          : null,
      'paused_at': outcome == null && paused == true
          ? now.toIso8601String()
          : null,
      'finished_at': outcome != null ? now.toIso8601String() : null,
      'outcome': outcome,
      'next_step': nextStep,
    });
    if (outcome != null) {
      final id = sessionAssignment[stored.id];
      final a = id == null ? null : assignments[id];
      if (a != null && a.state == 'in_progress') {
        assignments[a.id] = _copy(a, state: 'reviewed');
      }
    }
    notifyRemoteChange();
  }

  @override
  Future<void> pause(FocusSession session) async =>
      _change(session, paused: true);
  @override
  Future<void> resume(FocusSession session) async =>
      _change(session, paused: false);
  @override
  Future<void> finish(
    FocusSession session,
    String outcome,
    String? nextStep,
  ) async {
    if (!['finished', 'progress', 'interrupted'].contains(outcome) ||
        (nextStep?.length ?? 0) > 1000) {
      throw ArgumentError('Invalid session outcome');
    }
    _change(session, outcome: outcome, nextStep: nextStep);
  }

  @override
  Future<void> savePreferredMinutes(int minutes) async {
    _write();
    calls.add('pref:$minutes');
    if (minutes < 1 || minutes > 180) {
      throw ArgumentError('Use a duration of 1–180 minutes');
    }
    preferredMinutes = minutes;
    notifyRemoteChange();
  }

  @override
  Future<void> saveFocusTime(FocusTimeDraft d) async {
    calls.add('time:${d.id}');
    _write();
    if (d.weekdays.isEmpty ||
        d.budgetMinutes < 1 ||
        d.budgetMinutes > 180 ||
        !['work', 'sidegig'].contains(d.contextSlug)) {
      throw ArgumentError('Invalid focus time');
    }
    times[d.id] = FocusTimeItem(
      id: d.id,
      label: (d.label ?? '').trim().isEmpty ? null : d.label!.trim(),
      contextSlug: d.contextSlug,
      weekdays: ([...d.weekdays]..sort()),
      startTime: d.startTime.length == 5 ? '${d.startTime}:00' : d.startTime,
      budgetMinutes: d.budgetMinutes,
      enabled: d.enabled,
    );
    notifyRemoteChange();
  }

  @override
  Future<void> archiveFocusTime(String id) async {
    _write();
    calls.add('archive:$id');
    final t = times.remove(id);
    if (t != null) archivedTimes[id] = t;
    notifyRemoteChange();
  }

  @override
  Future<void> restoreFocusTime(String id, {required bool enabled}) async {
    _write();
    calls.add('restore:$id');
    if (!intents) throw StateError('restore_focus_time is not deployed');
    final t = archivedTimes.remove(id);
    if (t == null) {
      if (times.containsKey(id)) return;
      throw StateError('Focus time not found');
    }
    times[id] = FocusTimeItem(
      id: t.id,
      label: t.label,
      contextSlug: t.contextSlug,
      weekdays: t.weekdays,
      startTime: t.startTime,
      budgetMinutes: t.budgetMinutes,
      enabled: enabled,
    );
    notifyRemoteChange();
  }

  @override
  Future<void> assign(FocusAssignRequest r) async {
    calls.add('assign:${r.id}');
    _write();
    if (assignments.containsKey(r.id)) return;
    if (r.plannedMinutes < 1 || r.plannedMinutes > 180) {
      throw ArgumentError('Use planned minutes of 1–180');
    }
    if (r.localDate.compareTo(focusLocalDate(clock(), timezone)) < 0) {
      throw StateError('Choose today or a later day');
    }
    final reminder = await _eligible(r.reminder.id);
    FocusTimeItem? time;
    if (r.focusTimeId != null) {
      time = times[r.focusTimeId];
      if (time == null) throw StateError('Focus time not found');
      if (time.contextSlug != reminder.contextSlug) {
        throw StateError('This focus time is for another context');
      }
      if (!time.weekdays.contains(focusIsoWeekday(r.localDate))) {
        throw StateError("That day is not one of this focus time's days. Refresh and try again.");
      }
    }
    final start = time?.startTime ?? '${focusTimeHm(r.startTime)}:00';
    for (final old in assignments.values.where(
      (a) => a.reminderId == reminder.id && (a.planned || a.state == 'in_progress'),
    ).toList()) {
      if (old.state == 'in_progress') {
        throw StateError('Finish the current session first');
      }
      assignments[old.id] = _copy(old, state: 'moved');
    }
    final sameSlot = assignments.values.where(
      (a) =>
          (a.planned || a.state == 'in_progress') &&
          a.localDate == r.localDate &&
          a.focusTimeId == r.focusTimeId &&
          (r.focusTimeId != null || focusTimeHm(a.startTime) == focusTimeHm(start)),
    );
    final position = sameSlot.isEmpty
        ? 0
        : sameSlot.map((a) => a.position).reduce((a, b) => a > b ? a : b) + 1;
    assignments[r.id] = FocusAssignment(
      id: r.id,
      reminderId: reminder.id,
      title: reminder.title,
      contextSlug: reminder.contextSlug,
      focusTimeId: r.focusTimeId,
      localDate: r.localDate,
      startTime: start,
      plannedMinutes: r.plannedMinutes,
      position: position,
    );
    notifyRemoteChange();
  }

  @override
  Future<void> skip(String assignmentId) async {
    _write();
    calls.add('skip:$assignmentId');
    final a = assignments[assignmentId];
    if (a == null) throw StateError('Assignment not found');
    if (a.state == 'in_progress') {
      throw StateError('Finish the current session first');
    }
    if (a.planned) assignments[a.id] = _copy(a, state: 'skipped');
    notifyRemoteChange();
  }

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}
