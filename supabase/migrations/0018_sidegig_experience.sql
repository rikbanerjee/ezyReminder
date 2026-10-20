-- Side Gig work, follow-ups and expected payments. Existing reminders own delivery;
-- business facts remain independent. No changes to the notification sweep.
begin;

create table public.sidegig_work_state (
  reminder_id uuid primary key references public.reminders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  waiting boolean not null default false,
  next_step text check (char_length(next_step) <= 500),
  next_step_at timestamptz,
  minutes integer not null default 15 check (minutes between 1 and 180),
  updated_at timestamptz not null default now()
);
create table public.sidegig_obligations (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  reminder_id uuid unique references public.reminders(id) on delete set null,
  kind text not null check (kind in ('followup','payment')),
  title text not null check (char_length(title) between 1 and 180),
  person text,
  notes text,
  due_at timestamptz not null,
  state text not null default 'open' check (state in ('open','resolved','received','cancelled')),
  related_reminder_id uuid references public.reminders(id) on delete set null,
  related_payment_id uuid references public.sidegig_obligations(id) on delete set null,
  amount numeric(14,2) check (amount > 0),
  currency text check (currency ~ '^[A-Z]{3}$'),
  reference text,
  held_channels text[],
  held_snoozed_until timestamptz,
  last_contact_at timestamptz,
  received_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((amount is null) or currency is not null),
  check ((kind='payment' and state in ('open','received','cancelled')) or
         (kind='followup' and state in ('open','resolved','cancelled')))
);
create unique index sidegig_one_collection_followup on public.sidegig_obligations(user_id,related_payment_id)
  where kind='followup' and state='open' and related_payment_id is not null;
create index sidegig_obligations_due on public.sidegig_obligations(user_id,state,due_at);
create index sidegig_obligations_related on public.sidegig_obligations(user_id,related_reminder_id);
create table public.sidegig_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  obligation_id uuid not null references public.sidegig_obligations(id) on delete cascade,
  action text not null,
  notes text,
  happened_at timestamptz not null default now()
);
create table public.sidegig_operations (
  id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  target_id uuid not null,
  payload_hash text not null,
  primary key(user_id,id)
);
alter table public.sidegig_work_state enable row level security;
alter table public.sidegig_obligations enable row level security;
alter table public.sidegig_activity enable row level security;
alter table public.sidegig_operations enable row level security;
create policy sidegig_work_read on public.sidegig_work_state for select using(user_id=auth.uid());
create policy sidegig_obligation_read on public.sidegig_obligations for select using(user_id=auth.uid());
create policy sidegig_activity_read on public.sidegig_activity for select using(user_id=auth.uid());
revoke all on public.sidegig_work_state,public.sidegig_obligations,public.sidegig_activity,public.sidegig_operations from anon,authenticated;
grant select on public.sidegig_work_state,public.sidegig_obligations,public.sidegig_activity to authenticated;

-- A single retry-safe transaction contract for both clients. Payloads contain
-- only fields for the named action; a retry keeps its operation id and payload.
create function public.sidegig_mutate(p_operation_id uuid,p_action text,p_id uuid,p_data jsonb default '{}')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  u uuid:=auth.uid(); ctx contexts%rowtype; r reminders%rowtype;
  o sidegig_obligations%rowtype; op sidegig_operations%rowtype;
  v_title text; v_due timestamptz; v_related uuid; v_payment uuid; v_kind text;
  v_channels text[]; v_amount numeric; v_currency text; v_reminder uuid;
  v_date date; v_zone text; v_order boolean; v_step text;
begin
  if u is null then raise exception 'Sign in required' using errcode='28000'; end if;
  if p_operation_id is null or p_id is null or jsonb_typeof(p_data)<>'object' then
    raise exception 'A valid operation, record and fields are required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(u::text,18018));
  select * into op from sidegig_operations where user_id=u and id=p_operation_id;
  if found then
    if op.action<>p_action or op.target_id<>p_id or op.payload_hash<>md5(p_data::text) then
      raise exception 'This operation was already used for a different change' using errcode='22023'; end if;
    return p_id;
  end if;
  select * into ctx from contexts where user_id=u and slug='sidegig';
  if not found then raise exception 'Side Gig context is unavailable' using errcode='P0002'; end if;
  select coalesce((select timezone from user_settings where user_id=u),'UTC') into v_zone;
  if char_length(coalesce(p_data->>'notes',''))>5000 or char_length(coalesce(p_data->>'person',''))>200
    or char_length(coalesce(p_data->>'reference',''))>200 then
    raise exception 'Keep notes under 5000 characters and names/references under 200' using errcode='22023'; end if;

  if p_action='save_work' then
    select * into r from reminders where id=p_id for update;
    if found and (r.user_id<>u or r.context_id<>ctx.id) then raise exception 'Work not found' using errcode='P0002'; end if;
    if exists(select 1 from sidegig_obligations where reminder_id=p_id) then
      raise exception 'Open this commitment in Follow-ups or Payments' using errcode='22023'; end if;
    v_title:=nullif(btrim(p_data->>'title'),'');
    if v_title is null or char_length(v_title)>180 then raise exception 'Use a title of 1–180 characters' using errcode='22023'; end if;
    v_due:=nullif(p_data->>'due_at','')::timestamptz;
    v_order:=coalesce((p_data->>'is_order')::boolean,false);
    if v_order and v_due is null and nullif(p_data->>'ship_by','') is not null then
      v_due:=((p_data->>'ship_by')::date + time '09:00') at time zone v_zone;
    end if;
    v_step:=nullif(btrim(p_data->>'next_step'),'');
    if char_length(v_step)>500 then raise exception 'Keep the next step under 500 characters' using errcode='22023'; end if;
    if not v_order and exists(select 1 from orders where reminder_id=p_id and shipped_at is not null) then
      raise exception 'Keep a shipped order as an order' using errcode='22023'; end if;
    -- An empty list inherits context delivery, including bare Today captures.
    if p_data ? 'channels' then select coalesce(array_agg(value),'{}'::text[]) into v_channels from jsonb_array_elements_text(p_data->'channels');
    else v_channels:=coalesce(r.channels,array[case when ctx.default_channel='apns' then 'apns' else 'email' end]); end if;
    if not v_channels<@array['email','apns'] then
      raise exception 'Choose email or iPhone delivery' using errcode='22023'; end if;
    if r.id is null then
      insert into reminders(id,user_id,context_id,title,notes,due_at,channels,is_order,created_by)
        values(p_id,u,ctx.id,v_title,nullif(p_data->>'notes',''),v_due,v_channels,v_order,'ui');
    else
      update reminders set title=v_title,notes=nullif(p_data->>'notes',''),due_at=v_due,channels=v_channels,is_order=v_order,
        snoozed_until=case when due_at is distinct from v_due then null else snoozed_until end,
        status=case when status='snoozed' and due_at is distinct from v_due then 'open' else status end
        where id=p_id;
    end if;
    if v_order then
      if char_length(coalesce(p_data->>'tracking',''))>64 then raise exception 'Tracking number is too long' using errcode='22023'; end if;
      insert into orders(reminder_id,user_id,order_ref,recipient_name,ship_by,carrier,tracking_number)
        values(p_id,u,nullif(p_data->>'reference',''),nullif(p_data->>'person',''),nullif(p_data->>'ship_by','')::date,
          nullif(p_data->>'carrier',''),nullif(p_data->>'tracking',''))
        on conflict(reminder_id) do update set order_ref=excluded.order_ref,recipient_name=excluded.recipient_name,
          ship_by=excluded.ship_by,carrier=excluded.carrier,tracking_number=excluded.tracking_number;
    else
      delete from orders where reminder_id=p_id;
    end if;
    insert into sidegig_details(reminder_id,user_id,initiative_name,client_name)
      values(p_id,u,nullif(p_data->>'initiative',''),nullif(p_data->>'person',''))
      on conflict(reminder_id) do update set initiative_name=excluded.initiative_name,client_name=excluded.client_name;
    insert into sidegig_work_state(reminder_id,user_id,next_step,next_step_at,minutes)
      values(p_id,u,v_step,clock_timestamp(),coalesce((p_data->>'minutes')::integer,15))
      on conflict(reminder_id) do update set next_step=excluded.next_step,
        next_step_at=excluded.next_step_at,
        minutes=excluded.minutes,updated_at=clock_timestamp();

  elsif p_action in ('save_followup','save_payment') then
    v_kind:=case when p_action='save_followup' then 'followup' else 'payment' end;
    select * into o from sidegig_obligations where id=p_id for update;
    if found and (o.user_id<>u or o.kind<>v_kind) then raise exception 'Commitment not found' using errcode='P0002'; end if;
    if o.id is not null and o.state<>'open' then raise exception 'This commitment is already closed' using errcode='22023'; end if;
    v_title:=nullif(btrim(p_data->>'title'),''); v_due:=nullif(p_data->>'due_at','')::timestamptz;
    if v_title is null or char_length(v_title)>180 or v_due is null then
      raise exception 'Add a title and a follow-up or expected date' using errcode='22023'; end if;
    v_related:=nullif(p_data->>'related_id','')::uuid;
    v_payment:=nullif(p_data->>'related_payment_id','')::uuid;
    if v_related is not null and not exists(select 1 from reminders where id=v_related and user_id=u and context_id=ctx.id) then
      raise exception 'Related work not found in Side Gig' using errcode='P0002'; end if;
    if v_payment is not null and (v_kind<>'followup' or not exists(select 1 from sidegig_obligations where id=v_payment and user_id=u and kind='payment' and state='open')) then
      raise exception 'Expected payment not found' using errcode='P0002'; end if;
    v_amount:=null; v_currency:=null;
    if v_kind='payment' and nullif(p_data->>'amount','') is not null then
      if (p_data->>'amount')!~'^\d{1,12}(\.\d{1,2})?$' then raise exception 'Use a positive amount with up to two decimal places' using errcode='22023'; end if;
      v_amount:=(p_data->>'amount')::numeric;
      v_currency:=upper(nullif(btrim(p_data->>'currency'),''));
      if v_amount<=0 or v_currency is null or v_currency!~'^[A-Z]{3}$' then raise exception 'Add a positive amount and a three-letter currency' using errcode='22023'; end if;
    end if;
    if coalesce((p_data->>'block_work')::boolean,false) then
      if v_kind<>'followup' or v_related is null then raise exception 'Choose the work waiting for a response' using errcode='22023'; end if;
      if exists(select 1 from focus_sessions where user_id=u and reminder_id=v_related and finished_at is null) then
        raise exception 'Finish the current session before waiting for a response' using errcode='22023'; end if;
    end if;
    v_reminder:=coalesce(o.reminder_id,gen_random_uuid());
    if o.id is null then
      insert into reminders(id,user_id,context_id,title,notes,due_at,channels,created_by,tags)
        values(v_reminder,u,ctx.id,v_title,nullif(p_data->>'notes',''),v_due,
          array[case when ctx.default_channel='apns' then 'apns' else 'email' end],'ui',array['sidegig:'||v_kind||':'||p_id::text]);
      insert into sidegig_obligations(id,user_id,reminder_id,kind,title,person,notes,due_at,related_reminder_id,related_payment_id,amount,currency,reference)
        values(p_id,u,v_reminder,v_kind,v_title,nullif(p_data->>'person',''),nullif(p_data->>'notes',''),v_due,v_related,v_payment,v_amount,v_currency,nullif(p_data->>'reference',''));
    else
      update sidegig_obligations set title=v_title,person=nullif(p_data->>'person',''),notes=nullif(p_data->>'notes',''),due_at=v_due,
        related_reminder_id=v_related,related_payment_id=v_payment,amount=v_amount,currency=v_currency,reference=nullif(p_data->>'reference',''),updated_at=clock_timestamp() where id=p_id;
      update reminders set title=v_title,notes=nullif(p_data->>'notes',''),due_at=v_due,
        status='open',snoozed_until=null where id=v_reminder and user_id=u;
    end if;
    if coalesce((p_data->>'block_work')::boolean,false) then
      insert into sidegig_work_state(reminder_id,user_id,waiting) values(v_related,u,true)
        on conflict(reminder_id) do update set waiting=true,updated_at=clock_timestamp();
      update focus_assignments set state='cancelled',updated_at=clock_timestamp() where user_id=u and reminder_id=v_related and state='planned';
    end if;

  elsif p_action in ('contact','resolve','receive','cancel') then
    select * into o from sidegig_obligations where id=p_id and user_id=u for update;
    if not found then raise exception 'Commitment not found' using errcode='P0002'; end if;
    if o.state<>'open' then raise exception 'This commitment is already closed. Refresh to see its state.' using errcode='22023'; end if;
    if p_action='contact' then
      if o.kind<>'followup' then raise exception 'Choose a follow-up' using errcode='22023'; end if;
      v_due:=nullif(p_data->>'due_at','')::timestamptz;
      if v_due is null or v_due<=now() then raise exception 'Choose a future check-in time' using errcode='22023'; end if;
      update sidegig_obligations set due_at=v_due,last_contact_at=clock_timestamp(),updated_at=clock_timestamp() where id=p_id;
      update reminders set due_at=v_due,snoozed_until=null,status='open' where id=o.reminder_id;
    elsif p_action='resolve' then
      if o.kind<>'followup' then raise exception 'Record payments with Record received' using errcode='22023'; end if;
      update sidegig_obligations set state='resolved',updated_at=clock_timestamp() where id=p_id;
      update reminders set status='done',snoozed_until=null where id=o.reminder_id;
      if coalesce((p_data->>'unblock')::boolean,false) then
        if exists(select 1 from sidegig_obligations where user_id=u and related_reminder_id=o.related_reminder_id and id<>p_id and kind='followup' and state='open') then
          raise exception 'Other follow-ups are still open for this work' using errcode='22023'; end if;
        update sidegig_work_state set waiting=false,updated_at=clock_timestamp() where reminder_id=o.related_reminder_id and user_id=u;
      end if;
    elsif p_action='receive' then
      if o.kind<>'payment' then raise exception 'Choose an expected payment' using errcode='22023'; end if;
      v_date:=nullif(p_data->>'received_on','')::date;
      if v_date is null or v_date>(now() at time zone v_zone)::date then raise exception 'Choose today or an earlier received date' using errcode='22023'; end if;
      update sidegig_obligations set state='received',received_on=v_date,updated_at=clock_timestamp() where id=p_id;
      update reminders set status='done',snoozed_until=null where id=o.reminder_id;
      if coalesce((p_data->>'resolve_followup')::boolean,false) then
        update sidegig_obligations set state='resolved',updated_at=clock_timestamp() where user_id=u and related_payment_id=p_id and kind='followup' and state='open';
        update reminders set status='done',snoozed_until=null where user_id=u and id in (select reminder_id from sidegig_obligations where related_payment_id=p_id and state='resolved');
      end if;
    else
      update sidegig_obligations set state='cancelled',updated_at=clock_timestamp() where id=p_id;
      update reminders set status='cancelled',snoozed_until=null where id=o.reminder_id;
    end if;
    insert into sidegig_activity(user_id,obligation_id,action,notes) values(u,p_id,p_action,nullif(p_data->>'notes',''));

  elsif p_action in ('ship','shipping','complete','reopen_order') then
    select * into r from reminders where id=p_id and user_id=u for update;
    if not found then raise exception 'Reminder not found' using errcode='P0002'; end if;
    if p_action='complete' then
      if r.context_id<>ctx.id or r.is_order or exists(select 1 from sidegig_obligations where reminder_id=p_id) then raise exception 'Use this commitment’s completion action' using errcode='22023'; end if;
      update reminders set status='done',snoozed_until=null where id=p_id;
    else
      if not r.is_order or not exists(select 1 from orders where reminder_id=p_id and user_id=u) then raise exception 'Order not found' using errcode='P0002'; end if;
      if p_action='reopen_order' then
        if exists(select 1 from orders where reminder_id=p_id and shipped_at is not null) then raise exception 'This order is already shipped' using errcode='22023'; end if;
        update reminders set status='open',snoozed_until=null where id=p_id;
      else
        if char_length(coalesce(p_data->>'tracking',''))>64 then raise exception 'Keep tracking to 64 characters' using errcode='22023'; end if;
        if p_action='ship' and not exists(select 1 from orders where reminder_id=p_id and shipped_at is not null) then
          if r.status not in ('open','snoozed') then raise exception 'Reopen this order before recording shipment' using errcode='22023'; end if;
          perform public.mark_shipped(p_id,coalesce(p_data->>'tracking',''),coalesce(p_data->>'carrier',''));
        elsif p_action='shipping' then
          update orders set carrier=nullif(p_data->>'carrier',''),tracking_number=nullif(p_data->>'tracking','') where reminder_id=p_id;
        end if;
      end if;
    end if;
  else raise exception 'Unknown Side Gig action' using errcode='22023'; end if;
  insert into sidegig_operations(id,user_id,action,target_id,payload_hash) values(p_operation_id,u,p_action,p_id,md5(p_data::text));
  return p_id;
end $$;

-- Keep generic/older clients honest: a payment cannot become "received" merely
-- because someone checked its reminder. Cancellation/deletion preserves history.
create function public.sidegig_reminder_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare o sidegig_obligations%rowtype;
begin
  select * into o from sidegig_obligations where reminder_id=old.id;
  if not found then return case when tg_op='DELETE' then old else new end; end if;
  if tg_op='DELETE' then
    update sidegig_obligations set reminder_id=null,state=case when state='open' then 'cancelled' else state end,updated_at=clock_timestamp() where id=o.id;
    return old;
  end if;
  if new.user_id<>old.user_id or new.context_id<>old.context_id or new.is_order then raise exception 'Keep this commitment in Side Gig' using errcode='22023'; end if;
  if o.kind='payment' and o.state='open' and new.status='done' then raise exception 'Record payment received in Side Gig' using errcode='22023'; end if;
  if o.state<>'open' and new.status in ('open','snoozed') then raise exception 'This commitment is closed. Create a new commitment.' using errcode='22023'; end if;
  update sidegig_obligations set title=new.title,notes=new.notes,due_at=coalesce(new.due_at,due_at),
    state=case when new.status='cancelled' and state='open' then 'cancelled' when new.status='done' and kind='followup' and state='open' then 'resolved' else state end,
    updated_at=clock_timestamp() where id=o.id;
  -- An empty channel list means "use context default" in the delivery system.
  -- Hold the delivery timestamp as well; the independent expected date above
  -- remains visible and editable while its collection follow-up owns delivery.
  if o.kind='payment' and exists(select 1 from sidegig_obligations where related_payment_id=o.id and kind='followup' and state='open') then
    new.due_at:=null; new.snoozed_until:=null;
  end if;
  return new;
end $$;
create trigger sidegig_reminder_guard before update or delete on public.reminders for each row execute function public.sidegig_reminder_guard();
-- A collection follow-up becomes the single delivery source for that payment.
-- Restore the exact prior channel selection when the follow-up closes or moves.
create function public.sidegig_collection_delivery() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare payment uuid; p sidegig_obligations%rowtype; ids uuid[];
begin
  if tg_op='INSERT' then ids:=array[new.related_payment_id];
  else ids:=array[old.related_payment_id,new.related_payment_id]; end if;
  foreach payment in array ids loop
    if payment is null then continue; end if;
    select * into p from sidegig_obligations where id=payment and kind='payment';
    if not found then continue; end if;
    if exists(select 1 from sidegig_obligations where related_payment_id=payment and kind='followup' and state='open') then
      if p.held_channels is null then
        update sidegig_obligations set held_channels=(select channels from reminders where id=p.reminder_id),
          held_snoozed_until=(select snoozed_until from reminders where id=p.reminder_id) where id=payment;
      end if;
      update reminders set channels='{}',due_at=null,snoozed_until=null where id=p.reminder_id
        and (cardinality(channels)>0 or due_at is not null or snoozed_until is not null);
    elsif p.held_channels is not null then
      update reminders set channels=p.held_channels,due_at=p.due_at,snoozed_until=p.held_snoozed_until where id=p.reminder_id;
      update sidegig_obligations set held_channels=null,held_snoozed_until=null where id=payment;
    end if;
  end loop;
  return new;
end $$;
create trigger sidegig_collection_delivery after insert or update of state,related_payment_id on public.sidegig_obligations
  for each row when(new.kind='followup') execute function public.sidegig_collection_delivery();
create function public.sidegig_focus_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if exists(select 1 from sidegig_obligations where reminder_id=new.reminder_id) or
    exists(select 1 from sidegig_work_state where reminder_id=new.reminder_id and waiting) then
    raise exception 'Choose actionable work, or resolve its waiting follow-up first' using errcode='22023'; end if;
  return new;
end $$;
create trigger sidegig_session_guard before insert on public.focus_sessions for each row execute function public.sidegig_focus_guard();
create trigger sidegig_assignment_guard before insert or update on public.focus_assignments for each row when(new.state in ('planned','in_progress')) execute function public.sidegig_focus_guard();

-- Old shipping sheets still call this signature. Side Gig buyer follow-ups now
-- enter the same typed workflow; other contexts retain the existing behavior.
create or replace function public.create_follow_up(p_reminder_id uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid(); r reminders%rowtype; zone text; slug text; v_result uuid; due timestamptz;
begin
  if u is null then raise exception 'Sign in required' using errcode='28000'; end if;
  perform pg_advisory_xact_lock(hashtextextended(u::text,18018));
  select * into r from reminders where reminders.id=p_reminder_id and user_id=u;
  if not found then raise exception 'Reminder not found' using errcode='P0002'; end if;
  select c.slug into slug from contexts c where c.id=r.context_id and c.user_id=u;
  select coalesce((select timezone from user_settings where user_id=u),'UTC') into zone;
  due:=((now() at time zone zone)+interval '3 days') at time zone zone;
  if slug='sidegig' then
    select reminder_id into v_result from sidegig_obligations where user_id=u and related_reminder_id=r.id and kind='followup' and state='open' order by created_at limit 1;
    if v_result is not null then return v_result; end if;
    v_result:=gen_random_uuid();
    perform sidegig_mutate(gen_random_uuid(),'save_followup',v_result,jsonb_build_object('title','Follow up: '||r.title,'due_at',due,'related_id',r.id));
    return (select reminder_id from sidegig_obligations where sidegig_obligations.id=v_result and user_id=u);
  end if;
  insert into reminders(user_id,context_id,title,due_at,created_by) values(u,r.context_id,'Follow up: '||r.title,due,'ui') returning reminders.id into v_result;
  return v_result;
end $$;

create function public.get_sidegig_dashboard() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid(); zone text; work jsonb; obligations jsonb;
begin
  if u is null then raise exception 'Sign in required' using errcode='28000'; end if;
  select coalesce((select timezone from user_settings where user_id=u),'UTC') into zone;
  select coalesce(jsonb_agg(x.item order by x.sort_due nulls last,x.id),'[]') into work from (
    select r.id,coalesce(o.ship_by::timestamp at time zone zone,r.due_at) sort_due,jsonb_build_object(
      'id',r.id,'reminder_id',r.id,'kind',case when r.is_order then 'order' else 'work' end,
      'title',r.title,'notes',r.notes,'due_at',r.due_at,'status',r.status,'channels',r.channels,
      'person',coalesce(o.recipient_name,d.client_name),'initiative',d.initiative_name,'context_slug',c.slug,
      'next_step',case when w.next_step_at is not null and (s.finished_at is null or w.next_step_at>s.finished_at) then w.next_step else s.next_step end,
      'next_step_source',case when w.next_step_at is not null and (s.finished_at is null or w.next_step_at>s.finished_at) then 'current' else 'session' end,
      'last_worked_at',s.finished_at,'waiting',coalesce(w.waiting,false),'minutes',coalesce(w.minutes,15),
      'reference',o.order_ref,'ship_by',o.ship_by,'carrier',o.carrier,'tracking',o.tracking_number,'shipped_at',o.shipped_at,
      'updated_at',r.updated_at) item
    from reminders r join contexts c on c.id=r.context_id and c.user_id=u
      left join orders o on o.reminder_id=r.id and o.user_id=u
      left join sidegig_details d on d.reminder_id=r.id and d.user_id=u
      left join sidegig_work_state w on w.reminder_id=r.id and w.user_id=u
      left join lateral(select finished_at,next_step from focus_sessions where reminder_id=r.id and user_id=u and finished_at is not null order by finished_at desc,id desc limit 1) s on true
    where r.user_id=u and (c.slug='sidegig' or r.is_order) and not exists(select 1 from sidegig_obligations where reminder_id=r.id)
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'reminder_id',o.reminder_id,'kind',o.kind,'title',o.title,'notes',o.notes,'person',o.person,
    'due_at',o.due_at,'status',o.state,'related_id',o.related_reminder_id,'related_payment_id',o.related_payment_id,
    'amount',o.amount::text,'currency',o.currency,'reference',o.reference,'last_contact_at',o.last_contact_at,'received_on',o.received_on,
    'context_slug','sidegig','updated_at',o.updated_at,
    'activity',coalesce((select jsonb_agg(a.j order by a.at desc) from(select happened_at at,jsonb_build_object('action',action,'notes',notes,'happened_at',happened_at) j from sidegig_activity where obligation_id=o.id and user_id=u order by happened_at desc limit 20) a),'[]'::jsonb)
  ) order by o.due_at,o.id),'[]') into obligations from sidegig_obligations o where o.user_id=u;
  return jsonb_build_object('timezone',zone,'local_date',(now() at time zone zone)::date,'items',work||obligations,'api',18);
end $$;
revoke all on function public.sidegig_mutate(uuid,text,uuid,jsonb),public.get_sidegig_dashboard(),public.sidegig_reminder_guard(),public.sidegig_focus_guard(),public.sidegig_collection_delivery() from public,anon,authenticated;
grant execute on function public.sidegig_mutate(uuid,text,uuid,jsonb),public.get_sidegig_dashboard() to authenticated;
alter publication supabase_realtime add table public.sidegig_work_state,public.sidegig_obligations,public.sidegig_activity;
commit;
