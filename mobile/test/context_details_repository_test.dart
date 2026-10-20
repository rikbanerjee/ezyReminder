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
    'created reminder returns RPC id used for its Work panel upsert',
    () async {
      final id = await _createReminder(repository);
      expect(id, 'reminder-created');

      await repository.saveWorkDetails(
        id!,
        managerName: 'Mina',
        departmentResource: 'Design review',
        projectName: 'Fall launch',
      );

      expect(backend.rpcCalls.single.path, '/rest/v1/rpc/create_reminder');
      final upsert = backend.requests.singleWhere(
        (request) => request.path == '/rest/v1/work_details',
      );
      expect(upsert.method, 'POST');
      expect(upsert.body, {
        'reminder_id': 'reminder-created',
        'user_id': 'user-1',
        'manager_name': 'Mina',
        'department_resource': 'Design review',
        'project_name': 'Fall launch',
      });
      expect(
        backend.requests.where((request) => request.method == 'DELETE'),
        isEmpty,
      );
    },
  );

  test('Work panel upsert writes the expected fields and permits all-null enabled data', () async {
    await repository.saveWorkDetails(
      'work-reminder',
      managerName: null,
      departmentResource: null,
      projectName: null,
    );

    final upsert = backend.requests.single;
    expect(upsert.path, '/rest/v1/work_details');
    expect(upsert.body, {
      'reminder_id': 'work-reminder',
      'user_id': 'user-1',
      'manager_name': null,
      'department_resource': null,
      'project_name': null,
    });
  });

  test(
    'Side Gig upsert writes only its table and its nullable fields',
    () async {
      await repository.saveSideGigDetails(
        'gig-reminder',
        initiativeName: 'Ceramic shop',
        clientName: null,
      );

      final upsert = backend.requests.single;
      expect(upsert.method, 'POST');
      expect(upsert.path, '/rest/v1/sidegig_details');
      expect(upsert.body, {
        'reminder_id': 'gig-reminder',
        'user_id': 'user-1',
        'initiative_name': 'Ceramic shop',
        'client_name': null,
      });
      expect(
        backend.requests.where((request) => request.method == 'DELETE'),
        isEmpty,
      );
      expect(
        backend.requests.where(
          (request) => request.path == '/rest/v1/work_details',
        ),
        isEmpty,
      );
    },
  );

  test(
    'loading each panel scopes by reminder id and maps nullable fields',
    () async {
      backend.workDetails = {
        'manager_name': 'Lee',
        'department_resource': null,
        'project_name': 'Migration',
      };
      backend.sideGigDetails = {
        'initiative_name': null,
        'client_name': 'Northwind',
      };

      final work = await repository.loadWorkDetails('work-reminder');
      final gig = await repository.loadSideGigDetails('gig-reminder');

      expect(work?.managerName, 'Lee');
      expect(work?.departmentResource, isNull);
      expect(work?.projectName, 'Migration');
      expect(gig?.initiativeName, isNull);
      expect(gig?.clientName, 'Northwind');
      expect(backend.requests[0].path, '/rest/v1/work_details');
      expect(backend.requests[0].query['reminder_id'], 'eq.work-reminder');
      expect(backend.requests[1].path, '/rest/v1/sidegig_details');
      expect(backend.requests[1].query['reminder_id'], 'eq.gig-reminder');
    },
  );

  test('absent panel rows load as null', () async {
    expect(await repository.loadWorkDetails('no-work-row'), isNull);
    expect(await repository.loadSideGigDetails('no-gig-row'), isNull);
  });

  test(
    'failed panel write keeps created reminder id for update-based retry',
    () async {
      final id = await _createReminder(repository);
      backend.failDetailsTable = 'work_details';

      await expectLater(
        repository.saveWorkDetails(
          id!,
          managerName: 'Mina',
          departmentResource: null,
          projectName: null,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(
        backend.rpcCalls.where(
          (request) => request.path.endsWith('/create_reminder'),
        ),
        hasLength(1),
      );

      backend.failDetailsTable = null;
      await repository.save(
        id: id,
        title: 'A reminder',
        notes: null,
        dueAt: null,
        contextId: 'work-context',
        isOrder: false,
        channels: const [],
      );
      await repository.saveWorkDetails(
        id,
        managerName: 'Mina',
        departmentResource: null,
        projectName: null,
      );

      expect(backend.rpcCalls.map((request) => request.path), [
        '/rest/v1/rpc/create_reminder',
        '/rest/v1/rpc/update_reminder',
      ]);
      expect(
        backend.requests.where(
          (request) => request.path == '/rest/v1/work_details',
        ),
        hasLength(2),
      );
    },
  );
}

Future<String?> _createReminder(app.SupabaseRepository repository) =>
    repository.save(
      title: 'A reminder',
      notes: null,
      dueAt: null,
      contextId: 'work-context',
      isOrder: false,
      channels: const [],
    );

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
  Map<String, Object?>? workDetails;
  Map<String, Object?>? sideGigDetails;
  String? failDetailsTable;
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

    if (path.startsWith('/rest/v1/rpc/')) {
      rpcCalls.add(recorded);
      _json(
        request.response,
        200,
        path.endsWith('/create_reminder') ? 'reminder-created' : null,
      );
      return;
    }
    if ((path == '/rest/v1/work_details' ||
            path == '/rest/v1/sidegig_details') &&
        request.method == 'GET') {
      final data = path.endsWith('/work_details')
          ? workDetails
          : sideGigDetails;
      _json(request.response, 200, data);
      return;
    }
    if ((path == '/rest/v1/work_details' ||
            path == '/rest/v1/sidegig_details') &&
        request.method == 'POST') {
      if (failDetailsTable != null && path.endsWith('/$failDetailsTable')) {
        _json(request.response, 500, {
          'message': 'synthetic detail save failure',
          'code': 'TEST_FAILURE',
        });
        return;
      }
      if (path.endsWith('/work_details')) {
        workDetails = {...?workDetails, ...body};
      } else {
        sideGigDetails = {...?sideGigDetails, ...body};
      }
      request.response.statusCode = 201;
      request.response.headers.contentType = ContentType.json;
      await request.response.close();
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
