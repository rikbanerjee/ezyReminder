import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/util/quiet_hours.dart';

class SettingsContext {
  const SettingsContext({
    required this.id,
    required this.name,
    required this.slug,
    this.quietHours = const QuietHours(),
  });

  final String id;
  final String name;
  final String slug;
  final QuietHours quietHours;

  SettingsContext copyWith({QuietHours? quietHours}) => SettingsContext(
    id: id,
    name: name,
    slug: slug,
    quietHours: quietHours ?? this.quietHours,
  );
}

class SettingsData {
  const SettingsData({
    required this.email,
    required this.timezone,
    required this.contexts,
  });

  final String email;
  final String timezone;
  final List<SettingsContext> contexts;

  SettingsData copyWith({
    String? email,
    String? timezone,
    List<SettingsContext>? contexts,
  }) => SettingsData(
    email: email ?? this.email,
    timezone: timezone ?? this.timezone,
    contexts: contexts ?? this.contexts,
  );
}

abstract interface class SettingsRepository {
  Stream<void> get changes;

  Future<SettingsData> load();

  Future<void> saveTimezone(String timezone);

  Future<void> saveQuietHours(
    String contextId, {
    required String? start,
    required String? end,
  });

  Future<void> deleteAccount();

  void dispose();
}

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this.client);

  final SupabaseClient client;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  RealtimeChannel? _channel;
  bool _disposed = false;

  @override
  Stream<void> get changes {
    _subscribe();
    return _changes.stream;
  }

  String get _userId {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to manage settings.');
    return user.id;
  }

  @override
  Future<SettingsData> load() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to manage settings.');
    final settingsRow = await client
        .from('user_settings')
        .select('timezone')
        .eq('user_id', user.id)
        .maybeSingle();
    final rows = await client
        .from('contexts')
        .select('id,name,slug,quiet_hours')
        .order('name');
    return SettingsData(
      email: user.email ?? '',
      timezone: settingsRow?['timezone'] as String? ?? 'UTC',
      contexts: rows.map((row) {
        final rawQuietHours = row['quiet_hours'];
        final quietHours = rawQuietHours is Map
            ? QuietHours.fromJson(Map<String, Object?>.from(rawQuietHours))
            : const QuietHours();
        return SettingsContext(
          id: row['id'] as String,
          name: row['name'] as String,
          slug: row['slug'] as String,
          quietHours: quietHours,
        );
      }).toList(),
    );
  }

  @override
  Future<void> saveTimezone(String timezone) async {
    final value = timezone.trim();
    if (!isValidTimeZone(value)) {
      throw ArgumentError.value(
        value,
        'timezone',
        'Choose a valid IANA time zone.',
      );
    }
    await client.from('user_settings').upsert({
      'user_id': _userId,
      'timezone': value,
    }, onConflict: 'user_id');
  }

  @override
  Future<void> saveQuietHours(
    String contextId, {
    required String? start,
    required String? end,
  }) async {
    final rows = await client
        .from('contexts')
        .update({
          'quiet_hours': {'start': start ?? '', 'end': end ?? ''},
        })
        .eq('id', contextId)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('This context no longer exists. Refresh and try again.');
    }
  }

  @override
  Future<void> deleteAccount() async {
    _userId;
    final response = await client.functions.invoke(
      'delete-account',
      method: HttpMethod.post,
    );
    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['ok'] != true) {
      throw StateError('Account deletion was not confirmed by the server.');
    }
  }

  void _subscribe() {
    if (_disposed || _channel != null) return;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = client
        .channel('settings-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_settings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _changes.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'contexts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _changes.add(null),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final channel = _channel;
    _channel = null;
    if (channel != null) client.removeChannel(channel);
    _changes.close();
  }
}

class DemoSettingsRepository implements SettingsRepository {
  DemoSettingsRepository({
    String email = 'preview@example.com',
    String timezone = 'UTC',
    List<SettingsContext>? contexts,
  }) : _data = SettingsData(
         email: email,
         timezone: timezone,
         contexts:
             contexts ??
             const [
               SettingsContext(id: 'work', name: 'Work', slug: 'work'),
               SettingsContext(id: 'gig', name: 'Side Gig', slug: 'side_gig'),
               SettingsContext(id: 'social', name: 'Social', slug: 'social'),
               SettingsContext(id: 'shop', name: 'Shopping', slug: 'shopping'),
             ],
       );

  SettingsData _data;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool failTimezoneSave = false;
  final Set<String> failQuietHoursFor = {};
  bool failDelete = false;
  bool accountDeleted = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<SettingsData> load() async =>
      _data.copyWith(contexts: List<SettingsContext>.of(_data.contexts));

  @override
  Future<void> saveTimezone(String timezone) async {
    if (failTimezoneSave) throw StateError('offline');
    final value = timezone.trim();
    if (!isValidTimeZone(value)) {
      throw ArgumentError.value(
        value,
        'timezone',
        'Choose a valid IANA time zone.',
      );
    }
    _data = _data.copyWith(timezone: value);
    _changes.add(null);
  }

  @override
  Future<void> saveQuietHours(
    String contextId, {
    required String? start,
    required String? end,
  }) async {
    if (failQuietHoursFor.contains(contextId)) {
      throw StateError('offline');
    }
    final index = _data.contexts.indexWhere((item) => item.id == contextId);
    if (index < 0) throw StateError('This context no longer exists.');
    final contexts = List<SettingsContext>.of(_data.contexts);
    contexts[index] = contexts[index].copyWith(
      quietHours: QuietHours(start: start ?? '', end: end ?? ''),
    );
    _data = _data.copyWith(contexts: contexts);
    _changes.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    if (failDelete) throw StateError('offline');
    accountDeleted = true;
  }

  @override
  void dispose() {
    _changes.close();
  }
}
