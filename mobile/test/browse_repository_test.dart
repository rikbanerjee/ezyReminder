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
    'loadAll includes open, snoozed, and done but excludes cancelled',
    () async {
      backend.reminders = [
        _reminder('done-1', 'Completed', 'done'),
        _reminder('open-1', 'Open', 'open'),
        _reminder('snoozed-1', 'Snoozed', 'snoozed'),
        _reminder('cancelled-1', 'Cancelled', 'cancelled'),
      ];

      final rows = await repository.loadAll();

      expect(rows.map((row) => row.id), ['done-1', 'open-1', 'snoozed-1']);
      final request = backend.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/rest/v1/reminders');
      expect(request.query['select'], '*,contexts(id,name,slug)');
      expect(request.query['order'], startsWith('updated_at.desc'));
      expect(request.query['status'], contains('open'));
      expect(request.query['status'], contains('snoozed'));
      expect(request.query['status'], contains('done'));
      expect(request.query['status'], isNot(contains('cancelled')));
      expect(request.query.containsKey('user_id'), isFalse);
    },
  );

  test(
    'loadDoneToday filters to done rows updated since local day start',
    () async {
      backend.reminders = [
        _reminder('done-1', 'Completed today', 'done'),
        _reminder('open-1', 'Still open', 'open'),
      ];

      final rows = await repository.loadDoneToday();

      expect(rows.map((row) => row.id), ['done-1']);
      final request = backend.requests.single;
      expect(request.query['status'], 'eq.done');
      expect(request.query['updated_at'], startsWith('gte.'));
      expect(request.query['order'], startsWith('updated_at.desc'));
      expect(request.query.containsKey('user_id'), isFalse);
    },
  );

  test(
    'active ReminderRepository.load still filters open and snoozed by due date',
    () async {
      backend.reminders = [
        _reminder('open-1', 'Open', 'open'),
        _reminder('snoozed-1', 'Snoozed', 'snoozed'),
        _reminder('done-1', 'Completed', 'done'),
        _reminder('cancelled-1', 'Cancelled', 'cancelled'),
      ];

      final rows = await repository.load();

      final request = backend.requests.single;
      expect(rows.map((row) => row.id), ['open-1', 'snoozed-1']);
      expect(request.query['status'], contains('open'));
      expect(request.query['status'], contains('snoozed'));
      expect(request.query['order'], startsWith('due_at.asc'));
    },
  );

  test(
    'delete directly targets the reminder and requires an affected row',
    () async {
      await repository.deleteReminder('reminder-7');

      final request = backend.requests.single;
      expect(request.method, 'DELETE');
      expect(request.path, '/rest/v1/reminders');
      expect(request.query['id'], 'eq.reminder-7');
    },
  );

  test(
    'delete reports when RLS or a concurrent delete returns no rows',
    () async {
      backend.returnNoRows = true;

      await expectLater(
        repository.deleteReminder('missing-reminder'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no longer exists'),
          ),
        ),
      );
    },
  );

  test(
    'reopen sets open status, clears snooze, and checks affected row',
    () async {
      await repository.reopenReminder('reminder-8');

      final request = backend.requests.single;
      expect(request.method, 'PATCH');
      expect(request.path, '/rest/v1/reminders');
      expect(request.query['id'], 'eq.reminder-8');
      expect(request.body, {'status': 'open', 'snoozed_until': null});
    },
  );

  test('reopen reports when the reminder no longer exists', () async {
    backend.returnNoRows = true;

    await expectLater(
      repository.reopenReminder('missing-reminder'),
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

Map<String, Object?> _reminder(String id, String title, String status) => {
  'id': id,
  'title': title,
  'context_id': 'context-1',
  'notes': null,
  'due_at': '2026-10-20T12:00:00Z',
  'snoozed_until': status == 'snoozed' ? '2026-10-19T12:00:00Z' : null,
  'status': status,
  'is_order': false,
  'channels': <String>[],
  'updated_at': '2026-10-17T12:00:00Z',
  'contexts': {'id': 'context-1', 'name': 'Work', 'slug': 'work'},
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
  List<Map<String, Object?>> reminders = [];
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
    if (path == '/auth/v1/token') {
      _json(request.response, 200, _session());
      return;
    }
    final recorded = _RecordedRequest(
      request.method,
      path,
      request.uri.queryParameters,
      body,
    );
    requests.add(recorded);

    if (path == '/rest/v1/reminders' && request.method == 'GET') {
      final statusFilter = request.uri.queryParameters['status'];
      var matching = reminders.where((row) {
        if (statusFilter == null) return true;
        if (statusFilter.startsWith('eq.')) {
          return row['status'] == statusFilter.substring(3);
        }
        if (statusFilter.startsWith('in.(')) {
          final values = statusFilter
              .substring(4, statusFilter.length - 1)
              .replaceAll('"', '');
          return values.split(',').contains(row['status']);
        }
        return true;
      }).toList();
      if (request.uri.queryParameters['updated_at']?.startsWith('gte.') ??
          false) {
        matching = matching.where((row) => row['status'] == 'done').toList();
      }
      _json(request.response, 200, matching);
      return;
    }
    if (path == '/rest/v1/reminders' &&
        (request.method == 'PATCH' || request.method == 'DELETE')) {
      if (returnNoRows) {
        _json(request.response, 200, []);
        return;
      }
      final id = request.uri.queryParameters['id']?.replaceFirst('eq.', '');
      _json(request.response, 200, [
        {'id': id},
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
