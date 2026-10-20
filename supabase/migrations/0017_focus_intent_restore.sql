-- Planned starts keep an optional intended outcome, and an archived focus time can be restored under
-- the same id so its planned work stays attached. `focus_api` on the dashboard tells clients these exist.

-- Same signature plus an optional p_intended_outcome: callers passing three arguments keep working.
drop function public.start_assigned_focus(uuid, uuid, integer);
create function public.start_assigned_focus(
  p_session_id uuid, p_assignment_id uuid, p_duration_minutes integer default null, p_intended_outcome text default null
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_now timestamptz; v_existing public.focus_sessions%rowtype;
  a public.focus_assignments%rowtype; v_title text; v_slug text; v_minutes integer;
  v_intent text := nullif(btrim(p_intended_outcome), '');
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_session_id is null or p_assignment_id is null then raise exception 'Choose planned work to start' using errcode = '22023'; end if;
  if char_length(v_intent) > 500 then raise exception 'Keep the outcome to 500 characters' using errcode = '22023'; end if;
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
    values(p_session_id, v_user, a.reminder_id, v_title, v_slug, v_minutes, v_intent, v_now, v_now, v_now, a.id);
  update public.focus_assignments set state = 'in_progress', updated_at = v_now where id = a.id;
  return p_session_id;
end $$;

-- Undo for archive_focus_time: same id, so planned work linked to it is still its work.
-- p_enabled is the value the time had before archiving (archiving disables it). Restoring a live time is a no-op.
create function public.restore_focus_time(p_id uuid, p_enabled boolean default true) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_enabled is null then raise exception 'Choose whether the focus time is on' using errcode = '22023'; end if;
  update public.focus_times set archived_at = null, enabled = p_enabled, updated_at = clock_timestamp()
    where id = p_id and user_id = v_user and archived_at is not null;
  if not found and not exists(select 1 from public.focus_times where id = p_id and user_id = v_user) then
    raise exception 'Focus time not found' using errcode = 'P0002'; end if;
  return p_id;
end $$;

-- Dashboard v2 from 0016 plus focus_api = 17 (planned intents + restore available).
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
    'focus_times', v_times, 'assignments', v_assignments, 'focus_api', 17);
end $$;

revoke all on function public.start_assigned_focus(uuid, uuid, integer, text) from public, anon;
revoke all on function public.restore_focus_time(uuid, boolean) from public, anon;
revoke all on function public.get_focus_dashboard_v2() from public, anon;
grant execute on function public.start_assigned_focus(uuid, uuid, integer, text) to authenticated;
grant execute on function public.restore_focus_time(uuid, boolean) to authenticated;
grant execute on function public.get_focus_dashboard_v2() to authenticated;
