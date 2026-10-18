import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_templates.g.dart';

String homeCategory(String category) => category == 'filter'
    ? 'hvac'
    : homeTemplateData.containsKey(category)
    ? category
    : 'other';
HomeTaskTemplate homeTemplate(String category) => HomeTaskTemplate(
  homeTemplateData[homeCategory(category)] as Map<String, dynamic>,
);
final homeCategories = <String, String>{
  for (final entry in homeTemplateData.entries)
    entry.key: (entry.value as Map<String, dynamic>)['label'] as String,
};
final homeSections = <String, Map<String, dynamic>>{
  for (final entry in homeSectionData.entries)
    entry.key: entry.value as Map<String, dynamic>,
};

class HomeTaskTemplate {
  const HomeTaskTemplate(this.data);
  final Map<String, dynamic> data;
  String text(String key) => data[key] as String;
  String get section => text('section');
  List<Map<String, dynamic>> get fields =>
      (data['fields'] as List).cast<Map<String, dynamic>>();
  List<String> get repeatOptions =>
      (data['repeatOptions'] as List).cast<String>();
}

String homeRepeatLabel(String value) {
  if (value == 'off') return 'Does not repeat';
  if (value == 'd1') return 'Every day';
  if (value == 'd7') return 'Every week';
  if (value == 'd14') return 'Every 2 weeks';
  final n = int.parse(value.substring(1));
  return 'Every $n ${value.startsWith('d') ? 'day' : 'month'}${n == 1 ? '' : 's'}';
}

String homeRepeatValue(HomeMaintenance? item) => item?.repeatDays != null
    ? 'd${item!.repeatDays}'
    : item?.repeat != null
    ? 'm${item!.repeat}'
    : 'off';
String homeTaskSummary(
  String category,
  String asset,
  Map<String, dynamic> details,
) => [
  asset,
  if (homeCategory(category) == 'car') ...[
    (details['make'] as String?) ?? '',
    (details['model'] as String?) ?? '',
  ],
].where((s) => s.isNotEmpty).join(' · ');

class HomeMaintenance {
  HomeMaintenance(this.data);
  final Map<String, dynamic> data;
  String get id => data['reminder_id'] as String;
  String get title => data['title'] as String;
  String get category => homeCategory(data['category'] as String);
  Map<String, dynamic> get details =>
      Map<String, dynamic>.from(data['details'] as Map? ?? const {});
  int? get repeatDays => data['repeat_days'] as int?;
  String get asset => data['asset'] as String? ?? '';
  String get notes => data['notes'] as String? ?? '';
  int? get repeat => data['repeat_months'] as int?;
  String get status => data['status'] as String;
  DateTime? get due => DateTime.tryParse(
    data['snoozed_until'] as String? ?? data['due_at'] as String? ?? '',
  )?.toLocal();
}

abstract interface class HouseholdRepository {
  Future<List<HomeMaintenance>> load();
  Future<List<Map<String, dynamic>>> history();
  Future<void> save(Map<String, dynamic> params);
  Future<void> record(Map<String, dynamic> params);
  Future<void> delete(String id);
}

class SupabaseHouseholdRepository implements HouseholdRepository {
  SupabaseHouseholdRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<HomeMaintenance>> load() async {
    final details = await client.from('home_maintenance').select();
    if (details.isEmpty) return [];
    final reminders = await client
        .from('reminders')
        .select()
        .inFilter('id', details.map((d) => d['reminder_id']).toList());
    return [
      for (final d in details)
        for (final r in reminders)
          if (r['id'] == d['reminder_id']) HomeMaintenance({...r, ...d}),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> history() async => await client
      .from('home_service_records')
      .select()
      .order('serviced_at', ascending: false);
  @override
  Future<void> save(Map<String, dynamic> params) async {
    await client.rpc('save_home_task', params: params);
  }

  @override
  Future<void> record(Map<String, dynamic> params) async {
    await client.rpc('record_home_service', params: params);
  }

  @override
  Future<void> delete(String id) async {
    await client.from('reminders').delete().eq('id', id);
  }
}

/// Isolated preview data; no service records are sent to a real account.
class DemoHouseholdRepository implements HouseholdRepository {
  final items = <HomeMaintenance>[];
  final records = <Map<String, dynamic>>[];
  @override
  Future<List<HomeMaintenance>> load() async => List.of(items);
  @override
  Future<List<Map<String, dynamic>>> history() async => List.of(records);
  @override
  Future<void> save(Map<String, dynamic> params) async {
    final id =
        params['p_id'] ?? DateTime.now().microsecondsSinceEpoch.toString();
    items.removeWhere((m) => m.id == id);
    items.add(
      HomeMaintenance({
        'reminder_id': id,
        'title': params['p_title'],
        'notes': params['p_notes'],
        'category': params['p_category'],
        'asset': params['p_asset'],
        'repeat_months': params['p_repeat_months'],
        'repeat_days': params['p_repeat_days'],
        'details': Map<String, dynamic>.from(
          params['p_details'] as Map? ?? const {},
        ),
        'due_at': params['p_due_at'],
        'channels': params['p_channels'],
        'status': 'open',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  @override
  Future<void> record(Map<String, dynamic> params) async {
    final m = items.firstWhere((m) => m.id == params['p_id']);
    if (m.data['updated_at'] != params['p_expected_updated_at'] ||
        m.status == 'done') {
      throw StateError('Reminder changed. Refresh first.');
    }
    final date = DateTime.parse(params['p_serviced_at'] as String);
    records.insert(0, {
      ...m.data,
      'serviced_at': date.toIso8601String(),
      'notes': params['p_notes'],
    });
    if (m.repeat == null && m.repeatDays == null) {
      m.data['status'] = 'done';
    } else {
      final anchor = (m.category == 'bill' || m.category == 'study')
          ? DateTime.parse(m.data['due_at'] as String).toLocal()
          : date.toLocal();
      final month = DateTime(anchor.year, anchor.month + (m.repeat ?? 0), 1);
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      m.data['due_at'] = DateTime(
        month.year,
        month.month,
        (anchor.day > lastDay ? lastDay : anchor.day) + (m.repeatDays ?? 0),
        anchor.hour,
        anchor.minute,
      ).toUtc().toIso8601String();
    }
    m.data['updated_at'] = DateTime.now().toUtc().toIso8601String();
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((m) => m.id == id);
  }
}
