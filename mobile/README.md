# ezyReminder for iOS

The iOS client includes a simple Today list, All context filters, completion/snoozing/undo, All with search and completed reminders, reminder deletion, Shopping checklists, order details/Ship Queue, Work/Side Gig detail panels, and Settings for timezone, quiet hours, sign-out, and account deletion. See [PARITY_PROGRESS.md](docs/PARITY_PROGRESS.md) for the ordered build and validation results.

Google sign-in works as confirmed by Rik. Apple sign-in is restored and enabled alongside Google, with the Apple entitlement in the iOS target. The Supabase Apple provider is enabled for the native bundle ID; refreshed signing and real-account verification remain release checks; see [AUTH_SETUP.md](docs/AUTH_SETUP.md). Magic links, onboarding, APNs push delivery, Share Extension, widgets, and Foundation Models are still pending. The hosted APNs HTTP/2 transport gate in FLUTTER_IOS_PROMPT.md passed on 2026-10-19. Local notifications (Settings → Channels → iPhone notifications, Done / Snooze 1h from the lock screen) were built on 2026-10-19 and still need an on-device check; APNs push is still to be built. Shipping behavior and the real-account smoke test are documented in [SHIPPING.md](docs/SHIPPING.md).

All commands below run from the repository’s `mobile/` directory.

## Preview without a Supabase account

The preview uses representative fixture reminders stored only in memory. It never contacts Supabase. Run it explicitly with:

```sh
flutter run --dart-define=EZY_PREVIEW=true
```

The screen shows a **PREVIEW** badge. Saving and completing reminders changes only the in-memory fixtures.

## Run against Supabase

Copy `env/example.json` to `env/dev.json`, then replace the placeholders with the project URL and public anon/publishable key. Never put a service-role key here. `env/dev.json` is gitignored.

```sh
cp env/example.json env/dev.json
dart run tool/configure_ios_auth.dart env/dev.json
flutter run --dart-define-from-file=env/dev.json
```

Use Google or Apple after the provider setup in [AUTH_SETUP.md](docs/AUTH_SETUP.md), or sign in with an existing Supabase email/password account. Supabase Flutter persists the session on device. Reads use the signed-in user's RLS session; create and edit use the `create_reminder` and `update_reminder` RPCs. Direct completion and snooze writes request the changed row and report a missing or unauthorized reminder as an error.

## Open in Xcode

From `mobile/`, prepare the Flutter configuration before opening Xcode:

```sh
flutter pub get
dart run tool/configure_ios_auth.dart env/dev.json
flutter build ios --config-only --no-codesign --dart-define-from-file=env/dev.json
open ios/Runner.xcworkspace
```

The app bundle ID is `com.ezyreminder.app`. Choose the scheme that matches your destination:

- **Runner** → **Debug**, for an iOS simulator or debugging a connected phone.
- **RunnerDevice** → **Release**, for installing on a physical iPhone and launching from its home screen. Select the connected phone as the destination.

Physical-device signing uses your selected development team. Swift Package Manager is enabled; CocoaPods is not required. Both schemes run Flutter's framework preparation pre-action.

For an iPhone, select your own Team in Runner → Signing & Capabilities, connect the device, and use `flutter run --release --dart-define-from-file=env/dev.json -d <device-id>`. The simulator uses debug mode.

The development configuration in this checkout uses the existing web project's public URL and anon key. No password or service-role key is included. Live login and cross-client smoke tests require your account; simulator screenshots use preview fixtures.

## Local checks

```sh
flutter analyze
flutter test
flutter build ios --simulator --debug
```

## Carrier, tracking, and time controls

Order carrier fields offer UPS, USPS, FedEx, DHL, Postal, DoorDash, Uber, and Other (custom name). Shipped orders remain editable; the Shipped switch can reopen an order or mark it complete when saved. Apply migration 0010 before using shipment corrections against Supabase. Tracking fields show carrier-specific character limits, never silently truncate IDs, and block shipment confirmation for an overlong value. See [SHIPPING.md](docs/SHIPPING.md) for limits.

Reminder due times and custom snooze times use a compact calendar plus an hour/minute wheel with AM/PM (24-hour time when enabled on the device). Morning (9 AM), Noon, and Evening (6 PM) shortcuts change only the time; choose a date separately. Tap **OK** to apply or **Cancel** to keep the previous date/time.

## Focus sessions

Start Focus from an existing Work or Side Gig reminder or from Side Gig. Choose a 10/25/50-minute or custom session, pause/resume it, and save an outcome plus a next step. Reopening the app restores the server session. Closing the sheet keeps the timer running; the active session is reachable on Today and All. Focus never completes a reminder or marks an order shipped.

Migration `0012_focus_sessions.sql` was applied to hosted Supabase on 2026-10-18 and independently verified. Preview mode uses an isolated in-memory focus repository. Scheduled sessions, background timer notifications, and notification suppression are deferred.

Checks: `flutter test test/focus_test.dart` and `flutter analyze`. A real signed-in web → iPhone → web session handoff still needs verification after the client releases.

## Xcode “Unable to resolve module dependency: Flutter”

On 2026-10-18 the failing Xcode log showed `Release-iphonesimulator`. [Flutter does not support Release on a simulator](https://docs.flutter.dev/testing/build-modes); this configuration left native plugins unable to resolve the matching Flutter framework. Runner now defaults to Debug; the previous Release Run setup is retained as RunnerDevice. Open `ios/Runner.xcworkspace` and choose Runner for a simulator or RunnerDevice for your phone. If Xcode still shows stale errors from the previous build, use Product → Clean Build Folder and build the selected scheme again. Do not edit plugin files under `.pub-cache`.


## Simple Today capture, full Side Gig editing

Today and All capture only title, context and optional time. Choosing Side Gig leaves the form unchanged. Tap the saved task/order to open the canonical Side Gig editor and add notes, next step, duration or optional order/client fields without duplicating the record. Side Gig's own Add opens the full Task/Order/Follow-up/Expected payment flow.

Today has one date-grouped list and a recovery card only when a Focus session exists; no context-filter row, empty Focus setup or duplicate Ship soon preview. All retains search/filtering. Focus starts from details or Side Gig; weekly times stay in Settings.

Connected Side Gig editing requires `0018_sidegig_experience.sql` (pending hosted release as of 2026-10-19). This simplification adds no migration. Rebuild the mobile client. Preview mode needs no migration and shares captures/edits with Today and All in memory.
