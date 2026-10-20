import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'focus_models.dart';
import 'focus_repository.dart';

/// What Today's focus card shows, in priority order (DESIGN.md §9).
enum FocusCardKind { empty, highlight, upNext, running, paused, timeUp }

/// A missed planned task and the occurrence it belonged to.
class MissedFocusItem {
  const MissedFocusItem(this.assignment, this.occurrence);
  final FocusAssignment assignment;
  final FocusOccurrence occurrence;
}

/// The server owns transitions; this clock only renders persisted timestamps.
class FocusController extends ChangeNotifier {
  FocusController(
    this.repository, {
    DateTime Function()? clock,
    bool tick = true,
  }) : clock = clock ?? DateTime.now {
    _subscription = repository.changes.listen((_) => unawaited(reload()));
    if (tick) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) return;
        final current = state;
        if (current != null &&
            focusLocalDate(now, current.timezone) != current.localDate) {
          if (!_rollingDay) {
            _rollingDay = true;
            unawaited(reload().whenComplete(() => _rollingDay = false));
          }
        }
        final minute = now.millisecondsSinceEpoch ~/ 60000;
        if (current?.activeSession != null || minute != _minuteKey) {
          _minuteKey = minute;
          notifyListeners();
        }
      });
    }
    unawaited(reload());
  }
  final FocusRepository repository;
  final DateTime Function() clock;
  FocusState? state;
  List<FocusReminder> reminders = [];
  String? error;
  bool loading = true, busy = false;
  bool _disposed = false, _rollingDay = false;
  int _generation = 0, _minuteKey = -1;
  Duration _offset = Duration.zero;
  StreamSubscription<void>? _subscription;
  Timer? _timer;
  final Map<String, String> _intents = {};
  final Map<String, String?> _steps = {};

  /// Wired by the host page: complete a reminder / open it. Focus itself never
  /// completes or ships anything on its own.
  Future<void> Function(String reminderId)? onMarkDone;
  Future<void> Function(String reminderId)? onOpenReminder;

  DateTime get now => clock().toUtc().add(_offset);
  FocusSession? get session => state?.activeSession;
  String get timezone => state?.timezone ?? 'UTC';

  /// False on projects without migrations 0015/0016: Focus times and the
  /// saved-length UI stay hidden and the MVP behaviour (25 min) applies.
  bool get planning => state?.planning ?? false;
  bool get hasPreferences => state?.preferences ?? false;
  bool get hasIntents => planning && (state?.intents ?? false);
  int get preferredMinutes => state?.preferredMinutes ?? 25;
  List<FocusTimeItem> get focusTimes => state?.focusTimes ?? const [];
  bool get hasFocusTimes => planning && focusTimes.isNotEmpty;

  FocusReminder? reminderById(String? id) =>
      id == null ? null : reminders.where((r) => r.id == id).firstOrNull;

  FocusState? _occState;
  int _occMinute = -1;
  List<FocusOccurrence> _occCache = const [];

  /// Derived occurrences, recomputed only when the dashboard or the minute changes
  /// (the card rebuilds every second while a session runs).
  List<FocusOccurrence> get _occurrences {
    final s = state;
    if (s == null) return const [];
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (!identical(_occState, s) || _occMinute != minute) {
      _occState = s;
      _occMinute = minute;
      _occCache = s.occurrences(now);
    }
    return _occCache;
  }

  /// Occurrences that have not passed their window, soonest first.
  List<FocusOccurrence> get upcoming => [
    for (final o in _occurrences)
      if (!o.missed) o,
  ];

  /// Planned work whose occurrence passed unstarted, oldest first.
  List<MissedFocusItem> get missedItems => [
    for (final o in _occurrences)
      if (o.missed)
        for (final a in o.tasks) MissedFocusItem(a, o),
  ];

  FocusAssignment? assignmentFor(String reminderId) => state?.assignments
      .where((a) => a.planned && a.reminderId == reminderId)
      .firstOrNull;

  FocusCardKind get cardKind {
    final s = session;
    if (s != null) {
      return s.awaitingFinish(now)
          ? FocusCardKind.timeUp
          : s.paused
          ? FocusCardKind.paused
          : FocusCardKind.running;
    }
    if (reminderById(state?.highlight?.reminderId) != null) {
      return FocusCardKind.highlight;
    }
    if (upcoming.isNotEmpty) return FocusCardKind.upNext;
    return FocusCardKind.empty;
  }

  /// "Next step from last time" for a reminder (latest saved note only).
  String? nextStepFor(String? reminderId) {
    if (reminderId == null) return null;
    final s = state;
    if (s?.highlight?.reminderId == reminderId && s!.preferences) {
      return _blank(s.highlightNextStep);
    }
    if (s?.activeSession?.reminderId == reminderId && s!.preferences) {
      return _blank(s.sessionNextStep);
    }
    return _blank(_steps[reminderId]);
  }

  static String? _blank(String? v) => v == null || v.trim().isEmpty ? null : v;

  /// Drops a stale action error when the person moves to another view.
  void clearError() {
    if (error == null || _disposed) return;
    error = null;
    notifyListeners();
  }

  /// One id per user intent, kept across retries so an uncertain network
  /// failure cannot create a duplicate. Call [settle] once the intent is done.
  String intentId(String key) => _intents.putIfAbsent(key, newFocusId);
  void settle(String key) => _intents.remove(key);
  Future<bool>? _latestReload;

  /// Reloads the dashboard. A reload superseded by a newer one (a Realtime echo
  /// of our own write is the common case) resolves with that newer result, so a
  /// successful write is never reported as failed just because of the race.
  Future<bool> reload() {
    final future = _reload();
    _latestReload = future;
    return future;
  }

  Future<bool> _reload() async {
    final generation = ++_generation;
    try {
      final values = await Future.wait<Object>([
        repository.load(),
        repository.reminders(),
      ]);
      if (_disposed) return false;
      if (generation != _generation) return await (_latestReload ?? Future.value(false));
      state = values[0] as FocusState;
      reminders = values[1] as List<FocusReminder>;
      _offset = state!.serverNow.difference(clock().toUtc());
      error = null;
      loading = false;
      notifyListeners();
      unawaited(_refreshSteps(generation));
      return true;
    } catch (e) {
      if (!_disposed && generation == _generation) {
        error = focusError(e);
        loading = false;
        notifyListeners();
      }
      return false;
    }
  }

  /// Fetches saved next steps for the tasks the Today surfaces show, without
  /// blocking the dashboard. Stale values are replaced so the latest note wins.
  Future<void> _refreshSteps(int generation) async {
    final ids = <String>{
      // Anything cached may be stale after a review saved a newer note.
      ..._steps.keys,
      for (final o in upcoming.take(3))
        for (final a in o.tasks)
          if (a.reminderId != null) a.reminderId!,
      // Pre-0015 dashboards do not carry the highlight/session next steps.
      if (state?.preferences != true) ...[
        ?state?.highlight?.reminderId,
        ?state?.activeSession?.reminderId,
      ],
    };
    for (final id in ids) {
      try {
        final step = await repository.latestNextStep(id);
        if (_disposed || generation != _generation) return;
        if (_steps[id] != step) {
          _steps[id] = step;
          notifyListeners();
        }
      } catch (_) {
        // The inset is optional; never surface a failure for it.
      }
    }
  }

  Future<bool> mutate(Future<void> Function() action) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      if (!await reload()) {
        if (!_disposed) error = 'Your change may have saved. Reload Focus to confirm before retrying.';
        return false;
      }
      return true;
    } catch (e) {
      final message = focusError(e);
      await reload();
      if (!_disposed) error = message;
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// One-tap start of a reminder for [minutes] (no intended outcome).
  Future<bool> startReminder(FocusReminder reminder, int minutes, {String? intent}) {
    final key = 'start:${reminder.id}:$minutes:${intent ?? ''}';
    return mutate(() => repository.start(intentId(key), reminder, minutes, intent))
        .then((ok) {
          if (ok) settle(key);
          return ok;
        });
  }

  /// Start planned work, using its planned minutes unless [minutes] is given.
  /// [intent] is dropped before 0017, where the RPC cannot store it.
  Future<bool> startAssigned(FocusAssignment assignment, {int? minutes, String? intent}) {
    final m = minutes ?? assignment.plannedMinutes;
    final text = hasIntents ? intent : null;
    final key = 'assigned:${assignment.id}:$m:${text ?? ''}';
    return mutate(() => repository.startAssigned(intentId(key), assignment, m, text))
        .then((ok) {
          if (ok) settle(key);
          return ok;
        });
  }

  /// Saves the usual length; failures never block the session that triggered it.
  Future<void> rememberMinutes(int minutes) async {
    if (!hasPreferences || minutes == preferredMinutes) return;
    try {
      await repository.savePreferredMinutes(minutes);
      await reload();
    } catch (_) {
      // Best effort: the session already started.
    }
  }

  Future<bool> skipWork(FocusAssignment a) =>
      mutate(() => repository.skip(a.id));

  /// "Next Saturday": the same slot on the next matching weekday.
  Future<bool> moveToNextWeekday(MissedFocusItem item) {
    final a = item.assignment, o = item.occurrence;
    final reminder = reminderById(a.reminderId);
    if (reminder == null) {
      error = 'This reminder is no longer available for Focus.';
      notifyListeners();
      return Future.value(false);
    }
    final date = nextWeekdayAfter(a.localDate, focusIsoWeekday(a.localDate));
    // If the Focus time no longer runs on that weekday, keep the slot as a one-off.
    final time = o.time;
    final keepTime = time != null &&
        time.enabled &&
        time.weekdays.contains(focusIsoWeekday(date));
    final key = 'next:${a.id}';
    return mutate(
      () => repository.assign(
        FocusAssignRequest(
          id: intentId(key),
          reminder: reminder,
          localDate: date,
          startTime: o.startTime,
          plannedMinutes: a.plannedMinutes,
          focusTimeId: keepTime ? time.id : null,
        ),
      ),
    ).then((ok) {
      if (ok) settle(key);
      return ok;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    repository.dispose();
    super.dispose();
  }
}

String focusError(Object error) {
  if (error is PostgrestException) {
    if (['PGRST202', 'PGRST205', '42P01', '42883'].contains(error.code)) {
      return "Focus isn't available yet. Your reminders still work. Try again after the app is updated.";
    }
    if (error.code == '40001') {
      return 'This session changed on another device. Review it and try again.';
    }
    if (error.code == '23505') {
      return 'You already have a focus session. Open it to continue.';
    }
    return error.message;
  }
  return 'Could not confirm the change. Check your connection and try again.';
}
