# iOS build — human setup and phase gates

Status: Phase 0 inventories and Phase 1 shared groundwork complete on `ios-mvp`. Rik reports hosted migrations 0001–0007 are applied and migration history matches the repo. All five RPCs were independently confirmed in the connected API schema. The remaining Phase 1 hosted checks are still open. Rik authorized starting the Phase 2 Flutter spike on 2026-10-16; it is now built and locally validated, awaiting the iPhone go/no-go review in docs/PHASE2.md. This does not mark the hosted checks complete.

Migration 0007 is immutable now. Put all subsequent database changes in a new migration numbered 0008 or later; never edit or reapply 0007. Applied SHA-256: `55dae2dbbf14d29005e48d4ef4079bf3882b83392db9ded34bd0faeece752c8c`.

## Placeholders approved by Rik

- Bundle ID: `com.ezyreminder.app`.
- Team ID: `<TEAM_ID>`; Apple Developer membership/signing not yet confirmed.
- The configured app URL is `http://localhost:3001`; production domain is still needed.
- AASA uses `<TEAM_ID>.com.ezyreminder.app` until real signing details are available.

## Phase 1 gate — before Flutter spike

- [x] Apply migrations 0001–0007 and synchronize migration history. Rik reports 0005 already existed, 0006/0007 were rehearsed with rollback and then applied, and live main was checked against the stricter RLS.
- [x] Deploy `delete-account` with JWT verification enabled. Supabase supplies its built-in URL/anon/service-role environment variables; never copy the service-role key into a client. Deployed 2026-10-15 (v1, `verify_jwt: true`); calls with no auth header or a malformed token return 401. A real signed-in deletion has not been tested yet.
- [ ] Deploy the web changes through your usual process after the database migration is applied. The updated server actions require the new RPCs.
- [ ] Create an order reminder; edit its order toggle/details; mark shipped and create the +3d follow-up.
- [ ] Add, check, and delete Shopping items, including additions from two browser tabs.
- [ ] Confirm two signed-in tabs update each other without reloading, and an incoming update does not erase an unsaved sheet edit.
- [ ] Set the real Team ID in `public/.well-known/apple-app-site-association` and serve it from the production domain.
- [ ] Confirm `curl -I https://<domain>/.well-known/apple-app-site-association` returns 200, `application/json`, and no redirect without a login cookie.
- [x] Authorize a local Phase 1 checkpoint commit (Rik's deployment handoff).
- [x] Approve starting the Flutter spike (Rik, 2026-10-16). Outstanding hosted smoke tests remain unchecked above.

Production rollout: Rik reports live main still exposes Slack, while the hosted database no longer supports it. Deploy the `ios-mvp` web changes promptly. A legacy reminder with a Slack channel can fail the global enqueue batch. The separately committed `0008_guard_notification_channels.sql` repairs invalid arrays and rejects future unsupported channel writes; it is **not applied** to hosted Supabase. Do not choose Slack in the old production UI.

- [ ] Review/apply `0008_guard_notification_channels.sql` to prevent stale clients from breaking the global enqueue batch. An unsupported channel will fail that individual save instead. This does not update the old web UI; deploy the updated client too.

Do not select `apns` as a delivery channel yet: Phase 1 makes the schema ready, but the APNs dispatcher is built in Phase 5. No context defaults were switched to push.

## Later phases

- [ ] Apple Developer Program membership, Team ID, bundle registration, automatic signing.
- [ ] Push Notifications, Associated Domains, Sign in with Apple, and App Group `group.com.ezyreminder.app` capabilities.
- [ ] APNs `.p8`, Key ID, Team ID and bundle ID configured as server secrets by Rik.
- [ ] Apply notification migration and deploy sweep only after the APNs Edge HTTP/2 spike passes.
- [ ] Supabase Auth: allow `ezyreminder://login-callback`; later allow the production universal callback URL.
- [ ] Enable Apple provider and create/configure native Google iOS and web OAuth client IDs and reversed URL scheme.
- [ ] Create a password demo account with sample data for App Review.
- [ ] Run Flutter spike on an iPhone next to the PWA and give a go/no-go decision.
- [ ] Real-device checks for push/local deduplication, quiet hours, lock-screen Done/Snooze, rescheduling, sharing, and widgets.
- [ ] Privacy policy, App Store Connect record/privacy labels/screenshots, TestFlight upload and App Store submission.
- [ ] Install CocoaPods only if a required plugin cannot use Swift Package Manager.

Foundation Models remains a later phase; no AI bridge is part of this build.

## Native login follow-up (2026-10-16)

Google and Apple login implementations and visible buttons are now included. Follow [AUTH_SETUP.md](docs/AUTH_SETUP.md) to supply the iOS Google client ID/reversed scheme, authorize the IDs in Supabase, and configure Apple signing/provider support. Rebuild after configuration. Rik confirmed Google account sign-in works on 2026-10-17. Apple account sign-in remains unverified.

- [x] Rik confirmed Google sign-in works after the nonce fix (2026-10-17). Cancellation remains covered by automated tests; physical-device coverage is not independently confirmed.
- [ ] Configure/test Apple native success and cancellation; finish Apple revocation on account deletion before release.

### Google configuration update — 2026-10-17

- [x] Rik supplied the iOS OAuth client ID. Configured the ignored local Flutter environment and generated the matching callback URL scheme; existing web client ID retained.
- [ ] Supabase → Authentication → Sign In / Providers → Google: add the iOS client ID alongside the existing web ID (web first), then save.
- [x] Rik verified native Google sign-in on the rebuilt app (2026-10-17); the agent did not independently perform account authentication.

## Shipping parity follow-up — 2026-10-17

Rik confirmed the app works and authorized matching the web shipping options. Implemented order details, Ship Queue with badge/Ship soon, inline tracking/mark shipped, seven-day shipment history, and +3d follow-up through the existing shared Supabase operations. No new migration or carrier integration was needed.

- [x] Integrated `flutter analyze`: clean.
- [x] All 30 Flutter tests pass, including seven loopback-backend shipping tests and 1.5× text layout checks.
- [x] Simulator preview and configured iOS debug builds pass.
- [x] Native fixture smoke test: tracking → confirm shipment → follow-up → shipped history; order sheet also inspected.
- [ ] Real-account cross-client shipping smoke test from [SHIPPING.md](docs/SHIPPING.md); automated/native checks used fixtures and did not write real reminders.

## Priority parity build — 2026-10-17

Rik authorized building Shopping → All/search/deletion → Work/Side Gig panels → Settings → native notifications in order. The first four stages are implemented locally. See [PARITY_PROGRESS.md](docs/PARITY_PROGRESS.md).

- [x] Full Flutter suite: 120 tests pass; analysis clean.
- [x] iOS preview simulator build passes after each feature stage.
- [x] Native fixture review of Shopping, All/search/reopen/delete-cancel, and Work/Side Gig panel save/reopen; screenshots in docs/screenshots.
- [x] Settings navigation integration and widget/protocol tests cover saved timezone, quiet-hour clear/failure, typed account deletion and failed server responses.
- [ ] Settings native visual review: blocked when the Mac locked; no Settings screenshot or live-account deletion is claimed.
- [ ] Real-account cross-client checks for new checklists, panels, settings and deletion (use an expendable test account for account deletion).
- [ ] Required hosted Supabase Edge → APNs sandbox HTTP/2 transport proof before implementing notification delivery, per FLUTTER_IOS_PROMPT.md §2 and Phase 5. No APNs routes or defaults have been enabled.

- [x] Final Supabase/Google-configured debug simulator build passes (existing ignored env retained).
- [x] Prepared [APNs transport probe](../supabase/functions/apns-transport-probe/README.md); all 9 mocked/offline Node tests pass.
- [ ] Rik: deploy and invoke the probe from the hosted project, then share its JSON result. This uses an invalid synthetic token and no APNs signing key; it proves HTTP/2 transport only. Native notification implementation is gated on this result, not claimed complete.

## Shipment corrections (2026-10-17)

- [x] Applied `0010_edit_order_reminder.sql` to hosted Supabase on 2026-10-18 with Rik's explicit authorization. Shipment edit RPC and authenticated-only execute permission verified.
- [ ] Reinstall the iPhone app. Edit a shipped order's recipient/tracking and confirm the web reflects the correction without changing shipped time. Turn Shipped off and save: verify the reminder reopens and the order returns to Ship Queue. Turn it on and save: verify completion.
- [ ] Any new APNs migration must use the next unused number, starting with 0014; migrations 0001–0013 are applied and immutable.

## Home tab rollout (2026-10-18)

- [x] Applied `0011_home_maintenance.sql` to hosted Supabase on 2026-10-18 with Rik's explicit authorization. Both Home tables have RLS enabled, both RPCs allow authenticated users and reject anonymous users, and both tables are in Realtime.
- [ ] Release web and Flutter changes together after migration verification.
- [ ] On a signed-in phone and browser, create a grocery list and check items across devices; create a maintenance task, record service, and verify next due date plus history on both.
- [ ] Verify email delivery and registered-iPhone delivery for an upcoming maintenance task, including Personal quiet hours. No fake service data is inserted into the live account.

Migration numbering: Home is 0011; Focus is 0012. Any later APNs migration must use the next unused number.

## Six-hour overdue email repeat (2026-10-18)

- [x] With Rik’s explicit authorization on 2026-10-18, applied notification migrations 0008, 0009, 0013 and deployed the matching sweep. Cron was safely paused/resumed; health and database checks passed. See `supabase/functions/notification-sweep/EMAIL_REPEAT.md`. App migrations 0010–0012 remain pending.

Home validation: production web build, TypeScript, scoped ESLint, Home Dart analysis, 34 Home/Today/shopping/state-sync Flutter tests, and the isolated SQL ownership/recurrence/history tests pass. The web components were visually checked with sample data in light and dark mode at phone width; screenshots are `mobile/docs/screenshots/home-web-light.jpg` and `home-web-dark.jpg`. The Today tests now scroll lazy reminder rows into view before interacting; the combined 34-test run passes. Live account delivery and sync are not yet verified.

Hosted migration verification (2026-10-18): local and remote history now contain 0001–0013. This Home rollout applied only the missing 0010, 0011, and 0012; notification migrations 0008, 0009, and 0013 were already recorded before this push. Verified Home/Focus RLS, authenticated-only RPC grants, and all four Realtime tables. `notification-sweep` cron job 1 is active on its existing `*/5 * * * *` schedule; this rollout did not alter cron. Client deployment and signed-in phone/browser smoke tests remain pending. See `supabase/MIGRATION_STATUS.md`.

## Contextual Home sections (2026-10-18)

- [x] Home care, Groceries, Bill pay, and Study & kids sections implemented in web and Flutter with shared templates.
- [x] Added car make/model, HVAC filter size, battery type, bill amount/currency, and study subject/teacher fields; all labels, completion actions, history, and repeats are contextual.
- [x] Applied and verified migration 0014 on hosted Supabase; existing data and old save RPC remain compatible.
- [x] Full 149-test Flutter suite, Flutter analysis, production build, scoped lint/TypeScript, template generation check, and Home SQL tests pass.
- [x] Phone-width browser checks cover car fields, bill validation, study fields, and dark battery form. Sample-data screenshots: `docs/screenshots/home-contextual-car.jpg` and `home-contextual-battery-dark.jpg`.
- [ ] Release updated clients and verify real-account create/edit/complete/sync for a car task, bill reminder, and study follow-up.

Migrations 0001–0014 are applied and immutable. Start future migrations at the next unused number, currently 0015.
