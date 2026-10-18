import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/tokens.g.dart';
import 'features/auth/login_page.dart';
import 'features/focus/focus_controller.dart';
import 'features/focus/focus_models.dart';
import 'features/focus/focus_repository.dart';
import 'features/focus/focus_widgets.dart';
import 'features/home/home_page.dart';
import 'features/home/home_repository.dart';
import 'features/shopping/shopping_list_sheet.dart';
import 'features/ship_queue/ship_queue_page.dart';
import 'features/shipping/carrier_fields.dart';
import 'shared/widgets/compact_date_time_picker.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/settings_repository.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
const _preview = bool.fromEnvironment('EZY_PREVIEW');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connected = _url.isNotEmpty && _key.isNotEmpty && !_preview;
  if (connected) await Supabase.initialize(url: _url, publishableKey: _key);
  runApp(EzyApp(connected: connected, preview: _preview));
}

class EzyApp extends StatelessWidget {
  const EzyApp({
    super.key,
    required this.connected,
    required this.preview,
    this.repository,
    this.textScale,
  });
  final bool connected;
  final bool preview;
  final ReminderRepository? repository;
  final double? textScale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ezyReminder',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: textScale == null
            ? MediaQuery.textScalerOf(context)
            : TextScaler.linear(textScale!),
      ),
      child: child!,
    ),
    home: preview
        ? TodayPage(repository: repository ?? DemoRepository(), demo: true)
        : connected
        ? AuthGate(client: Supabase.instance.client)
        : const SetupPage(),
  );
}

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark
      ? EzyDesignTokens.darkBackground
      : EzyDesignTokens.lightBackground;
  final surface = dark
      ? EzyDesignTokens.darkSurface
      : EzyDesignTokens.lightSurface;
  final text = dark ? EzyDesignTokens.darkText : EzyDesignTokens.lightText;
  final secondary = dark
      ? EzyDesignTokens.darkText2
      : EzyDesignTokens.lightText2;
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: dark ? EzyDesignTokens.darkWork : EzyDesignTokens.lightWork,
      brightness: brightness,
      surface: surface,
      onSurface: text,
      error: dark ? EzyDesignTokens.darkDanger : EzyDesignTokens.lightDanger,
    ),
    textTheme: Typography.material2021().black.apply(
      bodyColor: text,
      displayColor: text,
      fontFamily: EzyDesignTokens.systemFontFamily,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
    ),
    dividerColor: dark
        ? EzyDesignTokens.darkHairline
        : EzyDesignTokens.lightHairline,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: text),
      behavior: SnackBarBehavior.floating,
    ),
    extensions: <ThemeExtension<dynamic>>[
      Palette(
        surface,
        text,
        secondary,
        dark ? EzyDesignTokens.darkHairline : EzyDesignTokens.lightHairline,
        [
          dark ? EzyDesignTokens.darkWork : EzyDesignTokens.lightWork,
          dark ? EzyDesignTokens.darkSidegig : EzyDesignTokens.lightSidegig,
          dark ? EzyDesignTokens.darkSocial : EzyDesignTokens.lightSocial,
          dark ? EzyDesignTokens.darkShopping : EzyDesignTokens.lightShopping,
        ],
        dark ? EzyDesignTokens.darkCardShadow : EzyDesignTokens.lightCardShadow,
        dark
            ? EzyDesignTokens.darkSheetShadow
            : EzyDesignTokens.lightSheetShadow,
      ),
    ],
  );
}

class Palette extends ThemeExtension<Palette> {
  const Palette(
    this.surface,
    this.text,
    this.secondary,
    this.hairline,
    this.contexts,
    this.cardShadow,
    this.sheetShadow,
  );
  final Color surface, text, secondary, hairline;
  final List<Color> contexts;
  final BoxShadow cardShadow, sheetShadow;
  @override
  Palette copyWith({
    Color? surface,
    Color? text,
    Color? secondary,
    Color? hairline,
    List<Color>? contexts,
    BoxShadow? cardShadow,
    BoxShadow? sheetShadow,
  }) => Palette(
    surface ?? this.surface,
    text ?? this.text,
    secondary ?? this.secondary,
    hairline ?? this.hairline,
    contexts ?? this.contexts,
    cardShadow ?? this.cardShadow,
    sheetShadow ?? this.sheetShadow,
  );
  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) => other is! Palette
      ? this
      : Palette(
          Color.lerp(surface, other.surface, t)!,
          Color.lerp(text, other.text, t)!,
          Color.lerp(secondary, other.secondary, t)!,
          Color.lerp(hairline, other.hairline, t)!,
          contexts,
          cardShadow,
          sheetShadow,
        );
}

class Reminder {
  Reminder({
    required this.id,
    required this.title,
    required this.contextId,
    required this.contextName,
    required this.contextSlug,
    this.notes,
    this.dueAt,
    this.snoozedUntil,
    this.status = 'open',
    this.isOrder = false,
    this.channels = const [],
    this.tags = const [],
  });
  final String id, contextId, contextName, contextSlug;
  String title;
  String? notes;
  DateTime? dueAt;
  DateTime? snoozedUntil;
  DateTime? get effectiveDueAt => snoozedUntil ?? dueAt;
  String status;
  bool isOrder;
  final List<String> channels;
  final List<String> tags;
  bool get isHomeMaintenance => tags.any((t) => t.startsWith('home:'));
  factory Reminder.fromMap(
    Map<String, dynamic> row,
    Map<String, dynamic> context,
  ) => Reminder(
    id: row['id'] as String,
    title: row['title'] as String,
    contextId: row['context_id'] as String,
    contextName: context['name'] as String? ?? 'Work',
    contextSlug: context['slug'] as String? ?? 'work',
    notes: row['notes'] as String?,
    dueAt: row['due_at'] == null
        ? null
        : DateTime.parse(row['due_at'] as String).toLocal(),
    snoozedUntil: row['snoozed_until'] == null
        ? null
        : DateTime.parse(row['snoozed_until'] as String).toLocal(),
    status: row['status'] as String? ?? 'open',
    isOrder: row['is_order'] as bool? ?? false,
    channels: List<String>.from(row['channels'] as List? ?? const []),
    tags: List<String>.from(row['tags'] as List? ?? const []),
  );
  Reminder copy() => Reminder(
    id: id,
    title: title,
    contextId: contextId,
    contextName: contextName,
    contextSlug: contextSlug,
    notes: notes,
    dueAt: dueAt,
    snoozedUntil: snoozedUntil,
    status: status,
    isOrder: isOrder,
    channels: channels,
    tags: tags,
  );
}

class OrderDetails {
  const OrderDetails({
    required this.reminderId,
    this.orderRef,
    this.recipientName,
    this.shipBy,
    this.carrier,
    this.trackingNumber,
    this.shippedAt,
    this.title = '',
    this.contextName = '',
    this.contextSlug = '',
    this.contextColor,
  });
  final String reminderId;
  final String? orderRef,
      recipientName,
      shipBy,
      carrier,
      trackingNumber,
      shippedAt;
  final String title, contextName;
  final String contextSlug;
  final Color? contextColor;
  bool get shipped => shippedAt != null;
}

class WorkDetails {
  const WorkDetails({
    this.managerName,
    this.departmentResource,
    this.projectName,
  });
  final String? managerName, departmentResource, projectName;
}

class SideGigDetails {
  const SideGigDetails({this.initiativeName, this.clientName});
  final String? initiativeName, clientName;
}

class ReminderCreationIdMissing implements Exception {
  const ReminderCreationIdMissing();
  @override
  String toString() =>
      'The server did not return a reminder ID. Refresh before retrying to avoid a duplicate.';
}

abstract interface class ContextDetailsRepository {
  Future<WorkDetails?> loadWorkDetails(String reminderId);
  Future<SideGigDetails?> loadSideGigDetails(String reminderId);
  Future<void> saveWorkDetails(
    String reminderId, {
    required String? managerName,
    required String? departmentResource,
    required String? projectName,
  });
  Future<void> saveSideGigDetails(
    String reminderId, {
    required String? initiativeName,
    required String? clientName,
  });
}

abstract interface class ShipmentEditingRepository {
  Future<void> saveOrderReminder({
    required Reminder reminder,
    required OrderDetails order,
    bool? shipped,
  });
}

abstract interface class ShippingRepository {
  Future<List<OrderDetails>> loadOrders();
  Future<Reminder?> loadReminderForOrder(String id);
  Future<void> markShipped(
    String reminderId,
    String? trackingNumber,
    String? carrier,
  );
  Future<void> createFollowUp(String reminderId);
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.label,
    required this.checked,
    required this.position,
  });
  final String id, label;
  final bool checked;
  final int position;
}

abstract interface class ShoppingRepository {
  Future<List<ShoppingItem>> loadShoppingItems(String reminderId);
  Future<Map<String, int>> loadShoppingCounts();
  Future<String> addShoppingItem(String reminderId, String label);
  Future<void> setShoppingItemChecked(String id, bool checked);
  Future<void> deleteShoppingItem(String id);
  Future<void> renameShoppingList(String id, String title);
  Future<String?> loadShoppingListTitle(String id);
}

abstract interface class BrowseRepository {
  Future<List<Reminder>> loadAll();
  Future<List<Reminder>> loadDoneToday();
  Future<void> deleteReminder(String id);
  Future<void> reopenReminder(String id);
}

class ContextItem {
  const ContextItem(this.id, this.name, this.slug);
  final String id, name, slug;
}

bool _isSideGigSlug(String? slug) =>
    slug == 'sidegig' || slug == 'side_gig' || slug == 'side-gig';

abstract interface class ReminderRepository {
  Future<List<ContextItem>> contexts();
  Future<List<Reminder>> load();
  Future<void> complete(String id);
  Future<void> restore(Reminder reminder);
  Future<void> snooze(String id, DateTime until);
  Future<String?> save({
    String? id,
    required String title,
    required String? notes,
    required DateTime? dueAt,
    required String contextId,
    required bool isOrder,
    required List<String> channels,
    String? orderRef,
    String? recipientName,
    String? shipBy,
    String? carrier,
  });
  Stream<void> get changes;
}

class SupabaseRepository
    implements
        ReminderRepository,
        ShippingRepository,
        ShipmentEditingRepository,
        ShoppingRepository,
        BrowseRepository,
        ContextDetailsRepository {
  SupabaseRepository(this.client);
  final SupabaseClient client;
  final _changes = StreamController<void>.broadcast();
  RealtimeChannel? _channel;
  @override
  Stream<void> get changes => _changes.stream;
  void subscribe() {
    _channel ??= client.channel('today-reminders')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reminders',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'contexts',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'shopping_items',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'work_details',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sidegig_details',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'home_maintenance',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'home_service_records',
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..subscribe();
  }

  void dispose() {
    final channel = _channel;
    if (channel != null) unawaited(client.removeChannel(channel));
    unawaited(_changes.close());
  }

  @override
  Future<List<ContextItem>> contexts() async {
    final rows = await client
        .from('contexts')
        .select('id,name,slug')
        .order('name');
    return rows
        .map(
          (r) => ContextItem(
            r['id'] as String,
            r['name'] as String,
            r['slug'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<List<Reminder>> load() async {
    final rows = await client
        .from('reminders')
        .select('*, contexts(id,name,slug)')
        .inFilter('status', ['open', 'snoozed'])
        .order('due_at', ascending: true, nullsFirst: false);
    return rows
        .map(
          (row) => Reminder.fromMap(
            row,
            Map<String, dynamic>.from(row['contexts'] as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<Reminder>> loadAll() =>
      _loadWithStatuses(const ['open', 'snoozed', 'done']);

  Future<List<Reminder>> _loadWithStatuses(List<String>? statuses) async {
    var query = client.from('reminders').select('*, contexts(id,name,slug)');
    if (statuses != null) query = query.inFilter('status', statuses);
    final rows = await query.order('updated_at', ascending: false);
    return rows
        .map(
          (row) => Reminder.fromMap(
            row,
            Map<String, dynamic>.from(row['contexts'] as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<Reminder>> loadDoneToday() async {
    final start = DateTime.now();
    final startOfDayUtc = DateTime(start.year, start.month, start.day).toUtc();
    final rows = await client
        .from('reminders')
        .select('*, contexts(id,name,slug)')
        .eq('status', 'done')
        .gte('updated_at', startOfDayUtc.toIso8601String())
        .order('updated_at', ascending: false);
    return rows
        .map(
          (row) => Reminder.fromMap(
            row,
            Map<String, dynamic>.from(row['contexts'] as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteReminder(String id) async {
    final rows = await client
        .from('reminders')
        .delete()
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw StateError('Reminder no longer exists.');
  }

  @override
  Future<void> reopenReminder(String id) async {
    final rows = await client
        .from('reminders')
        .update({'status': 'open', 'snoozed_until': null})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw StateError('Reminder no longer exists.');
  }

  @override
  Future<WorkDetails?> loadWorkDetails(String reminderId) async {
    final row = await client
        .from('work_details')
        .select('manager_name,department_resource,project_name')
        .eq('reminder_id', reminderId)
        .maybeSingle();
    if (row == null) return null;
    return WorkDetails(
      managerName: row['manager_name'] as String?,
      departmentResource: row['department_resource'] as String?,
      projectName: row['project_name'] as String?,
    );
  }

  @override
  Future<SideGigDetails?> loadSideGigDetails(String reminderId) async {
    final row = await client
        .from('sidegig_details')
        .select('initiative_name,client_name')
        .eq('reminder_id', reminderId)
        .maybeSingle();
    if (row == null) return null;
    return SideGigDetails(
      initiativeName: row['initiative_name'] as String?,
      clientName: row['client_name'] as String?,
    );
  }

  @override
  Future<void> saveWorkDetails(
    String reminderId, {
    required String? managerName,
    required String? departmentResource,
    required String? projectName,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to save follow-up details.');
    await client.from('work_details').upsert({
      'reminder_id': reminderId,
      'user_id': userId,
      'manager_name': managerName,
      'department_resource': departmentResource,
      'project_name': projectName,
    });
  }

  @override
  Future<void> saveSideGigDetails(
    String reminderId, {
    required String? initiativeName,
    required String? clientName,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to save initiative details.');
    await client.from('sidegig_details').upsert({
      'reminder_id': reminderId,
      'user_id': userId,
      'initiative_name': initiativeName,
      'client_name': clientName,
    });
  }

  @override
  Future<List<ShoppingItem>> loadShoppingItems(String reminderId) async {
    final rows = await client
        .from('shopping_items')
        .select('id,label,checked,position')
        .eq('reminder_id', reminderId)
        .order('position', ascending: true);
    return rows
        .map(
          (row) => ShoppingItem(
            id: row['id'] as String,
            label: row['label'] as String,
            checked: row['checked'] as bool? ?? false,
            position: row['position'] as int? ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<Map<String, int>> loadShoppingCounts() async {
    final rows = await client
        .from('shopping_items')
        .select('reminder_id,checked');
    final counts = <String, int>{};
    for (final row in rows) {
      if (row['checked'] != true) {
        final id = row['reminder_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  Future<String> addShoppingItem(String reminderId, String label) async {
    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) {
      throw ArgumentError.value(label, 'label', 'Item name is required.');
    }
    final result = await client.rpc(
      'add_shopping_item',
      params: {'p_reminder_id': reminderId, 'p_label': cleanLabel},
    );
    if (result is! String || result.isEmpty) {
      throw StateError('Could not confirm the new item. Refresh the list.');
    }
    return result;
  }

  @override
  Future<void> setShoppingItemChecked(String id, bool checked) async {
    final rows = await client
        .from('shopping_items')
        .update({'checked': checked})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw StateError('This item no longer exists.');
  }

  @override
  Future<void> deleteShoppingItem(String id) async {
    final rows = await client
        .from('shopping_items')
        .delete()
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw StateError('This item no longer exists.');
  }

  @override
  Future<void> renameShoppingList(String id, String title) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'List name is required.');
    }
    final rows = await client
        .from('reminders')
        .update({'title': cleanTitle})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw StateError('This list no longer exists.');
  }

  @override
  Future<String?> loadShoppingListTitle(String id) async {
    final row = await client
        .from('reminders')
        .select('title')
        .eq('id', id)
        .maybeSingle();
    return row?['title'] as String?;
  }

  @override
  Future<List<OrderDetails>> loadOrders() async {
    final rows = await client
        .from('orders')
        .select(
          'reminder_id,order_ref,recipient_name,ship_by,carrier,tracking_number,shipped_at,reminders!inner(id,title,context_id,status,contexts(name,slug))',
        );
    return rows.map<OrderDetails>((row) {
      final reminder = Map<String, dynamic>.from(row['reminders'] as Map);
      final context = Map<String, dynamic>.from(
        reminder['contexts'] as Map? ?? const {},
      );
      final shippedAt = row['shipped_at'] as String?;
      return OrderDetails(
        reminderId: row['reminder_id'] as String,
        orderRef: row['order_ref'] as String?,
        recipientName: row['recipient_name'] as String?,
        shipBy: row['ship_by'] as String?,
        carrier: row['carrier'] as String?,
        trackingNumber: row['tracking_number'] as String?,
        shippedAt: shippedAt,
        title: reminder['title'] as String? ?? '',
        contextName: context['name'] as String? ?? '',
        contextSlug: context['slug'] as String? ?? '',
        contextColor: null,
      );
    }).toList();
  }

  @override
  Future<Reminder?> loadReminderForOrder(String id) async {
    final row = await client
        .from('reminders')
        .select('*,contexts(id,name,slug)')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Reminder.fromMap(
      row,
      Map<String, dynamic>.from(row['contexts'] as Map),
    );
  }

  Future<void> saveOrder({
    required String reminderId,
    required String? orderRef,
    required String? recipientName,
    required String? shipBy,
    required String? carrier,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to save order details.');
    final existing = await client
        .from('orders')
        .select('reminder_id')
        .eq('reminder_id', reminderId)
        .maybeSingle();
    final fields = {
      'order_ref': orderRef,
      'recipient_name': recipientName,
      'ship_by': shipBy,
      'carrier': carrier,
    };
    if (existing == null) {
      await client.from('orders').insert({
        'reminder_id': reminderId,
        'user_id': userId,
        ...fields,
      });
    } else {
      final rows = await client
          .from('orders')
          .update(fields)
          .eq('reminder_id', reminderId)
          .select('reminder_id');
      if (rows.isEmpty) {
        throw StateError(
          'Order details were not saved because this order no longer exists.',
        );
      }
    }
  }

  @override
  Future<void> saveOrderReminder({
    required Reminder reminder,
    required OrderDetails order,
    bool? shipped,
  }) async {
    if (order.reminderId != reminder.id || !reminder.isOrder) {
      throw ArgumentError('An existing order reminder is required.');
    }
    final invalidTracking = trackingError(
      order.trackingNumber ?? '',
      order.carrier ?? '',
    );
    if (invalidTracking != null) throw ArgumentError(invalidTracking);
    try {
      await client.rpc(
        'edit_order_reminder',
        params: {
          'p_id': reminder.id,
          'p_title': reminder.title,
          'p_notes': reminder.notes,
          'p_due_at': reminder.dueAt?.toUtc().toIso8601String(),
          'p_context_id': reminder.contextId,
          'p_channels': reminder.channels,
          'p_order_ref': order.orderRef,
          'p_recipient_name': order.recipientName,
          'p_ship_by': order.shipBy,
          'p_carrier': order.carrier,
          'p_tracking_number': order.trackingNumber,
          'p_shipped': shipped,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') {
        throw StateError('Shipment editing needs database migration 0010.');
      }
      rethrow;
    }
  }

  @override
  Future<void> markShipped(
    String reminderId,
    String? trackingNumber,
    String? carrier,
  ) async {
    final current = (await loadOrders())
        .where((o) => o.reminderId == reminderId)
        .firstOrNull;
    if (current == null) throw StateError('Order no longer exists.');
    if (current.shipped) {
      throw StateError('This order is already marked shipped.');
    }
    final invalidTracking = trackingError(
      trackingNumber ?? current.trackingNumber ?? '',
      carrier ?? current.carrier ?? '',
    );
    if (invalidTracking != null) throw ArgumentError(invalidTracking);
    await client.rpc(
      'mark_shipped',
      params: {
        'p_reminder_id': reminderId,
        'p_tracking_number': trackingNumber ?? current.trackingNumber,
        'p_carrier': carrier ?? current.carrier,
      },
    );
  }

  @override
  Future<void> createFollowUp(String reminderId) async {
    await client.rpc('create_follow_up', params: {'p_reminder_id': reminderId});
  }

  @override
  Future<void> complete(String id) async {
    final rows = await client
        .from('reminders')
        .update({'status': 'done', 'snoozed_until': null})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw StateError('Reminder no longer exists.');
  }

  @override
  Future<void> restore(Reminder reminder) async {
    final rows = await client
        .from('reminders')
        .update({
          'status': reminder.status,
          'snoozed_until': reminder.snoozedUntil?.toUtc().toIso8601String(),
        })
        .eq('id', reminder.id)
        .select('id');
    if (rows.isEmpty) throw StateError('Reminder no longer exists.');
  }

  @override
  Future<void> snooze(String id, DateTime until) async {
    final rows = await client
        .from('reminders')
        .update({
          'status': 'snoozed',
          'snoozed_until': until.toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw StateError('Reminder no longer exists.');
  }

  @override
  Future<String?> save({
    String? id,
    required String title,
    required String? notes,
    required DateTime? dueAt,
    required String contextId,
    required bool isOrder,
    required List<String> channels,
    String? orderRef,
    String? recipientName,
    String? shipBy,
    String? carrier,
  }) async {
    if (id == null) {
      final createdId = await client.rpc(
        'create_reminder',
        params: {
          'p_title': title,
          'p_notes': notes,
          'p_due_at': dueAt?.toUtc().toIso8601String(),
          'p_context_id': contextId,
          'p_channels': channels,
          'p_is_order': isOrder,
          'p_order_ref': isOrder ? orderRef : null,
          'p_recipient_name': isOrder ? recipientName : null,
          'p_ship_by': isOrder ? shipBy : null,
          'p_carrier': isOrder ? carrier : null,
        },
      );
      if (createdId is! String || createdId.isEmpty) {
        throw const ReminderCreationIdMissing();
      }
      return createdId;
    } else {
      await client.rpc(
        'update_reminder',
        params: {
          'p_id': id,
          'p_title': title,
          'p_notes': notes,
          'p_due_at': dueAt?.toUtc().toIso8601String(),
          'p_context_id': contextId,
          'p_channels': channels,
          'p_is_order': isOrder,
        },
      );
      if (isOrder) {
        try {
          await saveOrder(
            reminderId: id,
            orderRef: orderRef,
            recipientName: recipientName,
            shipBy: shipBy,
            carrier: carrier,
          );
        } catch (error) {
          throw StateError(
            'Reminder saved, but order details failed to save: $error',
          );
        }
      }
      return id;
    }
  }
}

class DemoRepository
    implements
        ReminderRepository,
        ShippingRepository,
        ShipmentEditingRepository,
        ShoppingRepository,
        BrowseRepository,
        ContextDetailsRepository {
  DemoRepository() {
    _contexts = const [
      ContextItem('work', 'Work', 'work'),
      ContextItem('gig', 'Side Gig', 'side_gig'),
      ContextItem('social', 'Social', 'social'),
      ContextItem('shop', 'Shopping', 'shopping'),
    ];
    _items = [
      Reminder(
        id: 'fixture-1',
        title: 'Send the revised proposal',
        contextId: 'work',
        contextName: 'Work',
        contextSlug: 'work',
        dueAt: DateTime.now().add(const Duration(hours: 2)),
      ),
      Reminder(
        id: 'fixture-2',
        title: 'Photograph new listing',
        contextId: 'gig',
        contextName: 'Side Gig',
        contextSlug: 'side_gig',
        dueAt: DateTime.now().add(const Duration(hours: 5)),
      ),
      Reminder(
        id: 'fixture-3',
        title: 'Pick up oat milk',
        contextId: 'shop',
        contextName: 'Shopping',
        contextSlug: 'shopping',
      ),
      Reminder(
        id: 'fixture-4',
        title: 'Call Maya about Saturday',
        contextId: 'social',
        contextName: 'Social',
        contextSlug: 'social',
        dueAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ];
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _orders = [
      OrderDetails(
        reminderId: 'fixture-order',
        title: 'Ship handmade mug',
        contextName: 'Side Gig',
        contextSlug: 'side_gig',
        orderRef: 'Etsy #1042',
        recipientName: 'Sarah M.',
        shipBy:
            '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}',
        carrier: 'USPS',
      ),
    ];
    _items.add(
      Reminder(
        id: 'fixture-order',
        title: 'Ship handmade mug',
        contextId: 'gig',
        contextName: 'Side Gig',
        contextSlug: 'side_gig',
        isOrder: true,
      ),
    );
  }
  late final List<ContextItem> _contexts;
  late final List<Reminder> _items;
  late final List<OrderDetails> _orders;
  final Map<String, List<ShoppingItem>> _shoppingItems = {
    'fixture-3': [
      ShoppingItem(
        id: 'shop-1',
        label: 'Oat milk',
        checked: false,
        position: 0,
      ),
      ShoppingItem(
        id: 'shop-2',
        label: 'Coffee beans',
        checked: false,
        position: 1,
      ),
      ShoppingItem(
        id: 'shop-3',
        label: 'Dish soap',
        checked: true,
        position: 2,
      ),
    ],
  };
  final Map<String, WorkDetails> workDetails = {
    'fixture-1': const WorkDetails(
      managerName: 'Jordan Lee',
      departmentResource: 'Design Systems',
      projectName: 'Q4 launch',
    ),
  };
  final Map<String, SideGigDetails> sideGigDetails = {};
  final Set<String> failContextDetailWrites = {};
  int reminderCreateCalls = 0;
  int reminderUpdateCalls = 0;
  String? lastCreatedReminderId;
  final Set<String> failShoppingWrites = {};
  final Set<String> failBrowseWrites = {};
  final Map<String, Completer<void>> browseWriteGates = {};
  final Map<String, DateTime> completedAt = {};
  final Map<String, Completer<void>> shoppingWriteGates = {};
  @override
  Future<List<ShoppingItem>> loadShoppingItems(String reminderId) async =>
      List.of(_shoppingItems[reminderId] ?? const []);
  @override
  Future<Map<String, int>> loadShoppingCounts() async => {
    for (final entry in _shoppingItems.entries)
      entry.key: entry.value.where((item) => !item.checked).length,
  };
  @override
  Future<String> addShoppingItem(String reminderId, String label) async {
    final gate = shoppingWriteGates['add'];
    if (gate != null) await gate.future;
    if (failShoppingWrites.contains('add')) throw StateError('offline');
    label = label.trim();
    if (label.isEmpty) {
      throw ArgumentError.value(label, 'label', 'Item name is required.');
    }
    final items = _shoppingItems.putIfAbsent(reminderId, () => []);
    final id = 'shopping-${DateTime.now().microsecondsSinceEpoch}';
    items.add(
      ShoppingItem(
        id: id,
        label: label,
        checked: false,
        position: items.length,
      ),
    );
    _stream.add(null);
    return id;
  }

  @override
  Future<void> setShoppingItemChecked(String id, bool checked) async {
    final gate = shoppingWriteGates['toggle'];
    if (gate != null) await gate.future;
    if (failShoppingWrites.contains('toggle')) throw StateError('offline');
    for (final items in _shoppingItems.values) {
      final index = items.indexWhere((item) => item.id == id);
      if (index >= 0) {
        final item = items[index];
        items[index] = ShoppingItem(
          id: id,
          label: item.label,
          checked: checked,
          position: item.position,
        );
        _stream.add(null);
        return;
      }
    }
    throw StateError('This item no longer exists.');
  }

  @override
  Future<void> deleteShoppingItem(String id) async {
    final gate = shoppingWriteGates['delete'];
    if (gate != null) await gate.future;
    if (failShoppingWrites.contains('delete')) throw StateError('offline');
    for (final items in _shoppingItems.values) {
      final index = items.indexWhere((item) => item.id == id);
      if (index >= 0) {
        items.removeAt(index);
        _stream.add(null);
        return;
      }
    }
    throw StateError('This item no longer exists.');
  }

  @override
  Future<void> renameShoppingList(String id, String title) async {
    final gate = shoppingWriteGates['rename'];
    if (gate != null) await gate.future;
    if (failShoppingWrites.contains('rename')) throw StateError('offline');
    title = title.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(title, 'title', 'List name is required.');
    }
    _items.firstWhere((r) => r.id == id).title = title;
    _stream.add(null);
  }

  void remoteWorkDetailsUpdate(String reminderId, WorkDetails details) {
    workDetails[reminderId] = details;
    _stream.add(null);
  }

  void remoteSideGigDetailsUpdate(String reminderId, SideGigDetails details) {
    sideGigDetails[reminderId] = details;
    _stream.add(null);
  }

  @override
  Future<String?> loadShoppingListTitle(String id) async =>
      _items.where((r) => r.id == id).firstOrNull?.title;

  void remoteShoppingUpdate(String reminderId, List<ShoppingItem> items) {
    _shoppingItems[reminderId] = List.of(items);
    _stream.add(null);
  }

  int followUpCalls = 0;
  final _stream = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => _stream.stream;
  @override
  Future<List<ContextItem>> contexts() async => _contexts;
  @override
  Future<WorkDetails?> loadWorkDetails(String reminderId) async =>
      workDetails[reminderId];
  @override
  Future<SideGigDetails?> loadSideGigDetails(String reminderId) async =>
      sideGigDetails[reminderId];
  @override
  Future<void> saveWorkDetails(
    String reminderId, {
    required String? managerName,
    required String? departmentResource,
    required String? projectName,
  }) async {
    if (failContextDetailWrites.contains('work')) throw StateError('offline');
    workDetails[reminderId] = WorkDetails(
      managerName: managerName,
      departmentResource: departmentResource,
      projectName: projectName,
    );
    _stream.add(null);
  }

  @override
  Future<void> saveSideGigDetails(
    String reminderId, {
    required String? initiativeName,
    required String? clientName,
  }) async {
    if (failContextDetailWrites.contains('sidegig')) {
      throw StateError('offline');
    }
    sideGigDetails[reminderId] = SideGigDetails(
      initiativeName: initiativeName,
      clientName: clientName,
    );
    _stream.add(null);
  }

  @override
  Future<List<OrderDetails>> loadOrders() async => List.of(_orders);
  @override
  Future<Reminder?> loadReminderForOrder(String id) async =>
      _items.where((r) => r.id == id).firstOrNull?.copy();
  @override
  Future<void> saveOrderReminder({
    required Reminder reminder,
    required OrderDetails order,
    bool? shipped,
  }) async {
    final i = _orders.indexWhere((o) => o.reminderId == reminder.id);
    final r = _items.where((item) => item.id == reminder.id).firstOrNull;
    if (i < 0 ||
        r == null ||
        order.reminderId != reminder.id ||
        !reminder.isOrder) {
      throw StateError('Order no longer exists.');
    }
    final invalidTracking = trackingError(
      order.trackingNumber ?? '',
      order.carrier ?? '',
    );
    if (invalidTracking != null) throw ArgumentError(invalidTracking);
    final c = _contexts.firstWhere((c) => c.id == reminder.contextId);
    final previous = _orders[i];
    reminderUpdateCalls++;
    final edited = Reminder(
      id: r.id,
      title: reminder.title.trim(),
      notes: reminder.notes,
      dueAt: reminder.dueAt,
      contextId: c.id,
      contextName: c.name,
      contextSlug: c.slug,
      isOrder: true,
      channels: List.of(reminder.channels),
      status: shipped == true
          ? 'done'
          : shipped == false && previous.shipped
          ? 'open'
          : r.status,
      snoozedUntil: shipped == true || shipped == false && previous.shipped
          ? null
          : r.snoozedUntil,
    );
    _items[_items.indexOf(r)] = edited;
    if (edited.status == 'done') {
      completedAt[r.id] = DateTime.now();
    } else if (shipped == false && previous.shipped) {
      completedAt.remove(r.id);
    }
    _orders[i] = OrderDetails(
      reminderId: r.id,
      title: edited.title,
      contextName: c.name,
      contextSlug: c.slug,
      orderRef: order.orderRef,
      recipientName: order.recipientName,
      shipBy: order.shipBy,
      carrier: order.carrier,
      trackingNumber: order.trackingNumber,
      shippedAt: shipped == false
          ? null
          : previous.shippedAt ??
                (shipped == true
                    ? DateTime.now().toUtc().toIso8601String()
                    : null),
    );
    _stream.add(null);
  }

  @override
  Future<void> markShipped(
    String reminderId,
    String? trackingNumber,
    String? carrier,
  ) async {
    final i = _orders.indexWhere((o) => o.reminderId == reminderId);
    if (i < 0) throw StateError('Missing order');
    final o = _orders[i];
    if (o.shipped) throw StateError('Already shipped');
    final invalidTracking = trackingError(
      trackingNumber ?? o.trackingNumber ?? '',
      carrier ?? o.carrier ?? '',
    );
    if (invalidTracking != null) throw ArgumentError(invalidTracking);
    _orders[i] = OrderDetails(
      reminderId: o.reminderId,
      title: o.title,
      contextName: o.contextName,
      contextSlug: o.contextSlug,
      orderRef: o.orderRef,
      recipientName: o.recipientName,
      shipBy: o.shipBy,
      carrier: carrier ?? o.carrier,
      trackingNumber: trackingNumber ?? o.trackingNumber,
      shippedAt: DateTime.now().toIso8601String(),
    );
    final reminder = _items.where((r) => r.id == reminderId).firstOrNull;
    if (reminder != null) reminder.status = 'done';
  }

  @override
  Future<void> createFollowUp(String reminderId) async {
    followUpCalls++;
  }

  void remoteUpdateOrder(OrderDetails update, {bool completeReminder = false}) {
    final index = _orders.indexWhere((o) => o.reminderId == update.reminderId);
    if (index >= 0) _orders[index] = update;
    if (completeReminder) {
      final reminder = _items
          .where((r) => r.id == update.reminderId)
          .firstOrNull;
      if (reminder != null) reminder.status = 'done';
    }
    _stream.add(null);
  }

  @override
  Future<List<Reminder>> load() async =>
      _items.where((r) => r.status != 'done').map((r) => r.copy()).toList();
  @override
  Future<List<Reminder>> loadAll() async =>
      _items.map((r) => r.copy()).toList();
  @override
  Future<List<Reminder>> loadDoneToday() async {
    final today = DateTime.now();
    return _items
        .where((r) {
          final completed = completedAt[r.id];
          return r.status == 'done' &&
              completed != null &&
              completed.year == today.year &&
              completed.month == today.month &&
              completed.day == today.day;
        })
        .map((r) => r.copy())
        .toList();
  }

  @override
  Future<void> deleteReminder(String id) async {
    if (failBrowseWrites.contains('delete')) throw StateError('offline');
    final before = _items.length;
    _items.removeWhere((r) => r.id == id);
    if (_items.length == before) throw StateError('Reminder no longer exists.');
    _shoppingItems.remove(id);
    _orders.removeWhere((o) => o.reminderId == id);
    completedAt.remove(id);
    _stream.add(null);
  }

  @override
  Future<void> reopenReminder(String id) async {
    final gate = browseWriteGates['reopen'];
    if (gate != null) await gate.future;
    if (failBrowseWrites.contains('reopen')) throw StateError('offline');
    final reminder = _items.firstWhere((r) => r.id == id);
    reminder.status = 'open';
    reminder.snoozedUntil = null;
    completedAt.remove(id);
    _stream.add(null);
  }

  @override
  Future<void> complete(String id) async {
    final gate = browseWriteGates['complete'];
    if (gate != null) await gate.future;
    _items.firstWhere((r) => r.id == id).status = 'done';
    completedAt[id] = DateTime.now();
  }

  void notifyRemoteChange() => _stream.add(null);

  @override
  Future<void> restore(Reminder reminder) async {
    final item = _items.firstWhere((r) => r.id == reminder.id);
    item.status = reminder.status;
    item.snoozedUntil = reminder.snoozedUntil;
    if (item.status == 'done') {
      completedAt[item.id] = completedAt[item.id] ?? DateTime.now();
    } else {
      completedAt.remove(item.id);
    }
  }

  @override
  Future<void> snooze(String id, DateTime until) async {
    final r = _items.firstWhere((r) => r.id == id);
    r.status = 'snoozed';
    r.snoozedUntil = until;
  }

  @override
  Future<String?> save({
    String? id,
    required String title,
    required String? notes,
    required DateTime? dueAt,
    required String contextId,
    required bool isOrder,
    required List<String> channels,
    String? orderRef,
    String? recipientName,
    String? shipBy,
    String? carrier,
  }) async {
    final c = _contexts.firstWhere((e) => e.id == contextId);
    if (id == null) {
      reminderCreateCalls++;
      final newId = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
      lastCreatedReminderId = newId;
      _items.add(
        Reminder(
          id: newId,
          title: title,
          contextId: c.id,
          contextName: c.name,
          contextSlug: c.slug,
          notes: notes,
          dueAt: dueAt,
          isOrder: isOrder,
          channels: channels,
        ),
      );
      if (isOrder) {
        _orders.add(
          OrderDetails(
            reminderId: newId,
            title: title,
            contextName: c.name,
            orderRef: orderRef,
            recipientName: recipientName,
            shipBy: shipBy,
            carrier: carrier,
          ),
        );
      }
      return newId;
    } else {
      reminderUpdateCalls++;
      final r = _items.firstWhere((r) => r.id == id);
      r.title = title;
      r.notes = notes;
      r.dueAt = dueAt;
      r.isOrder = isOrder;
      if (!isOrder) {
        _orders.removeWhere((o) => o.reminderId == id);
      } else {
        final i = _orders.indexWhere((o) => o.reminderId == id);
        if (i < 0) {
          _orders.add(
            OrderDetails(
              reminderId: id,
              title: title,
              contextName: c.name,
              orderRef: orderRef,
              recipientName: recipientName,
              shipBy: shipBy,
              carrier: carrier,
            ),
          );
        } else {
          final o = _orders[i];
          _orders[i] = OrderDetails(
            reminderId: id,
            title: title,
            contextName: c.name,
            orderRef: orderRef,
            recipientName: recipientName,
            shipBy: shipBy,
            carrier: carrier,
            trackingNumber: o.trackingNumber,
            shippedAt: o.shippedAt,
          );
        }
      }
      return id;
    }
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  SupabaseRepository? _repository;
  String? _userId;

  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: widget.client.auth.onAuthStateChange,
    initialData: AuthState(
      AuthChangeEvent.initialSession,
      widget.client.auth.currentSession,
    ),
    builder: (context, snapshot) {
      final session = snapshot.data?.session;
      if (_userId != session?.user.id) {
        _repository?.dispose();
        _userId = session?.user.id;
        _repository = session == null
            ? null
            : (SupabaseRepository(widget.client)..subscribe());
      }
      return session == null
          ? LoginPage(client: widget.client)
          : TodayPage(
              key: ValueKey(session.user.id),
              repository: _repository!,
              onSignOut: widget.client.auth.signOut,
            );
    },
  );
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.bell, size: 54),
            const SizedBox(height: 16),
            Text(
              'Connect ezyReminder',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add mobile/env/dev.json with your Supabase URL and anon key, then run with --dart-define-from-file=env/dev.json.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.repository,
    this.demo = false,
    this.onSignOut,
    this.focusRepository,
  });
  final ReminderRepository repository;
  final FocusRepository? focusRepository;
  final bool demo;
  final Future<void> Function()? onSignOut;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<Reminder> reminders = [];
  List<Reminder> allReminders = [];
  List<Reminder> doneToday = [];
  List<ContextItem> contexts = [];
  List<OrderDetails> orders = [];
  Map<String, int>? shoppingCounts;
  String selected = 'all';
  String searchQuery = '';
  bool doneTodayExpanded = false;
  final deleting = <String>{};
  final completionPending = <String>{};
  String? homeOpenId;
  late final HouseholdRepository householdRepository =
      widget.repository is SupabaseRepository
      ? SupabaseHouseholdRepository(
          (widget.repository as SupabaseRepository).client,
        )
      : DemoHouseholdRepository();
  int tab = 0;
  bool loading = true;
  String? loadError;
  StreamSubscription<void>? subscription;
  final undo = <String, Reminder>{};
  int _refreshGeneration = 0;
  SettingsRepository? _settingsRepository;
  late final FocusController focusController;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final repository = widget.repository;
    focusController = FocusController(widget.focusRepository ?? (repository is SupabaseRepository
        ? SupabaseFocusRepository(repository.client)
        : DemoFocusRepository(loadReminders: () async {
            final rows = repository is BrowseRepository ? await (repository as BrowseRepository).loadAll() : await repository.load();
            return rows.where((r) => !r.isHomeMaintenance).map((r) => FocusReminder(id: r.id, title: r.title, contextSlug: r.contextSlug, status: r.status, dueAt: r.dueAt)).toList();
          })));
    refresh();
    subscription = widget.repository.changes.listen((_) { refresh(); unawaited(focusController.reload()); });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    _settingsRepository?.dispose();
    focusController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { refresh(); unawaited(focusController.reload()); }
  }

  Future<void> _openSettings() async {
    final remindersRepository = widget.repository;
    _settingsRepository ??= remindersRepository is SupabaseRepository
        ? SupabaseSettingsRepository(remindersRepository.client)
        : DemoSettingsRepository();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (settingsContext) {
          Future<void> leaveAccount() async {
            try {
              await widget.onSignOut?.call();
            } catch (_) {
              // Auth clears its local session before revoking the server token.
              if (remindersRepository is SupabaseRepository &&
                  remindersRepository.client.auth.currentSession != null) {
                rethrow;
              }
            }
            if (settingsContext.mounted) {
              Navigator.of(settingsContext).popUntil((route) => route.isFirst);
            }
          }

          return SettingsPage(
            repository: _settingsRepository!,
            onSignOut: leaveAccount,
            onDeleted: leaveAccount,
            onChanged: () {
              if (mounted) unawaited(refresh());
            },
          );
        },
      ),
    );
  }

  Widget _settingsButton() => IconButton(
    tooltip: 'Settings',
    onPressed: _openSettings,
    icon: const Icon(CupertinoIcons.gear),
  );

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    try {
      final ordersFuture = widget.repository is ShippingRepository
          ? (widget.repository as ShippingRepository).loadOrders().catchError(
              (_) => <OrderDetails>[],
            )
          : Future.value(<OrderDetails>[]);
      final countsFuture = widget.repository is ShoppingRepository
          ? (widget.repository as ShoppingRepository)
                .loadShoppingCounts()
                .then<Map<String, int>?>((counts) => counts)
                .catchError((_) => null)
          : Future.value(null);
      final browse = widget.repository is BrowseRepository
          ? widget.repository as BrowseRepository
          : null;
      final allFuture = browse?.loadAll() ?? widget.repository.load();
      final doneFuture = browse?.loadDoneToday() ?? Future.value(<Reminder>[]);
      final values = await Future.wait<Object?>([
        widget.repository.contexts(),
        widget.repository.load(),
        ordersFuture,
        countsFuture,
        allFuture,
        doneFuture,
      ]);
      if (!mounted || generation != _refreshGeneration) return;
      final pendingLocal = {
        for (final id in completionPending)
          if (allReminders.where((r) => r.id == id).firstOrNull case final row?)
            id: row.copy(),
      };
      setState(() {
        contexts = values[0] as List<ContextItem>;
        reminders = (values[1] as List<Reminder>)
            .where((reminder) => !deleting.contains(reminder.id))
            .toList();
        orders = values[2] as List<OrderDetails>;
        shoppingCounts = values[3] as Map<String, int>?;
        allReminders = (values[4] as List<Reminder>)
            .where((reminder) => !deleting.contains(reminder.id))
            .toList();
        doneToday = (values[5] as List<Reminder>)
            .where((reminder) => !deleting.contains(reminder.id))
            .toList();
        for (final entry in pendingLocal.entries) {
          allReminders.removeWhere((r) => r.id == entry.key);
          allReminders.add(entry.value);
          reminders.removeWhere((r) => r.id == entry.key);
          doneToday.removeWhere((r) => r.id == entry.key);
          if (entry.value.status == 'done') {
            doneToday.insert(0, entry.value.copy());
          } else {
            reminders.add(entry.value.copy());
          }
        }
        loading = false;
        loadError = null;
      });
    } catch (e) {
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          loading = false;
          loadError = 'Could not load reminders. Pull down to try again.';
        });
      }
    }
  }

  int? _shipDays(OrderDetails order) {
    final raw = order.shipBy;
    if (raw == null) return null;
    final parts = raw.split('-').map(int.parse).toList();
    final now = DateTime.now();
    return DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  }

  int get _shipSoonCount =>
      orders.where((o) => !o.shipped && (_shipDays(o) ?? 999) <= 3).length;

  Future<void> complete(Reminder r) async {
    if (r.isHomeMaintenance) {
      await _openSheet(r);
      return;
    }
    if (completionPending.contains(r.id) || deleting.contains(r.id)) return;
    HapticFeedback.lightImpact();
    final index = reminders.indexWhere((x) => x.id == r.id);
    if (index < 0) return;
    final previous = r.copy();
    setState(() {
      completionPending.add(r.id);
      reminders.removeAt(index);
      final all = allReminders.where((item) => item.id == r.id).firstOrNull;
      if (all != null) {
        all.status = 'done';
        all.snoozedUntil = null;
        if (!doneToday.any((item) => item.id == r.id)) {
          doneToday.insert(0, all.copy());
        }
      }
    });
    undo[r.id] = previous;
    final completion = widget.repository.complete(r.id);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('Completed “${r.title}”'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await completion;
              await widget.repository.restore(previous);
            } catch (_) {
              if (mounted) await refresh();
              return;
            }
            if (!mounted) return;
            setState(() {
              if (!reminders.any((item) => item.id == previous.id)) {
                reminders.insert(index.clamp(0, reminders.length), previous);
              }
            });
            undo.remove(r.id);
          },
        ),
      ),
    );
    try {
      await completion;
      if (mounted) setState(() => completionPending.remove(r.id));
    } catch (_) {
      if (mounted) {
        setState(() {
          completionPending.remove(r.id);
          final all = allReminders.where((item) => item.id == r.id).firstOrNull;
          if (all != null) {
            all.status = previous.status;
            all.snoozedUntil = previous.snoozedUntil;
          }
          doneToday.removeWhere((item) => item.id == r.id);
          if (previous.status == 'done' &&
              !doneToday.any((item) => item.id == r.id)) {
            doneToday.add(previous.copy());
          }
          if (!reminders.any((item) => item.id == previous.id)) {
            reminders.insert(index.clamp(0, reminders.length), previous);
          }
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not complete. Restored your reminder.'),
          ),
        );
      }
      if (mounted) await refresh();
    }
  }

  Future<void> toggleCompletionInAll(Reminder reminder) async {
    if (reminder.isHomeMaintenance) {
      await _openSheet(reminder);
      return;
    }
    if (widget.repository is! BrowseRepository ||
        deleting.contains(reminder.id) ||
        completionPending.contains(reminder.id)) {
      return;
    }
    final repository = widget.repository as BrowseRepository;
    final previous = reminder.copy();
    final reopening = previous.status == 'done';
    final current = allReminders.where((r) => r.id == reminder.id).firstOrNull;
    if (current == null) return;
    setState(() {
      completionPending.add(reminder.id);
      current.status = reopening ? 'open' : 'done';
      current.snoozedUntil = null;
      if (reopening) {
        if (!reminders.any((r) => r.id == current.id)) {
          reminders.add(current.copy());
        }
        doneToday.removeWhere((r) => r.id == current.id);
      } else {
        reminders.removeWhere((r) => r.id == current.id);
        if (!doneToday.any((r) => r.id == current.id)) {
          doneToday.insert(0, current.copy());
        }
      }
    });
    try {
      if (reopening) {
        await repository.reopenReminder(reminder.id);
      } else {
        await widget.repository.complete(reminder.id);
      }
      if (mounted) await refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        completionPending.remove(reminder.id);
        final item = allReminders.where((r) => r.id == previous.id).firstOrNull;
        if (item != null) {
          item.status = previous.status;
          item.snoozedUntil = previous.snoozedUntil;
        }
        reminders.removeWhere((r) => r.id == previous.id);
        doneToday.removeWhere((r) => r.id == previous.id);
        if (previous.status == 'done') {
          doneToday.add(previous.copy());
        } else {
          reminders.add(previous.copy());
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not confirm ${reopening ? 'reopen' : 'completion'}: $error',
          ),
        ),
      );
      await refresh();
    } finally {
      if (mounted) setState(() => completionPending.remove(reminder.id));
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    if (widget.repository is! BrowseRepository ||
        deleting.contains(reminder.id)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('“${reminder.title}” will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final indexAll = allReminders.indexWhere((r) => r.id == reminder.id);
    final indexActive = reminders.indexWhere((r) => r.id == reminder.id);
    final indexDone = doneToday.indexWhere((r) => r.id == reminder.id);
    setState(() {
      deleting.add(reminder.id);
      allReminders.removeWhere((r) => r.id == reminder.id);
      reminders.removeWhere((r) => r.id == reminder.id);
      doneToday.removeWhere((r) => r.id == reminder.id);
    });
    try {
      await (widget.repository as BrowseRepository).deleteReminder(reminder.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Reminder deleted.')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        deleting.remove(reminder.id);
        if (!allReminders.any((r) => r.id == reminder.id)) {
          allReminders.insert(indexAll.clamp(0, allReminders.length), reminder);
        }
        if (indexActive >= 0 && !reminders.any((r) => r.id == reminder.id)) {
          reminders.insert(
            indexActive.clamp(0, reminders.length),
            reminder.copy(),
          );
        }
        if (indexDone >= 0 && !doneToday.any((r) => r.id == reminder.id)) {
          doneToday.insert(
            indexDone.clamp(0, doneToday.length),
            reminder.copy(),
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete reminder: $error')),
      );
    } finally {
      if (mounted) setState(() => deleting.remove(reminder.id));
    }
  }

  List<Reminder> get visible => reminders
      .where((r) => selected == 'all' || r.contextId == selected)
      .toList();
  List<Reminder> get visibleDoneToday => doneToday
      .where((r) => selected == 'all' || r.contextId == selected)
      .toList();

  Widget _doneTodaySection(Palette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      InkWell(
        onTap: () => setState(() => doneTodayExpanded = !doneTodayExpanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                doneTodayExpanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 15,
                color: p.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'DONE TODAY (${visibleDoneToday.length})',
                style: TextStyle(
                  color: p.secondary,
                  fontSize: EzyDesignTokens.sectionHeaderFontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
        ),
      ),
      if (doneTodayExpanded)
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(EzyDesignTokens.rowRadius),
            boxShadow: [p.cardShadow],
          ),
          child: Column(
            children: [
              for (var i = 0; i < visibleDoneToday.length; i++)
                _row(
                  visibleDoneToday[i],
                  i,
                  visibleDoneToday.length,
                  p,
                  browse: true,
                ),
            ],
          ),
        ),
    ],
  );

  Widget _browseScreen(Palette p) {
    final query = searchQuery.trim().toLowerCase();
    final matching = allReminders.where((r) {
      final contextMatches = selected == 'all' || r.contextId == selected;
      return contextMatches &&
          (query.isEmpty || r.title.toLowerCase().contains(query));
    }).toList();
    final orderedContexts = contexts
        .where((c) => selected == 'all' || c.id == selected)
        .toList();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'All',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontWeight:
                                    EzyDesignTokens.screenTitleFontWeight,
                                fontSize: EzyDesignTokens.screenTitleFontSize,
                              ),
                        ),
                      ),
                      _settingsButton(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('all-search'),
                    onChanged: (value) => setState(() => searchQuery = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(CupertinoIcons.search),
                      hintText: 'Search reminders',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _contextPill('all', 'All', p),
                        ...contexts.map((c) => _contextPill(c.id, c.name, p)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FocusCard(controller: focusController, activeOnly: true),
                  if (loading)
                    for (var i = 0; i < 3; i++) _skeleton(p)
                  else if (loadError != null)
                    _empty(
                      loadError!,
                      CupertinoIcons.wifi_exclamationmark,
                      p,
                      onTap: refresh,
                    )
                  else if (matching.isEmpty)
                    _empty(
                      query.isEmpty
                          ? 'No reminders yet.'
                          : 'No reminders match “${searchQuery.trim()}”.',
                      CupertinoIcons.search,
                      p,
                    )
                  else ...[
                    for (final contextItem in orderedContexts)
                      ..._browseContext(
                        contextItem,
                        matching
                            .where((r) => r.contextId == contextItem.id)
                            .toList(),
                        p,
                      ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _browseContext(
    ContextItem contextItem,
    List<Reminder> source,
    Palette p,
  ) {
    if (source.isEmpty) return const [];
    int compare(Reminder a, Reminder b) {
      if ((a.status == 'done') != (b.status == 'done')) {
        return a.status == 'done' ? 1 : -1;
      }
      final ad = a.effectiveDueAt;
      final bd = b.effectiveDueAt;
      if (ad == null && bd == null) {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }

    final dated = source.where((r) => r.effectiveDueAt != null).toList()
      ..sort(compare);
    final someday = source.where((r) => r.effectiveDueAt == null).toList()
      ..sort(compare);
    final result = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 9, top: 12),
        child: Text(
          contextItem.name.toUpperCase(),
          style: TextStyle(
            color: _contextColor(p, contextItem.id),
            fontSize: EzyDesignTokens.sectionHeaderFontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: .7,
          ),
        ),
      ),
    ];
    if (dated.isNotEmpty) {
      result.add(_reminderCard(dated, p, browse: true));
      result.add(const SizedBox(height: 8));
    }
    if (someday.isNotEmpty) {
      result.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            'SOMEDAY',
            style: TextStyle(
              color: p.secondary,
              fontSize: EzyDesignTokens.sectionHeaderFontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: .6,
            ),
          ),
        ),
      );
      result.add(_reminderCard(someday, p, browse: true));
    }
    return result;
  }

  Widget _reminderCard(
    List<Reminder> items,
    Palette p, {
    required bool browse,
  }) => Container(
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(EzyDesignTokens.rowRadius),
      boxShadow: [p.cardShadow],
    ),
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++)
          _row(items[i], i, items.length, p, browse: browse),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<Palette>()!;
    final items = visible;
    return Scaffold(
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab == 0 || tab == 2) _quickAdd(p),
            BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: switch (tab) {
                2 => 3,
                3 => 2,
                _ => tab,
              },
              onTap: (i) => setState(() {
                tab = switch (i) {
                  2 => 3,
                  3 => 2,
                  _ => i,
                };
                if (tab == 2 && widget.repository is BrowseRepository) {
                  refresh();
                }
              }),
              items: [
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.calendar_today),
                  label: 'Today',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: _shipSoonCount > 0,
                    label: Text('$_shipSoonCount'),
                    child: Icon(CupertinoIcons.cube_box),
                  ),
                  label: 'Ship Queue',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.house),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(CupertinoIcons.list_bullet),
                  label: 'All',
                ),
              ],
            ),
          ],
        ),
      ),
      body: tab == 3
          ? HouseholdPage(
              reminders: widget.repository,
              repository: householdRepository,
              openId: homeOpenId,
              onSettings: _openSettings,
            )
          : tab == 1 && widget.repository is ShippingRepository
          ? SafeArea(
              child: ShipQueuePage(
                repository: widget.repository as ShippingRepository,
                onNewOrder: () => _openSheet(null, startWithOrder: true),
                onEditOrder: (id) async {
                  final reminder =
                      await (widget.repository as ShippingRepository)
                          .loadReminderForOrder(id);
                  if (mounted && reminder != null) await _openSheet(reminder);
                },
              ),
            )
          : tab == 2
          ? _browseScreen(p)
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Today',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        fontWeight: EzyDesignTokens
                                            .screenTitleFontWeight,
                                        fontSize:
                                            EzyDesignTokens.screenTitleFontSize,
                                        letterSpacing: -.3,
                                      ),
                                ),
                              ),
                              if (widget.demo)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.contexts[3].withValues(alpha: .14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'PREVIEW',
                                    style: TextStyle(
                                      color: p.contexts[3],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              _settingsButton(),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 48,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _contextPill('all', 'All', p),
                                ...contexts.map(
                                  (c) => _contextPill(c.id, c.name, p),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          FocusCard(controller: focusController, activeOnly: selected != 'all' && !['work', 'sidegig', 'side-gig', 'side_gig'].contains(contexts.where((c) => c.id == selected).firstOrNull?.slug)),
                          if (loading) ...[
                            for (var i = 0; i < 3; i++) _skeleton(p),
                          ] else if (loadError != null)
                            _empty(
                              loadError!,
                              CupertinoIcons.wifi_exclamationmark,
                              p,
                              onTap: refresh,
                            )
                          else if (items.isEmpty && visibleDoneToday.isEmpty)
                            _empty(
                              'All clear. Add a reminder when something comes to mind.',
                              CupertinoIcons.checkmark_circle,
                              p,
                            )
                          else ...[
                            ..._sections(items, p),
                            if (visibleDoneToday.isNotEmpty)
                              _doneTodaySection(p),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _contextPill(String id, String label, Palette p) {
    final active = selected == id;
    final tint = id == 'all' ? p.text : _contextColor(p, id);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        shape: const StadiumBorder(),
        selected: active,
        showCheckmark: false,
        onSelected: (_) => setState(() => selected = id),
        backgroundColor: p.surface,
        selectedColor: tint.withValues(alpha: .14),
        side: BorderSide(color: active ? tint : p.hairline),
        labelStyle: TextStyle(
          color: active ? tint : p.secondary,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  List<Widget> _sections(List<Reminder> items, Palette p) {
    final now = DateTime.now();
    final overdue = items
        .where(
          (r) => r.effectiveDueAt != null && r.effectiveDueAt!.isBefore(now),
        )
        .toList();
    final today = items
        .where(
          (r) =>
              r.effectiveDueAt != null &&
              _sameDay(r.effectiveDueAt!, now) &&
              !r.effectiveDueAt!.isBefore(now),
        )
        .toList();
    final upcoming = items
        .where(
          (r) =>
              r.effectiveDueAt != null &&
              r.effectiveDueAt!.isAfter(now) &&
              !_sameDay(r.effectiveDueAt!, now),
        )
        .toList();
    final someday = items.where((r) => r.effectiveDueAt == null).toList();
    final groups = <(String, List<Reminder>)>[
      ('Overdue', overdue),
      ('Today', today),
      ('Upcoming', upcoming),
      ('Someday', someday),
    ];
    final result = <Widget>[];
    for (final group in groups) {
      if (group.$1 == 'Upcoming') {
        final shipSoon = orders
            .where((o) => !o.shipped && (_shipDays(o) ?? 999) <= 3)
            .toList();
        if (shipSoon.isNotEmpty) {
          result.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 9, top: 10),
              child: InkWell(
                onTap: () => setState(() => tab = 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SHIP SOON',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.secondary,
                          fontSize: EzyDesignTokens.sectionHeaderFontSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .7,
                        ),
                      ),
                    ),
                    Text(
                      'Ship Queue',
                      style: TextStyle(color: p.contexts[1], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
          result.add(
            Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(EzyDesignTokens.rowRadius),
                boxShadow: [p.cardShadow],
              ),
              child: Column(
                children: shipSoon.map((o) {
                  final days = _shipDays(o)!;
                  return Material(
                    color: p.surface,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        CupertinoIcons.cube_box,
                        color: p.contexts[1],
                      ),
                      title: Text(
                        o.orderRef?.isNotEmpty == true ? o.orderRef! : o.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${o.recipientName ?? 'Order'} · ${days < 0
                            ? '${-days}d overdue'
                            : days == 0
                            ? 'today'
                            : days == 1
                            ? 'tomorrow'
                            : 'in $days days'}',
                      ),
                      onTap: () => setState(() => tab = 1),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
          result.add(const SizedBox(height: 14));
        }
      }
      if (group.$2.isEmpty) continue;
      result.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 9, top: 10),
          child: Text(
            group.$1.toUpperCase(),
            style: TextStyle(
              color: group.$1 == 'Overdue'
                  ? Theme.of(context).colorScheme.error
                  : p.secondary,
              fontSize: EzyDesignTokens.sectionHeaderFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: .7,
            ),
          ),
        ),
      );
      result.add(
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(EzyDesignTokens.rowRadius),
            boxShadow: [p.cardShadow],
          ),
          child: Column(
            children: [
              for (var i = 0; i < group.$2.length; i++)
                _row(group.$2[i], i, group.$2.length, p),
            ],
          ),
        ),
      );
      result.add(const SizedBox(height: 14));
    }
    return result;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  Color _contextColor(Palette p, String id) {
    final slug = contexts.where((c) => c.id == id).firstOrNull?.slug;
    final index = switch (slug) {
      'work' => 0,
      _ when _isSideGigSlug(slug) => 1,
      'social' => 2,
      'shopping' => 3,
      _ => 0,
    };
    return p.contexts[index];
  }

  Widget _row(
    Reminder r,
    int index,
    int count,
    Palette p, {
    bool browse = false,
  }) {
    final color = _contextColor(p, r.contextId);
    final due = r.effectiveDueAt;
    final isDone = r.status == 'done';
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (browse) {
            await toggleCompletionInAll(r);
          } else {
            await complete(r);
          }
          return false;
        }
        _snoozeMenu(r);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: p.contexts[2],
        child: const Icon(CupertinoIcons.checkmark, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: p.contexts[0].withValues(alpha: .2),
        child: Icon(CupertinoIcons.alarm, color: p.contexts[0]),
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: index < count - 1
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.hairline.withValues(alpha: .7)),
                ),
              )
            : null,
        child: Row(
          children: [
            _Ring(
              key: ValueKey('ring-${r.id}'),
              color: color,
              completed: isDone,
              onTap: () => browse ? toggleCompletionInAll(r) : complete(r),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => _openSheet(r),
                onLongPress: () => _showReminderMenu(r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      r.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDone ? p.secondary : p.text,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      r.contextSlug == 'shopping'
                          ? '${shoppingCounts == null ? 'Shopping list' : '${shoppingCounts![r.id] ?? 0} items left'} · ${r.contextName}'
                          : '${due == null ? 'Someday' : _relativeDue(due)} · ${r.contextName}',
                      style: TextStyle(
                        fontSize: EzyDesignTokens.dueChipFontSize,
                        color: due != null && due.isBefore(DateTime.now())
                            ? Theme.of(context).colorScheme.error
                            : p.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            if (r.isOrder)
              Icon(CupertinoIcons.cube_box, size: 16, color: p.secondary),
            if (r.channels.contains('email'))
              Icon(CupertinoIcons.envelope, size: 16, color: p.secondary),
            IconButton(
              tooltip: 'Reminder actions',
              onPressed: () => _showReminderMenu(r),
              icon: Icon(CupertinoIcons.ellipsis, color: p.secondary, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeDue(DateTime due) {
    final now = DateTime.now();
    final minutes = (due.difference(now).inMilliseconds.abs() / 60000).round();
    final past = due.isBefore(now);
    if (minutes < 60) {
      return past
          ? '${minutes.clamp(1, 60)}m overdue'
          : 'in ${minutes.clamp(1, 60)}m';
    }
    if (minutes < 1440 && _sameDay(due, now)) {
      final hours = (minutes / 60).round();
      return past ? '${hours}h overdue' : 'in ${hours}h';
    }
    return _dueLabel(due);
  }

  String _dueLabel(DateTime d) => _sameDay(d, DateTime.now())
      ? '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}'
      : '${d.month}/${d.day}';
  Widget _skeleton(Palette p) => Container(
    height: 62,
    margin: const EdgeInsets.only(bottom: 9),
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [p.cardShadow],
    ),
  );
  Widget _empty(String text, IconData icon, Palette p, {VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            children: [
              Icon(icon, size: 34, color: p.secondary),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.secondary),
              ),
            ],
          ),
        ),
      );
  Widget _quickAdd(Palette p) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          onTap: () => _openSheet(null),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.hairline),
              boxShadow: [p.cardShadow],
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.add, color: p.contexts[0]),
                const SizedBox(width: 11),
                Flexible(
                  child: Text(
                    'Remind me to…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.secondary, fontSize: 16),
                  ),
                ),
                const Spacer(),
                Icon(CupertinoIcons.arrow_up_circle_fill, color: p.contexts[0]),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _showReminderMenu(Reminder reminder) {
    if (deleting.contains(reminder.id)) return;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (menuContext) => CupertinoActionSheet(
        title: Text(reminder.title),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(menuContext);
              _openSheet(reminder);
            },
            child: const Text('Edit'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(menuContext);
              _deleteReminder(reminder);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(menuContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _snoozeMenu(Reminder r) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('Snooze “${r.title}”'),
        actions: [
          for (final option in [
            ('1 hour', DateTime.now().add(const Duration(hours: 1))),
            (
              'Tonight',
              DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
                19,
              ),
            ),
            (
              'Tomorrow',
              DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day + 1,
                9,
              ),
            ),
          ])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _snooze(
                  r,
                  option.$2.isAfter(DateTime.now())
                      ? option.$2
                      : DateTime(
                          option.$2.year,
                          option.$2.month,
                          option.$2.day + 1,
                          option.$2.hour,
                          option.$2.minute,
                        ),
                );
              },
              child: Text(option.$1),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickSnooze(r);
            },
            child: const Text('Pick…'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickSnooze(Reminder r) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => CompactDateTimePicker(
        initial: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    if (picked != null && mounted) await _snooze(r, picked);
  }

  Future<void> _snooze(Reminder r, DateTime until) async {
    final old = r.copy();
    setState(() {
      r.status = 'snoozed';
      r.snoozedUntil = until;
    });
    try {
      await widget.repository.snooze(r.id, until);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text('Snoozed until ${_dueLabel(until)}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                widget.repository
                    .restore(old)
                    .then((_) {
                      if (mounted) refresh();
                    })
                    .catchError((Object error) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not undo snooze. Pull down to refresh.',
                            ),
                          ),
                        );
                        refresh();
                      }
                    });
              },
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          r.status = old.status;
          r.snoozedUntil = old.snoozedUntil;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not snooze. Restored your reminder.'),
          ),
        );
      }
    }
  }

  Future<void> _openSheet(
    Reminder? reminder, {
    bool startWithOrder = false,
  }) async {
    if (reminder?.isHomeMaintenance == true) {
      setState(() {
        homeOpenId = reminder!.id;
        tab = 3;
      });
      return;
    }
    final snapshot = reminder?.copy();
    if (snapshot != null &&
        snapshot.contextSlug == 'shopping' &&
        widget.repository is ShoppingRepository) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Theme.of(context).brightness == Brightness.dark
            ? EzyDesignTokens.darkScrim
            : EzyDesignTokens.lightScrim,
        sheetAnimationStyle: AnimationStyle(
          duration: reduceMotion
              ? Duration.zero
              : EzyDesignTokens.sheetDuration,
          curve: reduceMotion ? Curves.linear : EzyDesignTokens.sheetCurve,
        ),
        builder: (_) => ShoppingListSheet(
          reminder: snapshot,
          repository: widget.repository as ShoppingRepository,
          changes: widget.repository.changes,
        ),
      );
      if (mounted && result == true) refresh();
      return;
    }
    OrderDetails? order;
    var orderLoadFailed = false;
    WorkDetails? workDetails;
    SideGigDetails? sideGigDetails;
    if (reminder?.isOrder == true && widget.repository is ShippingRepository) {
      try {
        order = (await (widget.repository as ShippingRepository).loadOrders())
            .where((o) => o.reminderId == reminder!.id)
            .firstOrNull;
      } catch (error) {
        orderLoadFailed = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load order details: $error')),
          );
        }
      }
    }
    if (reminder != null && widget.repository is ContextDetailsRepository) {
      try {
        final repository = widget.repository as ContextDetailsRepository;
        final values = await Future.wait<Object?>([
          repository.loadWorkDetails(reminder.id),
          repository.loadSideGigDetails(reminder.id),
        ]);
        workDetails = values[0] as WorkDetails?;
        sideGigDetails = values[1] as SideGigDetails?;
      } catch (error) {
        orderLoadFailed = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load context details: $error')),
          );
        }
      }
    }
    if (!mounted || orderLoadFailed) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!mounted) return;
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: (Theme.of(context).brightness == Brightness.dark
          ? EzyDesignTokens.darkScrim
          : EzyDesignTokens.lightScrim),
      sheetAnimationStyle: AnimationStyle(
        duration: reduceMotion ? Duration.zero : EzyDesignTokens.sheetDuration,
        reverseDuration: reduceMotion
            ? Duration.zero
            : EzyDesignTokens.sheetDuration,
        curve: reduceMotion ? Curves.linear : EzyDesignTokens.sheetCurve,
        reverseCurve: reduceMotion ? Curves.linear : EzyDesignTokens.sheetCurve,
      ),
      builder: (ctx) => _ReminderSheet(
        reminder: snapshot,
        onFocus: snapshot != null && (snapshot.contextSlug == 'work' || _isSideGigSlug(snapshot.contextSlug)) && (snapshot.status == 'open' || snapshot.status == 'snoozed') ? () => Navigator.pop(ctx, 'focus') : null,
        contexts: contexts,
        save: widget.repository.save,
        changes: widget.repository.changes,
        reload: widget.repository.load,
        startWithOrder: startWithOrder,
        order: order,
        loadOrder: reminder == null || widget.repository is! ShippingRepository
            ? null
            : () async =>
                  (await (widget.repository as ShippingRepository).loadOrders())
                      .where((o) => o.reminderId == reminder.id)
                      .firstOrNull,
        saveOrderReminder: widget.repository is ShipmentEditingRepository
            ? (widget.repository as ShipmentEditingRepository).saveOrderReminder
            : null,
        markShipped: widget.repository is ShippingRepository
            ? (id, tracking, carrier) =>
                  (widget.repository as ShippingRepository).markShipped(
                    id,
                    tracking,
                    carrier,
                  )
            : null,
        createFollowUp: widget.repository is ShippingRepository
            ? (id) =>
                  (widget.repository as ShippingRepository).createFollowUp(id)
            : null,
        workDetails: workDetails,
        sideGigDetails: sideGigDetails,
        loadWorkDetails:
            reminder == null || widget.repository is! ContextDetailsRepository
            ? null
            : () => (widget.repository as ContextDetailsRepository)
                  .loadWorkDetails(reminder.id),
        loadSideGigDetails:
            reminder == null || widget.repository is! ContextDetailsRepository
            ? null
            : () => (widget.repository as ContextDetailsRepository)
                  .loadSideGigDetails(reminder.id),
        saveWorkDetails: widget.repository is ContextDetailsRepository
            ? (
                id, {
                required managerName,
                required departmentResource,
                required projectName,
              }) => (widget.repository as ContextDetailsRepository)
                  .saveWorkDetails(
                    id,
                    managerName: managerName,
                    departmentResource: departmentResource,
                    projectName: projectName,
                  )
            : null,
        saveSideGigDetails: widget.repository is ContextDetailsRepository
            ? (id, {required initiativeName, required clientName}) =>
                  (widget.repository as ContextDetailsRepository)
                      .saveSideGigDetails(
                        id,
                        initiativeName: initiativeName,
                        clientName: clientName,
                      )
            : null,
      ),
    );
    if (!mounted) return;
    if (result == 'focus' && snapshot != null) {
      await openFocus(context, focusController, reminder: FocusReminder(id: snapshot.id, title: snapshot.title, contextSlug: snapshot.contextSlug, status: snapshot.status, dueAt: snapshot.dueAt));
      return;
    }
    if (result is String && widget.repository is ShoppingRepository) {
      await refresh();
      final created = reminders.where((r) => r.id == result).firstOrNull;
      if (mounted && created != null) await _openSheet(created);
    } else if (result == true) {
      refresh();
    }
  }
}

class _Ring extends StatefulWidget {
  const _Ring({
    super.key,
    required this.color,
    required this.onTap,
    this.completed = false,
  });
  final Color color;
  final VoidCallback onTap;
  final bool completed;
  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: EzyDesignTokens.rowPopDuration,
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool completing = false;
  void tap() {
    if (completing) return;
    HapticFeedback.selectionClick();
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onTap();
      return;
    }
    completing = true;
    controller.forward(from: 0).whenComplete(() {
      completing = false;
      widget.onTap();
    });
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.completed ? 'Reopen reminder' : 'Complete reminder',
    child: GestureDetector(
      onTap: tap,
      child: ScaleTransition(
        scale: TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(
              begin: EzyDesignTokens.rowPopScaleStart,
              end: EzyDesignTokens.rowPopScalePeak,
            ).chain(CurveTween(curve: Curves.easeOut)),
            weight: 50,
          ),
          TweenSequenceItem(
            tween: Tween(
              begin: EzyDesignTokens.rowPopScalePeak,
              end: EzyDesignTokens.rowPopScaleEnd,
            ).chain(CurveTween(curve: Curves.easeIn)),
            weight: 50,
          ),
        ]).animate(controller),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.completed ? widget.color : Colors.transparent,
              border: Border.all(color: widget.color, width: 2.2),
            ),
            child: widget.completed
                ? const Icon(
                    CupertinoIcons.checkmark,
                    size: 14,
                    color: Colors.white,
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({
    required this.reminder,
    required this.contexts,
    required this.save,
    required this.changes,
    required this.reload,
    this.startWithOrder = false,
    this.onFocus,
    this.order,
    this.loadOrder,
    this.markShipped,
    this.saveOrderReminder,
    this.createFollowUp,
    this.workDetails,
    this.sideGigDetails,
    this.loadWorkDetails,
    this.loadSideGigDetails,
    this.saveWorkDetails,
    this.saveSideGigDetails,
  });
  final Reminder? reminder;
  final List<ContextItem> contexts;
  final Stream<void> changes;
  final Future<List<Reminder>> Function() reload;
  final bool startWithOrder;
  final VoidCallback? onFocus;
  final OrderDetails? order;
  final Future<OrderDetails?> Function()? loadOrder;
  final Future<void> Function({
    required Reminder reminder,
    required OrderDetails order,
    bool? shipped,
  })?
  saveOrderReminder;
  final Future<void> Function(String, String?, String?)? markShipped;
  final Future<void> Function(String)? createFollowUp;
  final WorkDetails? workDetails;
  final SideGigDetails? sideGigDetails;
  final Future<WorkDetails?> Function()? loadWorkDetails;
  final Future<SideGigDetails?> Function()? loadSideGigDetails;
  final Future<void> Function(
    String, {
    required String? managerName,
    required String? departmentResource,
    required String? projectName,
  })?
  saveWorkDetails;
  final Future<void> Function(
    String, {
    required String? initiativeName,
    required String? clientName,
  })?
  saveSideGigDetails;
  final Future<String?> Function({
    String? id,
    required String title,
    required String? notes,
    required DateTime? dueAt,
    required String contextId,
    required bool isOrder,
    required List<String> channels,
    String? orderRef,
    String? recipientName,
    String? shipBy,
    String? carrier,
  })
  save;
  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet>
    with WidgetsBindingObserver {
  late final title = TextEditingController(text: widget.reminder?.title ?? '');
  late final notes = TextEditingController(text: widget.reminder?.notes ?? '');
  String? contextId;
  DateTime? dueAt;
  bool isOrder = false, saving = false, attempted = false;
  late final orderRef = TextEditingController();
  late final recipient = TextEditingController();
  late final carrier = TextEditingController();
  late final tracking = TextEditingController();
  late final managerName = TextEditingController();
  late final departmentResource = TextEditingController();
  late final projectName = TextEditingController();
  late final initiativeName = TextEditingController();
  late final clientName = TextEditingController();
  bool showWorkPanel = false, showSideGigPanel = false;
  String? draftReminderId;
  bool creationResultUnknown = false;
  int detailLoadGeneration = 0;
  DateTime? shipBy;
  String? titleError, contextError;
  final dirty = <String>{};
  StreamSubscription<void>? realtime;
  List<String> channels = const [];
  bool merging = false;
  bool shipping = false;
  bool shipmentShipped = false;
  OrderDetails? currentOrder;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    currentOrder = widget.order;
    shipmentShipped = widget.order?.shipped ?? false;
    contextId = widget.reminder?.contextId;
    dueAt = widget.reminder?.dueAt;
    isOrder = widget.reminder?.isOrder ?? widget.startWithOrder;
    orderRef.text = widget.order?.orderRef ?? '';
    recipient.text = widget.order?.recipientName ?? '';
    carrier.text = widget.order?.carrier ?? '';
    tracking.text = widget.order?.trackingNumber ?? '';
    if (widget.order?.shipBy case final value?) {
      final p = value.split('-').map(int.parse).toList();
      shipBy = DateTime(p[0], p[1], p[2]);
    }
    channels = widget.reminder?.channels ?? const [];
    final work = widget.workDetails;
    final sideGig = widget.sideGigDetails;
    managerName.text = work?.managerName ?? '';
    departmentResource.text = work?.departmentResource ?? '';
    projectName.text = work?.projectName ?? '';
    initiativeName.text = sideGig?.initiativeName ?? '';
    clientName.text = sideGig?.clientName ?? '';
    showWorkPanel = work != null;
    showSideGigPanel = sideGig != null;
    title.addListener(() {
      if (!merging) dirty.add('title');
    });
    notes.addListener(() {
      if (!merging) dirty.add('notes');
    });
    orderRef.addListener(() {
      if (!merging) dirty.add('orderRef');
    });
    recipient.addListener(() {
      if (!merging) dirty.add('recipient');
    });
    carrier.addListener(() {
      if (!merging) dirty.add('carrier');
    });
    tracking.addListener(() {
      if (!merging) dirty.add('tracking');
    });
    managerName.addListener(() {
      if (!merging) dirty.add('work.manager');
    });
    departmentResource.addListener(() {
      if (!merging) dirty.add('work.department');
    });
    projectName.addListener(() {
      if (!merging) dirty.add('work.project');
    });
    initiativeName.addListener(() {
      if (!merging) dirty.add('sidegig.initiative');
    });
    clientName.addListener(() {
      if (!merging) dirty.add('sidegig.client');
    });
    realtime = widget.changes.listen((_) => _mergeRemote());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    title.dispose();
    notes.dispose();
    orderRef.dispose();
    recipient.dispose();
    carrier.dispose();
    tracking.dispose();
    managerName.dispose();
    departmentResource.dispose();
    projectName.dispose();
    initiativeName.dispose();
    clientName.dispose();
    realtime?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _mergeRemote();
  }

  Future<void> _save() async {
    if (creationResultUnknown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not confirm creation. Refresh before retrying to avoid a duplicate.',
          ),
        ),
      );
      return;
    }
    setState(() => attempted = true);
    final badTitle = title.text.trim().isEmpty;
    final badContext = contextId == null;
    if (badTitle || badContext) {
      setState(() {
        titleError = badTitle ? 'Title required' : null;
        contextError = badContext ? 'Choose a context' : null;
      });
      return;
    }
    final atomicOrderEdit =
        widget.reminder != null &&
        isOrder &&
        currentOrder != null &&
        widget.saveOrderReminder != null;
    final invalidTracking = atomicOrderEdit
        ? trackingError(tracking.text, carrier.text)
        : null;
    if (invalidTracking != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(invalidTracking)));
      return;
    }
    final submittedContextId = contextId!;
    final submittedIsOrder = isOrder;
    final submittedWorkPanel = showWorkPanel;
    final submittedSideGigPanel = showSideGigPanel;
    final submittedManagerName = _nullable(managerName.text);
    final submittedDepartmentResource = _nullable(departmentResource.text);
    final submittedProjectName = _nullable(projectName.text);
    final submittedInitiativeName = _nullable(initiativeName.text);
    final submittedClientName = _nullable(clientName.text);
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    try {
      String? savedId;
      if (atomicOrderEdit) {
        final existing = widget.reminder!;
        await widget.saveOrderReminder!(
          reminder: Reminder(
            id: existing.id,
            title: title.text.trim(),
            notes: _nullable(notes.text),
            dueAt: dueAt,
            contextId: submittedContextId,
            contextName: existing.contextName,
            contextSlug: existing.contextSlug,
            isOrder: true,
            channels: List.of(channels),
          ),
          order: OrderDetails(
            reminderId: existing.id,
            orderRef: _nullable(orderRef.text),
            recipientName: _nullable(recipient.text),
            shipBy: shipBy == null ? null : _dateOnly(shipBy!),
            carrier: _nullable(carrier.text),
            trackingNumber: _nullable(tracking.text),
          ),
          shipped: dirty.contains('shipmentStatus') ? shipmentShipped : null,
        );
        savedId = existing.id;
      } else {
        savedId = await widget.save(
          id: widget.reminder?.id ?? draftReminderId,
          title: title.text.trim(),
          notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
          dueAt: dueAt,
          contextId: submittedContextId,
          isOrder: submittedIsOrder,
          channels: channels,
          orderRef: orderRef.text.trim().isEmpty ? null : orderRef.text.trim(),
          recipientName: recipient.text.trim().isEmpty
              ? null
              : recipient.text.trim(),
          shipBy: shipBy == null ? null : _dateOnly(shipBy!),
          carrier: carrier.text.trim().isEmpty ? null : carrier.text.trim(),
        );
      }
      if (savedId == null &&
          widget.reminder?.id == null &&
          draftReminderId == null) {
        creationResultUnknown = true;
        throw StateError(
          'The server did not return a reminder ID, so this reminder may have been saved. Refresh before retrying to avoid a duplicate.',
        );
      }
      final stableId = widget.reminder?.id ?? draftReminderId ?? savedId;
      if (widget.reminder == null && stableId != null) {
        // Retain the create RPC's ID before the optional second write. A failed
        // panel upsert can then be retried without creating a duplicate reminder.
        draftReminderId = stableId;
      }
      if (stableId != null &&
          widget.saveWorkDetails != null &&
          _contextSlug(submittedContextId) == 'work' &&
          submittedWorkPanel) {
        try {
          await widget.saveWorkDetails!(
            stableId,
            managerName: submittedManagerName,
            departmentResource: submittedDepartmentResource,
            projectName: submittedProjectName,
          );
        } catch (error) {
          throw StateError(
            'Reminder saved, but follow-up details failed to save: $error',
          );
        }
      }
      if (stableId != null &&
          widget.saveSideGigDetails != null &&
          _isSideGigSlug(_contextSlug(submittedContextId)) &&
          !submittedIsOrder &&
          submittedSideGigPanel) {
        try {
          await widget.saveSideGigDetails!(
            stableId,
            initiativeName: submittedInitiativeName,
            clientName: submittedClientName,
          );
        } catch (error) {
          throw StateError(
            'Reminder saved, but initiative details failed to save: $error',
          );
        }
      }
      if (mounted) {
        final createdShoppingList =
            widget.reminder == null &&
            _contextSlug(submittedContextId) == 'shopping';
        Navigator.pop(context, createdShoppingList ? savedId : true);
      }
    } catch (e) {
      if (mounted) {
        if (e is ReminderCreationIdMissing) creationResultUnknown = true;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _mergeRemote() async {
    final id = widget.reminder?.id ?? draftReminderId;
    if (id == null) return;
    final generation = ++detailLoadGeneration;
    try {
      final remote = (await widget.reload())
          .where((r) => r.id == id)
          .firstOrNull;
      final remoteOrder = await widget.loadOrder?.call();
      final remoteWork = await widget.loadWorkDetails?.call();
      final remoteSideGig = await widget.loadSideGigDetails?.call();
      if (generation != detailLoadGeneration) return;
      if (!mounted) return;
      merging = true;
      setState(() {
        if (remote != null) {
          if (!dirty.contains('title')) title.text = remote.title;
          if (!dirty.contains('notes')) notes.text = remote.notes ?? '';
          if (!dirty.contains('context')) contextId = remote.contextId;
          if (!dirty.contains('dueAt')) dueAt = remote.dueAt;
          if (!dirty.contains('isOrder')) isOrder = remote.isOrder;
          if (!dirty.contains('channels')) channels = remote.channels;
        }
        if (remoteOrder != null) {
          currentOrder = remoteOrder;
          if (!dirty.contains('tracking')) {
            tracking.text = remoteOrder.trackingNumber ?? '';
          }
          if (!dirty.contains('shipmentStatus')) {
            shipmentShipped = remoteOrder.shipped;
          }
          if (!dirty.contains('orderRef')) {
            orderRef.text = remoteOrder.orderRef ?? '';
          }
          if (!dirty.contains('recipient')) {
            recipient.text = remoteOrder.recipientName ?? '';
          }
          if (!dirty.contains('carrier')) {
            carrier.text = remoteOrder.carrier ?? '';
          }
          if (!dirty.contains('shipBy')) {
            shipBy = _parseShipBy(remoteOrder.shipBy);
          }
        }
        if (remoteWork != null) {
          if (!dirty.contains('work.manager')) {
            managerName.text = remoteWork.managerName ?? '';
          }
          if (!dirty.contains('work.department')) {
            departmentResource.text = remoteWork.departmentResource ?? '';
          }
          if (!dirty.contains('work.project')) {
            projectName.text = remoteWork.projectName ?? '';
          }
          if (showWorkPanel == false &&
              !dirty.any((field) => field.startsWith('work.')) &&
              !dirty.contains('work.enabled')) {
            showWorkPanel = true;
          }
        }
        if (remoteSideGig != null) {
          if (!dirty.contains('sidegig.initiative')) {
            initiativeName.text = remoteSideGig.initiativeName ?? '';
          }
          if (!dirty.contains('sidegig.client')) {
            clientName.text = remoteSideGig.clientName ?? '';
          }
          if (showSideGigPanel == false &&
              !dirty.any((field) => field.startsWith('sidegig.')) &&
              !dirty.contains('sidegig.enabled')) {
            showSideGigPanel = true;
          }
        }
      });
      merging = false;
    } catch (_) {
      merging = false;
      // Keep the user's in-progress edits visible when a refresh is unavailable.
    }
  }

  DateTime? _parseShipBy(String? value) {
    if (value == null) return null;
    final parts = value.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _markShipped() async {
    final id = widget.reminder?.id;
    if (id == null || widget.markShipped == null || shipping) return;
    if (dirty.difference({'tracking'}).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Save your reminder changes before marking it shipped.',
          ),
        ),
      );
      return;
    }
    final invalidTracking = trackingError(
      tracking.text.trim().isEmpty
          ? currentOrder?.trackingNumber ?? ''
          : tracking.text,
      carrier.text,
    );
    if (invalidTracking != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(invalidTracking)));
      return;
    }
    setState(() => shipping = true);
    final messenger = ScaffoldMessenger.of(context);
    var followUpPendingOrDone = false;
    try {
      await widget.markShipped!(
        id,
        tracking.text.trim().isEmpty
            ? currentOrder?.trackingNumber
            : tracking.text.trim(),
        carrier.text.trim().isEmpty
            ? currentOrder?.carrier
            : carrier.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Shipped ✓ — remind me to follow up?'),
          action: widget.createFollowUp == null
              ? null
              : SnackBarAction(
                  label: '+3d follow-up',
                  onPressed: () async {
                    if (followUpPendingOrDone) return;
                    followUpPendingOrDone = true;
                    try {
                      await widget.createFollowUp!(id);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Follow-up scheduled')),
                      );
                    } catch (error) {
                      followUpPendingOrDone = false;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Could not create follow-up: $error'),
                        ),
                      );
                    }
                  },
                ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark shipped: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => shipping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<Palette>()!;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .48,
      maxChildSize: .96,
      expand: false,
      builder: (ctx, scroll) => Material(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(EzyDesignTokens.sheetRadius),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(EzyDesignTokens.sheetRadius),
            ),
            boxShadow: [p.sheetShadow],
          ),
          child: AbsorbPointer(
            absorbing: saving,
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + kb),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.secondary.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.reminder == null ? 'New reminder' : 'Reminder',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: title,
                  autofocus: widget.reminder == null,
                  decoration: InputDecoration(
                    hintText: 'What do you need to remember?',
                    errorText: titleError,
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: titleError == null
                            ? p.hairline
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  onChanged: (_) {
                    if (attempted && title.text.trim().isNotEmpty) {
                      setState(() => titleError = null);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: contextId,
                  decoration: InputDecoration(
                    labelText: 'Context',
                    errorText: contextError,
                    border: const OutlineInputBorder(),
                  ),
                  items: widget.contexts
                      .map(
                        (c) => DropdownMenuItem(
                          key: ValueKey('context-option-${c.id}'),
                          value: c.id,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    contextId = v;
                    contextError = null;
                    dirty.add('context');
                    if (_isShopping && isOrder) {
                      isOrder = false;
                      dirty.add('isOrder');
                    }
                  }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('When'),
                  subtitle: Text(dueAt == null ? 'No date' : _format(dueAt!)),
                  trailing: const Icon(CupertinoIcons.calendar),
                  onTap: _pickDateTime,
                ),
                if (dueAt != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() {
                        dueAt = null;
                        dirty.add('dueAt');
                      }),
                      child: const Text('No date'),
                    ),
                  ),
                if (!_isShopping)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Order'),
                    subtitle: const Text('Add to Ship Queue'),
                    value: isOrder,
                    onChanged: (v) => setState(() {
                      isOrder = v;
                      dirty.add('isOrder');
                    }),
                  ),
                if (isOrder) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: orderRef,
                    decoration: const InputDecoration(
                      labelText: 'Order ref',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: recipient,
                    decoration: const InputDecoration(
                      labelText: 'Recipient',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ship by'),
                    subtitle: Text(
                      shipBy == null ? 'No date' : _dateOnly(shipBy!),
                    ),
                    trailing: const Icon(CupertinoIcons.calendar),
                    onTap: _pickShipBy,
                  ),
                  if (shipBy != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() {
                          shipBy = null;
                          dirty.add('shipBy');
                        }),
                        child: const Text('No date'),
                      ),
                    ),
                  CarrierField(
                    controller: carrier,
                    onChanged: () => setState(() {}),
                  ),
                  if (widget.reminder != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TrackingField(
                        controller: tracking,
                        carrier: carrier.text,
                        suffixIcon: IconButton(
                          tooltip: 'Paste tracking number',
                          icon: const Icon(CupertinoIcons.doc_on_clipboard),
                          onPressed: () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (data?.text != null && mounted) {
                              tracking.text = data!.text!;
                            }
                          },
                        ),
                      ),
                    ),
                  if (widget.reminder != null &&
                      currentOrder != null &&
                      widget.saveOrderReminder != null)
                    SwitchListTile.adaptive(
                      key: const ValueKey('shipment-status-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Shipped'),
                      subtitle: Text(
                        shipmentShipped
                            ? 'Completed shipment'
                            : currentOrder!.shipped
                            ? 'Saving returns this order to Ship Queue and reopens its reminder.'
                            : 'Saving as shipped also completes this reminder.',
                      ),
                      value: shipmentShipped,
                      onChanged: (value) => setState(() {
                        shipmentShipped = value;
                        dirty.add('shipmentStatus');
                      }),
                    ),
                  if (currentOrder?.shipped == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Shipped${currentOrder?.shippedAt == null ? '' : ' · ${DateTime.tryParse(currentOrder!.shippedAt!)?.toLocal().month}/${DateTime.tryParse(currentOrder!.shippedAt!)?.toLocal().day}'}',
                      style: TextStyle(color: p.secondary),
                    ),
                    if (currentOrder?.trackingNumber?.isNotEmpty == true)
                      SelectableText(
                        'Tracking · ${currentOrder!.trackingNumber}',
                      ),
                  ] else if (widget.markShipped != null &&
                      widget.reminder != null &&
                      !shipmentShipped)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: shipping ? null : _markShipped,
                        icon: const Icon(CupertinoIcons.cube_box),
                        label: Text(
                          shipping ? 'Marking shipped…' : 'Mark shipped',
                        ),
                      ),
                    ),
                ],
                if (_isWork && widget.saveWorkDetails != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    key: const ValueKey('work-details-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add follow-up details'),
                    value: showWorkPanel,
                    onChanged: (value) => setState(() {
                      showWorkPanel = value;
                      dirty.add('work.enabled');
                    }),
                  ),
                  if (showWorkPanel) ...[
                    TextField(
                      key: const ValueKey('work-manager'),
                      controller: managerName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Manager',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('work-department-resource'),
                      controller: departmentResource,
                      decoration: const InputDecoration(
                        labelText: 'Department resource',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('work-project'),
                      controller: projectName,
                      decoration: const InputDecoration(
                        labelText: 'Project',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
                if (_isSideGig &&
                    !isOrder &&
                    widget.saveSideGigDetails != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    key: const ValueKey('sidegig-details-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add initiative details'),
                    value: showSideGigPanel,
                    onChanged: (value) => setState(() {
                      showSideGigPanel = value;
                      dirty.add('sidegig.enabled');
                    }),
                  ),
                  if (showSideGigPanel) ...[
                    TextField(
                      key: const ValueKey('sidegig-initiative'),
                      controller: initiativeName,
                      decoration: const InputDecoration(
                        labelText: 'Initiative',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('sidegig-client'),
                      controller: clientName,
                      decoration: const InputDecoration(
                        labelText: 'Client / buyer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
                if (widget.onFocus != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(onPressed: saving ? null : widget.onFocus, icon: const Icon(CupertinoIcons.scope), label: const Text('Focus on this')),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: saving ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(saving ? 'Saving…' : 'Save reminder'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _format(DateTime d) =>
      '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}, ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.day} · ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  bool get _isShopping =>
      widget.contexts.where((c) => c.id == contextId).firstOrNull?.slug ==
      'shopping';
  bool get _isWork => _contextSlug(contextId) == 'work';
  bool get _isSideGig => _isSideGigSlug(_contextSlug(contextId));
  String? _contextSlug(String? id) =>
      widget.contexts.where((c) => c.id == id).firstOrNull?.slug;
  Future<void> _pickShipBy() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: shipBy ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        shipBy = DateTime(picked.year, picked.month, picked.day);
        dirty.add('shipBy');
      });
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = dueAt ?? now.add(const Duration(hours: 1));
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => CompactDateTimePicker(initial: initial),
    );
    if (picked != null && mounted) {
      setState(() {
        dueAt = picked;
        dirty.add('dueAt');
      });
    }
  }
}
