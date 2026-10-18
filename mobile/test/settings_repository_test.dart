import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ezyreminder/features/settings/settings_repository.dart';

void main() {
  late _SupabaseHarness backend;
  late SupabaseClient client;
  late SupabaseSettingsRepository repository;

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
    repository = SupabaseSettingsRepository(client);
  });

  tearDown(() async {
    repository.dispose();
    await client.dispose();
    await backend.close();
  });

  test(
    'load returns authenticated email, UTC fallback, and owner contexts',
    () async {
      backend.settingsRow = null;
      backend.contextRows = [
        _context('work-id', 'Work', 'work', {'start': '18:30', 'end': '08:00'}),
        _context('shop-id', 'Shopping', 'shopping', {}),
      ];

      final data = await repository.load();

      expect(data.email, 'owner@example.com');
      expect(data.timezone, 'UTC');
      expect(data.contexts.map((context) => context.slug), [
        'work',
        'shopping',
      ]);
      expect(data.contexts.first.quietHours.start, '18:30');
      expect(data.contexts.first.quietHours.end, '08:00');
      expect(data.contexts.last.quietHours.start, isNull);
      expect(backend.requests[0].path, '/rest/v1/user_settings');
      expect(backend.requests[0].query['user_id'], 'eq.user-1');
      expect(backend.requests[1].path, '/rest/v1/contexts');
      expect(backend.requests[1].query.containsKey('user_id'), isFalse);
    },
  );

  test('load uses the saved timezone when a settings row exists', () async {
    backend.settingsRow = {'timezone': 'America/New_York'};
    backend.contextRows = [];

    final data = await repository.load();

    expect(data.timezone, 'America/New_York');
  });

  test(
    'timezone save trims and upserts only authenticated user id and timezone',
    () async {
      await repository.saveTimezone('  America/Los_Angeles  ');

      final request = backend.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/rest/v1/user_settings');
      expect(request.query['on_conflict'], 'user_id');
      expect(request.body, {
        'user_id': 'user-1',
        'timezone': 'America/Los_Angeles',
      });
    },
  );

  test('invalid timezone is rejected before any database request', () async {
    await expectLater(
      repository.saveTimezone('  Mars/Olympus  '),
      throwsA(isA<ArgumentError>()),
    );
    expect(backend.requests, isEmpty);
  });

  test(
    'quiet-hours save patches only the selected context with exact values',
    () async {
      await repository.saveQuietHours(
        'context-9',
        start: '21:15',
        end: '07:45',
      );

      final request = backend.requests.single;
      expect(request.method, 'PATCH');
      expect(request.path, '/rest/v1/contexts');
      expect(request.query['id'], 'eq.context-9');
      expect(request.body, {
        'quiet_hours': {'start': '21:15', 'end': '07:45'},
      });
    },
  );

  test(
    'clearing quiet hours writes empty endpoints and zero affected rows fail',
    () async {
      await repository.saveQuietHours('context-9', start: null, end: null);

      expect(backend.requests.single.body, {
        'quiet_hours': {'start': '', 'end': ''},
      });

      backend.returnNoContextRows = true;
      await expectLater(
        repository.saveQuietHours(
          'missing-context',
          start: '20:00',
          end: '08:00',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('context no longer exists'),
          ),
        ),
      );
    },
  );

  test('account deletion sends authenticated POST without user id and requires ok response', () async {
    backend.deleteAccountData = {'ok': true};

    await repository.deleteAccount();

    final request = backend.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/functions/v1/delete-account');
    expect(request.bodyBytes, isEmpty);
    expect(request.query, isEmpty);
    expect(request.headers['authorization'], startsWith('Bearer '));
    expect(request.headers['authorization'], contains('eyJhbGciOiJub25l'));
    expect(request.bodyBytes, isNot(contains(utf8.encode('user-1'))));
    expect(client.auth.currentUser?.id, 'user-1');
  });

  test('account deletion rejects unconfirmed and HTTP error responses without signing out', () async {
    backend.deleteAccountData = {'ok': false};
    await expectLater(repository.deleteAccount(), throwsA(isA<StateError>()));
    expect(client.auth.currentUser?.id, 'user-1');

    backend.deleteAccountStatus = 500;
    backend.deleteAccountData = {'error': 'Unable to delete account'};
    await expectLater(
      repository.deleteAccount(),
      throwsA(isA<FunctionException>()),
    );
    expect(client.auth.currentUser?.id, 'user-1');
  });
}

Map<String, Object?> _context(
  String id,
  String name,
  String slug,
  Map<String, Object?> quietHours,
) => {'id': id, 'name': name, 'slug': slug, 'quiet_hours': quietHours};

class _RecordedRequest {
  const _RecordedRequest(
    this.method,
    this.path,
    this.query,
    this.body,
    this.bodyBytes,
    this.headers,
  );
  final String method, path;
  final Map<String, String> query;
  final Map<String, dynamic> body;
  final List<int> bodyBytes;
  final Map<String, String> headers;
}

class _SupabaseHarness {
  _SupabaseHarness._(this.server) {
    _subscription = server.listen(_handle);
  }

  final HttpServer server;
  late final StreamSubscription<HttpRequest> _subscription;
  final List<_RecordedRequest> requests = [];
  Map<String, Object?>? settingsRow = {'timezone': 'UTC'};
  List<Map<String, Object?>> contextRows = [];
  bool returnNoContextRows = false;
  int deleteAccountStatus = 200;
  Object? deleteAccountData = {'ok': true};
  int get port => server.port;

  static Future<_SupabaseHarness> start() async => _SupabaseHarness._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (all, next) => all..addAll(next),
    );
    final rawBody = utf8.decode(bytes);
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
      bytes,
      _headers(request.headers),
    );
    requests.add(recorded);

    if (path == '/rest/v1/user_settings' && request.method == 'GET') {
      _json(request.response, 200, settingsRow == null ? [] : [settingsRow]);
      return;
    }
    if (path == '/rest/v1/contexts' && request.method == 'GET') {
      _json(request.response, 200, contextRows);
      return;
    }
    if (path == '/rest/v1/user_settings' && request.method == 'POST') {
      request.response.statusCode = 201;
      await request.response.close();
      return;
    }
    if (path == '/rest/v1/contexts' && request.method == 'PATCH') {
      _json(
        request.response,
        200,
        returnNoContextRows
            ? []
            : [
                {
                  'id': request.uri.queryParameters['id']?.replaceFirst(
                    'eq.',
                    '',
                  ),
                },
              ],
      );
      return;
    }
    if (path == '/functions/v1/delete-account' && request.method == 'POST') {
      _json(request.response, deleteAccountStatus, deleteAccountData);
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

Map<String, String> _headers(HttpHeaders headers) {
  final values = <String, String>{};
  headers.forEach((name, entries) => values[name] = entries.join(','));
  return values;
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
