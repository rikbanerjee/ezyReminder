# ezyReminder — Product & Technical Plan

A reminder app for people juggling a corporate job and side gigs. As simple as Apple Notes, but it *reaches out to you* — via iPhone notifications or email — and understands that "ship order #42" is different from "prep for Monday's standup."

## 1. Product principles

1. **Capture in under 5 seconds.** One text box, smart parsing ("ship mug order tue 6pm #sidegig"). No required fields beyond the text.
2. **Contexts, not folders.** Every reminder lives in exactly one context: **Work**, **Side Gig**, **Social/Personal**, **Shopping**. Contexts drive default channel (email for every context until the iOS app adds push; Social → WhatsApp once v1.5 lands; Shopping → none/in-app), color, and quiet hours. Shopping is the odd one out — it's a running checklist, not a single due-date item (§3.1).
3. **The app comes to you.** Reminders are useless if you have to open the app. Delivery via iPhone notifications and email is the core feature, not an add-on.
4. **Orders are first-class.** A reminder can be flagged as an **Order** with a tiny bit of structure (recipient, carrier, tracking #, ship-by date) so a "Ship Queue" view and future Shippo integration are trivial.
5. **Agent-ready.** Everything the UI can do, an API can do — so Claude Cowork, OpenClaw-style agents, or a cron job can create/complete reminders.

## 2. Tech stack (decided)

| Layer | Choice | Why |
|---|---|---|
| Web client | Next.js 15 (App Router), TypeScript, Tailwind, shadcn/ui | Fast to build, PWA-friendly, huge ecosystem |
| iOS client (2026-10) | Flutter (`mobile/`), Android later from the same project | Native feel, pixel-matches the prototype, one codebase for both phones (MOBILE.md) |
| Backend | Next.js API routes / server actions | One deployable unit |
| DB + Auth | Supabase (Postgres, Row Level Security, magic-link auth) | Free tier, realtime, built-in auth |
| Scheduling | Supabase `pg_cron` → Edge Function every minute (fallback: Vercel Cron) | Reliable due-reminder sweep |
| Email | Resend | Simple API, generous free tier |
| iOS notifications | On-device local notifications + APNs from the sweep (hybrid, deduped) | Works offline *and* for web-created reminders (MOBILE.md §3) |
| WhatsApp | Twilio WhatsApp API (v2; template messages) | Least Meta-approval friction |
| Shipping (future) | Shippo API | Labels, rates, tracking webhooks |
| Hosting | Vercel | Zero-config Next.js deploys |

## 3. Data model

```sql
-- contexts: work / sidegig / social (user-editable labels & colors)
contexts (id, user_id, name, slug, color, default_channel, quiet_hours jsonb)

reminders (
  id uuid pk,
  user_id uuid,
  context_id uuid,          -- work | sidegig | social
  title text,
  notes text,
  due_at timestamptz,
  recurrence text,          -- rrule string, null = one-off
  channels text[],          -- ['email','whatsapp'] (+ 'apns' with the iOS app)
  status text,              -- open | done | snoozed | cancelled
  snoozed_until timestamptz,
  tags text[],
  is_order boolean default false,
  created_by text,          -- 'ui' | 'api' | 'agent:<name>'
  created_at, updated_at
)

orders (                    -- 1:1 with a reminder when is_order = true
  reminder_id uuid pk fk,
  order_ref text,           -- e.g. Etsy/Shopify order #
  recipient_name text,
  ship_to jsonb,
  ship_by date,
  carrier text,
  tracking_number text,
  shippo_transaction_id text,   -- null until Shippo integration
  shipped_at timestamptz
)

notifications (             -- delivery log, powers retries + "did it send?"
  id, reminder_id, channel, scheduled_for, sent_at,
  status,                   -- pending | sent | failed | retrying
  provider_message_id, error text
)

api_keys (id, user_id, name, key_hash, scopes text[], last_used_at)
```

RLS on every table by `user_id`. Single-user is v1, but the schema is multi-user-safe from day one.

## 3.1 Context-specific detail panels (2026-07 addition)

Same pattern as Orders (§3): a toggle on the reminder detail sheet reveals a small, optional field set scoped to the reminder's context. None of these are required — quick-add still creates a bare reminder in under 5s; these panels are for the (optional) follow-up step.

```sql
-- Work — "who do I follow up with / what project is this"
work_details (
  reminder_id uuid pk fk -> reminders,
  manager_name text,
  department_resource text,   -- other team/dept contact
  project_name text
)

-- Side Gig — lighter than Work; only for non-order side-gig items
-- (order-flagged reminders use `orders`, not this)
sidegig_details (
  reminder_id uuid pk fk -> reminders,
  initiative_name text,
  client_name text            -- optional buyer/client
)

-- Shopping — the context itself is a checklist, not a due-date item.
-- A Shopping reminder's "title" is the list name (e.g. "Costco run");
-- items are children, added/checked/deleted instantly (no Save step).
shopping_items (
  id uuid pk,
  reminder_id uuid fk -> reminders,
  label text not null,
  checked boolean default false,
  position int not null,
  created_at timestamptz default now()
)
```

RLS on all three, scoped through the parent reminder's `user_id` (same pattern as `orders`). Shopping reminders typically have no `due_at` and are excluded from the Overdue/Today/Upcoming buckets — they live in a dedicated section (or the Someday bucket) showing "N items left" instead of a due chip.

## 4. Service integrations

### 4.0 Auth (decided)
Supabase Auth only — magic-link plus **Google OAuth** as a sign-in option. No Firebase. Reasoning: the data model (§3) is relational with RLS keyed on `auth.uid()`; splitting auth (Firebase) from data (Supabase) would mean reconciling two identity systems for no benefit, and Firestore doesn't fit the joined `reminders`/`orders`/`notifications` schema. Supabase's free tier includes unlimited social-login auth, so this stays free.

Setup: create one OAuth 2.0 **Web application** Client ID in Google Cloud Console → Credentials, with authorized redirect URI `https://<project-ref>.supabase.co/auth/v1/callback`. Paste that Client ID + Secret into Supabase → Authentication → Providers → Google. App calls `supabase.auth.signInWithOAuth({ provider: 'google' })`.


### 4.1 Notification pipeline (v1 core)
- `pg_cron` fires an Edge Function every minute: `SELECT reminders due AND status='open'` → enqueue a `notifications` row per channel → dispatch.
- Each channel is a small adapter behind one interface: `send(reminder, channel) → {ok, providerMessageId | error}`. Adding a channel later = one new adapter file.
- Retries: 3 attempts with backoff; failures visible in UI ("⚠ Email delivery failed").
- Overdue email repeats (2026-10-18): after each successful email, automatically snooze the reminder for **6 hours** while retaining its original due date. Repeat until completion/cancellation or an explicit reschedule. Failed provider attempts keep their bounded retry policy; quiet hours still delay actual delivery.
- Quiet hours per context: work reminders don't ping WhatsApp at 11pm; they defer to next allowed window (user-overridable per reminder).

**Email (Resend)** — v1, week 1. Reply-to-complete stretch goal: replying "done" marks the reminder done (inbound webhook).

**iOS notifications** — v1 with the Flutter app. A hybrid of on-device local notifications (scheduled by the app, works offline) and APNs push from the sweep (covers reminders created or edited on the web), deduplicated so each reminder fires once. Actionable: **Done · Snooze 1h**. Full design in MOBILE.md §3.

**Slack** — removed 2026-10 (adapter, OAuth routes and `slack_integrations` table deleted in `0006_remove_slack.sql`) to keep delivery simple.

**WhatsApp (Twilio)** — v1.5 (after email + iOS notifications are solid). Requires a pre-approved message template, e.g. `Reminder: {{1}} is due {{2}}. Reply DONE to complete.` Inbound webhook handles DONE/SNOOZE replies. Costs ~ $0.005–0.05/message; show a monthly count in settings.

### 4.2 Shipping — Shippo (future, designed-for now)
- v1 ships the **Order** flag + Ship Queue view with manual carrier/tracking entry. No API dependency.
- Integration seam: `lib/shipping/provider.ts` interface (`createLabel`, `getRates`, `trackShipment`) with a `ManualProvider` now and `ShippoProvider` later — also keeps the door open for EasyPost/Veeqo.
- When Shippo lands: "Buy label" button on an order → store `shippo_transaction_id` → Shippo tracking webhook auto-completes the reminder when delivered and can auto-create a "follow up with buyer" reminder.

### 4.3 Agent access (Claude Cowork / OpenClaw / any MCP client)
Two layers, same underlying service functions:

1. **REST API** (`/api/v1/*`, bearer API keys, per-key scopes):
   - `GET/POST /reminders`, `PATCH /reminders/:id` (complete/snooze/edit)
   - `GET /reminders?due_before=&context=&is_order=true`
   - `POST /orders/:id/shipped`
2. **MCP server** (`@ezyreminder/mcp`, thin wrapper over the REST API) exposing tools: `create_reminder`, `list_due_reminders`, `complete_reminder`, `snooze_reminder`, `list_ship_queue`, `mark_order_shipped`. This is what makes "hey Claude, remind me to ship the Portland order Friday" work from Cowork.
- All agent writes carry `created_by: 'agent:<name>'` for auditability; a settings toggle can require confirmation for agent-initiated deletes.

### 4.4 Capture integrations (later, in priority order)
Email-in address (`todo@…`); iOS Share Sheet via the Flutter app's Share Extension (web: PWA share_target).

## 5. UX / design

### 5.1 Design language
- Apple-Notes energy: warm white background, one accent color per context (Work = blue, Side Gig = amber, Social = green), system font stack, generous whitespace, no dashboard clutter.
- Dark mode from day one (system-follow).
- Mobile-first layout; desktop is the same column, wider.

### 5.2 Information architecture — revised 2026-10-19
**Today · Side Gig · Home · All.** Today is a single reminder list across the four contexts: Overdue, Today, Upcoming, Someday and collapsed Done today. No context filters or duplicate Ship soon block. Today retains the full Focus card: choose/start a reminder, planned work, and running-session recovery. All provides search, context filters and completed records. Side Gig owns independent work, Ship Queue, follow-ups and payments.

- **Add from Today:** tap the docked bar → "What would you like to add?" (Work · Side Gig · Home · Social · Shopping) → the destination's existing chooser and form, saved through its own atomic RPC, then a toast with View. Home stays a destination over the four contexts (bills/study/care are Social, groceries are Shopping). See DESIGN.md §5.1.
- **Quick capture (All):** tap the docked bar → title, blank context select, optional compact date/time, Save. Choosing Side Gig does not change the form. Notes, delivery controls and domain fields wait for editing.
- **Details:** tapping a saved Side Gig task/order from Today or All opens the canonical Side Gig editor on the same reminder ID. Other contexts retain their respective detail/checklist editors. Shopping opens its checklist after capture.
- **Side Gig creation:** scoped Add offers Task / Order / Follow-up / Expected payment with full forms. Task/Order details share their implementation with editing from Today; atomic writes remain `sidegig_mutate`.
- **Reminder row:** completion ring, title, context/due metadata, channel/order icons. Shipping and payment actions remain explicit in their domain views.
- **Swipe/keyboard:** existing completion and snooze behavior. Empty/error states are short and inline.

### 5.3 Screens (complete list — deliberately short)
1. **Home** (list above) 2. **Reminder detail** (bottom sheet) 3. **Ship Queue** 4. **Settings** (channels, quiet hours, contexts, API keys, integrations) 5. **Auth** (magic link).

## 6. Roadmap

| Phase | Scope | Est. |
|---|---|---|
| **0 — Scaffold** | Next.js + Supabase, auth, schema, RLS | ~1 day |
| **1 — Core loop** | CRUD, quick-add parsing, contexts, list views, done/snooze | 2–3 days |
| **2 — Delivery** | Cron sweep, email (Resend), notification log (Slack DM shipped, then removed 2026-10) | 2–3 days |
| **3 — Orders** | Order flag, Ship Queue, manual tracking | 1–2 days |
| **4 — PWA/iOS** | Manifest, service worker, share_target, install flow (see MOBILE.md) | 1–2 days |
| **5 — WhatsApp** | Twilio templates, inbound DONE/SNOOZE | 2 days |
| **6 — Agents** | REST API keys + MCP server | 2–3 days |
| **7 — Shippo** | Label purchase, tracking webhooks | 2–3 days |
| **8 — iOS app (Flutter)** | RPCs + Realtime, Flutter screens, hybrid notifications, Share Extension, TestFlight (MOBILE.md §6) | 3–5 weeks |

## 7. Risks / notes
- WhatsApp is the highest-friction channel (template approval, cost) — that's why it's phase 5, not phase 2.
- iOS notifications come from the native Flutter app, not Web Push; email is the reliable fallback for web-only users.
- Keep Supabase Edge Function sweep idempotent (claim rows with `FOR UPDATE SKIP LOCKED`) so double-fires can't double-notify.


## 8. Focus — approved first slice (2026-10)

The Focus MVP adds one daily highlight from an existing open Work or Side Gig reminder, a start-now timer (1–180 minutes) with pause/resume, and an explicit session outcome with an optional next step. Sessions persist in Supabase so refreshes and the second client can recover the same timer; reaching zero waits for the user to finish the session. Focus does not change reminder deadlines, completion, shipment state, or notification delivery.

See [FOCUS_PLAN.md](FOCUS_PLAN.md) for the scope, interaction rules, database contract, and follow-on work. This slice implements the shared backend, web client, and Flutter client. Future scheduling and focus notifications are deferred.

The next proposed iteration is documented in [FOCUS_IMPLEMENTATION_PLAN.md](FOCUS_IMPLEMENTATION_PLAN.md): reusable weekly Focus times (for example Thursday evening or Saturday at 9 AM), explicit task assignment independent of deadlines, simpler starts/returns, and phased notification support. This is planned work; scheduled Focus delivery is not yet shipped.

## 9. Home — contextual household tasks (2026-10)

Home has four independent sections: **Home care**, **Groceries**, **Bill pay**, and **Study & kids**. Section pills keep optional needs out of each other's way; choosing a section does not require setup in the others. Home is a view, so every reminder still belongs to one of the four contexts. Grocery lists use Shopping; all other Home tasks use Social/Personal and its quiet hours.

Home care includes Car service & maintenance, HVAC & air filters, Dryer maintenance, Smart-home batteries, and Other home care. HVAC includes air-filter tasks; legacy Filter changes reminders/history remain intact and appear under HVAC. Smart-home batteries replaces the separate Filter card.

Every template controls task, item/person, due date, repeat, instructions, completion, and history labels. Cars have Car name plus separate make/model fields. HVAC has System or room and optional Air-filter size. Dryer uses Dryer location. Battery tasks use Device & location plus Battery or charger type. Bills use Bill name, Biller or provider, optional Amount due/Currency, Payment due, Billing schedule, and payment records. Study uses Study task or follow-up, Student or family member, Subject or course, Teacher or school contact, and progress/next-step records. Optional fields never block a simple reminder.

Repeat presets suit the task: care is generally monthly; batteries and study also offer weekly intervals, and study supports daily. Care repeats from actual completion. Bill and study repeats advance from the planned due date, so early payments or late sessions do not move the schedule. One-time completion closes the reminder. History snapshots the template details and survives deletion of the reminder.

`design/home-templates.json` is the shared copy/field source for web, generated Flutter templates, and the prototype (`node scripts/gen-home-templates.mjs`). Additive migration `0014_contextual_home_tasks.sql` extends 0011 with category-specific details and day intervals. New clients use atomic `save_home_task`; the old save RPC remains compatible. `record_home_service` retains its signature and now snapshots contextual fields and follows the correct repeat anchor. RLS, completion-version checks, existing delivery channels, and quiet hours continue to apply.


## 10. Side Gig destination (approved 2026-10-19)

Side Gig replaces the Ship-only tab with Overview, Tasks, Ship Queue, Follow-ups and Payments. The complete product contract is `SIDEGIG_EXPERIENCE.md`; visual rules are DESIGN.md §10 and `design/sidegig-prototype.html`. Shared backend changes are additive migration 0018, with owner-only state/history, retry-safe atomic RPCs, ordinary reminder delivery and independent fulfillment/collection semantics. No new context, calendar integration, payment processing or CRM entity is introduced. Both clients share these contracts. Shipping-only legacy links remain valid. Local implementation and hosted release status are recorded separately in LAUNCH.md and supabase/MIGRATION_STATUS.md.
