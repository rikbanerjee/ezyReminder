-- Home groups Shopping and Social/Personal maintenance without adding a context.
create table public.home_maintenance (
  reminder_id uuid primary key references public.reminders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('car','hvac','dryer','filter','other')),
  asset text not null default '',
  repeat_months integer check (repeat_months between 1 and 120)
);
create table public.home_service_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reminder_id uuid references public.reminders(id) on delete set null,
  title text not null,
  category text not null check (category in ('car','hvac','dryer','filter','other')),
  asset text not null,
  serviced_at timestamptz not null,
  notes text not null default '',
  created_at timestamptz not null default now()
);
create index home_service_records_user_date on public.home_service_records(user_id, serviced_at desc);
alter table public.home_maintenance enable row level security;
alter table public.home_service_records enable row level security;
-- Writes go through RPCs so reminder + details + history remain atomic.
create policy home_maintenance_read on public.home_maintenance for select using (user_id = auth.uid());
create policy home_service_records_read on public.home_service_records for select using (user_id = auth.uid());
grant select on public.home_maintenance, public.home_service_records to authenticated;

create function public.save_home_maintenance(
  p_id uuid, p_title text, p_notes text, p_due_at timestamptz,
  p_category text, p_asset text, p_repeat_months integer, p_channels text[]
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_user uuid := auth.uid(); v_id uuid; v_context uuid;
begin
  if v_user is null then raise exception 'Sign in required'; end if;
  if nullif(btrim(p_title),'') is null then raise exception 'Title required'; end if;
  if p_due_at is null then raise exception 'Next due date required'; end if;
  if p_channels is null or not (p_channels @> array['email']::text[])
     or not (p_channels <@ array['email','apns']::text[]) then
    raise exception 'Email fallback is required';
  end if;
  if p_id is null then
    select id into v_context from contexts where user_id=v_user and slug='social';
    if v_context is null then raise exception 'Personal context missing'; end if;
    insert into reminders(user_id,context_id,title,notes,due_at,channels,tags)
      values(v_user,v_context,btrim(p_title),nullif(btrim(p_notes),''),p_due_at,p_channels,array['home:' || p_category])
      returning id into v_id;
  else
    select r.id into v_id from reminders r join home_maintenance h on h.reminder_id=r.id
      where r.id=p_id and r.user_id=v_user and h.user_id=v_user for update of r;
    if v_id is null then raise exception 'Maintenance reminder not found'; end if;
    update reminders set title=btrim(p_title), notes=nullif(btrim(p_notes),''), due_at=p_due_at,
      channels=p_channels, tags=array['home:' || p_category], status='open', snoozed_until=null where id=v_id;
  end if;
  insert into home_maintenance(reminder_id,user_id,category,asset,repeat_months)
    values(v_id,v_user,p_category,coalesce(btrim(p_asset),''),p_repeat_months)
    on conflict(reminder_id) do update set category=excluded.category,asset=excluded.asset,repeat_months=excluded.repeat_months;
  return v_id;
end $$;

create function public.record_home_service(
  p_id uuid, p_expected_updated_at timestamptz, p_serviced_at timestamptz, p_notes text
) returns uuid language plpgsql security definer set search_path = public as $$
declare r reminders%rowtype; h home_maintenance%rowtype; v_record uuid; v_zone text;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into r from reminders where id=p_id and user_id=auth.uid() for update;
  if not found then raise exception 'Maintenance reminder not found'; end if;
  if r.updated_at is distinct from p_expected_updated_at or r.status not in ('open','snoozed') then
    raise exception 'Reminder changed. Refresh before recording service.';
  end if;
  select * into h from home_maintenance where reminder_id=p_id and user_id=auth.uid();
  if not found then raise exception 'Maintenance details missing'; end if;
  if p_serviced_at is null or p_serviced_at > now() then raise exception 'Service date must be now or earlier'; end if;
  select timezone into v_zone from user_settings where user_id=auth.uid();
  v_zone := coalesce(v_zone,'UTC');
  insert into home_service_records(user_id,reminder_id,title,category,asset,serviced_at,notes)
    values(auth.uid(),r.id,r.title,h.category,h.asset,p_serviced_at,coalesce(btrim(p_notes),'')) returning id into v_record;
  update reminders set status=case when h.repeat_months is null then 'done' else 'open' end,
    due_at=case when h.repeat_months is null then due_at else
      ((p_serviced_at at time zone v_zone) + make_interval(months => h.repeat_months)) at time zone v_zone end,
    snoozed_until=null where id=r.id;
  return v_record;
end $$;
revoke all on function public.save_home_maintenance(uuid,text,text,timestamptz,text,text,integer,text[]) from public,anon;
revoke all on function public.record_home_service(uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.save_home_maintenance(uuid,text,text,timestamptz,text,text,integer,text[]) to authenticated;
grant execute on function public.record_home_service(uuid,timestamptz,timestamptz,text) to authenticated;
alter publication supabase_realtime add table public.home_maintenance, public.home_service_records;
