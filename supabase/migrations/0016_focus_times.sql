-- Focus times (weekly availability) and task assignments. Occurrences are derived, never stored:
-- an occurrence is (focus_time_id, local_date) and its UTC start comes from the account timezone.
-- Only RPCs write these tables, keeping both clients on the same state machine.
create function public.focus_weekdays_valid(p_weekdays smallint[]) returns boolean
language sql immutable set search_path = pg_temp as $$
  select p_weekdays is not null and cardinality(p_weekdays) between 1 and 7
    and p_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]
    and cardinality(p_weekdays) = (select count(distinct d) from unnest(p_weekdays) d) $$;
revoke all on function public.focus_weekdays_valid(smallint[]) from public, anon, authenticated;

create table public.focus_times (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  label text check (char_length(label) between 1 and 40),
  context_slug text not null check (context_slug in ('work', 'sidegig')),
  weekdays smallint[] not null check (public.focus_weekdays_valid(weekdays)), -- ISO 1=Mon..7=Sun
  start_time time not null,
  budget_minutes integer not null default 30 check (budget_minutes between 1 and 180),
  enabled boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index focus_times_user on public.focus_times(user_id) where archived_at is null;

create table public.focus_assignments (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  reminder_id uuid references public.reminders(id) on delete set null,
  reminder_title text not null,
  context_slug text not null check (context_slug in ('work', 'sidegig')),
  focus_time_id uuid references public.focus_times(id) on delete set null, -- null = one-off "Pick another day"
  local_date date not null,
  start_time time not null,
  planned_minutes integer not null check (planned_minutes between 1 and 180),
  position integer not null default 0,
  state text not null default 'planned' check (state in ('planned', 'in_progress', 'reviewed', 'skipped', 'moved', 'cancelled')),
  moved_to uuid references public.focus_assignments(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (moved_to is null or state = 'moved')
);
create unique index focus_assignments_one_outstanding on public.focus_assignments(reminder_id) where state in ('planned', 'in_progress');
create index focus_assignments_user_outstanding on public.focus_assignments(user_id, local_date, start_time, position) where state in ('planned', 'in_progress');

alter table public.focus_sessions add column assignment_id uuid references public.focus_assignments(id) on delete set null;
create unique index focus_sessions_assignment on public.focus_sessions(assignment_id) where assignment_id is not null;

alter table public.focus_times enable row level security;
alter table public.focus_assignments enable row level security;
create policy focus_times_read on public.focus_times for select to authenticated using (user_id = auth.uid());
create policy focus_assignments_read on public.focus_assignments for select to authenticated using (user_id = auth.uid());
revoke all on public.focus_times, public.focus_assignments from public, anon, authenticated;
grant select on public.focus_times, public.focus_assignments to authenticated;

create function public.save_focus_time(
  p_id uuid, p_label text, p_context_slug text, p_weekdays smallint[], p_start_time time,
  p_budget_minutes integer default 30, p_enabled boolean default true
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz := clock_timestamp(); v_existing public.focus_times%rowtype;
  v_label text := nullif(btrim(p_label), ''); v_days smallint[]; v_start time;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_id is null or p_start_time is null or p_enabled is null then raise exception 'Choose days and a start time' using errcode = '22023'; end if;
  if char_length(v_label) > 40 then raise exception 'Keep the name under 40 characters' using errcode = '22023'; end if;
  if p_context_slug is null or p_context_slug not in ('work', 'sidegig') then raise exception 'Choose Work or Side Gig' using errcode = '22023'; end if;
  if not public.focus_weekdays_valid(p_weekdays) then raise exception 'Choose at least one weekday' using errcode = '22023'; end if;
  if p_budget_minutes is null or p_budget_minutes not between 1 and 180 then raise exception 'Use a time budget of 1–180 minutes' using errcode = '22023'; end if;
  select array_agg(d order by d) into v_days from unnest(p_weekdays) d;
  v_start := make_time(extract(hour from p_start_time)::int, extract(minute from p_start_time)::int, 0);
  select * into v_existing from public.focus_times where id = p_id;
  if found then
    if v_existing.user_id <> v_user then raise exception 'Focus time not found' using errcode = 'P0002'; end if;
    if v_existing.archived_at is not null then raise exception 'This focus time was removed' using errcode = '22023'; end if;
    update public.focus_times set label = v_label, context_slug = p_context_slug, weekdays = v_days,
      start_time = v_start, budget_minutes = p_budget_minutes, enabled = p_enabled, updated_at = v_now where id = p_id;
  else
    insert into public.focus_times(id, user_id, label, context_slug, weekdays, start_time, budget_minutes, enabled, created_at, updated_at)
      values(p_id, v_user, v_label, p_context_slug, v_days, v_start, p_budget_minutes, p_enabled, v_now, v_now);
  end if;
  return p_id;
end $$;

create function public.archive_focus_time(p_id uuid) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); v_now timestamptz := clock_timestamp();
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  -- Planned assignments keep their own date/time and stay visible and recoverable.
  update public.focus_times set archived_at = v_now, enabled = false, updated_at = v_now
    where id = p_id and user_id = v_user and archived_at is null;
  if not found and not exists(select 1 from public.focus_times where id = p_id and user_id = v_user) then
    raise exception 'Focus time not found' using errcode = 'P0002'; end if;
  return p_id;
end $$;

create function public.assign_focus_work(
  p_id uuid, p_reminder_id uuid, p_focus_time_id uuid, p_local_date date, p_start_time time, p_planned_minutes integer
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz; v_zone text; v_existing public.focus_assignments%rowtype;
  v_title text; v_slug text; v_ft public.focus_times%rowtype; v_start time; v_old public.focus_assignments%rowtype;
  v_position integer;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_id is null or p_local_date is null then raise exception 'Choose a day' using errcode = '22023'; end if;
  if p_planned_minutes is null or p_planned_minutes not between 1 and 180 then raise exception 'Use planned minutes of 1–180' using errcode = '22023'; end if;
  -- Same per-user lock as starts: moves, starts and reviews of one person's plan never interleave.
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 12012));
  select * into v_existing from public.focus_assignments where id = p_id;
  if found then
    if v_existing.user_id <> v_user then raise exception 'Assignment not found' using errcode = 'P0002'; end if;
    return p_id;
  end if;
  v_now := clock_timestamp();
  select timezone into v_zone from public.user_settings where user_id = v_user;
  if p_local_date < (v_now at time zone coalesce(v_zone, 'UTC'))::date then
    raise exception 'Choose today or a later day' using errcode = '22023'; end if;
  select r.title, c.slug into v_title, v_slug
    from public.reminders r join public.contexts c on c.id = r.context_id
    where r.id = p_reminder_id and r.user_id = v_user and c.user_id = v_user
      and r.status in ('open', 'snoozed') and c.slug in ('work', 'sidegig') for share of r for key share of c;
  if not found then raise exception 'Choose an open Work or Side Gig reminder' using errcode = '22023'; end if;
  if p_focus_time_id is null then
    if p_start_time is null then raise exception 'Choose a start time' using errcode = '22023'; end if;
    v_start := make_time(extract(hour from p_start_time)::int, extract(minute from p_start_time)::int, 0);
  else
    select * into v_ft from public.focus_times where id = p_focus_time_id and user_id = v_user for share;
    if not found then raise exception 'Focus time not found' using errcode = 'P0002'; end if;
    if v_ft.archived_at is not null then raise exception 'This focus time was removed' using errcode = '22023'; end if;
    if v_ft.context_slug <> v_slug then raise exception 'This focus time is for another context' using errcode = '22023'; end if;
    if not (extract(isodow from p_local_date)::int = any(v_ft.weekdays)) then
      raise exception 'That day is not one of this focus time''s days. Refresh and try again.' using errcode = '22023'; end if;
    v_start := v_ft.start_time; -- the focus time is authoritative; p_start_time is only used for one-offs
  end if;
  select * into v_old from public.focus_assignments
    where user_id = v_user and reminder_id = p_reminder_id and state in ('planned', 'in_progress') for update;
  if found then
    if v_old.state = 'in_progress' then raise exception 'Finish the current session first' using errcode = '55000'; end if;
    update public.focus_assignments set state = 'moved', updated_at = v_now where id = v_old.id;
  end if;
  select coalesce(max(a.position) + 1, 0) into v_position from public.focus_assignments a
    where a.user_id = v_user and a.state in ('planned', 'in_progress') and a.local_date = p_local_date
      and a.focus_time_id is not distinct from p_focus_time_id
      and (p_focus_time_id is not null or a.start_time = v_start);
  insert into public.focus_assignments(id, user_id, reminder_id, reminder_title, context_slug, focus_time_id,
    local_date, start_time, planned_minutes, position, state, created_at, updated_at)
    values(p_id, v_user, p_reminder_id, v_title, v_slug, p_focus_time_id, p_local_date, v_start,
      p_planned_minutes, v_position, 'planned', v_now, v_now);
  if v_old.id is not null then
    update public.focus_assignments set moved_to = p_id where id = v_old.id;
  end if;
  return p_id;
end $$;

create function public.skip_focus_work(p_id uuid) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); a public.focus_assignments%rowtype;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select * into a from public.focus_assignments where id = p_id and user_id = v_user for update;
  if not found then raise exception 'Assignment not found' using errcode = 'P0002'; end if;
  if a.state = 'in_progress' then raise exception 'Finish the current session first' using errcode = '55000'; end if;
  if a.state = 'planned' then
    update public.focus_assignments set state = 'skipped', updated_at = clock_timestamp() where id = p_id;
  end if;
  return p_id; -- reminders are never touched; already-resolved assignments are a safe no-op
end $$;

create function public.start_assigned_focus(p_session_id uuid, p_assignment_id uuid, p_duration_minutes integer default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz; v_existing public.focus_sessions%rowtype;
  a public.focus_assignments%rowtype; v_title text; v_slug text; v_minutes integer;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_session_id is null or p_assignment_id is null then raise exception 'Choose planned work to start' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 12012));
  select * into v_existing from public.focus_sessions where id = p_session_id;
  if found then
    if v_existing.user_id <> v_user then raise exception 'Session not found' using errcode = 'P0002'; end if;
    return v_existing.id;
  end if;
  select * into a from public.focus_assignments where id = p_assignment_id and user_id = v_user for update;
  if not found then raise exception 'Assignment not found' using errcode = 'P0002'; end if;
  if exists(select 1 from public.focus_sessions where user_id = v_user and finished_at is null) then
    raise exception 'Finish your current focus session first' using errcode = '23505'; end if;
  if a.state <> 'planned' then raise exception 'This plan is no longer available. Refresh and try again.' using errcode = '22023'; end if;
  v_minutes := coalesce(p_duration_minutes, a.planned_minutes);
  if v_minutes not between 1 and 180 then raise exception 'Use a duration of 1–180 minutes' using errcode = '22023'; end if;
  select r.title, c.slug into v_title, v_slug
    from public.reminders r join public.contexts c on c.id = r.context_id
    where r.id = a.reminder_id and r.user_id = v_user and c.user_id = v_user
      and r.status in ('open', 'snoozed') and c.slug in ('work', 'sidegig') for key share of r, c;
  if not found then raise exception 'Choose an open Work or Side Gig reminder' using errcode = '22023'; end if;
  v_now := clock_timestamp();
  insert into public.focus_sessions(id, user_id, reminder_id, reminder_title, context_slug,
    duration_minutes, intended_outcome, started_at, last_resumed_at, updated_at, assignment_id)
    values(p_session_id, v_user, a.reminder_id, v_title, v_slug, v_minutes, null, v_now, v_now, v_now, a.id);
  update public.focus_assignments set state = 'in_progress', updated_at = v_now where id = a.id;
  return p_session_id;
end $$;

-- Finishing through either finish RPC (including the 0012 one old clients call) reviews the assignment.
create function public.focus_review_assignment() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.focus_assignments set state = 'reviewed', updated_at = new.finished_at
    where id = new.assignment_id and state = 'in_progress';
  return new;
end $$;
create trigger focus_sessions_review_assignment after update of finished_at on public.focus_sessions
  for each row when (old.finished_at is null and new.finished_at is not null and new.assignment_id is not null)
  execute function public.focus_review_assignment();

-- A reminder that is deleted, leaves open/snoozed or leaves Work/Side Gig loses its planned work.
-- In-progress assignments stay until their session is reviewed.
create function public.focus_cancel_planned_work() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' or new.status not in ('open', 'snoozed')
    or not exists(select 1 from public.contexts c where c.id = new.context_id and c.slug in ('work', 'sidegig')) then
    update public.focus_assignments set state = 'cancelled', updated_at = clock_timestamp()
      where reminder_id = old.id and state = 'planned';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger reminders_cancel_planned_focus_delete before delete on public.reminders
  for each row execute function public.focus_cancel_planned_work();
create trigger reminders_cancel_planned_focus_update after update of status, context_id on public.reminders
  for each row when (old.status is distinct from new.status or old.context_id is distinct from new.context_id)
  execute function public.focus_cancel_planned_work();
revoke all on function public.focus_review_assignment(), public.focus_cancel_planned_work() from public, anon, authenticated;

-- v2 dashboard: adds the non-archived focus times and outstanding assignments (with deadlines).
create or replace function public.get_focus_dashboard_v2() returns jsonb
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_state jsonb; v_minutes integer; v_highlight uuid; v_session uuid;
  v_highlight_step text; v_session_step text; v_times jsonb; v_assignments jsonb;
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  v_state := public.get_focus_state();
  select preferred_minutes into v_minutes from public.focus_preferences where user_id = v_user;
  v_highlight := nullif(v_state->'highlight'->>'reminder_id', '')::uuid;
  v_session := nullif(v_state->'active_session'->>'reminder_id', '')::uuid;
  select s.next_step into v_highlight_step from public.focus_sessions s
    where s.user_id = v_user and s.reminder_id = v_highlight and s.finished_at is not null
    order by s.finished_at desc, s.id desc limit 1;
  select s.next_step into v_session_step from public.focus_sessions s
    where s.user_id = v_user and s.reminder_id = v_session and s.finished_at is not null
    order by s.finished_at desc, s.id desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'label', t.label, 'context_slug', t.context_slug,
      'weekdays', t.weekdays, 'start_time', t.start_time, 'budget_minutes', t.budget_minutes,
      'enabled', t.enabled, 'updated_at', t.updated_at) order by t.start_time, t.created_at, t.id), '[]'::jsonb)
    into v_times from public.focus_times t where t.user_id = v_user and t.archived_at is null;
  select coalesce(jsonb_agg(x.j order by x.local_date, x.start_time, x.position, x.created_at, x.id), '[]'::jsonb)
    into v_assignments from (
      select a.local_date, a.start_time, a.position, a.created_at, a.id, jsonb_build_object(
        'id', a.id, 'reminder_id', a.reminder_id, 'reminder_title', coalesce(r.title, a.reminder_title),
        'context_slug', coalesce(c.slug, a.context_slug), 'focus_time_id', a.focus_time_id, 'focus_time_label', t.label,
        'local_date', a.local_date, 'start_time', a.start_time, 'planned_minutes', a.planned_minutes,
        'position', a.position, 'state', a.state, 'moved_to', a.moved_to, 'updated_at', a.updated_at,
        'due_at', r.due_at, 'ship_by', o.ship_by) as j
      from public.focus_assignments a
        left join public.reminders r on r.id = a.reminder_id
        left join public.contexts c on c.id = r.context_id
        left join public.orders o on o.reminder_id = r.id
        left join public.focus_times t on t.id = a.focus_time_id
      where a.user_id = v_user and a.state in ('planned', 'in_progress')
      order by a.local_date, a.start_time, a.position, a.created_at, a.id limit 200) x;
  return v_state || jsonb_build_object('preferred_minutes', coalesce(v_minutes, 25),
    'highlight_next_step', v_highlight_step, 'session_next_step', v_session_step,
    'focus_times', v_times, 'assignments', v_assignments);
end $$;

revoke all on function public.get_focus_dashboard_v2() from public, anon;
revoke all on function public.save_focus_time(uuid, text, text, smallint[], time, integer, boolean) from public, anon;
revoke all on function public.archive_focus_time(uuid) from public, anon;
revoke all on function public.assign_focus_work(uuid, uuid, uuid, date, time, integer) from public, anon;
revoke all on function public.skip_focus_work(uuid) from public, anon;
revoke all on function public.start_assigned_focus(uuid, uuid, integer) from public, anon;
grant execute on function public.get_focus_dashboard_v2() to authenticated;
grant execute on function public.save_focus_time(uuid, text, text, smallint[], time, integer, boolean) to authenticated;
grant execute on function public.archive_focus_time(uuid) to authenticated;
grant execute on function public.assign_focus_work(uuid, uuid, uuid, date, time, integer) to authenticated;
grant execute on function public.skip_focus_work(uuid) to authenticated;
grant execute on function public.start_assigned_focus(uuid, uuid, integer) to authenticated;
alter publication supabase_realtime add table public.focus_times, public.focus_assignments;
