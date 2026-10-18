-- Contextual Home tasks; preserve 0011's RPCs for existing clients.
begin;
alter table public.home_maintenance drop constraint home_maintenance_category_check;
alter table public.home_maintenance add constraint home_maintenance_category_check
  check (category in ('car','hvac','dryer','filter','battery','bill','study','other'));
alter table public.home_service_records drop constraint home_service_records_category_check;
alter table public.home_service_records add constraint home_service_records_category_check
  check (category in ('car','hvac','dryer','filter','battery','bill','study','other'));
alter table public.home_maintenance add column details jsonb not null default '{}'::jsonb check (jsonb_typeof(details)='object');
alter table public.home_maintenance add column repeat_days integer check (repeat_days between 1 and 3660);
alter table public.home_maintenance add constraint home_task_one_repeat_unit check (repeat_days is null or repeat_months is null);
alter table public.home_service_records add column details jsonb not null default '{}'::jsonb check (jsonb_typeof(details)='object');

-- New named RPC avoids an ambiguous overload in PostgREST and keeps old saves valid.
create function public.save_home_task(
  p_id uuid, p_title text, p_notes text, p_due_at timestamptz,
  p_category text, p_asset text, p_repeat_months integer, p_channels text[],
  p_details jsonb default '{}'::jsonb, p_repeat_days integer default null
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_allowed text[]; v_field record;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_repeat_days is not null and p_repeat_months is not null then raise exception 'Choose days or months, not both'; end if;
  if p_details is null or jsonb_typeof(p_details) <> 'object' then raise exception 'Task details must be an object'; end if;
  v_allowed := case p_category
    when 'car' then array['make','model']
    when 'hvac' then array['filter_size']
    when 'filter' then array['filter_size']
    when 'battery' then array['battery_type']
    when 'bill' then array['amount','currency']
    when 'study' then array['subject','teacher']
    else '{}'::text[] end;
  for v_field in select key,value from jsonb_each(p_details) loop
    if not (v_field.key = any(v_allowed)) or jsonb_typeof(v_field.value) <> 'string'
      or length(v_field.value #>> '{}') > 1000 then raise exception 'Invalid details for this Home task'; end if;
  end loop;
  if p_category='bill' then
    if coalesce(p_details->>'amount','') <> '' and (p_details->>'amount') !~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' then raise exception 'Enter a valid bill amount'; end if;
    if coalesce(p_details->>'currency','') <> '' and (p_details->>'currency') !~ '^[A-Z]{3}$' then raise exception 'Use a three-letter currency'; end if;
    if coalesce(p_details->>'amount','') <> '' and coalesce(p_details->>'currency','') = '' then raise exception 'Currency required for bill amount'; end if;
  end if;
  -- Clear the previous unit before 0011's writer changes it. Ownership is
  -- rechecked by that function; failure rolls this update back as well.
  if p_id is not null then
    update home_maintenance set repeat_days=null where reminder_id=p_id and user_id=auth.uid();
  end if;
  v_id := public.save_home_maintenance(p_id,p_title,p_notes,p_due_at,p_category,p_asset,p_repeat_months,p_channels);
  update home_maintenance set details=p_details, repeat_days=p_repeat_days where reminder_id=v_id and user_id=auth.uid();
  return v_id;
end $$;
revoke all on function public.save_home_task(uuid,text,text,timestamptz,text,text,integer,text[],jsonb,integer) from public,anon;
grant execute on function public.save_home_task(uuid,text,text,timestamptz,text,text,integer,text[],jsonb,integer) to authenticated;

create or replace function public.record_home_service(
  p_id uuid, p_expected_updated_at timestamptz, p_serviced_at timestamptz, p_notes text
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare r reminders%rowtype; h home_maintenance%rowtype; v_record uuid; v_zone text; v_anchor timestamptz; v_next timestamptz;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into r from reminders where id=p_id and user_id=auth.uid() for update;
  if not found then raise exception 'Home task not found'; end if;
  if r.updated_at is distinct from p_expected_updated_at or r.status not in ('open','snoozed') then
    raise exception 'Reminder changed. Refresh before recording completion.';
  end if;
  select * into h from home_maintenance where reminder_id=p_id and user_id=auth.uid();
  if not found then raise exception 'Home task details missing'; end if;
  if p_serviced_at is null or p_serviced_at > now() then raise exception 'Completion date must be now or earlier'; end if;
  select timezone into v_zone from user_settings where user_id=auth.uid();
  v_zone := coalesce(v_zone,'UTC');
  -- Bills and study follow the planned due date, so paying early or studying
  -- late does not drift the schedule. Care tasks repeat from actual completion.
  v_anchor := case when h.category in ('bill','study') then coalesce(r.due_at,p_serviced_at) else p_serviced_at end;
  if h.repeat_months is not null or h.repeat_days is not null then
    v_next := ((v_anchor at time zone v_zone) + make_interval(months=>coalesce(h.repeat_months,0),days=>coalesce(h.repeat_days,0))) at time zone v_zone;
  end if;
  insert into home_service_records(user_id,reminder_id,title,category,asset,serviced_at,notes,details)
    values(auth.uid(),r.id,r.title,h.category,h.asset,p_serviced_at,coalesce(btrim(p_notes),''),h.details) returning id into v_record;
  update reminders set status=case when v_next is null then 'done' else 'open' end,
    due_at=coalesce(v_next,due_at), snoozed_until=null where id=r.id;
  return v_record;
end $$;
-- 0011's grants remain on the replaced function. No records/categories are
-- rewritten: old filter tasks and history render under HVAC in both clients.
commit;
