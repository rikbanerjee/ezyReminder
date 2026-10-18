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
  Future<void> pause(FocusSession session);
  Future<void> resume(FocusSession session);
  Future<void> finish(FocusSession session, String outcome, String? nextStep);
  void dispose();
}

class SupabaseFocusRepository implements FocusRepository {
  SupabaseFocusRepository(this.client) {
    final user = client.auth.currentUser?.id;
    _channel = client.channel('focus-${user ?? 'signed-out'}');
    for (final table in [
      'focus_sessions',
      'focus_highlights',
      'user_settings',
    ]) {
      _channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: user == null
            ? null
            : PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: user,
              ),
        callback: (_) => _emit(),
      );
    }
    _channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) _emit();
    });
  }
  final SupabaseClient client;
  final _changes = StreamController<void>.broadcast();
  late final RealtimeChannel _channel;
  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<FocusState> load() async => FocusState.fromMap(
    Map<String, dynamic>.from(await client.rpc('get_focus_state') as Map),
  );
  @override
  Future<List<FocusReminder>> reminders() async {
    final rows = await client
        .from('reminders')
        .select('id,title,status,due_at,contexts!inner(slug)')
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
          ),
        )
        .toList();
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
    unawaited(_changes.close());
  }
}

/// Preview data is kept separate from reminders: ending focus cannot complete a
/// reminder or ship an order. Supply the same repository to retain preview state.
class DemoFocusRepository implements FocusRepository {
  DemoFocusRepository({
    required this.loadReminders,
    DateTime Function()? clock,
    this.timezone = 'UTC',
  }) : clock = clock ?? DateTime.now;
  final Future<List<FocusReminder>> Function() loadReminders;
  final DateTime Function() clock;
  final String timezone;
  final _changes = StreamController<void>.broadcast();
  final Map<String, FocusHighlight> highlights = {};
  final Map<String, FocusSession> sessions = {};
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
  Future<FocusState> load() async => FocusState(
    serverNow: clock().toUtc(),
    localDate: focusLocalDate(clock(), timezone),
    timezone: timezone,
    highlight: highlights[focusLocalDate(clock(), timezone)],
    activeSession: active,
  );
  @override
  Future<List<FocusReminder>> reminders() async =>
      (await loadReminders()).where((r) => r.eligible).toList();
  @override
  Future<String?> latestNextStep(String reminderId) async {
    final rows =
        sessions.values
            .where((s) => s.reminderId == reminderId && s.finishedAt != null)
            .toList()
          ..sort((a, b) {
            final time = b.finishedAt!.compareTo(a.finishedAt!);
            return time == 0 ? b.id.compareTo(a.id) : time;
          });
    return rows.firstOrNull?.nextStep;
  }

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

  @override
  Future<void> start(
    String id,
    FocusReminder reminder,
    int minutes,
    String? intent,
  ) async {
    _write();
    if (sessions.containsKey(id)) return;
    if (active != null) {
      throw StateError('Finish your current focus session first.');
    }
    final eligible = await _eligible(reminder.id);
    if (minutes < 1 || minutes > 180 || (intent?.length ?? 0) > 500) {
      throw ArgumentError('Invalid focus duration or intent');
    }
    final now = clock().toUtc();
    sessions[id] = FocusSession(
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
    notifyRemoteChange();
  }

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
  void dispose() {
    unawaited(_changes.close());
  }
}
