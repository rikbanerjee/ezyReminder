# Build Prompt — ezyReminder iOS app (Flutter) alongside the existing web app

Paste everything below into your coding agent (Claude Code, run from the repo root).

---

You are the **orchestrator** for building the ezyReminder iOS app in Flutter, alongside the existing Next.js web app. You plan, delegate to subagents, verify their work, integrate, and report to Rik. You write very little feature code yourself.

**Before anything else**, read `CLAUDE.md`, `MOBILE.md` (the iOS plan — §2 sync, §3 notifications, §6 build order, §7 App Review), `DESIGN.md` (both clients follow it) and `PLAN.md`. Open `design/prototype.html` in a browser at phone width. These files are the spec: **if the web app and the prototype disagree, the prototype wins.** Don't re-ask Rik for anything those files answer.

Run `git status`. If the tree isn't clean, stop and ask Rik to commit first. Work on the branch `ios-mvp` (check it out, or create it from `main` if it doesn't exist).

Ask Rik **one** message up front, then proceed with placeholders for anything he doesn't know yet:
1. Bundle ID (placeholder `com.ezyreminder.app`)
2. Production web domain for universal links (placeholder: the host in `NEXT_PUBLIC_APP_URL`)
3. Whether his Apple Developer account and Team ID exist yet

---

## 1. Current state (verified 2026-10-14)

- **Web app is live** (Next.js 15, Vercel). Phases 0–4 are shipped. Slack was removed in `0006_remove_slack.sql`, and delivery is email via Resend. Uncommitted onboarding work (`0005_onboarding.sql`, `/onboarding`) gates new users on `user_settings.onboarded_at`.
- **Schema** (`supabase/migrations/0001`–`0006`):
  - Tables: `contexts`, `reminders`, `orders`, `notifications`, `api_keys`, `user_settings`, `work_details`, `sidegig_details`, `shopping_items`. All have RLS by `user_id`.
  - `reminders.updated_at` exists (trigger maintained).
  - Channel check constraints currently allow `('email','whatsapp')`.
- **All writes live in `app/actions.ts`** (Next.js server actions with `revalidatePath`). Multi-step ones (`createReminder` = reminder + order, `markShipped`, `createFollowUp`, `addShoppingItem` with a position counter) are **not transactional** and can only be called by the web app.
- **Delivery sweep** (`supabase/functions/notification-sweep/index.ts`, Deno, pg_cron every minute):
  - `enqueue_due_notifications()` fans out over `reminders.channels`, or the context's `default_channel` if empty. It dedupes on `(reminder_id, channel, scheduled_for)`.
  - `claim_due_notifications()` claims rows with `FOR UPDATE SKIP LOCKED`.
  - Quiet hours defer via `maybeDeferForQuietHours`; retries use backoff.
- **Shared, Node-free modules** are imported verbatim by both Next.js and Deno: `lib/quiet-hours.ts`, `lib/integrations/*`, `lib/dates.ts` (no imports).
- **Realtime is not enabled** on any table; no table is in the `supabase_realtime` publication.
- **Auth:**
  - Web magic link uses PKCE through `app/auth/callback/route.ts`.
  - Google sign-in has two paths: `signInWithOAuth`, and native Google Identity Services (`components/auth/google-native-button.tsx`).
  - There is no Apple sign-in and no email+password login.
- **Middleware** (`middleware.ts`) redirects unauthenticated requests to `/login` for every path it matches. Its matcher **does not exclude `/.well-known/`**, so it would currently break Apple's `apple-app-site-association` (AASA) fetch.
- **Toolchain on Rik's Mac:**
  - Installed: Flutter 3.47.3 (Dart 3.13), Xcode 26.6, iPhone 17 Pro / Pro Max / 17e simulators, Supabase CLI 2.120, Node 26 (runs `.ts` tests natively with `node --test`).
  - **Not installed:** CocoaPods (use Swift Package Manager: `flutter config --enable-swift-package-manager`), and Docker (so **no local Supabase** — you cannot run `supabase db reset`).

## 2. What you must be aware of (hard rules)

**The web app must keep working at every step.** It's in production.
- Migrations are additive only: no renames or drops of anything the web uses.
- Server actions become thin wrappers over the new RPCs. Don't rewrite web UI that isn't in scope.
- After every web change: `npx tsc --noEmit`, `npm run lint` and `npm run build` must pass.

**Things you must never do yourself.** Rik does these; you write the files and the instructions:
- Apply migrations to the hosted Supabase project.
- Deploy edge functions.
- Set secrets.
- Push to git, deploy to Vercel, or upload to TestFlight or the App Store.

**One backend, two clients.**
- Flutter talks to Supabase directly, with the **anon key and the user's session only**. The service-role key never ships in the app.
- Supabase URL and anon key come from `--dart-define-from-file=env/dev.json` (gitignored), with `mobile/env/example.json` committed.
- Every direct insert from Flutter sets `user_id = auth.uid()`, or RLS rejects it.
- App writes use `created_by: 'ui'`, same as the web. `agent:<name>` is reserved for the future API and MCP server.

**RPCs:**
- Use `security invoker` so RLS still applies.
- Make them transactional.
- **Validate that `context_id` belongs to `auth.uid()`.** Foreign-key checks bypass RLS, so today a client could attach a reminder to another user's context. The current `createReminder` has this gap; the RPC must close it.

**Last edit wins** (Rik's decision): plain updates, no version checks. But a Realtime event must **never overwrite a field the user is currently editing** in an open sheet. Merge only non-dirty fields.

**Sweep invariants** (see `CLAUDE.md`):
- It stays idempotent (dedupe plus `SKIP LOCKED`; never a second scheduler).
- Quiet hours **defer, not suppress**, on every channel, including locally scheduled notifications.
- New adapters follow the shared-module rules: relative imports with `.ts` extensions, no `@/` aliases, no `node:` imports, no npm packages, WebCrypto only.

**Dates must match across clients.**
- Port `lib/dates.ts` and `lib/quiet-hours.ts` to Dart as `mobile/lib/core/util/dates.dart` and `quiet_hours.dart`.
- Both the TypeScript and Dart versions must pass the **same JSON fixtures** in `shared/fixtures/`.
- `lib/dates.ts` uses device-local time; `quiet-hours.ts` uses `user_settings.timezone`. Mirror this exactly, and pin `TZ` in tests.

**UI parity:**
- Tokens come from `design/tokens.json` (Phase 1). Never hand-type a hex value or shadow in Dart.
- Map them as: `BoxShadow` for the shadows; `Cubic(0.32, 0.72, 0, 1)` at 300ms for the sheet; a 40% scrim; `DraggableScrollableSheet` with half and full heights.
- Use the system font (SF on iOS); don't bundle SF Pro (licence).
- Honour Reduced Motion (`MediaQuery.disableAnimations`), Dynamic Type up to at least 1.5×, 44pt touch targets, VoiceOver labels and dark mode.
- If the web app has a bug relative to the prototype, **don't copy the bug**. Note it in `mobile/docs/PARITY.md` as a web follow-up.

**No Slack, no Firebase, no Web Push.**
- Slack is gone; don't reintroduce it.
- Auth is Supabase-only. APNs is sent directly, without Firebase Cloud Messaging.
- `WEB_PUSH_PROMPT.md` is on hold.
- WhatsApp is a stub, so hide it in the iOS UI.

**The APNs device token needs native code.** Nothing in Flutter exposes the raw APNs token without Firebase. Write a small Pigeon (or `MethodChannel`) bridge in `AppDelegate.swift` that calls `registerForRemoteNotifications` and forwards the token and any errors to Dart. That's about 50 lines.

**APNs requires HTTP/2.** In Phase 5, first prove that `fetch` from a Supabase Edge Function negotiates HTTP/2 with `api.sandbox.push.apple.com`. If it can't, **stop and report**; don't invent a relay.

**Only one agent touches `mobile/ios/` (Runner, `project.pbxproj`, entitlements, extensions) at a time.** Xcode project files don't merge.

**Repo hygiene:**
- Add `mobile/**` to `eslint.config.mjs` ignores and the `tsconfig.json` exclude.
- Add a `.vercelignore` containing `mobile/`.
- Keep the Flutter-generated `mobile/.gitignore`.
- Never commit `env/*.json` (other than the example), `.p8` keys or `GoogleService`-style secrets.

**Pinned packages.** Check pub.dev for the current stable versions, prefer verified publishers, and pin exact versions in `pubspec.yaml`. The baseline set:
- `supabase_flutter`, `flutter_riverpod`, `go_router`, `freezed` + `json_serializable`, `intl`, `flutter_timezone` + `timezone`
- `flutter_slidable`, `flutter_local_notifications`, `sign_in_with_apple`, `google_sign_in`, `crypto` (for the Apple nonce)
- `receive_sharing_intent`, `home_widget`, `pigeon` (dev)

Don't add packages beyond these without saying why in your report.

## 3. Decisions already made (don't relitigate)

- **Stack:** Next.js for web, Flutter for iOS (Android later from the same project), Supabase for everything else. Apple-only features are thin Swift targets.
- **Notifications:** hybrid on-device local notifications plus APNs from the sweep, deduplicated, with email as the fallback (`MOBILE.md` §3).
- **The `apns` channel means "this user's iPhone(s), falling back to email."**
  - Add `'apns'` to both channel check constraints.
  - When the sweep dispatches `apns` and the user has no live device token, it sends the email instead. The notification row records `provider_message_id = 'email-fallback:<id>'`.
  - Context defaults stay `email`. When the app registers its first device, it shows a one-time prompt, "Send reminders to this iPhone?", which flips that user's `email` contexts to `apns`.
- **Dedupe with local notifications:**
  - Add a `local_schedules` table: `user_id`, `reminder_id`, `device_token_id`, `fire_at`, `scheduled_at`; unique on `(reminder_id, device_token_id)`; RLS by user.
  - When dispatching `apns`, the sweep skips the push for any device that has a `local_schedules` row whose `fire_at` equals the reminder's current effective due time (`coalesce(snoozed_until, due_at)`, after any quiet-hours deferral).
  - If every live device is covered, the notification is marked `sent` with `provider_message_id = 'local'`.
  - The local notification identifier and `apns-collapse-id` are both the reminder id, so in the worst case iOS replaces one notification with the other rather than showing two.
- **Out of scope for this build:** Android, Apple Foundation Models (planned in `MOBILE.md` §4 — don't build the bridge yet), Web Push, WhatsApp, Shippo, and the REST API / MCP server (though the RPCs you add are what they'll reuse).

## 4. How to orchestrate subagents

- **Briefs must stand alone.** Subagents don't see this prompt or your conversation. Every brief includes:
  - the goal, and the exact files and directories the agent **owns** (it may edit only those);
  - the relevant rules from §2 (paste them in);
  - which spec sections to read (e.g. "`DESIGN.md` §4.2, §5.1; `MOBILE.md` §3");
  - acceptance criteria with the exact commands that must pass;
  - the report format below.
- **Parallel only when ownership doesn't overlap.** Run parallel builders with `isolation: "worktree"`, then merge them **one at a time** yourself, running the gate commands after each merge. At most 4 builders run concurrently.
- **Agent types:**
  - `Explore`: read-only inventories.
  - `Plan`: architecture checks.
  - `principal-engineer-builder`: implementation.
  - `ios-test-runner`: `xcodebuild` / XCTest runs and screenshot export (Swift targets).
  - `general-purpose`: `flutter test integration_test` and `xcrun simctl io booted screenshot` runs, and fresh-context reviews.
  - Hand all token-heavy simulator runs to a test-runner agent so your own context stays small.
- **Shared code** (`mobile/lib/core/**`, `mobile/lib/shared/**`, `pubspec.yaml`, `mobile/ios/**`) is owned by **you** between waves. Feature agents that need a change there put it in their report under "Core change requests". You apply it, then re-run the affected agents.
- **Verify; don't trust.** Re-run every acceptance command yourself after merging. A subagent saying "tests pass" is a claim, not evidence.
- **Gates.** At each **STOP** below, send Rik a short report:
  - what was built;
  - the command results;
  - screenshots where relevant;
  - what he must do by hand (copied from `mobile/HUMAN_TODO.md`);
  - decisions you made that he might want to change.

  Then wait. After he approves, commit that phase on `ios-mvp`, with a message ending in your session's attribution lines. Never push.

**Subagent report format** (require it in every brief):
```
## Done
- <what, file paths>
## Commands run
- <command> → <pass/fail, key output>
## Deviations from brief
## Core change requests
## Open questions / risks
```

---

## 5. Phases

### Phase 0: Recon (2 read-only `Explore` agents, in parallel)

- **0A: Parity inventory** → `mobile/docs/PARITY.md`.
  - Every screen, state, gesture, animation, toast, empty state and validation message in `design/prototype.html`, `DESIGN.md` and the web components (`components/home/*`, `components/ship-queue/*`, `components/settings/*`, `components/onboarding/*`, the login page).
  - One checklist row per item, with source references (`file:line` or prototype selector), grouped by screen.
  - Mark rows where the web diverges from the prototype.
- **0B: Data-access inventory** → `mobile/docs/DATA_ACCESS.md`.
  - Every Supabase read and write in `app/actions.ts`, `lib/*-data.ts`, `lib/orders.ts`, `lib/shopping-items.ts`, `lib/work-details.ts`, `lib/sidegig-details.ts` and the components.
  - Classify each as **direct CRUD** (safe under RLS from Flutter), **needs RPC** (multi-step or invariant), or **needs edge function** (uses secrets, e.g. `retryNotification`).

You review both files and fix anything missing. Continue without a STOP.

### Phase 1: Shared backend groundwork (web-only changes; up to 4 builders in parallel, plus one sequential)

- **1A: Database** (owns `supabase/migrations/0007_ios_foundation.sql` and `lib/supabase/types.ts`):
  - RPCs `create_reminder`, `mark_shipped`, `create_follow_up` and `add_shopping_item`, each `security invoker`, transactional and context-ownership-checked. Return the new or affected ids.
  - Add `reminders`, `orders`, `shopping_items`, `work_details`, `sidegig_details` and `contexts` to `supabase_realtime`. Set `replica identity full` where delete events need the old row.
  - Tables `device_tokens` (`id`, `user_id`, `token` unique, `platform 'ios'`, `environment 'sandbox'|'production'`, `app_version`, `last_seen_at`, `disabled_at`) and `local_schedules` (§3), with RLS and indexes.
  - Allow `'apns'` in both channel check constraints.
  - Update the hand-written `Database` types (no `any`).
  - Include a commented-out rollback section at the bottom of the migration.
- **1B: Delete account** (owns `supabase/functions/delete-account/`, and the Settings section in `components/settings/settings-view.tsx`):
  - An edge function that verifies the caller's JWT and deletes the auth user (which cascades).
  - A web "Delete account" control with a typed confirmation.
- **1C: Design tokens** (owns `design/tokens.json`, `scripts/gen-tokens.mjs`, the token block in `app/globals.css`, and the generated `mobile/lib/core/theme/tokens.g.dart`):
  - Extract every DESIGN.md §2 token: colors light and dark, the three shadows, radii, type scale, spacing, motion durations and curves.
  - The generator writes the CSS variables and the Dart constants.
  - **The web must look identical afterwards.** Diff the generated CSS values against the current ones and show the diff is empty in your report.
  - Add an `npm run tokens` script.
- **1D: Shared fixtures** (owns `shared/fixtures/*.json` and `lib/*.test.ts`):
  - Cases for `bucketFor`, `relativeDue`, `snoozeTarget`, `isQuietNow` and `nextAllowedTime`, covering overnight quiet windows, DST transitions (America/Los_Angeles, Europe/London), multiple timezones, midnight boundaries and empty quiet hours.
  - Run with `TZ=... node --test lib/*.test.ts`, and add `npm run test:shared`.
- **1E: Web refactor** (sequential, **after 1A merges**; owns `app/actions.ts`, `app/r/`, `components/realtime-refresh.tsx`, `middleware.ts`, `next.config.ts`, `public/.well-known/`):
  - Server actions call the 1A RPCs, keeping their signatures and `revalidatePath` calls.
  - A Realtime client subscription that calls a debounced `router.refresh()`, plus a refresh when the tab regains focus.
  - A `/r/[id]` route that opens that reminder's sheet (reuse the existing home sheet state; e.g. redirect to `/?open=<id>` if the home view supports it, otherwise add that).
  - `public/.well-known/apple-app-site-association` (served as `application/json`, no redirect), with `applinks` paths `/r/*` and `/auth/mobile-callback*` and `<TEAM_ID>.<BUNDLE_ID>` placeholders.
  - **Exclude `/.well-known/` from the middleware matcher.**
  - Add `mobile/**` to the eslint and tsconfig excludes, and create `.vercelignore`.

**Gate commands:** `npx tsc --noEmit`, `npm run lint`, `npm run build`, `npm run test:shared`, `npm run tokens` (no diff on a second run).

**STOP.** Rik applies migration 0007, deploys `delete-account`, and smoke-tests the web: create an order reminder; mark it shipped and use the +3d follow-up; add a shopping item; confirm two browser tabs update each other live; confirm `curl -I <domain>/.well-known/apple-app-site-association` returns 200 with JSON.

### Phase 2: Flutter spike (1 builder, about 1–2 days, go/no-go)

- Create the project: `flutter create --org <reverse-domain> --project-name ezyreminder --platforms ios mobile`. Enable Swift Package Manager.
- The builder owns `mobile/` entirely in this phase.
- Build a minimal **Today** screen against real Supabase data, signed in with **email + password** (that's also the App Review demo-account path). It should include:
  - section cards with the real shadows;
  - a reminder row with a context-colored ring, tap to complete with the pop animation, and swipe right to complete / left for the snooze menu;
  - the reminder sheet opening with the Apple curve and drag-to-dismiss;
  - light and dark mode.
- Use the 1C tokens. Shortcuts are allowed in the architecture, but **not in the visuals**.
- A test-runner agent captures simulator screenshots (iPhone 17 Pro, light and dark) next to the prototype at the same width.

**STOP: go/no-go.** Rik runs it on his iPhone (`flutter run --release`) next to the PWA. If he says no-go, stop the whole build and summarize what felt wrong.

### Phase 3: Foundation (1 builder, sequential; this is where your shared core gets built)

- **Layout:**
  - `mobile/lib/core/{theme,models,data,auth,routing,util}`
  - `mobile/lib/shared/widgets`
  - `mobile/lib/features/{today,all,sheet,shopping,ship_queue,settings,onboarding,notifications,auth}`
- **Models:** freezed models for every table the app reads, matching `lib/supabase/types.ts`.
- **Repository layer:** typed repositories over `supabase_flutter`, using direct CRUD or RPCs per `DATA_ACCESS.md`. Every mutation is optimistic with rollback and a 5-second undo toast (`DESIGN.md` §6). One Realtime subscription per table feeds Riverpod providers, using the dirty-field merge rule from §2.
- **Auth:**
  - Email + password (reviewer).
  - Magic link with PKCE via the `ezyreminder://login-callback` deep link; the universal link `https://<domain>/auth/mobile-callback` comes later, once AASA is live.
  - Google: native `google_sign_in`, then `signInWithIdToken`. This needs the iOS client ID plus the web client ID as `serverClientId`.
  - **Sign in with Apple:** generate a raw nonce, send its SHA-256 to Apple, then call `signInWithIdToken(provider: apple, idToken, nonce: raw)`.
  - Session persistence, and an onboarding gate on `user_settings.onboarded_at` that mirrors the web.
- **Routing:** `go_router` with deep links for `/r/:id` (opens the sheet) and `compose?prefill=` (opens the create sheet prefilled; the Share Extension uses it later).
- **Ports:** `dates.dart` and `quiet_hours.dart` pass every `shared/fixtures` case (`flutter test`).
- **Shared widgets:** card, pill, context dot, ring, toast/undo, sheet scaffold (curve, scrim, drag, half/full heights), haptics helper (`HapticFeedback`), reduced-motion helper, field validation (red outline + one-line message; never a silently disabled button — `DESIGN.md` §5.1).
- **Also:** `mobile/README.md` (how to run, dart-defines) and `mobile/HUMAN_TODO.md` (§6 below, kept current from here on).

**Gate:** `flutter analyze` clean; `flutter test` green; `flutter build ios --simulator --debug` succeeds; sign-in works on the simulator for every method that doesn't need Rik's console setup (list which ones are blocked).

**STOP.** Short architecture review with Rik.

### Phase 4: Screens (4 builders in parallel, worktrees; each owns only its `features/<x>/` folder and its tests)

- **4A: Today + All + app shell.**
  - Large title that collapses on scroll.
  - Context pills with the active pill in the context's color and a spring indicator.
  - Sections in order: Overdue, Today, Ship soon (only when non-empty), Upcoming, Done today (collapsed).
  - The full row anatomy.
  - Gestures: swipe right to complete, swipe left for snooze presets (1h / Tonight / Tomorrow / Pick…), long-press context menu (Edit / Duplicate / Move context / Delete).
  - Tab bar (Today / Ship Queue with a badge / All).
  - The docked quick-add bar as a **tap-anywhere trigger** that opens the create sheet.
  - All tab: search plus grouping by context, including a Someday group.
- **4B: Reminder sheet (create and edit).**
  - Inline-editable title with validation.
  - Context select starting as a disabled "Choose template" placeholder.
  - The compact custom `DateTimePicker` with an **OK** button (not the native wheel).
  - Repeat presets.
  - DELIVER VIA: 📱 iPhone and ✉ Email (no WhatsApp), plus the quiet-hours line.
  - Order / Work / Side Gig panels that slide open from a toggle.
  - Mark shipped inline, then the toast with **+3d follow-up**.
  - Delete.
- **4C: Shopping + Ship Queue.**
  - Shopping checklist sheet: always-focused add field; each add/check/delete is an instant write; checked items struck through.
  - Ship Queue sorted by ship-by, with danger states, inline tracking field that expands in the row, and "Shipped this week" collapsed.
- **4D: Settings + Onboarding + Login.**
  - Settings as an iOS grouped table: timezone, quiet hours per context, appearance (system/light/dark), notification status per device, sign out, **Delete account** (calls the 1B function, typed confirmation).
  - Onboarding.
  - Login with all four sign-in methods.

Each builder must:
- tick its `PARITY.md` rows;
- write widget tests, plus golden tests in light and dark (goldens are for layout regressions only — fonts differ in tests);
- check Dynamic Type at 1.0× and 1.5× and VoiceOver labels;
- report any core change requests.

**Integration** (you): merge the builders one at a time. Apply the core change requests. Run `flutter analyze` and `flutter test`. Have a test-runner agent capture every screen in light and dark on the iPhone 17 Pro and 17e simulators.

**Parity review:** a fresh `general-purpose` reviewer (read-only, no builder context) scores every `PARITY.md` row pass/fail against the screenshots and the prototype. Failures go back to the owning builder. Repeat until everything passes or a failure is explicitly accepted by Rik.

**STOP.** Rik reviews on his device.

### Phase 5: Notifications (2 builders in parallel)

- **5A: Server** (owns `lib/integrations/apns/index.ts`, `supabase/functions/notification-sweep/`, `supabase/migrations/0010_apns.sql`; use the next unused number if more migrations have landed):
  - **First:** a spike proving HTTP/2 from Edge Functions to APNs sandbox (see §2). Report the result before building on it.
  - The adapter:
    - ES256 provider JWT signed with WebCrypto from `APNS_KEY_P8`, `APNS_KEY_ID` and `APNS_TEAM_ID`; cached about 50 minutes.
    - Sandbox or production host chosen by the token's `environment`.
    - Headers: `apns-topic` = bundle id, `apns-push-type: alert`, `apns-collapse-id` = reminder id.
    - Payload: title/body, `thread-id` = context slug, `category` = `REMINDER`, and `reminder_id`.
    - Mark the token disabled on `410` or `BadDeviceToken`.
  - Sweep `dispatch` for `apns`: the local-schedule dedupe, then a push to each uncovered live device, otherwise the email fallback (§3). The quiet-hours deferral path stays unchanged.
  - The enqueue function handles `apns` like any other channel.
  - Add tests for the JWT and payload building (pure functions, run under `node --test`).
- **5B: App** (owns `mobile/lib/features/notifications/`, plus `AppDelegate.swift` and Runner capabilities — **the only agent touching `mobile/ios/` in this phase**):
  - The Pigeon token bridge.
  - Push Notifications capability and Background Modes (remote notifications, background fetch).
  - Permission requested **only from a user gesture**, after onboarding. The app works fully if it's declined.
  - Upsert into `device_tokens`, then the one-time "Send reminders to this iPhone?" prompt (§3).
  - **Local scheduling:**
    - Schedule the soonest 64 open future reminders, shifted by quiet hours to `nextAllowedTime`, with identifier = reminder id.
    - Upsert `local_schedules`.
    - Reschedule on launch, resume, Realtime changes and background refresh; cancel on complete or delete.
  - `REMINDER` category with **Done** and **Snooze 1h** actions that work from the lock screen (background Supabase write using the persisted session).
  - Tapping a notification opens the reminder's sheet.
  - Foreground presentation as a banner.
  - Test payloads with `xcrun simctl push booted <bundle-id> payload.apns`.

**Gate:** server unit tests pass; `flutter test` passes; simulated pushes render, and their actions work.

**STOP: real-device test with Rik** (his `HUMAN_TODO` items: APNs key, secrets, APNs migration 0010 or the next unused number, deploying the sweep). Run these cases:
1. Reminder created on the web, due in 3 minutes, app killed → exactly one push.
2. Reminder created on the phone in airplane mode → exactly one local notification.
3. A reminder due during quiet hours fires when the window ends.
4. Done from the lock screen → the web shows it completed.
5. Rescheduling on the web after the phone scheduled it → it fires once, at the new time.

### Phase 6: Share Extension + widget (1 builder, sequential; owns `mobile/ios/**` additions)

- App Group `group.<bundle-id>`.
- **Share Extension** (via `receive_sharing_intent`): shared URL or text opens the create sheet prefilled. Never auto-save, matching how the web `share_target` behaves.
- **WidgetKit widget** (SwiftUI, via `home_widget`):
  - Small: Today count + next reminder.
  - Medium: next 3 + Ship Queue count.
  - The app writes a JSON snapshot to the App Group on every data change.
  - Widget taps deep-link to `/r/:id` or the Ship Queue.
  - Light and dark.
- A test-runner agent (`ios-test-runner`) builds every target with `xcodebuild` and captures widget previews.

**STOP:** a real-device check by Rik.

### Phase 7: Release readiness (3 read-only reviewers in parallel, then 1 fixer)

- **App Review auditor:**
  - Every item in `MOBILE.md` §7.
  - `PrivacyInfo.xcprivacy` for the app and every plugin.
  - Info.plist usage strings.
  - `ITSAppUsesNonExemptEncryption = false`.
  - The reviewer demo account documented in `mobile/RELEASE.md`.
  - No over-the-air code updates.
- **Security reviewer:**
  - No service-role key or secrets in `mobile/`.
  - RLS on every new table.
  - The RPC context-ownership checks.
  - Deep-link and `/r/:id` input validation.
  - Token handling.
  - The `delete-account` auth check.
- **Final parity reviewer:** the full `PARITY.md` pass.
- **Fixer** addresses the confirmed findings.
- Then write `mobile/RELEASE.md`: the `flutter build ipa` steps, signing notes, App Store Connect fields (privacy labels, screenshots, privacy-policy URL), and the TestFlight steps for Rik.
- Update `MOBILE.md` (status), the `CLAUDE.md` roadmap line and the `LAUNCH.md` status table.

**STOP: final report.**

## 6. Human-only checklist (keep `mobile/HUMAN_TODO.md` current; surface the relevant items at each STOP)

- [ ] Apple Developer Program ($99/yr); Team ID
- [ ] Bundle ID, App Group, and the Push / Associated Domains / Sign in with Apple capabilities (Xcode automatic signing covers most of this)
- [ ] APNs auth key (`.p8`) and Key ID → `supabase secrets set APNS_KEY_P8=… APNS_KEY_ID=… APNS_TEAM_ID=… APNS_BUNDLE_ID=…`
- [ ] Apply pending migrations (0007 foundation is applied; 0008 guards reminder channels; 0009 fixes notification occurrences; 0010 is reserved for APNs); deploy `delete-account` and `notification-sweep`
- [ ] Supabase Auth:
  - add the redirect URL `ezyreminder://login-callback` (and the universal-link URL later);
  - enable the Apple provider with the bundle ID as the client ID;
  - add the iOS Google client ID to the Google provider's authorized client IDs.
- [ ] Google Cloud: create an iOS OAuth client; add its reversed client ID as a URL scheme
- [ ] Production domain serving the AASA file; the Associated Domains entitlement `applinks:<domain>`
- [ ] Reviewer demo account (email + password), with seeded sample data
- [ ] Privacy policy URL (`LAUNCH.md` already lists the privacy and terms pages as needed)
- [ ] App Store Connect app record, privacy nutrition labels, screenshots
- [ ] Real-device tests at the Phase 2, 4, 5 and 6 gates
- [ ] `brew install cocoapods`, only if a required plugin doesn't support Swift Package Manager

## 7. Final report to Rik

- What shipped, by phase.
- Command results.
- Screenshots: every screen, light and dark.
- Remaining `HUMAN_TODO` items.
- Accepted parity deviations.
- Web follow-ups found during parity work.
- Decisions you made that he should confirm.
- Known risks, including the 64-notification limit, background-action reliability, and HTTP/2 from Edge Functions.
