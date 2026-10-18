-- Start-now focus sessions are independent of reminder delivery and completion.
-- Only RPCs write these tables, keeping both clients on the same state machine.
create table public.focus_highlights (
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  reminder_id uuid references public.reminders(id) on delete set null,
  reminder_title text not null,
  context_slug text not null check (context_slug in ('work', 'sidegig')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, local_date)
);

create table public.focus_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  reminder_id uuid references public.reminders(id) on delete set null,
  reminder_title text not null,
  context_slug text not null check (context_slug in ('work', 'sidegig')),
  duration_minutes integer not null check (duration_minutes between 1 and 180),
  intended_outcome text check (char_length(intended_outcome) <= 500),
  started_at timestamptz not null,
  last_resumed_at timestamptz,
  paused_at timestamptz,
  elapsed_seconds double precision not null default 0,
  finished_at timestamptz,
  outcome text check (outcome in ('finished', 'progress', 'interrupted')),
  next_step text check (char_length(next_step) <= 1000),
  updated_at timestamptz not null,
  check (elapsed_seconds >= 0 and elapsed_seconds <= duration_minutes * 60),
  check (finished_at is null or finished_at >= started_at),
  check (last_resumed_at is null or last_resumed_at >= started_at),
  check (paused_at is null or paused_at >= started_at),
  check (
    (finished_at is not null and outcome is not null and last_resumed_at is null and paused_at is null)
    or (finished_at is null and outcome is null and next_step is null and
      ((last_resumed_at is not null and paused_at is null)
        or (last_resumed_at is null and paused_at is not null)))
  )
);
create unique index focus_sessions_one_unfinished on public.focus_sessions(user_id) where finished_at is null;
create index focus_sessions_reminder_history on public.focus_sessions(user_id, reminder_id, finished_at desc);
alter table public.focus_highlights enable row level security;
alter table public.focus_sessions enable row level security;
create policy focus_highlights_read on public.focus_highlights for select to authenticated using (user_id = auth.uid());
create policy focus_sessions_read on public.focus_sessions for select to authenticated using (user_id = auth.uid());
revoke all on public.focus_highlights, public.focus_sessions from public, anon, authenticated;
grant select on public.focus_highlights, public.focus_sessions to authenticated;

create function public.get_focus_state() returns jsonb
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz := clock_timestamp();
  v_zone text; v_date date; v_highlight jsonb; v_session jsonb;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select timezone into v_zone from public.user_settings where user_id = v_user;
  v_zone := coalesce(v_zone, 'UTC');
  v_date := (v_now at time zone v_zone)::date;
  select to_jsonb(h) into v_highlight from public.focus_highlights h where h.user_id = v_user and h.local_date = v_date;
  select to_jsonb(s) into v_session from public.focus_sessions s where s.user_id = v_user and s.finished_at is null;
  return jsonb_build_object('server_now', v_now, 'timezone', v_zone, 'local_date', v_date,
    'highlight', v_highlight, 'active_session', v_session);
end $$;

create function public.set_focus_highlight(p_reminder_id uuid) returns date
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz; v_zone text; v_date date; v_title text; v_slug text;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 12012));
  v_now := clock_timestamp();
  select timezone into v_zone from public.user_settings where user_id = v_user;
  v_date := (v_now at time zone coalesce(v_zone, 'UTC'))::date;
  if p_reminder_id is null then
    delete from public.focus_highlights where user_id = v_user and local_date = v_date;
    return v_date;
  end if;
  select r.title, c.slug into v_title, v_slug
    from public.reminders r join public.contexts c on c.id = r.context_id
    where r.id = p_reminder_id and r.user_id = v_user and c.user_id = v_user
      and r.status in ('open', 'snoozed') and c.slug in ('work', 'sidegig') for key share of r, c;
  if not found then raise exception 'Choose an open Work or Side Gig reminder' using errcode = '22023'; end if;
  insert into public.focus_highlights(user_id, local_date, reminder_id, reminder_title, context_slug, created_at, updated_at)
    values(v_user, v_date, p_reminder_id, v_title, v_slug, v_now, v_now)
    on conflict(user_id, local_date) do update set reminder_id = excluded.reminder_id,
      reminder_title = excluded.reminder_title, context_slug = excluded.context_slug, updated_at = excluded.updated_at
    where focus_highlights.reminder_id is distinct from excluded.reminder_id;
  return v_date;
end $$;

create function public.start_focus_session(
  p_id uuid, p_reminder_id uuid, p_duration_minutes integer, p_intended_outcome text default null
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz; v_title text; v_slug text;
  v_existing public.focus_sessions%rowtype; v_intent text := nullif(btrim(p_intended_outcome), '');
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_id is null or p_duration_minutes is null or p_duration_minutes not between 1 and 180
    or char_length(v_intent) > 500 then raise exception 'Use a duration of 1–180 minutes and an outcome up to 500 characters' using errcode = '22023'; end if;
  -- Serializes simultaneous starts across devices, including the empty-table case.
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 12012));
  select * into v_existing from public.focus_sessions where id = p_id;
  if found then
    if v_existing.user_id <> v_user then raise exception 'Session not found' using errcode = 'P0002'; end if;
    return v_existing.id;
  end if;
  if exists(select 1 from public.focus_sessions where user_id = v_user and finished_at is null) then
    raise exception 'Finish your current focus session first' using errcode = '23505';
  end if;
  select r.title, c.slug into v_title, v_slug
    from public.reminders r join public.contexts c on c.id = r.context_id
    where r.id = p_reminder_id and r.user_id = v_user and c.user_id = v_user
      and r.status in ('open', 'snoozed') and c.slug in ('work', 'sidegig') for key share of r, c;
  if not found then raise exception 'Choose an open Work or Side Gig reminder' using errcode = '22023'; end if;
  v_now := clock_timestamp();
  insert into public.focus_sessions(id, user_id, reminder_id, reminder_title, context_slug,
    duration_minutes, intended_outcome, started_at, last_resumed_at, updated_at)
    values(p_id, v_user, p_reminder_id, v_title, v_slug, p_duration_minutes, v_intent, v_now, v_now, v_now);
  return p_id;
end $$;

create function public.pause_focus_session(p_id uuid, p_expected_updated_at timestamptz) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); s public.focus_sessions%rowtype; v_now timestamptz;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select * into s from public.focus_sessions where id = p_id and user_id = v_user for update;
  if not found then raise exception 'Session not found' using errcode = 'P0002'; end if;
  if s.finished_at is not null or s.paused_at is not null then return p_id; end if;
  if s.updated_at is distinct from p_expected_updated_at then raise exception 'Session changed. Refresh and try again.' using errcode = '40001'; end if;
  v_now := greatest(clock_timestamp(), s.updated_at + interval '1 microsecond');
  update public.focus_sessions set elapsed_seconds = least(duration_minutes * 60,
    s.elapsed_seconds + greatest(0, extract(epoch from v_now - s.last_resumed_at))),
    last_resumed_at = null, paused_at = v_now, updated_at = v_now where id = p_id;
  return p_id;
end $$;

create function public.resume_focus_session(p_id uuid, p_expected_updated_at timestamptz) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); s public.focus_sessions%rowtype; v_now timestamptz;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select * into s from public.focus_sessions where id = p_id and user_id = v_user for update;
  if not found then raise exception 'Session not found' using errcode = 'P0002'; end if;
  if s.finished_at is not null or s.last_resumed_at is not null then return p_id; end if;
  if s.updated_at is distinct from p_expected_updated_at then raise exception 'Session changed. Refresh and try again.' using errcode = '40001'; end if;
  if s.elapsed_seconds >= s.duration_minutes * 60 then raise exception 'Time is up. Finish this session to record your outcome.' using errcode = '22023'; end if;
  v_now := greatest(clock_timestamp(), s.updated_at + interval '1 microsecond');
  update public.focus_sessions set last_resumed_at = v_now, paused_at = null, updated_at = v_now where id = p_id;
  return p_id;
end $$;

create function public.finish_focus_session(
  p_id uuid, p_expected_updated_at timestamptz, p_outcome text, p_next_step text default null
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); s public.focus_sessions%rowtype; v_now timestamptz;
  v_step text := nullif(btrim(p_next_step), '');
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select * into s from public.focus_sessions where id = p_id and user_id = v_user for update;
  if not found then raise exception 'Session not found' using errcode = 'P0002'; end if;
  if s.finished_at is not null then return p_id; end if;
  if p_outcome is null or p_outcome not in ('finished', 'progress', 'interrupted') or char_length(v_step) > 1000 then
    raise exception 'Choose an outcome and keep the next step under 1000 characters' using errcode = '22023'; end if;
  if s.updated_at is distinct from p_expected_updated_at then raise exception 'Session changed. Refresh and try again.' using errcode = '40001'; end if;
  v_now := greatest(clock_timestamp(), s.updated_at + interval '1 microsecond');
  update public.focus_sessions set elapsed_seconds = least(duration_minutes * 60,
    s.elapsed_seconds + case when s.last_resumed_at is null then 0 else greatest(0, extract(epoch from v_now - s.last_resumed_at)) end),
    finished_at = v_now, outcome = p_outcome, next_step = v_step,
    last_resumed_at = null, paused_at = null, updated_at = v_now where id = p_id;
  return p_id;
end $$;

revoke all on function public.get_focus_state() from public, anon;
revoke all on function public.set_focus_highlight(uuid) from public, anon;
revoke all on function public.start_focus_session(uuid, uuid, integer, text) from public, anon;
revoke all on function public.pause_focus_session(uuid, timestamptz) from public, anon;
revoke all on function public.resume_focus_session(uuid, timestamptz) from public, anon;
revoke all on function public.finish_focus_session(uuid, timestamptz, text, text) from public, anon;
grant execute on function public.get_focus_state() to authenticated;
grant execute on function public.set_focus_highlight(uuid) to authenticated;
grant execute on function public.start_focus_session(uuid, uuid, integer, text) to authenticated;
grant execute on function public.pause_focus_session(uuid, timestamptz) to authenticated;
grant execute on function public.resume_focus_session(uuid, timestamptz) to authenticated;
grant execute on function public.finish_focus_session(uuid, timestamptz, text, text) to authenticated;
alter publication supabase_realtime add table public.focus_highlights, public.focus_sessions;
