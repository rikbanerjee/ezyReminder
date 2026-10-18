import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ezyreminder/main.dart' as app;

void main() {
  late _SupabaseHarness backend;
  late SupabaseClient client;
  late app.SupabaseRepository repository;

  setUp(() async {
    backend = await _SupabaseHarness.start();
    client = SupabaseClient(
      'http://127.0.0.1:${backend.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'owner@example.com',
      password: 'local-test-password',
    );
    repository = app.SupabaseRepository(client);
  });

  tearDown(() async {
    repository.dispose();
    await client.dispose();
    await backend.close();
  });

  test(
    'new order sends a date-only ship-by value in create_reminder RPC',
    () async {
      await repository.save(
        title: 'Ship the mug',
        notes: null,
        dueAt: null,
        contextId: 'side-gig-context',
        isOrder: true,
        channels: const ['email'],
        orderRef: 'ORD-42',
        recipientName: 'Mina',
        shipBy: '2026-11-02',
        carrier: 'USPS',
      );

      expect(backend.rpcCalls, hasLength(1));
      expect(backend.rpcCalls.single.path, '/rest/v1/rpc/create_reminder');
      expect(backend.rpcCalls.single.body, {
        'p_title': 'Ship the mug',
        'p_notes': null,
        'p_due_at': null,
        'p_context_id': 'side-gig-context',
        'p_channels': ['email'],
        'p_is_order': true,
        'p_order_ref': 'ORD-42',
        'p_recipient_name': 'Mina',
        'p_ship_by': '2026-11-02',
        'p_carrier': 'USPS',
      });
      expect(
        backend.requests.where((request) => request.path == '/rest/v1/orders'),
        isEmpty,
      );
    },
  );

  test('editing order details updates only four fields and keeps tracking metadata', () async {
    backend.order = _order();

    await repository.save(
      id: 'reminder-1',
      title: 'Ship the mug tomorrow',
      notes: 'Fragile',
      dueAt: null,
      contextId: 'side-gig-context',
      isOrder: true,
      channels: const ['email'],
      orderRef: 'ORD-43',
      recipientName: 'Mina K',
      shipBy: '2026-11-03',
      carrier: 'FedEx',
    );

    final patch = backend.requests.singleWhere(
      (request) => request.method == 'PATCH',
    );
    expect(patch.body.keys.toSet(), {
      'order_ref',
      'recipient_name',
      'ship_by',
      'carrier',
    });
    expect(backend.order['tracking_number'], '9400111899223856920000');
    expect(backend.order['shipped_at'], '2026-10-12T15:30:00Z');
    expect(backend.order['order_ref'], 'ORD-43');
    expect(backend.rpcCalls.map((request) => request.path), [
      '/rest/v1/rpc/update_reminder',
    ]);
  });

  test(
    'an explicit null ship-by stays null when the reminder has a due date',
    () async {
      backend.order = _order();

      await repository.save(
        id: 'reminder-1',
        title: 'Ship the mug',
        notes: null,
        dueAt: DateTime.utc(2026, 11, 4, 18, 30),
        contextId: 'side-gig-context',
        isOrder: true,
        channels: const ['email'],
        shipBy: null,
      );

      final reminderUpdate = backend.rpcCalls.singleWhere(
        (request) => request.path == '/rest/v1/rpc/update_reminder',
      );
      final orderPatch = backend.requests.singleWhere(
        (request) => request.method == 'PATCH',
      );
      expect(reminderUpdate.body['p_due_at'], '2026-11-04T18:30:00.000Z');
      expect(orderPatch.body['ship_by'], isNull);
    },
  );

  test(
    'marking shipped keeps existing tracking details when arguments are absent',
    () async {
      backend.order = _order(shippedAt: null);

      await repository.markShipped('reminder-1', null, null);

      final call = backend.rpcCalls.single;
      expect(call.path, '/rest/v1/rpc/mark_shipped');
      expect(call.body, {
        'p_reminder_id': 'reminder-1',
        'p_tracking_number': '9400111899223856920000',
        'p_carrier': 'USPS',
      });
    },
  );

  test('shipment correction sends all fields and status in one RPC', () async {
    await repository.saveOrderReminder(
      reminder: app.Reminder(
        id: 'reminder-1',
        title: 'Corrected shipment',
        contextId: 'side-gig-context',
        contextName: 'Side Gig',
        contextSlug: 'side_gig',
        isOrder: true,
        notes: 'Updated note',
        dueAt: DateTime.utc(2026, 11, 4, 18, 30),
        channels: ['email'],
      ),
      order: const app.OrderDetails(
        reminderId: 'reminder-1',
        orderRef: 'ORD-fixed',
        recipientName: 'Mina B',
        shipBy: '2026-11-04',
        carrier: 'UPS',
        trackingNumber: '1Z999AA10123456784',
      ),
      shipped: false,
    );
    expect(
      backend.requests.where((r) => r.path.startsWith('/rest/')),
      hasLength(1),
    );
    final call = backend.rpcCalls.single;
    expect(call.path, '/rest/v1/rpc/edit_order_reminder');
    expect(call.body, {
      'p_id': 'reminder-1',
      'p_title': 'Corrected shipment',
      'p_notes': 'Updated note',
      'p_due_at': '2026-11-04T18:30:00.000Z',
      'p_context_id': 'side-gig-context',
      'p_channels': ['email'],
      'p_order_ref': 'ORD-fixed',
      'p_recipient_name': 'Mina B',
      'p_ship_by': '2026-11-04',
      'p_carrier': 'UPS',
      'p_tracking_number': '1Z999AA10123456784',
      'p_shipped': false,
    });
  });

  test(
    'detail-only correction preserves status intent and can clear tracking',
    () async {
      await repository.saveOrderReminder(
        reminder: app.Reminder(
          id: 'reminder-1',
          title: 'Order',
          contextId: 'side-gig-context',
          contextName: 'Side Gig',
          contextSlug: 'side_gig',
          isOrder: true,
        ),
        order: const app.OrderDetails(reminderId: 'reminder-1'),
      );
      expect(backend.rpcCalls.single.body['p_shipped'], isNull);
      expect(backend.rpcCalls.single.body['p_tracking_number'], isNull);
    },
  );

  test('overlength tracking is rejected before the shipment RPC', () async {
    backend.order = _order(shippedAt: null);
    await expectLater(
      repository.markShipped('reminder-1', '1' * 35, 'UPS'),
      throwsArgumentError,
    );
    expect(backend.rpcCalls, isEmpty);
  });

  test(
    'mark shipped rejects an already shipped order without calling RPC',
    () async {
      backend.order = _order(shippedAt: '2026-10-12T15:30:00Z');

      await expectLater(
        repository.markShipped('reminder-1', null, null),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already marked shipped'),
          ),
        ),
      );
      expect(backend.rpcCalls, isEmpty);
    },
  );

  test(
    'reports reminder success when saving order details fails afterward',
    () async {
      backend.order = _order();
      backend.failOrderUpdate = true;

      await expectLater(
        repository.save(
          id: 'reminder-1',
          title: 'Ship the mug tomorrow',
          notes: null,
          dueAt: null,
          contextId: 'side-gig-context',
          isOrder: true,
          channels: const ['email'],
          orderRef: 'ORD-43',
          recipientName: 'Mina K',
          shipBy: '2026-11-03',
          carrier: 'FedEx',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            startsWith('Reminder saved, but order details failed to save:'),
          ),
        ),
      );
      expect(backend.rpcCalls.single.path, '/rest/v1/rpc/update_reminder');
    },
  );

  test('reports partial save when order PATCH matches zero rows', () async {
    backend.order = _order();
    backend.returnNoRowsOnOrderUpdate = true;

    await expectLater(
      repository.save(
        id: 'reminder-1',
        title: 'Ship the mug tomorrow',
        notes: null,
        dueAt: null,
        contextId: 'side-gig-context',
        isOrder: true,
        channels: const ['email'],
        orderRef: 'ORD-43',
        recipientName: 'Mina K',
        shipBy: '2026-11-03',
        carrier: 'FedEx',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          startsWith('Reminder saved, but order details failed to save:'),
        ),
      ),
    );
    expect(backend.rpcCalls.single.path, '/rest/v1/rpc/update_reminder');
  });
}

Map<String, Object?> _order({String? shippedAt = '2026-10-12T15:30:00Z'}) => {
  'reminder_id': 'reminder-1',
  'order_ref': 'ORD-42',
  'recipient_name': 'Mina',
  'ship_by': '2026-11-02',
  'carrier': 'USPS',
  'tracking_number': '9400111899223856920000',
  'shipped_at': shippedAt,
  'reminders': {
    'id': 'reminder-1',
    'title': 'Ship the mug',
    'context_id': 'side-gig-context',
    'status': 'open',
    'contexts': {'name': 'Side Gig', 'slug': 'side_gig'},
  },
};

class _RecordedRequest {
  const _RecordedRequest(this.method, this.path, this.body);
  final String method, path;
  final Map<String, dynamic> body;
}

class _SupabaseHarness {
  _SupabaseHarness._(this.server) {
    _subscription = server.listen(_handle);
  }

  final HttpServer server;
  late final StreamSubscription<HttpRequest> _subscription;
  final List<_RecordedRequest> requests = [];
  final List<_RecordedRequest> rpcCalls = [];
  Map<String, Object?> order = _order();
  bool failOrderUpdate = false;
  bool returnNoRowsOnOrderUpdate = false;
  int get port => server.port;

  static Future<_SupabaseHarness> start() async => _SupabaseHarness._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  Future<void> _handle(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    final body = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;
    final path = request.uri.path;
    final recorded = _RecordedRequest(request.method, path, body);
    requests.add(recorded);

    if (path == '/auth/v1/token') {
      _json(request.response, 200, _session());
      return;
    }
    if (path.startsWith('/rest/v1/rpc/')) {
      rpcCalls.add(recorded);
      _json(
        request.response,
        200,
        path.endsWith('/create_reminder') ? 'reminder-new' : null,
      );
      return;
    }
    if (path == '/rest/v1/orders' && request.method == 'GET') {
      if (request.uri.queryParameters['select'] == 'reminder_id') {
        _json(request.response, 200, [
          {'reminder_id': order['reminder_id']},
        ]);
      } else {
        _json(request.response, 200, [order]);
      }
      return;
    }
    if (path == '/rest/v1/orders' && request.method == 'PATCH') {
      if (failOrderUpdate) {
        _json(request.response, 500, {
          'message': 'synthetic order detail failure',
          'code': 'TEST_FAILURE',
        });
        return;
      }
      if (returnNoRowsOnOrderUpdate) {
        _json(request.response, 200, []);
        return;
      }
      order = {...order, ...body};
      _json(request.response, 200, [
        {'reminder_id': order['reminder_id']},
      ]);
      return;
    }
    _json(request.response, 404, {'message': 'Unexpected request $path'});
  }

  Future<void> close() async {
    await _subscription.cancel();
    await server.close(force: true);
  }

  void _json(HttpResponse response, int status, Object? value) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
    unawaited(response.close());
  }
}

Map<String, Object?> _session() => {
  'access_token': 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJ1c2VyLTEiLCJleHAiOjQxMDAwMDAwMDAsImF1ZCI6ImF1dGhlbnRpY2F0ZWQifQ.signature',
  'expires_in': 3600,
  'refresh_token': 'test-refresh-token',
  'token_type': 'bearer',
  'user': {
    'id': 'user-1',
    'app_metadata': {
      'provider': 'email',
      'providers': ['email'],
    },
    'user_metadata': <String, Object?>{},
    'aud': 'authenticated',
    'email': 'owner@example.com',
    'phone': '',
    'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'role': 'authenticated',
  },
};
