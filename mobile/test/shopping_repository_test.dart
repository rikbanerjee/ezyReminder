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

  test('add trims the item label and returns the RPC-created id', () async {
    final id = await repository.addShoppingItem('list-1', '  oat milk  ');

    expect(id, 'item-created');
    expect(backend.rpcCalls, hasLength(1));
    expect(backend.rpcCalls.single.path, '/rest/v1/rpc/add_shopping_item');
    expect(backend.rpcCalls.single.body, {
      'p_reminder_id': 'list-1',
      'p_label': 'oat milk',
    });
  });

  test('add rejects a blank item label before making a request', () async {
    await expectLater(
      repository.addShoppingItem('list-1', '  \n '),
      throwsA(isA<ArgumentError>()),
    );
    expect(backend.rpcCalls, isEmpty);
  });

  test('load items scopes to the list and orders by position', () async {
    backend.items = [
      _item('item-2', 'Bananas', 'list-2', false, 0),
      _item('item-1', 'Coffee', 'list-1', true, 2),
      _item('item-3', 'Oats', 'list-1', false, 1),
    ];

    final items = await repository.loadShoppingItems('list-1');

    expect(backend.requests.single.query['order'], startsWith('position.asc'));
    expect(items.map((item) => item.id), ['item-3', 'item-1']);
    expect(items.map((item) => item.position), [1, 2]);
    final request = backend.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/rest/v1/shopping_items');
    expect(request.query['reminder_id'], 'eq.list-1');
    expect(request.query['order'], startsWith('position.asc'));
  });

  test(
    'shopping counts omit checked items and remain grouped by reminder',
    () async {
      backend.items = [
        _item('a-1', 'Milk', 'list-a', false, 0),
        _item('a-2', 'Bread', 'list-a', true, 1),
        _item('b-1', 'Apples', 'list-b', false, 0),
        _item('b-2', 'Rice', 'list-b', false, 1),
        _item('c-1', 'Tea', 'list-c', true, 0),
      ];

      expect(await repository.loadShoppingCounts(), {'list-a': 1, 'list-b': 2});
      expect(backend.requests.single.path, '/rest/v1/shopping_items');
      expect(backend.requests.single.query['select'], 'reminder_id,checked');
    },
  );

  test(
    'toggle checks only the requested item and requires an affected row',
    () async {
      backend.items = [_item('item-9', 'Milk', 'list-1', false, 0)];
      await repository.setShoppingItemChecked('item-9', true);

      final patch = backend.requests.single;
      expect(patch.method, 'PATCH');
      expect(patch.path, '/rest/v1/shopping_items');
      expect(patch.query['id'], 'eq.item-9');
      expect(patch.body, {'checked': true});
    },
  );

  test('toggle reports when the item no longer exists', () async {
    backend.returnNoRows = true;

    await expectLater(
      repository.setShoppingItemChecked('gone-item', false),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no longer exists'),
        ),
      ),
    );
  });

  test(
    'delete targets only the requested item and requires an affected row',
    () async {
      backend.items = [_item('item-10', 'Bread', 'list-1', false, 0)];
      await repository.deleteShoppingItem('item-10');

      final deletion = backend.requests.single;
      expect(deletion.method, 'DELETE');
      expect(deletion.path, '/rest/v1/shopping_items');
      expect(deletion.query['id'], 'eq.item-10');
    },
  );

  test('delete reports when the item no longer exists', () async {
    backend.returnNoRows = true;

    await expectLater(
      repository.deleteShoppingItem('gone-item'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no longer exists'),
        ),
      ),
    );
  });

  test(
    'renaming trims the title and requires an affected reminder row',
    () async {
      await repository.renameShoppingList('list-3', '  Farmers market  ');

      final patch = backend.requests.single;
      expect(patch.method, 'PATCH');
      expect(patch.path, '/rest/v1/reminders');
      expect(patch.query['id'], 'eq.list-3');
      expect(patch.body, {'title': 'Farmers market'});
    },
  );

  test('renaming rejects blank title and reports a missing list', () async {
    await expectLater(
      repository.renameShoppingList('list-3', '  '),
      throwsA(isA<ArgumentError>()),
    );
    expect(backend.requests, isEmpty);

    backend.returnNoRows = true;
    await expectLater(
      repository.renameShoppingList('list-3', 'Renamed list'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no longer exists'),
        ),
      ),
    );
  });
}

Map<String, Object?> _item(
  String id,
  String label,
  String reminderId,
  bool checked,
  int position,
) => {
  'id': id,
  'label': label,
  'reminder_id': reminderId,
  'checked': checked,
  'position': position,
};

class _RecordedRequest {
  const _RecordedRequest(this.method, this.path, this.query, this.body);
  final String method, path;
  final Map<String, String> query;
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
  List<Map<String, Object?>> items = [];
  bool returnNoRows = false;
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
    final recorded = _RecordedRequest(
      request.method,
      path,
      request.uri.queryParameters,
      body,
    );
    if (path != '/auth/v1/token') requests.add(recorded);

    if (path == '/auth/v1/token') {
      _json(request.response, 200, _session());
      return;
    }
    if (path.startsWith('/rest/v1/rpc/')) {
      rpcCalls.add(recorded);
      _json(request.response, 200, 'item-created');
      return;
    }
    if (path == '/rest/v1/shopping_items' && request.method == 'GET') {
      final reminderFilter = request.uri.queryParameters['reminder_id'];
      var matching = items
          .where(
            (item) =>
                reminderFilter == null ||
                item['reminder_id'] == reminderFilter.replaceFirst('eq.', ''),
          )
          .toList();
      if (request.uri.queryParameters['order']?.startsWith('position.asc') ??
          false) {
        matching.sort(
          (a, b) => (a['position']! as int).compareTo(b['position']! as int),
        );
      }
      _json(request.response, 200, matching);
      return;
    }
    if (path == '/rest/v1/shopping_items' &&
        (request.method == 'PATCH' || request.method == 'DELETE')) {
      final id = request.uri.queryParameters['id']?.replaceFirst('eq.', '');
      final index = items.indexWhere((item) => item['id'] == id);
      if (returnNoRows || index < 0) {
        _json(request.response, 200, []);
        return;
      }
      if (request.method == 'PATCH') {
        items[index] = {...items[index], ...body};
      } else {
        items.removeAt(index);
      }
      _json(request.response, 200, [
        {'id': id},
      ]);
      return;
    }
    if (path == '/rest/v1/reminders' && request.method == 'PATCH') {
      if (returnNoRows) {
        _json(request.response, 200, []);
        return;
      }
      _json(request.response, 200, [
        {'id': request.uri.queryParameters['id']?.replaceFirst('eq.', '')},
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
