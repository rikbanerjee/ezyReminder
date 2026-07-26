-- ezyReminder — initial schema (PLAN.md §3)
-- Single-user today, multi-user-safe always: every table carries user_id
-- and is locked down with Row Level Security.

create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────────────────────────────────
-- contexts: Work / Side Gig / Social — user-editable labels & colors
-- ─────────────────────────────────────────────────────────────────────────
create table contexts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  slug text not null,
  color text not null,
  default_channel text not null check (default_channel in ('email', 'slack', 'whatsapp')),
  quiet_hours jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, slug)
);

comment on table contexts is 'Work / Side Gig / Social contexts (PLAN.md §3). Seeded per-user on signup.';

-- ─────────────────────────────────────────────────────────────────────────
-- reminders
-- ─────────────────────────────────────────────────────────────────────────
create table reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  context_id uuid not null references contexts (id) on delete restrict,
  title text not null,
  notes text,
  due_at timestamptz,
  recurrence text, -- rrule string; null = one-off
  channels text[] not null default '{}'::text[],
  status text not null default 'open' check (status in ('open', 'done', 'snoozed', 'cancelled')),
  snoozed_until timestamptz,
  tags text[] not null default '{}'::text[],
  is_order boolean not null default false,
  created_by text not null default 'ui', -- 'ui' | 'api' | 'agent:<name>'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index reminders_user_due_idx on reminders (user_id, due_at) where status = 'open';
create index reminders_user_status_idx on reminders (user_id, status);
create index reminders_context_idx on reminders (context_id);
create index reminders_is_order_idx on reminders (user_id, is_order) where is_order = true;

comment on table reminders is 'Core reminder rows (PLAN.md §3). channels holds a subset of email/slack/whatsapp overriding the context default.';

-- ─────────────────────────────────────────────────────────────────────────
-- orders — 1:1 with a reminder when is_order = true
-- ─────────────────────────────────────────────────────────────────────────
create table orders (
  reminder_id uuid primary key references reminders (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  order_ref text,
  recipient_name text,
  ship_to jsonb,
  ship_by date,
  carrier text,
  tracking_number text,
  shippo_transaction_id text, -- null until Shippo integration (PLAN.md §4.2)
  shipped_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index orders_user_ship_by_idx on orders (user_id, ship_by) where shipped_at is null;

comment on table orders is 'Order detail attached to a reminder flagged is_order (PLAN.md §3). Powers the Ship Queue view.';

-- ─────────────────────────────────────────────────────────────────────────
-- notifications — delivery log, powers retries + "did it send?"
-- ─────────────────────────────────────────────────────────────────────────
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  reminder_id uuid not null references reminders (id) on delete cascade,
  channel text not null check (channel in ('email', 'slack', 'whatsapp')),
  scheduled_for timestamptz not null,
  sent_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'retrying')),
  attempt_count integer not null default 0,
  provider_message_id text,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Powers the pg_cron minute-sweep claim query (PLAN.md §4.1, §7):
-- `... WHERE status = 'pending' AND scheduled_for <= now() FOR UPDATE SKIP LOCKED`
create index notifications_sweep_idx on notifications (scheduled_for) where status in ('pending', 'retrying');
create index notifications_reminder_idx on notifications (reminder_id);

comment on table notifications is 'One row per (reminder, channel) delivery attempt. Sweep claims rows with FOR UPDATE SKIP LOCKED to stay idempotent.';

-- ─────────────────────────────────────────────────────────────────────────
-- api_keys — scoped keys for the agent-facing REST API (PLAN.md §4.3)
-- ─────────────────────────────────────────────────────────────────────────
create table api_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  key_hash text not null unique,
  scopes text[] not null default '{}'::text[],
  require_delete_confirmation boolean not null default true,
  last_used_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table api_keys is 'Bearer keys for /api/v1/* and the MCP server. Only key_hash is stored; the raw key is shown once at creation.';

-- ─────────────────────────────────────────────────────────────────────────
-- updated_at maintenance
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger contexts_set_updated_at before update on contexts
  for each row execute function set_updated_at();
create trigger reminders_set_updated_at before update on reminders
  for each row execute function set_updated_at();
create trigger orders_set_updated_at before update on orders
  for each row execute function set_updated_at();
create trigger notifications_set_updated_at before update on notifications
  for each row execute function set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- Row Level Security — every table, scoped by user_id (CLAUDE.md conventions)
-- ─────────────────────────────────────────────────────────────────────────
alter table contexts enable row level security;
alter table reminders enable row level security;
alter table orders enable row level security;
alter table notifications enable row level security;
alter table api_keys enable row level security;

create policy "contexts_select_own" on contexts for select using (auth.uid() = user_id);
create policy "contexts_insert_own" on contexts for insert with check (auth.uid() = user_id);
create policy "contexts_update_own" on contexts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "contexts_delete_own" on contexts for delete using (auth.uid() = user_id);

create policy "reminders_select_own" on reminders for select using (auth.uid() = user_id);
create policy "reminders_insert_own" on reminders for insert with check (auth.uid() = user_id);
create policy "reminders_update_own" on reminders for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "reminders_delete_own" on reminders for delete using (auth.uid() = user_id);

create policy "orders_select_own" on orders for select using (auth.uid() = user_id);
create policy "orders_insert_own" on orders for insert with check (auth.uid() = user_id);
create policy "orders_update_own" on orders for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "orders_delete_own" on orders for delete using (auth.uid() = user_id);

create policy "notifications_select_own" on notifications for select using (auth.uid() = user_id);
create policy "notifications_insert_own" on notifications for insert with check (auth.uid() = user_id);
create policy "notifications_update_own" on notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "notifications_delete_own" on notifications for delete using (auth.uid() = user_id);

-- api_keys: readable by owner, but only the server (service role, which
-- bypasses RLS) ever writes key_hash — clients only ever see it once at
-- creation time via a server action, never re-read the hash afterwards.
create policy "api_keys_select_own" on api_keys for select using (auth.uid() = user_id);
create policy "api_keys_delete_own" on api_keys for delete using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- Seed default contexts for a new user (CLAUDE.md: Work/Side Gig/Social,
-- default channels per PLAN.md §5.2 — Work→Slack, Side Gig→email, Social→WhatsApp)
-- ─────────────────────────────────────────────────────────────────────────
create or replace function handle_new_user_contexts()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.contexts (user_id, name, slug, color, default_channel, quiet_hours)
  values
    (new.id, 'Work', 'work', '#3478F6', 'slack', '{"start": "18:00", "end": "08:00"}'::jsonb),
    (new.id, 'Side Gig', 'sidegig', '#F5A623', 'email', '{"start": "21:00", "end": "08:00"}'::jsonb),
    (new.id, 'Social', 'social', '#34C759', 'whatsapp', '{"start": "22:00", "end": "09:00"}'::jsonb);
  return new;
end;
$$;

create trigger on_auth_user_created_seed_contexts
  after insert on auth.users
  for each row execute function handle_new_user_contexts();
