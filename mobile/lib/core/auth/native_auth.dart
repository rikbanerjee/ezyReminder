import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const _googleReversedClientId = String.fromEnvironment(
  'GOOGLE_IOS_REVERSED_CLIENT_ID',
);
const _appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED');

/// Error presented as setup guidance in the login screen.
class NativeAuthSetupException implements Exception {
  const NativeAuthSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A provider dismissed by the user is a normal outcome, not a login failure.
class NativeAuthCancelled implements Exception {
  const NativeAuthCancelled();
}

abstract interface class GoogleIdentity {
  Future<void> initialize({
    required String clientId,
    required String serverClientId,
    required String nonce,
    required String rawNonce,
  });
  Future<List<String>> configuredUrlSchemes();
  Future<GoogleTokens?> authenticate();
}

class GoogleTokens {
  const GoogleTokens({
    required this.idToken,
    required this.accessToken,
    required this.rawNonce,
  });
  final String? idToken;
  final String? accessToken;
  final String rawNonce;
}

abstract interface class AppleIdentity {
  Future<bool> isAvailable();
  Future<AppleIdentityToken?> authenticate(String hashedNonce);
}

class AppleIdentityToken {
  const AppleIdentityToken(this.idToken);
  final String? idToken;
}

abstract interface class NativeTokenExchanger {
  Future<void> google({
    required String idToken,
    required String accessToken,
    required String rawNonce,
  });
  Future<void> apple({required String idToken, required String rawNonce});
  String generateRawNonce();
}

/// Native Google and Apple authentication exchanged directly for a Supabase session.
/// All provider boundaries are injectable so the flow can be tested without SDKs/network.
class NativeAuth {
  NativeAuth({
    GoogleIdentity? google,
    AppleIdentity? apple,
    this.exchanger,
    bool? isApplePlatform,
    String googleIosClientId = _googleIosClientId,
    String googleWebClientId = _googleWebClientId,
    String googleReversedClientId = _googleReversedClientId,
    this.appleEnabled = _appleSignInEnabled,
  }) : _google = google ?? _GoogleIdentity(),
       _apple = apple ?? _AppleIdentity(),
       _isApplePlatform = isApplePlatform ?? Platform.isIOS,
       _iosClientId = googleIosClientId,
       _webClientId = googleWebClientId,
       _reversedClientId = googleReversedClientId;

  final GoogleIdentity _google;
  final AppleIdentity _apple;
  final String _iosClientId, _webClientId, _reversedClientId;
  final bool appleEnabled;
  final bool _isApplePlatform;
  final NativeTokenExchanger? exchanger;
  NativeTokenExchanger get _tokens =>
      exchanger ??
      (throw StateError('NativeAuth requires a Supabase token exchanger.'));

  Future<void> signInWithGoogle() async {
    if (_iosClientId.isEmpty ||
        _webClientId.isEmpty ||
        _reversedClientId.isEmpty) {
      throw const NativeAuthSetupException(
        'Google sign-in needs the iOS and web client IDs plus the reversed iOS client ID. Add them to the local Flutter run configuration.',
      );
    }
    final iosClientIdPrefix = _iosClientId.split('.').first;
    if (!_iosClientId.endsWith('.apps.googleusercontent.com') ||
        _reversedClientId != 'com.googleusercontent.apps.$iosClientIdPrefix') {
      throw const NativeAuthSetupException(
        'The Google iOS client ID and reversed client ID do not match. Check the OAuth client values in the local Flutter run configuration.',
      );
    }
    final schemes = await _google.configuredUrlSchemes();
    if (!schemes.contains(_reversedClientId)) {
      throw const NativeAuthSetupException(
        'Google sign-in is not configured for this iOS build. Add the reversed client ID URL scheme, then rebuild the app.',
      );
    }
    final rawNonce = _tokens.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    await _google.initialize(
      clientId: _iosClientId,
      serverClientId: _webClientId,
      nonce: hashedNonce,
      rawNonce: rawNonce,
    );
    final credential = await _google.authenticate();
    if (credential == null) {
      throw const NativeAuthCancelled();
    }
    final idToken = credential.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const NativeAuthSetupException(
        'Google did not return an ID token. Check the OAuth client configuration.',
      );
    }
    final accessToken = credential.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const NativeAuthSetupException(
        'Google did not return an access token. Check the OAuth client configuration.',
      );
    }
    if (credential.rawNonce.isEmpty) {
      throw const NativeAuthSetupException(
        'Google sign-in could not preserve its security nonce. Please try again.',
      );
    }
    await _tokens.google(
      idToken: idToken,
      accessToken: accessToken,
      rawNonce: credential.rawNonce,
    );
  }

  Future<void> signInWithApple() async {
    if (!appleEnabled) {
      throw const NativeAuthSetupException(
        'Apple sign-in is not enabled yet. Configure the Apple provider in Supabase and enable the Apple capability for this app.',
      );
    }
    if (!_isApplePlatform || !await _apple.isAvailable()) {
      throw const NativeAuthSetupException(
        'Sign in with Apple is unavailable on this device.',
      );
    }
    final rawNonce = _tokens.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final credential = await _apple.authenticate(hashedNonce);
    if (credential == null) throw const NativeAuthCancelled();
    final idToken = credential.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const NativeAuthSetupException(
        'Apple did not return an ID token. Please try again.',
      );
    }
    await _tokens.apple(idToken: idToken, rawNonce: rawNonce);
  }
}

class _GoogleIdentity implements GoogleIdentity {
  static const _channel = MethodChannel('ezyreminder/auth_config');
  static Future<_GoogleInitialization>? _initialization;
  final _signIn = GoogleSignIn.instance;

  @override
  Future<List<String>> configuredUrlSchemes() async {
    try {
      return (await _channel.invokeListMethod<String>('googleUrlSchemes')) ??
          const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> initialize({
    required String clientId,
    required String serverClientId,
    required String nonce,
    required String rawNonce,
  }) async {
    final pending = _initialization;
    if (pending != null) {
      final initialized = await pending;
      if (initialized.clientId != clientId ||
          initialized.serverClientId != serverClientId) {
        throw const NativeAuthSetupException(
          'Google sign-in was initialized with a different OAuth client configuration. Restart the app after correcting its configuration.',
        );
      }
      return;
    }

    final initialization = _initialize(
      clientId: clientId,
      serverClientId: serverClientId,
      nonce: nonce,
      rawNonce: rawNonce,
    );
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  Future<_GoogleInitialization> _initialize({
    required String clientId,
    required String serverClientId,
    required String nonce,
    required String rawNonce,
  }) async {
    await _signIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
      nonce: nonce,
    );
    return _GoogleInitialization(clientId, serverClientId, rawNonce);
  }

  @override
  Future<GoogleTokens?> authenticate() async {
    try {
      await _signIn.signOut();
      final account = await _signIn.authenticate(scopeHint: const ['email']);
      final auth = account.authentication;
      final authorization = await account.authorizationClient
          .authorizationForScopes(const ['email']);
      final granted =
          authorization ??
          await account.authorizationClient.authorizeScopes(const ['email']);
      return GoogleTokens(
        idToken: auth.idToken,
        accessToken: granted.accessToken,
        rawNonce: (await _initialization!).rawNonce,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const NativeAuthCancelled();
      }
      rethrow;
    }
  }
}

class _GoogleInitialization {
  const _GoogleInitialization(
    this.clientId,
    this.serverClientId,
    this.rawNonce,
  );
  final String clientId, serverClientId, rawNonce;
}

class _AppleIdentity implements AppleIdentity {
  @override
  Future<bool> isAvailable() => SignInWithApple.isAvailable();

  @override
  Future<AppleIdentityToken?> authenticate(String hashedNonce) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      return AppleIdentityToken(credential.identityToken);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const NativeAuthCancelled();
      }
      rethrow;
    }
  }
}

class SupabaseTokenExchanger implements NativeTokenExchanger {
  SupabaseTokenExchanger(this.client, {this.idTokenSignIn});
  final SupabaseClient client;
  final Future<void> Function({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  })?
  idTokenSignIn;

  @override
  Future<void> google({
    required String idToken,
    required String accessToken,
    required String rawNonce,
  }) async {
    await _signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
      nonce: rawNonce,
    );
  }

  @override
  Future<void> apple({
    required String idToken,
    required String rawNonce,
  }) async {
    await _signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  Future<void> _signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  }) async {
    final injected = idTokenSignIn;
    if (injected != null) {
      await injected(
        provider: provider,
        idToken: idToken,
        accessToken: accessToken,
        nonce: nonce,
      );
      return;
    }
    await client.auth.signInWithIdToken(
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
      nonce: nonce,
    );
  }

  @override
  String generateRawNonce() => client.auth.generateRawNonce();
}
