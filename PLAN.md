# ezyReminder — Product & Technical Plan

A reminder app for people juggling a corporate job and side gigs. As simple as Apple Notes, but it *reaches out to you* — via email, Slack, or WhatsApp — and understands that "ship order #42" is different from "prep for Monday's standup."

## 1. Product principles

1. **Capture in under 5 seconds.** One text box, smart parsing ("ship mug order tue 6pm #sidegig"). No required fields beyond the text.
2. **Contexts, not folders.** Every reminder lives in exactly one context: **Work**, **Side Gig**, **Social/Personal**, **Shopping**. Contexts drive default channel (Work → Slack, Side Gig → email/WhatsApp, Social → WhatsApp, Shopping → none/in-app), color, and quiet hours. Shopping is the odd one out — it's a running checklist, not a single due-date item (§3.1).
3. **The app comes to you.** Reminders are useless if you have to open the app. Delivery via email/Slack/WhatsApp is the core feature, not an add-on.
4. **Orders are first-class.** A reminder can be flagged as an **Order** with a tiny bit of structure (recipient, carrier, tracking #, ship-by date) so a "Ship Queue" view and future Shippo integration are trivial.
5. **Agent-ready.** Everything the UI can do, an API can do — so Claude Cowork, OpenClaw-style agents, or a cron job can create/complete reminders.

## 2. Tech stack (decided)

| Layer | Choice | Why |
|---|---|---|
| Frontend | Next.js 15 (App Router), TypeScript, Tailwind, shadcn/ui | Fast to build, PWA-friendly, huge ecosystem |
| Backend | Next.js API routes / server actions | One deployable unit |
| DB + Auth | Supabase (Postgres, Row Level Security, magic-link auth) | Free tier, realtime, built-in auth |
| Scheduling | Supabase `pg_cron` → Edge Function every minute (fallback: Vercel Cron) | Reliable due-reminder sweep |
| Email | Resend | Simple API, generous free tier |
| Slack | Slack app (bot token, `chat.postMessage` DM) | Reliable work-channel delivery |
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
  channels text[],          -- ['email','slack','whatsapp']
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
- Retries: 3 attempts with backoff; failures visible in UI ("⚠ Slack delivery failed").
- Quiet hours per context: work reminders don't ping WhatsApp at 11pm; they defer to next allowed window (user-overridable per reminder).

**Email (Resend)** — v1, week 1. Reply-to-complete stretch goal: replying "done" marks the reminder done (inbound webhook).

**Slack** — v1. Single-workspace Slack app, bot token stored per user, DM via `chat.postMessage` with Block Kit buttons: **Done · Snooze 1h · Snooze 1d**. Interactivity endpoint: `/api/integrations/slack/actions`.

**WhatsApp (Twilio)** — v1.5 (after email+Slack are solid). Requires a pre-approved message template, e.g. `Reminder: {{1}} is due {{2}}. Reply DONE to complete.` Inbound webhook handles DONE/SNOOZE replies. Costs ~ $0.005–0.05/message; show a monthly count in settings.

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
Slack slash command `/remind-me ship order #42 friday` → creates a Side Gig reminder; email-in address (`todo@…`); iOS Share Sheet via PWA share_target.

## 5. UX / design

### 5.1 Design language
- Apple-Notes energy: warm white background, one accent color per context (Work = blue, Side Gig = amber, Social = green), system font stack, generous whitespace, no dashboard clutter.
- Dark mode from day one (system-follow).
- Mobile-first layout; desktop is the same column, wider.

### 5.2 Information architecture
```
┌──────────────────────────────────────┐
│  [All] [Work] [Side Gig] [Social]    │  ← context pills (filter)
│──────────────────────────────────────│
│  + Quick add: "type anything…"       │  ← smart-parse input, always on top
│──────────────────────────────────────│
│  OVERDUE (red)                       │
│  TODAY                               │
│  🚚 SHIP QUEUE (n)   ← only if n>0   │
│  UPCOMING                            │
│  DONE (collapsed)                    │
└──────────────────────────────────────┘
```
- **Quick add parsing:** natural-ish language → `"ship mug order tue 6pm #sidegig @whatsapp"` sets title, due date, context, channel. Parsed chips render below the input before saving so nothing feels magical/wrong. Library: `chrono-node` for dates.
- **Reminder row:** checkbox · title · context dot · due chip ("in 2h", red if overdue) · channel icons · 🚚 if order. Tap → detail sheet (notes, recurrence, channels, order fields).
- **Ship Queue view:** orders sorted by ship-by date; each row has order ref, recipient, ship-by countdown, and a one-tap **Mark shipped** (asks for tracking # inline). This is the "easy way to tag orders" — flag at creation via 🚚 toggle or `#order` in quick add.
- **Swipe/keyboard:** swipe right = done, swipe left = snooze menu (1h / tonight / tomorrow / next week). Desktop: `n` new, `e` done, `s` snooze.
- **Empty/error states:** friendly, single-line. Delivery failures show inline with a retry button.

### 5.3 Screens (complete list — deliberately short)
1. **Home** (list above) 2. **Reminder detail** (bottom sheet) 3. **Ship Queue** 4. **Settings** (channels, quiet hours, contexts, API keys, integrations) 5. **Auth** (magic link).

## 6. Roadmap

| Phase | Scope | Est. |
|---|---|---|
| **0 — Scaffold** | Next.js + Supabase, auth, schema, RLS | ~1 day |
| **1 — Core loop** | CRUD, quick-add parsing, contexts, list views, done/snooze | 2–3 days |
| **2 — Delivery** | Cron sweep, email (Resend), Slack DM + action buttons, notification log | 2–3 days |
| **3 — Orders** | Order flag, Ship Queue, manual tracking | 1–2 days |
| **4 — PWA/iOS** | Manifest, service worker, share_target, install flow (see MOBILE.md) | 1–2 days |
| **5 — WhatsApp** | Twilio templates, inbound DONE/SNOOZE | 2 days |
| **6 — Agents** | REST API keys + MCP server | 2–3 days |
| **7 — Shippo** | Label purchase, tracking webhooks | 2–3 days |

## 7. Risks / notes
- WhatsApp is the highest-friction channel (template approval, cost) — that's why it's phase 5, not phase 2.
- Web push on iOS requires the PWA to be installed to Home Screen (iOS 16.4+); email/Slack/WhatsApp are the reliable channels regardless.
- Keep Supabase Edge Function sweep idempotent (claim rows with `FOR UPDATE SKIP LOCKED`) so double-fires can't double-notify.
