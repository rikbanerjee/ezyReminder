import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../focus/focus_models.dart';

class GigItem {
  GigItem(Map<String, dynamic> value) : data = Map.of(value);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get kind => data['kind'] as String;
  String get title => data['title'] as String? ?? '';
  String? text(String key) => data[key]?.toString();
  String get status => text('status') ?? 'open';
  bool get open => ['open', 'snoozed'].contains(status);
  bool get work => kind == 'work' || kind == 'order';
  bool get waiting => data['waiting'] == true;
  bool get eligible =>
      work &&
      open &&
      !waiting &&
      ['work', 'sidegig'].contains(text('context_slug'));
  int get minutes => (data['minutes'] as num?)?.toInt() ?? 15;
  String? dueDate(String zone) => kind == 'order'
      ? text('ship_by')
      : text('due_at') == null
      ? null
      : focusLocalDate(DateTime.parse(text('due_at')!), zone);
  FocusReminder get focusReminder => FocusReminder(
    id: text('reminder_id') ?? id,
    title: title,
    contextSlug: text('context_slug') ?? 'sidegig',
    status: status,
    dueAt: DateTime.tryParse(text('due_at') ?? ''),
    isOrder: kind == 'order',
    shipBy: text('ship_by'),
  );
}

class GigDashboard {
  const GigDashboard({
    required this.items,
    required this.timezone,
    required this.localDate,
  });
  final List<GigItem> items;
  final String timezone, localDate;
  factory GigDashboard.fromMap(Map<String, dynamic> row) => GigDashboard(
    items: [
      for (final r in row['items'] as List)
        GigItem(Map<String, dynamic>.from(r as Map)),
    ],
    timezone: row['timezone'] as String,
    localDate: row['local_date'] as String,
  );
  int compare(GigItem a, GigItem b) =>
      (a.dueDate(timezone) ?? '9999').compareTo(b.dueDate(timezone) ?? '9999');
  List<GigItem> get attention {
    final next = addLocalDays(localDate, 1);
    final collections = items
        .where((r) => r.kind == 'followup' && r.open)
        .map((r) => r.text('related_payment_id'))
        .toSet();
    return items.where((r) {
      if (!r.open ||
          r.waiting ||
          (r.kind == 'order' && r.text('shipped_at') != null) ||
          (r.kind == 'payment' && collections.contains(r.id))) {
        return false;
      }
      final day = r.dueDate(timezone);
      return day != null &&
          day.compareTo(r.kind == 'order' ? next : localDate) <= 0;
    }).toList()..sort(compare);
  }

  GigItem? get resume {
    final rows = items.where((r) => r.eligible).toList();
    rows.sort((a, b) {
      final aAt = a.text('last_worked_at'), bAt = b.text('last_worked_at');
      if (aAt != null || bAt != null) return (bAt ?? '').compareTo(aAt ?? '');
      return compare(a, b);
    });
    return rows.firstOrNull;
  }
}

/// Precise decimal totals, grouped by currency. Unknown amounts are counted separately.
({List<String> totals, int unknown}) gigMoney(Iterable<GigItem> rows) {
  final sums = <String, BigInt>{};
  var unknown = 0;
  for (final r in rows) {
    final amount = r.text('amount'), currency = r.text('currency');
    if (amount == null || currency == null) {
      unknown++;
      continue;
    }
    final parts = amount.split('.');
    final cents =
        BigInt.parse(parts[0]) * BigInt.from(100) +
        BigInt.parse('${parts.length > 1 ? parts[1] : ''}00'.substring(0, 2));
    sums[currency] = (sums[currency] ?? BigInt.zero) + cents;
  }
  final keys = sums.keys.toList()..sort();
  return (
    totals: [
      for (final key in keys)
        '$key ${sums[key]! ~/ BigInt.from(100)}.${(sums[key]! % BigInt.from(100)).toString().padLeft(2, '0')}',
    ],
    unknown: unknown,
  );
}

abstract interface class GigRepository {
  Stream<void> get changes;
  Future<GigDashboard> load();
  Future<void> mutate(
    String operation,
    String action,
    String id,
    Map<String, dynamic> payload,
  );
  void dispose();
}

class SupabaseGigRepository implements GigRepository {
  SupabaseGigRepository(this.client) {
    _channel = client.channel('sidegig-${client.auth.currentUser?.id}');
    for (final table in [
      'reminders',
      'orders',
      'sidegig_details',
      'sidegig_work_state',
      'sidegig_obligations',
      'sidegig_activity',
      'focus_sessions',
    ]) {
      _channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      );
    }
    _channel.subscribe();
  }
  final SupabaseClient client;
  final _changes = StreamController<void>.broadcast();
  late final RealtimeChannel _channel;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<GigDashboard> load() async => GigDashboard.fromMap(
    Map<String, dynamic>.from(await client.rpc('get_sidegig_dashboard') as Map),
  );
  @override
  Future<void> mutate(
    String operation,
    String action,
    String id,
    Map<String, dynamic> payload,
  ) async {
    await client.rpc(
      'sidegig_mutate',
      params: {
        'p_operation_id': operation,
        'p_action': action,
        'p_id': id,
        'p_data': payload,
      },
    );
  }

  @override
  void dispose() {
    unawaited(client.removeChannel(_channel));
    unawaited(_changes.close());
  }
}

/// Isolated preview/test repository; connected accounts always use Supabase.
class MemoryGigRepository implements GigRepository {
  // ignore: prefer_initializing_formals
  MemoryGigRepository({this.seed, this.onMutation, List<GigItem>? items})
    // ignore: prefer_initializing_formals
    : _items = items;
  final Future<List<GigItem>> Function()? seed;
  final Future<void> Function(
    String action,
    String id,
    Map<String, dynamic> payload,
  )?
  onMutation;
  List<GigItem>? _items;
  final _changes = StreamController<void>.broadcast();
  final _operations = <String>{};
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<GigDashboard> load() async {
    if (seed != null) {
      final fresh = await seed!();
      final current = {for (final r in _items ?? <GigItem>[]) r.id: r};
      for (final r in fresh) {
        current[r.id] = GigItem({...?current[r.id]?.data, ...r.data});
      }
      _items = current.values.toList();
    }
    _items ??= [];
    return GigDashboard(
      items: List.of(_items!),
      timezone: 'America/New_York',
      localDate: focusLocalDate(DateTime.now(), 'America/New_York'),
    );
  }

  @override
  Future<void> mutate(
    String operation,
    String action,
    String id,
    Map<String, dynamic> payload,
  ) async {
    if (_operations.contains(operation)) return;
    await load();
    await onMutation?.call(action, id, payload);
    final old = _items!.where((r) => r.id == id).firstOrNull;
    if (action.startsWith('save_')) {
      final row = Map<String, dynamic>.of(old?.data ?? {});
      row.addAll(payload);
      row.addAll({
        'id': id,
        'reminder_id': old?.text('reminder_id') ?? id,
        'kind': action == 'save_work'
            ? payload['is_order'] == true
                  ? 'order'
                  : 'work'
            : action == 'save_payment'
            ? 'payment'
            : 'followup',
        'status': 'open',
        'context_slug': 'sidegig',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _items!.removeWhere((r) => r.id == id);
      _items!.add(GigItem(row));
      if (payload['block_work'] == true) {
        final parent = _items!
            .where((r) => r.id == payload['related_id'])
            .firstOrNull;
        parent?.data['waiting'] = true;
      }
    } else if (old != null) {
      if (action == 'ship') {
        old.data.addAll({
          'shipped_at': DateTime.now().toUtc().toIso8601String(),
          'status': 'done',
          ...payload,
        });
      }
      if (action == 'shipping') old.data.addAll(payload);
      if (action == 'complete') old.data['status'] = 'done';
      if (action == 'reopen_order') old.data['status'] = 'open';
      if (action == 'receive') {
        old.data.addAll({'status': 'received', ...payload});
      }
      if (action == 'contact') {
        old.data.addAll({
          'last_contact_at': DateTime.now().toUtc().toIso8601String(),
          ...payload,
        });
      }
      if (action == 'resolve') {
        old.data['status'] = 'resolved';
        if (payload['unblock'] == true) {
          final parent = _items!
              .where((r) => r.id == old.text('related_id'))
              .firstOrNull;
          parent?.data['waiting'] = false;
        }
      }
      if (action == 'cancel') old.data['status'] = 'cancelled';
    } else {
      throw StateError('Commitment not found');
    }
    _operations.add(operation);
    _changes.add(null);
  }

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}
