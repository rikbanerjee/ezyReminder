# Native Google and Apple login

Both provider buttons are present in the Flutter login screen. Apple sign-in was restored on 2026-10-19: the Apple entitlement/capability is enabled, Apple defaults on (and is on in the ignored local configuration), and the button supports both appearance modes. They exchange native identity tokens for the same Supabase session used by email/password; there is no second identity backend. Actual provider login needs the console/signing setup below. Provider setup and a signed device are still required for a real sign-in. Secrets never go into Flutter.

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
3. Apple is enabled by default; `env/example.json` and the ignored local `env/dev.json` both set `"APPLE_SIGN_IN_ENABLED": true`. An explicit false is available for an intentionally unconfigured build. Rebuild and use an Apple-ID-signed-in device/simulator.

For **native iOS**, authorize `com.ezyreminder.app` in Supabase's Apple **Client IDs** and enable the provider. A web Services ID and OAuth secret are not required for this native ID-token flow. Keep nonce verification on and “Allow users without an email” off. Web Apple sign-in is a separate OAuth configuration: it needs a registered Apple Services ID first in Supabase's client-ID list plus a server-side secret. The web login currently keeps its Google/email flow.

On 2026-10-19 the signed-in dashboard was checked: Apple is enabled with client ID `com.ezyreminder.app`; Google is also enabled. Apple's Developer portal confirms the same account's paid membership for team `Q5ERUTYL6M`, renewing October 19, 2027. Sign in with Apple was enabled and saved on the app ID. The replacement **ezyReminder Development Apple Login** profile was generated for the existing development certificate and registered iPhone, downloaded, and installed locally. Its decoded entitlement is `com.apple.developer.applesignin = [Default]`; it expires October 19, 2027. The old October 17 Personal Team profile lacks that entitlement and must not be selected.

Xcode initially retained its Personal Team status despite the account refresh. Restarting exposed an empty Apple Accounts list. After the owner signed in again, automatic signing regenerated **iOS Team Provisioning Profile: com.ezyreminder.app** with the Apple entitlement on October 19, 2026. The capability/profile changes were explicitly authorized; no credentials are stored in the repository.

When testing Apple’s Hide My Email option, also verify reminder email delivery through the private relay and configure the sender domain in your Apple account.

The app generates a fresh raw nonce, sends its SHA-256 hash to Apple, then submits the returned identity token and original nonce to Supabase. Reference: [Supabase Apple sign-in](https://supabase.com/docs/guides/auth/social-login/auth-apple?platform=flutter).

## Validation and remaining release work

Automated tests use fake identity providers and token exchangers; they do not log into a real Google/Apple account. Real provider success, cancellation, account linking, and device signing need a manual smoke test after console setup. Existing password login remains available for the reviewer account.

Before App Store release, complete the account-deletion/Apple-token-revocation review and the release gates in `MOBILE.md` §7. Adding login buttons does not mark those gates complete.

Implementation checks (2026-10-19): static analysis and all 15 native-auth tests pass, including Apple default enablement, hashed/provider vs raw/Supabase nonce handling, cancellation, unavailable devices and missing tokens. The connected simulator build passes with both Google IDs and Apple enabled, and without the `EZY_PREVIEW` bypass. These checks do not claim a successful real Apple account login.

## Device and TestFlight builds

Always prepare a connected build after using preview mode. Otherwise Xcode may reuse the last generated Dart defines and skip login.

```sh
dart run tool/configure_ios_auth.dart env/dev.json
flutter build ios --config-only --no-codesign --dart-define-from-file=env/dev.json
open ios/Runner.xcworkspace
```

Choose **Runner** for a Debug simulator build, or **RunnerDevice** for a Release phone build. The selected team is `Q5ERUTYL6M`; the bundle ID is `com.ezyreminder.app`. In Signing & Capabilities, automatic signing must produce a profile containing `com.apple.developer.applesignin = [Default]`. The managed profile was refreshed and verified after Xcode account sign-in on October 19, 2026. A profile created before Apple was enabled must be refreshed. Do not remove the entitlement just to make signing pass.

For TestFlight, select a generic iOS device destination and **Product → Archive**, then validate the archive in Organizer. Create/select the App Store Connect app with this bundle ID and use a build number not previously uploaded. Upload/distribution is a separate step; building or archiving does not publish anything. See [Apple's distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).

Notification testing is separate work: the native permission/token/scheduling bridge and delivery adapter are not implemented yet. The hosted HTTP/2 transport probe must pass before the APNs phase; see `supabase/functions/apns-transport-probe/README.md` and `FLUTTER_IOS_PROMPT.md` §2/Phase 5. Apple Developer membership and a successful login/archive do not establish push delivery.


## Nonce mismatch fix — 2026-10-17

The Google iOS SDK can include a nonce in its identity token even when the application has not supplied one. The old app exchange omitted the corresponding nonce, and Supabase correctly rejected it with “Passed nonce and nonce in id_token should either both exist or not.”

The app now creates an explicit raw nonce, supplies its SHA-256 hash when initializing Google, carries the original nonce with the returned credentials, and passes it to Supabase’s ID-token exchange. Google’s SDK supports the nonce at initialization, so the initialization future and its matching nonce are cached for the SDK lifetime and reused across recreated login controllers. Interactive retries clear the SDK’s cached signed-in account before starting a new chooser. Supabase nonce verification stays enabled.

Stop and rebuild the app after updating this code; a running login controller from an older binary cannot gain the new nonce handling. Real Google sign-in must be retried after installing the new build.

## Latest build result — 2026-10-19

- Connected iOS simulator build succeeds; installed with Apple enabled, Google IDs intact, and no preview bypass. The existing Supabase session restores correctly.
- Unsigned Release archive compiles at `build/ios/archive/Runner.xcarchive` (0.1.0, build 1). It is not a signed/distributable IPA. Flutter also flags the current placeholder app icon/launch image for replacement before release.
- After the owner signed into Xcode again, the signed Release archive succeeded at `build/ios/archive/ezyReminder.xcarchive` (0.1.0, build 1). `codesign --verify --deep --strict` passes. The app signature and embedded managed profile both contain `com.apple.developer.applesignin = [Default]`, under team `Q5ERUTYL6M`; the profile expires October 19, 2027.
- The signed Release app was installed and launched successfully on Rik's connected iPhone using `devicectl`. Apple is enabled, Google client IDs are configured, and the connected Supabase configuration is active with no preview bypass. Successful launch does not establish a successful real Apple sign-in.
- This is a development-signed archive for the registered iPhone. TestFlight distribution/export and a real Apple account login smoke test remain separate checks. No TestFlight upload has occurred.
