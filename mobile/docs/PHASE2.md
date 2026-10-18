# Phase 2 — Flutter iOS spike

Started 2026-10-16 on `ios-mvp`, following Rik's authorization to continue. The remaining hosted Phase 1 smoke tests are still listed in `HUMAN_TODO.md`.

This is the device-feel checkpoint specified by `FLUTTER_IOS_PROMPT.md`, before the Phase 3 architecture and full screen/notification work. Existing notification fixes and applied migrations are preserved.

## Scope

- Flutter iOS Runner, bundle ID `com.ezyreminder.app`, Swift Package Manager, no signing team.
- Real Supabase email/password authentication with persisted sessions and RLS-backed reminder access.
- Today, context filters, completion, snoozing, undo, and create/edit sheet with the shared design tokens.
- Explicit in-memory preview mode for simulator visual checks; preview never writes to Supabase.

## Validation

- `flutter analyze`: clean in the integrated root project.
- `flutter test --reporter expanded`: all 8 tests pass, including failed completion rollback, pending-write Undo, dirty-title Realtime merge, validation, and 1.0×/1.5× text sizes.
- `flutter build ios --simulator --debug --no-codesign --dart-define=EZY_PREVIEW=true`: passed; the preview ran on iPhone 17 Pro / iOS 26.5.
- A Supabase-configured simulator debug build also passed and was launched successfully to the email/password login screen (`screenshots/login-dark.png`). Actual login and cross-client updates still require an existing password account and a manual signed-in smoke test.
- Native row tap and compact calendar were opened and inspected in the simulator. Light/dark screenshots are in `screenshots/`: `today-light.png`, `today-dark.png`, `sheet-dark.png`, `date-picker-dark.png`. These show in-memory preview data, not a live account.
- `plutil -lint ios/Runner/Info.plist` and `git diff --check`: passed.
- `env/dev.json` was prepared from the existing web public URL/anon key and verified gitignored; no password, service-role key, or provider secret is included. No hosted migration, deployment, account creation, or real reminder write was performed.

## Implementation choices

The spike intentionally uses a small repository interface and Flutter state; Phase 3 introduces the planned Riverpod/models/routing structure. Only `supabase_flutter` and the standard Flutter Cupertino icon assets are runtime dependencies, pinned exactly. `cupertino_icons` is needed to bundle the glyph font used by Flutter's native-style controls ([official package](https://pub.dev/packages/cupertino_icons)); the SDK's default `flutter_lints` development dependency is pinned too. No extra notification or AI packages were added prematurely.

The context pill strip scrolls horizontally; the partially visible Shopping pill signals additional filters. All four contexts are reachable. Full screen parity remains Phase 4 work; this is not an App Store-ready app. Shared Dart date/quiet-hours fixture coverage, full panel layouts and motion, magic-link auth and real-provider verification, and notification delivery remain later phase gates.

The generated Xcode project initially inferred a local signing team. The checked-in project clears it, keeping the approved placeholder policy; Rik selects his Team for physical-device signing. No phase commit or push was made before the device review.

## Device gate

Rik should run the spike on his iPhone next to the PWA and assess scrolling, completion gestures, the sheet, keyboard, and readability. Phase 3 follows approval of this checkpoint. Push/local notifications, magic-link login, full Shopping/Ship Queue/Settings/Onboarding, Share Extension, widgets, and Foundation Models are not claimed in this spike. Native Google/Apple login was added in a user-requested follow-up; see AUTH_SETUP.md for the required provider configuration and manual verification.

## Shipping follow-up — 2026-10-17

Rik confirmed the app works and authorized native shipping parity. Order details, Ship Queue, tracking/mark shipped, recent shipments, and +3d follow-up have been added using the existing shared backend. See [SHIPPING.md](SHIPPING.md) for the current scope and validation; the original spike results above are historical.
