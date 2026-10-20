-- Remembered Focus duration + dashboard v2 (one round trip for the Today card).
-- Only RPCs write focus_preferences; 0012 RPCs and their callers stay unchanged.
create table public.focus_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  preferred_minutes integer not null default 25 check (preferred_minutes between 1 and 180),
  updated_at timestamptz not null default now()
);
alter table public.focus_preferences enable row level security;
create policy focus_preferences_read on public.focus_preferences for select to authenticated using (user_id = auth.uid());
revoke all on public.focus_preferences from public, anon, authenticated;
grant select on public.focus_preferences to authenticated;

create function public.save_focus_preferences(p_preferred_minutes integer) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); v_now timestamptz := clock_timestamp();
begin
  if v_user is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_preferred_minutes is null or p_preferred_minutes not between 1 and 180 then
    raise exception 'Use a duration of 1–180 minutes' using errcode = '22023'; end if;
  insert into public.focus_preferences(user_id, preferred_minutes, updated_at)
    values(v_user, p_preferred_minutes, v_now)
    on conflict(user_id) do update set preferred_minutes = excluded.preferred_minutes, updated_at = excluded.updated_at;
  return p_preferred_minutes;
end $$;

-- get_focus_state() plus preferred_minutes and the latest saved next step for the highlighted
-- and the active session's reminder. Only the latest finished session counts: a deliberately blank
-- note stays blank and never falls back to an older one. security invoker => RLS applies.
create function public.get_focus_dashboard_v2() returns jsonb
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_state jsonb; v_minutes integer;
  v_highlight uuid; v_session uuid; v_highlight_step text; v_session_step text;
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
  return v_state || jsonb_build_object('preferred_minutes', coalesce(v_minutes, 25),
    'highlight_next_step', v_highlight_step, 'session_next_step', v_session_step);
end $$;

revoke all on function public.save_focus_preferences(integer) from public, anon;
revoke all on function public.get_focus_dashboard_v2() from public, anon;
grant execute on function public.save_focus_preferences(integer) to authenticated;
grant execute on function public.get_focus_dashboard_v2() to authenticated;
alter publication supabase_realtime add table public.focus_preferences;
