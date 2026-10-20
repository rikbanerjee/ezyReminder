import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/native_auth.dart';
import '../../core/theme/tokens.g.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.client, this.nativeAuth});
  final SupabaseClient client;
  final NativeAuth? nativeAuth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _auth =
      widget.nativeAuth ??
      NativeAuth(exchanger: SupabaseTokenExchanger(widget.client));
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _emailError, _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on NativeAuthCancelled {
      // Dismissing a system account chooser is an expected user action.
    } on NativeAuthSetupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not sign in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailSignIn() {
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _emailError = email.contains('@') ? null : 'Enter a valid email address.';
      _passwordError = password.isEmpty ? 'Enter your password.' : null;
    });
    if (_emailError != null || _passwordError != null) return Future.value();
    return _run(() async {
      await widget.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hairline = dark
        ? EzyDesignTokens.darkHairline
        : EzyDesignTokens.lightHairline;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(CupertinoIcons.bell, size: 44),
                  const SizedBox(height: 20),
                  Text(
                    'Good to see you',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to your reminders',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 30),
                  _ProviderButton(
                    label: 'Continue with Google',
                    icon: const _GoogleMark(),
                    busy: _busy,
                    onPressed: () => _run(_auth.signInWithGoogle),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: SignInWithAppleButton(
                      text: 'Continue with Apple',
                      height: 52,
                      borderRadius: BorderRadius.circular(
                        EzyDesignTokens.rowRadius,
                      ),
                      style: dark
                          ? SignInWithAppleButtonStyle.white
                          : SignInWithAppleButtonStyle.black,
                      onPressed: _busy
                          ? null
                          : () => _run(_auth.signInWithApple),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Divider(color: hairline)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or use email',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                      Expanded(child: Divider(color: hairline)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: 'Email',
                      errorText: _emailError,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: _passwordError,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
                    onSubmitted: (_) => _emailSignIn(),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _emailSignIn,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_busy ? 'Signing in…' : 'Sign in with email'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final Widget icon;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: busy ? null : onPressed,
    icon: icon,
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      side: BorderSide(color: Theme.of(context).dividerColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EzyDesignTokens.rowRadius),
      ),
    ),
  );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 21,
    height: 21,
    child: Center(
      child: Text(
        'G',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}
