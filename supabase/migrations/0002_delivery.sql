-- ezyReminder — delivery pipeline (PLAN.md §4.1, Phase 2)
-- Adds: per-user Slack OAuth installs, per-user timezone (needed to resolve
-- quiet_hours, which are wall-clock local), a 'sending' claim state, and a
-- SECURITY DEFINER RPC the minute-sweep uses to atomically claim due
-- notifications (FOR UPDATE SKIP LOCKED isn't reachable through PostgREST).

-- ─────────────────────────────────────────────────────────────────────────
-- user_settings — one row per user; timezone drives quiet-hours resolution
-- ─────────────────────────────────────────────────────────────────────────
create table user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  timezone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table user_settings is 'Per-user delivery settings. timezone resolves contexts.quiet_hours (wall-clock local) — see lib/quiet-hours.ts.';

create trigger user_settings_set_updated_at before update on user_settings
  for each row execute function set_updated_at();

alter table user_settings enable row level security;

create policy "user_settings_select_own" on user_settings for select using (auth.uid() = user_id);
create policy "user_settings_insert_own" on user_settings for insert with check (auth.uid() = user_id);
create policy "user_settings_update_own" on user_settings for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function handle_new_user_settings()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.user_settings (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created_seed_settings
  after insert on auth.users
  for each row execute function handle_new_user_settings();

-- ─────────────────────────────────────────────────────────────────────────
-- slack_integrations — one Slack workspace install per user (bot token DMs
-- the installing user; PLAN.md §4.1 "bot token stored per user")
-- ─────────────────────────────────────────────────────────────────────────
create table slack_integrations (
  user_id uuid primary key references auth.users (id) on delete cascade,
  team_id text not null,
  team_name text,
  bot_token text not null,
  slack_user_id text not null, -- DM target (chat.postMessage channel = user id)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table slack_integrations is 'Slack OAuth install per user. bot_token DMs slack_user_id via chat.postMessage.';

create trigger slack_integrations_set_updated_at before update on slack_integrations
  for each row execute function set_updated_at();

alter table slack_integrations enable row level security;

create policy "slack_integrations_select_own" on slack_integrations for select using (auth.uid() = user_id);
create policy "slack_integrations_insert_own" on slack_integrations for insert with check (auth.uid() = user_id);
create policy "slack_integrations_update_own" on slack_integrations for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "slack_integrations_delete_own" on slack_integrations for delete using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- notifications — add 'sending' as a transient claimed state
-- ─────────────────────────────────────────────────────────────────────────
alter table notifications drop constraint notifications_status_check;
alter table notifications add constraint notifications_status_check
  check (status in ('pending', 'sending', 'sent', 'failed', 'retrying'));

-- ─────────────────────────────────────────────────────────────────────────
-- claim_due_notifications — atomic FOR UPDATE SKIP LOCKED claim for the
-- minute-sweep (CLAUDE.md: "Notification sweep must be idempotent"). Runs
-- as SECURITY DEFINER since it must cross user_id boundaries; execution is
-- restricted to service_role only (the edge function's credential).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function claim_due_notifications(p_limit int default 25)
returns setof notifications
language plpgsql
security definer set search_path = public
as $$
declare
  ids uuid[];
begin
  select array_agg(id) into ids from (
    select id from notifications
    where status in ('pending', 'retrying') and scheduled_for <= now()
    order by scheduled_for
    for update skip locked
    limit p_limit
  ) t;

  if ids is null then
    return;
  end if;

  return query
    update notifications
    set status = 'sending', updated_at = now()
    where id = any(ids)
    returning *;
end;
$$;

revoke all on function claim_due_notifications(int) from public, anon, authenticated;
grant execute on function claim_due_notifications(int) to service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- enqueue_due_notifications — creates one notifications row per (reminder,
-- channel) once a reminder becomes due. Dedupes on
-- (reminder_id, channel, scheduled_for) so re-running every minute is a
-- no-op until the reminder's effective due time actually changes (e.g. a
-- fresh snooze), which keeps the sweep idempotent without extra state.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function enqueue_due_notifications()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  insert into notifications (user_id, reminder_id, channel, scheduled_for)
  select
    r.user_id,
    r.id,
    chan,
    coalesce(r.snoozed_until, r.due_at)
  from reminders r
  cross join lateral unnest(
    case when array_length(r.channels, 1) > 0
      then r.channels
      else array[(select c.default_channel from contexts c where c.id = r.context_id)]
    end
  ) as chan
  where r.status in ('open', 'snoozed')
    and coalesce(r.snoozed_until, r.due_at) is not null
    and coalesce(r.snoozed_until, r.due_at) <= now()
    and not exists (
      select 1 from notifications n
      where n.reminder_id = r.id
        and n.channel = chan
        and n.scheduled_for = coalesce(r.snoozed_until, r.due_at)
    );
end;
$$;

revoke all on function enqueue_due_notifications() from public, anon, authenticated;
grant execute on function enqueue_due_notifications() to service_role;
