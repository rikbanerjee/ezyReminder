# Native Google and Apple login

Both provider buttons are present in the Flutter login screen. They exchange native identity tokens for the same Supabase session used by email/password; there is no second identity backend. Actual provider login needs the console/signing setup below. No console changes, secrets, or account creation were performed by this implementation.

## Google

1. In Google Cloud, use the existing OAuth project. Keep the existing **Web application** OAuth client used by Supabase. Create an **iOS** OAuth client for bundle ID `com.ezyreminder.app`.
2. Add the iOS client ID to the authorized client IDs for Supabase Auth → Google, alongside the existing web client ID. Keep any Google client secret server-side in Supabase; it never goes into Flutter.
3. Set these public identifiers in ignored `mobile/env/dev.json`:

   ```json
   {
     "GOOGLE_IOS_CLIENT_ID": "123-example.apps.googleusercontent.com",
     "GOOGLE_WEB_CLIENT_ID": "123-web.apps.googleusercontent.com",
     "GOOGLE_IOS_REVERSED_CLIENT_ID": "com.googleusercontent.apps.123-example"
   }
   ```

4. From `mobile/`, generate the callback scheme and rebuild:

   ```sh
   dart run tool/configure_ios_auth.dart env/dev.json
   flutter run --dart-define-from-file=env/dev.json
   ```

   The script writes ignored `ios/Flutter/AuthConfig.xcconfig`; Debug/Release/Profile include it. Info.plist registers its URL scheme. The app verifies the scheme in the actual installed bundle before calling Google's SDK, so missing setup produces a message instead of a native SDK crash. A hot reload is insufficient after changing OAuth IDs or URL schemes.

No Firebase project or Firebase runtime is needed. Reference: [Google's iOS integration](https://developers.google.com/identity/sign-in/ios/start-integrating), [Flutter Google plugin configuration](https://pub.dev/packages/google_sign_in_ios), [Supabase ID-token exchange](https://supabase.com/docs/reference/dart/auth-signinwithidtoken).

## Apple

1. Select your Apple Developer Team in Xcode → Runner → Signing & Capabilities. Register `com.ezyreminder.app` and enable **Sign in with Apple** for that App ID. The project already references `Runner.entitlements` with the Apple sign-in entitlement.
2. Enable Supabase Auth → Apple and authorize the native bundle ID. Follow the provider's console instructions for your native app; any required server credentials stay in Supabase, never in Flutter.
3. Set `"APPLE_SIGN_IN_ENABLED": true` in ignored `env/dev.json` only after those settings are ready. Rebuild and use an Apple-ID-signed-in device/simulator. Without setup, the visible Apple button explains what is missing.

When testing Apple’s Hide My Email option, also verify reminder email delivery through the private relay and configure the sender domain in your Apple account.

The app generates a fresh raw nonce, sends its SHA-256 hash to Apple, then submits the returned identity token and original nonce to Supabase. Reference: [Supabase Apple sign-in](https://supabase.com/docs/guides/auth/social-login/auth-apple?platform=flutter).

## Validation and remaining release work

Automated tests use fake identity providers and token exchangers; they do not log into a real Google/Apple account. Real provider success, cancellation, account linking, and device signing need a manual smoke test after console setup. Existing password login remains available for the reviewer account.

Before App Store release, complete the account-deletion/Apple-token-revocation review and the other release gates in `HUMAN_TODO.md`. Adding login buttons does not mark those gates complete.

Implementation checks: the simulator build with both native plugins passed; the rebuilt screen was installed and its Google/Apple buttons verified in `screenshots/login-providers-dark.png`. Static analysis is clean. All 19 Flutter tests passed (8 reminder/UI checks plus 11 provider/token/nonce and login checks), including the nonce mismatch regression. No real provider sign-in is claimed.

## Nonce mismatch fix — 2026-10-17

The Google iOS SDK can include a nonce in its identity token even when the application has not supplied one. The old app exchange omitted the corresponding nonce, and Supabase correctly rejected it with “Passed nonce and nonce in id_token should either both exist or not.”

The app now creates an explicit raw nonce, supplies its SHA-256 hash when initializing Google, carries the original nonce with the returned credentials, and passes it to Supabase’s ID-token exchange. Google’s SDK supports the nonce at initialization, so the initialization future and its matching nonce are cached for the SDK lifetime and reused across recreated login controllers. Interactive retries clear the SDK’s cached signed-in account before starting a new chooser. Supabase nonce verification stays enabled.

Stop and rebuild the app after updating this code; a running login controller from an older binary cannot gain the new nonce handling. Real Google sign-in must be retried after installing the new build.
