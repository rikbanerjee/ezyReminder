import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/util/quiet_hours.dart';

/// iOS keeps at most 64 pending local notifications per app (MOBILE.md §3).
const maxPendingAlerts = 64;

/// Lock-screen actions. Snooze matches the server's "Snooze 1h".
const doneAction = 'DONE';
const snoozeAction = 'SNOOZE_1H';
const snoozeFor = Duration(hours: 1);

enum AlertPermission { notDetermined, denied, allowed }

/// One scheduled iPhone alert. The identifier is the reminder id, so a later
/// APNs push with the same `apns-collapse-id` replaces it instead of doubling.
class ReminderAlert {
  const ReminderAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.threadId,
    required this.canComplete,
  });

  final String id, title, body, threadId;
  final DateTime fireAt;

  /// Orders, Side Gig work and Home tasks finish in their own forms, so
  /// their alerts offer Snooze only; tapping opens that form.
  final bool canComplete;

  String get category => canComplete ? 'REMINDER' : 'REMINDER_OPEN';

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'fireAt': fireAt.millisecondsSinceEpoch,
    'thread': threadId,
    'category': category,
  };

  factory ReminderAlert.fromMap(Map<Object?, Object?> map) => ReminderAlert(
    id: map['id'] as String,
    title: map['title'] as String? ?? '',
    body: map['body'] as String? ?? '',
    fireAt: DateTime.fromMillisecondsSinceEpoch(
      (map['fireAt'] as num?)?.toInt() ?? 0,
      isUtc: true,
    ),
    threadId: map['thread'] as String? ?? '',
    canComplete: map['category'] == 'REMINDER',
  );

  ReminderAlert at(DateTime when) => ReminderAlert(
    id: id,
    title: title,
    body: body,
    fireAt: when.toUtc(),
    threadId: threadId,
    canComplete: canComplete,
  );
}

/// The reminder fields alert planning needs, independent of either UI.
class AlertReminder {
  const AlertReminder({
    required this.id,
    required this.title,
    required this.contextName,
    required this.contextSlug,
    this.notes,
    this.status = 'open',
    this.dueAt,
    this.snoozedUntil,
    this.isOrder = false,
    this.tags = const [],
    this.quietHours,
  });

  final String id, title, contextName, contextSlug, status;
  final String? notes;
  final DateTime? dueAt, snoozedUntil;
  final bool isOrder;
  final List<String> tags;
  final QuietHours? quietHours;

  factory AlertReminder.fromRow(Map<String, dynamic> row) {
    final context = Map<String, dynamic>.from(row['contexts'] as Map? ?? {});
    final quiet = context['quiet_hours'];
    DateTime? time(String key) =>
        row[key] == null ? null : DateTime.parse(row[key] as String).toUtc();
    return AlertReminder(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      notes: row['notes'] as String?,
      status: row['status'] as String? ?? 'open',
      dueAt: time('due_at'),
      snoozedUntil: time('snoozed_until'),
      isOrder: row['is_order'] as bool? ?? false,
      tags: List<String>.from(row['tags'] as List? ?? const []),
      contextName: context['name'] as String? ?? 'Work',
      contextSlug: context['slug'] as String? ?? 'work',
      quietHours: quiet is Map
          ? QuietHours.fromJson(Map<String, Object?>.from(quiet))
          : null,
    );
  }
}

/// The soonest [limit] future alerts. A due time inside the context's quiet
/// hours moves to the end of the window, as the server sweep does.
List<ReminderAlert> planReminderAlerts(
  Iterable<AlertReminder> reminders, {
  required String timeZone,
  required DateTime now,
  int limit = maxPendingAlerts,
}) {
  final zone = isValidTimeZone(timeZone) ? timeZone : 'UTC';
  final alerts = <ReminderAlert>[];
  for (final r in reminders) {
    if (r.status != 'open' && r.status != 'snoozed') continue;
    final due = r.snoozedUntil ?? r.dueAt;
    if (due == null) continue;
    final fireAt = deferForQuietHours(due, r.quietHours, zone);
    if (!fireAt.isAfter(now)) continue;
    alerts.add(
      ReminderAlert(
        id: r.id,
        title: r.title,
        body: _body(r),
        fireAt: fireAt,
        threadId: r.contextSlug,
        canComplete:
            !r.isOrder &&
            !r.tags.any(
              (t) => t.startsWith('sidegig:') || t.startsWith('home:'),
            ),
      ),
    );
  }
  alerts.sort((a, b) {
    final byTime = a.fireAt.compareTo(b.fireAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return alerts.take(limit).toList();
}

DateTime deferForQuietHours(DateTime due, QuietHours? quiet, String zone) {
  final at = due.toUtc();
  if (quiet == null || !isQuietNow(quiet, zone, now: at)) return at;
  return nextAllowedTime(quiet, zone, now: at);
}

String _body(AlertReminder r) {
  final note = r.notes?.trim().split('\n').first.trim() ?? '';
  final detail = r.isOrder ? 'Order' : note;
  if (detail.isEmpty) return r.contextName;
  final clipped = detail.length > 120 ? '${detail.substring(0, 119)}…' : detail;
  return '${r.contextName} · $clipped';
}

/// Everything sync needs: open reminders and the account time zone.
class AlertSnapshot {
  const AlertSnapshot({required this.reminders, required this.timeZone});
  final List<AlertReminder> reminders;
  final String timeZone;
}

abstract interface class AlertSource {
  /// Null when nobody is signed in.
  Future<AlertSnapshot?> load();
  Future<void> complete(String id);
  Future<void> snooze(String id, DateTime until);
}

class SupabaseAlertSource implements AlertSource {
  SupabaseAlertSource(this.client);
  final SupabaseClient client;

  @override
  Future<AlertSnapshot?> load() async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    final rows = await client
        .from('reminders')
        .select(
          'id,title,notes,status,due_at,snoozed_until,is_order,tags,contexts(name,slug,quiet_hours)',
        )
        .inFilter('status', ['open', 'snoozed']);
    final settings = await client
        .from('user_settings')
        .select('timezone')
        .eq('user_id', user.id)
        .maybeSingle();
    return AlertSnapshot(
      reminders: rows.map(AlertReminder.fromRow).toList(),
      timeZone: settings?['timezone'] as String? ?? 'UTC',
    );
  }

  // Same writes as the Today list. Already done or deleted elsewhere is fine.
  @override
  Future<void> complete(String id) => client
      .from('reminders')
      .update({'status': 'done', 'snoozed_until': null})
      .eq('id', id)
      .inFilter('status', ['open', 'snoozed']);

  @override
  Future<void> snooze(String id, DateTime until) => client
      .from('reminders')
      .update({
        'status': 'snoozed',
        'snoozed_until': until.toUtc().toIso8601String(),
      })
      .eq('id', id)
      .inFilter('status', ['open', 'snoozed']);
}

/// Native side: `mobile/ios/Runner/ReminderNotifications.swift`.
abstract interface class AlertPlatform {
  Future<AlertPermission> permission();
  Future<bool> requestPermission();

  /// Makes [alerts] the complete pending set and clears delivered alerts
  /// whose reminder is no longer open (not in [open]).
  Future<void> replace(List<ReminderAlert> alerts, {required Set<String> open});

  /// Adds or replaces these alerts, leaving the rest pending.
  Future<void> add(List<ReminderAlert> alerts);
  Future<void> sendTest();
  Future<void> openSettings();

  /// The reminder whose alert was tapped, once.
  Future<String?> takeOpened();

  /// Ready to receive `job` and `opened` calls from iOS.
  Future<void> attach(
    Future<Object?> Function(String method, Object? args) handler,
  );
  Future<void> detach();
}

class MethodChannelAlertPlatform implements AlertPlatform {
  static const _channel = MethodChannel('ezyreminder/notifications');

  @override
  Future<AlertPermission> permission() async =>
      switch (await _channel.invokeMethod<String>('permission')) {
        'allowed' => AlertPermission.allowed,
        'denied' => AlertPermission.denied,
        _ => AlertPermission.notDetermined,
      };

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('request') ?? false;

  @override
  Future<void> replace(
    List<ReminderAlert> alerts, {
    required Set<String> open,
  }) => _channel.invokeMethod('replace', {
    'alerts': [for (final a in alerts) a.toMap()],
    'open': open.toList(),
  });

  @override
  Future<void> add(List<ReminderAlert> alerts) => _channel.invokeMethod('add', {
    'alerts': [for (final a in alerts) a.toMap()],
  });

  @override
  Future<void> sendTest() => _channel.invokeMethod('test');

  @override
  Future<void> openSettings() => _channel.invokeMethod('openSettings');

  @override
  Future<String?> takeOpened() => _channel.invokeMethod<String>('takeOpened');

  @override
  Future<void> attach(
    Future<Object?> Function(String method, Object? args) handler,
  ) async {
    _channel.setMethodCallHandler(
      (call) => handler(call.method, call.arguments),
    );
    await _channel.invokeMethod('attach');
  }

  @override
  Future<void> detach() async {
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod('detach');
  }
}

/// Keeps this iPhone's local alerts in step with the account and carries out
/// Done / Snooze 1h from the lock screen. Runs in the app and, when the app
/// isn't running, in the background engine (`notification_jobs.dart`).
class ReminderAlerts {
  ReminderAlerts({
    required this.source,
    AlertPlatform? platform,
    DateTime Function()? clock,
  }) : platform = platform ?? MethodChannelAlertPlatform(),
       _clock = clock ?? DateTime.now;

  final AlertSource source;
  final AlertPlatform platform;
  final DateTime Function() _clock;
  static const _queueKey = 'notifications.queued_actions';

  Future<void>? _running;
  bool _again = false;

  Future<AlertPermission> permission() async {
    try {
      return await platform.permission();
    } catch (_) {
      return AlertPermission.denied;
    }
  }

  /// Call only from a tap: iOS shows its permission prompt once.
  Future<AlertPermission> enable() async {
    await platform.requestPermission();
    final status = await permission();
    if (status == AlertPermission.allowed) await sync();
    return status;
  }

  /// Reschedules from the server. Overlapping calls coalesce into one rerun.
  Future<void> sync() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = () async {
      try {
        do {
          _again = false;
          await _syncOnce();
        } while (_again);
      } finally {
        _running = null;
      }
    }();
  }

  Future<void> _syncOnce() async {
    if (await permission() != AlertPermission.allowed) return;
    try {
      await _flushQueued();
    } catch (_) {
      // Still offline: keep the queue and schedule what we can.
    }
    final snapshot = await source.load();
    if (snapshot == null) {
      await clear();
      return;
    }
    await platform.replace(
      planReminderAlerts(
        snapshot.reminders,
        timeZone: snapshot.timeZone,
        now: _clock().toUtc(),
      ),
      open: {for (final r in snapshot.reminders) r.id},
    );
  }

  /// Signing out leaves nothing of this account on the lock screen.
  Future<void> clear() async {
    try {
      await platform.replace(const [], open: const {});
    } catch (_) {}
  }

  /// A `job` from iOS: `{kind: sync}` or `{kind: action, action, id, alert}`.
  Future<void> run(Map<Object?, Object?> job) async {
    if (job['kind'] == 'action') {
      final alert = job['alert'] is Map
          ? ReminderAlert.fromMap(job['alert'] as Map<Object?, Object?>)
          : null;
      await act(job['id'] as String, job['action'] as String, alert: alert);
    } else {
      await sync();
    }
  }

  /// Done or Snooze 1h. Offline taps are kept and replayed on the next sync.
  Future<void> act(String id, String action, {ReminderAlert? alert}) async {
    final now = _clock().toUtc();
    if (action == snoozeAction && alert != null) {
      // Remind again in an hour even if the write has to wait for a network.
      await platform.add([alert.at(now.add(snoozeFor))]);
    }
    try {
      await _apply(id, action, now);
    } on PostgrestException {
      // The server refused it (e.g. signed out); retrying won't help.
      return;
    } catch (_) {
      await _queue(id, action, now);
      return;
    }
    try {
      await sync();
    } catch (_) {}
  }

  Future<void> _apply(String id, String action, DateTime at) async {
    if (action == doneAction) {
      await source.complete(id);
    } else if (action == snoozeAction) {
      await source.snooze(id, at.add(snoozeFor));
    }
  }

  Future<void> _queue(String id, String action, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    final queued = prefs.getStringList(_queueKey) ?? [];
    queued.add(
      jsonEncode({'id': id, 'action': action, 'at': at.toIso8601String()}),
    );
    await prefs.setStringList(_queueKey, queued);
  }

  Future<void> _flushQueued() async {
    final prefs = await SharedPreferences.getInstance();
    final queued = prefs.getStringList(_queueKey) ?? [];
    while (queued.isNotEmpty) {
      final item = Map<String, Object?>.from(jsonDecode(queued.first) as Map);
      final at = DateTime.parse(item['at'] as String);
      final action = item['action'] as String;
      // A snooze whose hour already passed has nothing left to do.
      if (action == doneAction || at.add(snoozeFor).isAfter(_clock())) {
        try {
          await _apply(item['id'] as String, action, at);
        } on PostgrestException {
          // Refused, not offline: drop it rather than retry forever.
        }
      }
      queued.removeAt(0);
      await prefs.setStringList(_queueKey, queued);
    }
  }
}
