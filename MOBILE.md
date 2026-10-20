# ezyReminder — iOS/Android Strategy

**Decided 2026-10:** native iOS app in **Flutter**, alongside the existing Next.js web app. Android comes later from the same Flutter project. This replaces the earlier "PWA → Capacitor wrapper" plan.

## 1. Why Flutter (and not Capacitor or SwiftUI)

- **Capacitor** wraps the web UI. It's cheap, but it doesn't give native-feeling rendering, and an App Store app that's mostly a website risks rejection under guideline 4.2.
- **SwiftUI** gives the best iOS fidelity (Liquid Glass, system sheets, Foundation Models without a bridge). But Android would then be a third UI in Kotlin, alongside web and iOS.
- **Flutter** draws every pixel itself, so it can match `design/prototype.html` exactly (custom tokens, shadows, Apple's sheet curve). It ships iOS now and Android later from one codebase. The only Swift needed is a few thin native targets (§5).

Apple doesn't reject apps for using Flutter. The real App Review risks are listed in §7.

## 2. Two clients, one backend

```
             Supabase (Postgres + RLS + RPCs + Realtime + sweep)
              ▲                                       ▲
   Flutter iOS app (mobile/)                 Next.js web app (any browser,
   (Android later)                           incl. iPhone Safari)
              └────────── same DESIGN.md tokens ──────┘
```

- **Same data:** both clients use Supabase directly under RLS (`supabase_flutter` / `@supabase/ssr`), with one login and one set of reminders. A reminder created on the iPhone app shows up in the browser, and the other way round.
- **Same behaviour:** multi-step writes move out of Next.js server actions (`app/actions.ts`) into **Postgres RPC functions** that both clients call: `create_reminder` (reminder + order rows), `mark_shipped`, `create_follow_up`, `add_shopping_item` (position counter). Simple single-row CRUD stays a direct table call. Anything needing secrets (e.g. `retryNotification`) becomes an edge function. The REST API and MCP server (PLAN.md §4.3) reuse the same RPCs.
- **Live sync:** both clients subscribe to Supabase Realtime on `reminders`, `orders` and `shopping_items`, and refetch on focus. An edit made on one device appears on the other without a reload.
- **Conflicts: last edit wins** (decided 2026-10). An `updated_at` precondition can be added later if this ever bites.
- **Same look:** a single `design/tokens.json` (colors, shadows, radii, type scale, motion) generates both `app/globals.css` variables and the Flutter `ThemeExtension`. Change a token once and both clients follow.
- **Same dates:** due times are stored in UTC and rendered in `user_settings.timezone`. The Dart port of `lib/dates.ts` must pass the same shared test fixtures, so "in 2h" and "Tue 6pm" read identically on both clients.
- **Account time zone follows the iPhone (2026-10-19):** Settings → **Use iPhone time zone** (on by default) copies the phone's IANA zone (`TimeZone.current.identifier` over the `ezyreminder/device` channel) into `user_settings.timezone` on launch, on resume and when Settings opens. Saving a zone by hand turns it off; the choice is stored on the device. The Dart tz database is the full one (`latest_all`) so legacy names such as `EST` resolve as they do in Postgres instead of falling back to UTC.
- **One link, both places:** `/r/<id>` opens a single reminder. With universal links (`/.well-known/apple-app-site-association`) it opens the iOS app when installed, otherwise the web page. Email notifications link there too.

## 3. Notifications: hybrid local + APNs, email fallback

Slack was removed 2026-10. Channels are now **iOS notifications** plus **email** (Resend) as the fallback. WhatsApp remains a v1.5 stub.

| Path | Covers | How |
|---|---|---|
| **Local** (on-device) | Reminders the phone knows about, including while offline | `flutter_local_notifications`. The app reschedules on launch, on Realtime changes and on background refresh. iOS allows at most 64 pending, so schedule the soonest 64. |
| **APNs** (server push) | Reminders created or edited on the web, or anything the phone hasn't synced yet | A new `apns` channel adapter in `lib/integrations/apns/`, called by the existing minute sweep. ES256 JWT signed with WebCrypto (stays Node-free like the other adapters). A `device_tokens` table, with RLS, stores tokens. |
| **Email** | Web-only users; fallback when push fails or there's no device | Existing Resend adapter. |

**Deduplication (a reminder notifies once):**
- When the app schedules a local notification, it records an ack (`reminder_id`, `due_at` version, device) in a `local_schedules` table.
- The sweep skips the APNs send for a reminder whose current `due_at` has a live local ack from that device.
- Any edit changes `due_at`/`updated_at`, which invalidates the ack. The phone reschedules on its next sync; if it hasn't synced by due time, APNs covers it.
- The notification identifier is the reminder id, so if both paths ever fire, iOS replaces one with the other rather than showing two.

**Other rules:**
- Quiet hours are enforced by the server sweep for APNs and email, and by the app when scheduling local notifications (same `lib/quiet-hours.ts` logic, ported to Dart with shared fixtures).
- Actionable notifications offer **Done** and **Snooze 1h**, using `UNNotificationCategory` via the plugin.
- Asking for push permission must come from a user gesture, and the app must work fine if it's declined (email still fires).

## 4. On-device AI: Apple Foundation Models (planned)

- **Uses:** prefilling the create sheet from free text ("ship Sarah's Etsy order by Fri" → context, due, `is_order`, recipient, ship-by); extracting order fields in the Share Extension; suggesting a context or channel; a short daily summary.
- **Constraints:** Swift-only API, iOS 26+, Apple Intelligence devices only (iPhone 15 Pro and later), a ~4K-token context window. Good at extraction and classification, not world knowledge.
- **Shape:**
  - A Pigeon bridge with one entry point. Dart sends the text and the user's contexts; Swift runs a `LanguageModelSession` with a `@Generable ReminderDraft` and returns JSON.
  - In Dart, a `ReminderDraftParser` interface with three implementations: `AppleFoundationModelsParser`, `GeminiNanoParser` (Android, later) and `RuleBasedParser` (a port of `lib/parse/quick-add.ts`, used as the fallback everywhere).
  - Pick the implementation at runtime based on model availability.
  - The Foundation Models code lives in a shared Swift package linked by the Runner, Share Extension and widget targets.
- **AI never saves on its own.** It fills the sheet; the user taps save (`created_by: 'ui'`). On-device processing also avoids App Review's third-party-AI data-sharing consent requirement.

## 5. Swift targets (thin, data bridged via an App Group)

- **Share Extension:** replaces the PWA `share_target`. A shared URL or text prefills a new reminder (`receive_sharing_intent`).
- **WidgetKit widget:** Today and Ship Queue (`home_widget`).
- **Later:** App Intents for Siri, and Live Activities for ship-by countdowns.

## 6. Build order

1. **Backend groundwork** (helps the web app too): server actions → Postgres RPCs; Realtime on the web; `design/tokens.json` with CSS generation; `/r/<id>` route.
2. **Flutter spike (1–2 days):** Today screen and reminder sheet against real Supabase data, run on device next to the PWA. Go/no-go on feel before committing further.
3. **Scaffold properly:** `mobile/` project, theme from tokens, auth (magic link via universal link, Google via `signInWithIdToken`, **Sign in with Apple**), demo reviewer account.
4. **Port the screens:** Today, reminder sheet (Order/Work/Side Gig panels), DateTimePicker, Shopping checklist, Ship Queue, All, Settings (including **Delete account**), Onboarding.
5. **Notifications:** local scheduling, then `device_tokens` + `local_schedules` + the APNs adapter, then actionable categories.
6. **Share Extension and widget.**
7. **TestFlight**, then App Store submission (§7 checklist).
8. **Later:** Foundation Models bridge (§4); then Android (FCM adapter, Play Store, Gemini Nano parser).

## 7. App Review checklist (bake in from day one)

- [ ] Sign in with Apple, since Google login is offered (4.8)
- [ ] Demo account with a password for reviewers, because magic links can't reach them (2.1)
- [ ] In-app account deletion, backed by an edge function (5.1.1(v))
- [ ] `PrivacyInfo.xcprivacy` present for the app and all plugins; privacy nutrition labels accurate
- [ ] App works fully with push declined; no marketing pushes (4.5.4)
- [ ] No over-the-air code updates (2.5.2)
- [ ] Built with a current Xcode and iOS SDK
- [ ] If paid features ever ship in-app, they use Apple's in-app purchase (3.1)

## 8. Web app (stays)

The Next.js PWA remains the browser client: manifest, serwist, share_target and the install nudge all stay. Web Push (`WEB_PUSH_PROMPT.md`) is **on hold**: its Slack-related instructions are obsolete, so revisit it only if browser-only users need push. For now, browser users get email and iPhone users get the native app.

## 9. Home tab (2026-10)

Home provides optional Home care, Groceries, Bill pay, and Study & kids section pills. Car, HVAC & air filters, Dryer, Smart-home batteries and Other home care are the maintenance cards. Forms, placeholders, repeat options and completion labels come from `design/home-templates.json`, generated into `features/home/home_templates.g.dart`. Car make/model and other category fields persist and appear in history snapshots. The legacy Filter category renders under HVAC.

`features/home/` uses the shared atomic RPCs: new task saves call `save_home_task` (migration 0014); completion retains `record_home_service`. Care repeats from actual completion, while bills and study advance their planned date. Day intervals support daily/weekly study and weekly battery care. Existing RLS, Realtime, foreground refresh, quiet hours and delivery apply. Today/All task rows open the right Home section. Hosted schema and client release status are tracked separately in `supabase/MIGRATION_STATUS.md` and `mobile/HUMAN_TODO.md`.


## 10. Side Gig destination (2026-10-19)

`features/sidegig/` implements the approved five-section Side Gig experience and uses the same migration 0018 RPCs as the web client. The second tab is Side Gig; Today shipping links open its Ship Queue section. Typed follow-up/payment reminders open their Side Gig completion flow from Today/All. The page survives tab changes, refreshes from Realtime and foreground resume, and shares the existing FocusController. Money is parsed/summed with BigInt minor units. Shipping, waiting and collection transitions are atomic on the backend. This is client code, not evidence of a signed release or hosted migration.


## 11. Today Add flow (2026-10-19)

`features/add/today_add_flow.dart` hosts the "What would you like to add?" sheet opened from Today and All (DESIGN.md §5.1). It reuses `GigFormSheet`, `MaintenanceEditor` and the reminder sheet through a small `AddFlowNav` (Back/Close with the form's unsaved state) and an `onSaved` callback; visited forms stay mounted offstage so Back keeps drafts. Saves use the same repositories and RPCs as Side Gig and Home (`HouseholdRepository.save` now returns the reminder ID). The All tab opens the same flow (the minimal capture sheet was retired 2026-10-19). Regression coverage: `test/today_add_flow_test.dart`.
