# iOS build — human setup and phase gates

Status: Phase 0 inventories and Phase 1 shared groundwork complete on `ios-mvp`. Rik reports hosted migrations 0001–0007 are applied and migration history matches the repo. All five RPCs were independently confirmed in the connected API schema. The remaining Phase 1 checks are still open; Flutter project creation starts in Phase 2.

Migration 0007 is immutable now. Put all subsequent database changes in a new migration numbered 0008 or later; never edit or reapply 0007. Applied SHA-256: `55dae2dbbf14d29005e48d4ef4079bf3882b83392db9ded34bd0faeece752c8c`.

## Placeholders approved by Rik

- Bundle ID: `com.ezyreminder.app`.
- Team ID: `<TEAM_ID>`; Apple Developer membership/signing not yet confirmed.
- The configured app URL is `http://localhost:3001`; production domain is still needed.
- AASA uses `<TEAM_ID>.com.ezyreminder.app` until real signing details are available.

## Phase 1 gate — before Flutter spike

- [x] Apply migrations 0001–0007 and synchronize migration history. Rik reports 0005 already existed, 0006/0007 were rehearsed with rollback and then applied, and live main was checked against the stricter RLS.
- [ ] Deploy `delete-account` with JWT verification enabled. Supabase supplies its built-in URL/anon/service-role environment variables; never copy the service-role key into a client.
- [ ] Deploy the web changes through your usual process after the database migration is applied. The updated server actions require the new RPCs.
- [ ] Create an order reminder; edit its order toggle/details; mark shipped and create the +3d follow-up.
- [ ] Add, check, and delete Shopping items, including additions from two browser tabs.
- [ ] Confirm two signed-in tabs update each other without reloading, and an incoming update does not erase an unsaved sheet edit.
- [ ] Set the real Team ID in `public/.well-known/apple-app-site-association` and serve it from the production domain.
- [ ] Confirm `curl -I https://<domain>/.well-known/apple-app-site-association` returns 200, `application/json`, and no redirect without a login cookie.
- [x] Authorize a local Phase 1 checkpoint commit (Rik's deployment handoff).
- [ ] Complete the outstanding Phase 1 checks and approve starting the Flutter spike.

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
