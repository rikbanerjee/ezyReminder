import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ezyreminder/core/auth/native_auth.dart';
import 'package:ezyreminder/features/auth/login_page.dart';

void main() {
  group('NativeAuth Google', () {
    test('hashes the SDK nonce and exchanges the matching raw nonce', () async {
      final google = _FakeGoogle(
        schemes: const ['com.googleusercontent.apps.123'],
      );
      final exchanger = _FakeExchanger();
      final auth = NativeAuth(
        google: google,
        exchanger: exchanger,
        googleIosClientId: '123.apps.googleusercontent.com',
        googleWebClientId: 'web-client',
        googleReversedClientId: 'com.googleusercontent.apps.123',
      );

      await auth.signInWithGoogle();

      expect(google.initializedWith, (
        '123.apps.googleusercontent.com',
        'web-client',
      ));
      expect(
        google.initializationNonce,
        sha256.convert(utf8.encode(exchanger.rawNonce)).toString(),
      );
      expect(google.initializationRawNonce, exchanger.rawNonce);
      expect(exchanger.googleTokens, (
        'google-id',
        'google-access',
        exchanger.rawNonce,
      ));
    });

    test('does not call Google SDK when scheme is absent', () async {
      final google = _FakeGoogle();
      final auth = NativeAuth(
        google: google,
        exchanger: _FakeExchanger(),
        googleIosClientId: '123.apps.googleusercontent.com',
        googleWebClientId: 'web-client',
        googleReversedClientId: 'com.googleusercontent.apps.123',
      );

      await expectLater(
        auth.signInWithGoogle(),
        throwsA(isA<NativeAuthSetupException>()),
      );
      expect(google.initializeCalls, 0);
      expect(google.authenticateCalls, 0);
    });

    test('missing IDs fail before native setup probe', () async {
      final google = _FakeGoogle();
      final auth = NativeAuth(google: google, exchanger: _FakeExchanger());

      await expectLater(
        auth.signInWithGoogle(),
        throwsA(isA<NativeAuthSetupException>()),
      );
      expect(google.urlProbeCalls, 0);
    });

    test(
      'provider cancellation is surfaced as a normal cancellation',
      () async {
        final auth = NativeAuth(
          google: _FakeGoogle(
            schemes: const ['com.googleusercontent.apps.123'],
            cancelled: true,
          ),
          exchanger: _FakeExchanger(),
          googleIosClientId: '123.apps.googleusercontent.com',
          googleWebClientId: 'web',
          googleReversedClientId: 'com.googleusercontent.apps.123',
        );
        await expectLater(
          auth.signInWithGoogle(),
          throwsA(isA<NativeAuthCancelled>()),
        );
      },
    );
  });

  test('Google keeps SDK nonce across NativeAuth instances', () async {
    final google = _FakeGoogle(
      schemes: const ['com.googleusercontent.apps.123'],
    );
    final firstExchange = _FakeExchanger(rawNonce: 'first-process-nonce');
    final secondExchange = _FakeExchanger(rawNonce: 'discarded-new-nonce');

    await _googleAuth(google, firstExchange).signInWithGoogle();
    await _googleAuth(google, secondExchange).signInWithGoogle();

    expect(google.sdkInitializationCalls, 1);
    expect(firstExchange.googleTokens?.$3, 'first-process-nonce');
    expect(secondExchange.googleTokens?.$3, 'first-process-nonce');
  });

  test(
    'Google retries initialization after SDK initialization failure',
    () async {
      final google = _FakeGoogle(
        schemes: const ['com.googleusercontent.apps.123'],
        failInitializeOnce: true,
      );
      final exchanger = _FakeExchanger();
      final auth = _googleAuth(google, exchanger);

      await expectLater(auth.signInWithGoogle(), throwsStateError);
      await auth.signInWithGoogle();

      expect(google.sdkInitializationCalls, 2);
      expect(exchanger.googleTokens?.$3, exchanger.rawNonce);
    },
  );

  test(
    'Supabase Google exchange includes the access token and raw nonce',
    () async {
      final received = <String, Object?>{};
      final exchange = SupabaseTokenExchanger(
        SupabaseClient(
          'https://example.supabase.co',
          'anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
        idTokenSignIn:
            ({required provider, required idToken, accessToken, nonce}) async {
              received.addAll({
                'provider': provider,
                'idToken': idToken,
                'accessToken': accessToken,
                'nonce': nonce,
              });
            },
      );

      await exchange.google(
        idToken: 'google-id',
        accessToken: 'google-access',
        rawNonce: 'raw-google-nonce',
      );

      expect(received['provider'], OAuthProvider.google);
      expect(received['idToken'], 'google-id');
      expect(received['accessToken'], 'google-access');
      expect(received['nonce'], 'raw-google-nonce');
    },
  );

  test('Apple hashes the provider nonce but exchanges the raw nonce', () async {
    final apple = _FakeApple();
    final exchanger = _FakeExchanger();
    final auth = NativeAuth(
      apple: apple,
      exchanger: exchanger,
      appleEnabled: true,
      isApplePlatform: true,
    );

    await auth.signInWithApple();

    expect(apple.receivedNonce, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(apple.receivedNonce, isNot(exchanger.rawNonce));
    expect(exchanger.appleTokens, ('apple-id', exchanger.rawNonce));
  });

  test(
    'Apple disabled reports setup and does not launch provider UI',
    () async {
      final apple = _FakeApple();
      final auth = NativeAuth(apple: apple, exchanger: _FakeExchanger());
      await expectLater(
        auth.signInWithApple(),
        throwsA(isA<NativeAuthSetupException>()),
      );
      expect(apple.authenticateCalls, 0);
    },
  );

  testWidgets('login presents both providers and email password fallback', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final auth = NativeAuth(
      google: _FakeGoogle(),
      apple: _FakeApple(),
      exchanger: _FakeExchanger(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(client: client, nativeAuth: auth),
      ),
    );

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
  });

  testWidgets('dismissing Google chooser does not show a failure message', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final auth = NativeAuth(
      google: _FakeGoogle(
        schemes: const ['com.googleusercontent.apps.123'],
        cancelled: true,
      ),
      exchanger: _FakeExchanger(),
      googleIosClientId: '123.apps.googleusercontent.com',
      googleWebClientId: 'web-client',
      googleReversedClientId: 'com.googleusercontent.apps.123',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(client: client, nativeAuth: auth),
      ),
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not sign in'), findsNothing);
    expect(find.textContaining('not configured'), findsNothing);
  });
}

class _FakeGoogle implements GoogleIdentity {
  _FakeGoogle({
    this.schemes = const [],
    this.cancelled = false,
    this.failInitializeOnce = false,
  });
  final List<String> schemes;
  final bool cancelled;
  bool failInitializeOnce;
  int initializeCalls = 0, authenticateCalls = 0, urlProbeCalls = 0;
  int sdkInitializationCalls = 0;
  (String, String)? initializedWith;
  String? initializationNonce, initializationRawNonce, _sessionRawNonce;
  @override
  Future<List<String>> configuredUrlSchemes() async {
    urlProbeCalls++;
    return schemes;
  }

  @override
  Future<void> initialize({
    required String clientId,
    required String serverClientId,
    required String nonce,
    required String rawNonce,
  }) async {
    initializeCalls++;
    initializedWith = (clientId, serverClientId);
    initializationNonce = nonce;
    initializationRawNonce = rawNonce;
    if (_sessionRawNonce == null || failInitializeOnce) {
      sdkInitializationCalls++;
      if (failInitializeOnce) {
        failInitializeOnce = false;
        _sessionRawNonce = null;
        throw StateError('SDK initialization failed');
      }
      _sessionRawNonce = rawNonce;
    }
  }

  @override
  Future<GoogleTokens?> authenticate() async {
    authenticateCalls++;
    return cancelled
        ? null
        : GoogleTokens(
            idToken: 'google-id',
            accessToken: 'google-access',
            rawNonce: _sessionRawNonce ?? 'test-raw-nonce',
          );
  }
}

class _FakeApple implements AppleIdentity {
  String? receivedNonce;
  int authenticateCalls = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<AppleIdentityToken?> authenticate(String hashedNonce) async {
    authenticateCalls++;
    receivedNonce = hashedNonce;
    return const AppleIdentityToken('apple-id');
  }
}

class _FakeExchanger implements NativeTokenExchanger {
  _FakeExchanger({this.rawNonce = 'test-raw-nonce'});
  (String, String, String)? googleTokens;
  (String, String)? appleTokens;
  final String rawNonce;
  @override
  String generateRawNonce() => rawNonce;
  @override
  Future<void> google({
    required String idToken,
    required String accessToken,
    required String rawNonce,
  }) async {
    googleTokens = (idToken, accessToken, rawNonce);
  }

  @override
  Future<void> apple({
    required String idToken,
    required String rawNonce,
  }) async {
    appleTokens = (idToken, rawNonce);
  }
}

NativeAuth _googleAuth(_FakeGoogle google, _FakeExchanger exchanger) =>
    NativeAuth(
      google: google,
      exchanger: exchanger,
      googleIosClientId: '123.apps.googleusercontent.com',
      googleWebClientId: 'web-client',
      googleReversedClientId: 'com.googleusercontent.apps.123',
    );
