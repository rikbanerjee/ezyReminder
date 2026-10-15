-- ezyReminder — shared web/iOS write primitives and iOS notification state.
-- This migration is additive; all RPCs run as the caller so RLS remains active.

begin;

-- APNs is an iOS delivery channel. Keep WhatsApp as the existing v1.5 stub.
alter table contexts drop constraint contexts_default_channel_check;
alter table contexts add constraint contexts_default_channel_check
  check (default_channel in ('email', 'whatsapp', 'apns'));
alter table notifications drop constraint notifications_channel_check;
alter table notifications add constraint notifications_channel_check
  check (channel in ('email', 'whatsapp', 'apns'));

-- Direct reminder writes must not use a foreign key to attach another user's
-- context: PostgreSQL FK checks do not apply the referenced table's RLS.
drop policy reminders_insert_own on reminders;
create policy reminders_insert_own on reminders for insert
  with check (
    auth.uid() = user_id and exists (
      select 1 from contexts c where c.id = context_id and c.user_id = auth.uid()
    )
  );
drop policy reminders_update_own on reminders;
create policy reminders_update_own on reminders for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id and exists (
      select 1 from contexts c where c.id = context_id and c.user_id = auth.uid()
    )
  );

-- iOS device registrations. Token uniqueness is global so one APNs token
-- cannot accidentally be registered to multiple accounts.
create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null unique,
  platform text not null default 'ios' check (platform = 'ios'),
  environment text not null check (environment in ('sandbox', 'production')),
  app_version text,
  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz,
  created_at timestamptz not null default now()
);
create index device_tokens_user_live_idx on device_tokens (user_id, last_seen_at desc)
  where disabled_at is null;
alter table device_tokens enable row level security;
create policy device_tokens_select_own on device_tokens for select using (auth.uid() = user_id);
create policy device_tokens_insert_own on device_tokens for insert with check (auth.uid() = user_id);
create policy device_tokens_update_own on device_tokens for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy device_tokens_delete_own on device_tokens for delete using (auth.uid() = user_id);

-- A local schedule acknowledges that one device already scheduled this due
-- time. The sweep compares fire_at with the reminder's current effective due time.
create table local_schedules (
  user_id uuid not null references auth.users (id) on delete cascade,
  reminder_id uuid not null references reminders (id) on delete cascade,
  device_token_id uuid not null references device_tokens (id) on delete cascade,
  fire_at timestamptz not null,
  scheduled_at timestamptz not null default now(),
  primary key (reminder_id, device_token_id)
);
create index local_schedules_due_idx on local_schedules (reminder_id, fire_at);
create index local_schedules_user_idx on local_schedules (user_id, scheduled_at desc);
alter table local_schedules enable row level security;
create policy local_schedules_select_own on local_schedules for select using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ) and exists (
    select 1 from device_tokens d where d.id = device_token_id and d.user_id = auth.uid()
  )
);
create policy local_schedules_insert_own on local_schedules for insert with check (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ) and exists (
    select 1 from device_tokens d where d.id = device_token_id and d.user_id = auth.uid()
  )
);
create policy local_schedules_update_own on local_schedules for update
  using (
    auth.uid() = user_id and exists (
      select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
    ) and exists (
      select 1 from device_tokens d where d.id = device_token_id and d.user_id = auth.uid()
    )
  )
  with check (
    auth.uid() = user_id and exists (
      select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
    ) and exists (
      select 1 from device_tokens d where d.id = device_token_id and d.user_id = auth.uid()
    )
  );
create policy local_schedules_delete_own on local_schedules for delete using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ) and exists (
    select 1 from device_tokens d where d.id = device_token_id and d.user_id = auth.uid()
  )
);

-- Direct child writes must belong to the authenticated parent, as well as
-- matching the denormalized user_id column.
drop policy notifications_select_own on notifications;
create policy notifications_select_own on notifications for select using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy notifications_insert_own on notifications;
create policy notifications_insert_own on notifications for insert with check (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy notifications_update_own on notifications;
create policy notifications_update_own on notifications for update
  using (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ))
  with check (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ));
drop policy notifications_delete_own on notifications;
create policy notifications_delete_own on notifications for delete using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);

drop policy orders_insert_own on orders;
drop policy orders_select_own on orders;
create policy orders_select_own on orders for select using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
create policy orders_insert_own on orders for insert with check (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid() and r.is_order
  )
);
drop policy orders_update_own on orders;
create policy orders_update_own on orders for update
  using (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ))
  with check (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid() and r.is_order
  ));
drop policy orders_delete_own on orders;
create policy orders_delete_own on orders for delete using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);

drop policy work_details_select_own on work_details;
create policy work_details_select_own on work_details for select using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy work_details_insert_own on work_details;
create policy work_details_insert_own on work_details for insert with check (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy work_details_update_own on work_details;
create policy work_details_update_own on work_details for update
  using (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ))
  with check (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ));
drop policy work_details_delete_own on work_details;
create policy work_details_delete_own on work_details for delete using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);

drop policy sidegig_details_select_own on sidegig_details;
create policy sidegig_details_select_own on sidegig_details for select using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy sidegig_details_insert_own on sidegig_details;
create policy sidegig_details_insert_own on sidegig_details for insert with check (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy sidegig_details_update_own on sidegig_details;
create policy sidegig_details_update_own on sidegig_details for update
  using (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ))
  with check (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ));
drop policy sidegig_details_delete_own on sidegig_details;
create policy sidegig_details_delete_own on sidegig_details for delete using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);

drop policy shopping_items_select_own on shopping_items;
create policy shopping_items_select_own on shopping_items for select using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy shopping_items_insert_own on shopping_items;
create policy shopping_items_insert_own on shopping_items for insert with check (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);
drop policy shopping_items_update_own on shopping_items;
create policy shopping_items_update_own on shopping_items for update
  using (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ))
  with check (auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  ));
drop policy shopping_items_delete_own on shopping_items;
create policy shopping_items_delete_own on shopping_items for delete using (
  auth.uid() = user_id and exists (
    select 1 from reminders r where r.id = reminder_id and r.user_id = auth.uid()
  )
);

create or replace function create_reminder(
  p_title text,
  p_notes text,
  p_due_at timestamptz,
  p_context_id uuid,
  p_channels text[],
  p_is_order boolean,
  p_order_ref text,
  p_recipient_name text,
  p_ship_by date,
  p_carrier text
) returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_reminder_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_context_id is null or not exists (
    select 1 from contexts c where c.id = p_context_id and c.user_id = v_user_id
  ) then raise exception 'Context not found' using errcode = '23503'; end if;
  if nullif(btrim(p_title), '') is null then raise exception 'Reminder title is required' using errcode = '22023'; end if;

  insert into reminders (user_id, context_id, title, notes, due_at, channels, is_order, created_by)
  values (v_user_id, p_context_id, btrim(p_title), p_notes, p_due_at,
    coalesce(p_channels, '{}'::text[]), coalesce(p_is_order, false), 'ui')
  returning id into v_reminder_id;

  if coalesce(p_is_order, false) then
    insert into orders (reminder_id, user_id, order_ref, recipient_name, ship_by, carrier)
    values (v_reminder_id, v_user_id, p_order_ref, p_recipient_name,
      coalesce(p_ship_by, (p_due_at at time zone 'UTC')::date), p_carrier);
  end if;
  return v_reminder_id;
end;
$$;

create or replace function update_reminder(
  p_id uuid,
  p_title text,
  p_notes text,
  p_due_at timestamptz,
  p_context_id uuid,
  p_channels text[],
  p_is_order boolean
) returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing_order orders%rowtype;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_context_id is null or not exists (
    select 1 from contexts c where c.id = p_context_id and c.user_id = v_user_id
  ) then raise exception 'Context not found' using errcode = '23503'; end if;
  if nullif(btrim(p_title), '') is null then raise exception 'Reminder title is required' using errcode = '22023'; end if;
  if not exists (select 1 from reminders r where r.id = p_id and r.user_id = v_user_id for update) then
    raise exception 'Reminder not found' using errcode = 'P0002';
  end if;

  update reminders set title = btrim(p_title), notes = p_notes, due_at = p_due_at,
    context_id = p_context_id, channels = coalesce(p_channels, '{}'::text[]),
    is_order = coalesce(p_is_order, false)
  where id = p_id and user_id = v_user_id;

  if coalesce(p_is_order, false) then
    select * into v_existing_order from orders o where o.reminder_id = p_id and o.user_id = v_user_id for update;
    if not found then
      insert into orders (reminder_id, user_id, ship_by)
      values (p_id, v_user_id, (p_due_at at time zone 'UTC')::date);
    end if;
  else
    delete from orders where reminder_id = p_id and user_id = v_user_id;
  end if;
  return p_id;
end;
$$;

create or replace function mark_shipped(
  p_reminder_id uuid,
  p_tracking_number text,
  p_carrier text
) returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if not exists (
    select 1 from reminders r
    join contexts c on c.id = r.context_id
    join orders o on o.reminder_id = r.id
    where r.id = p_reminder_id and r.user_id = v_user_id
      and c.user_id = v_user_id and o.user_id = v_user_id
    for update of r, o
  ) then raise exception 'Order reminder not found' using errcode = 'P0002'; end if;

  update orders set shipped_at = now(), tracking_number = nullif(p_tracking_number, ''),
    carrier = nullif(p_carrier, '')
  where reminder_id = p_reminder_id and user_id = v_user_id;
  update reminders set status = 'done', snoozed_until = null
  where id = p_reminder_id and user_id = v_user_id;
  return p_reminder_id;
end;
$$;

create or replace function create_follow_up(p_reminder_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_source reminders%rowtype;
  v_timezone text;
  v_new_id uuid;
  v_due_at timestamptz;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select * into v_source from reminders r
  where r.id = p_reminder_id and r.user_id = v_user_id;
  if not found then raise exception 'Reminder not found' using errcode = 'P0002'; end if;
  if not exists (select 1 from contexts c where c.id = v_source.context_id and c.user_id = v_user_id) then
    raise exception 'Context not found' using errcode = '23503';
  end if;

  select coalesce((select s.timezone from user_settings s where s.user_id = v_user_id), 'UTC')
    into v_timezone;
  -- Preserve the current wall-clock time and advance by three local calendar days.
  v_due_at := ((now() at time zone v_timezone) + interval '3 days') at time zone v_timezone;
  insert into reminders (user_id, context_id, title, due_at, created_by)
  values (v_user_id, v_source.context_id, 'Follow up: ' || v_source.title, v_due_at, 'ui')
  returning id into v_new_id;
  return v_new_id;
end;
$$;

create or replace function add_shopping_item(p_reminder_id uuid, p_label text)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_position integer;
  v_item_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if nullif(btrim(p_label), '') is null then raise exception 'Item label is required' using errcode = '22023'; end if;
  perform 1 from reminders r join contexts c on c.id = r.context_id
  where r.id = p_reminder_id and r.user_id = v_user_id
    and c.user_id = v_user_id and c.slug = 'shopping'
  for update of r;
  if not found then raise exception 'Shopping list not found' using errcode = 'P0002'; end if;

  select coalesce(max(i.position), -1) + 1 into v_position
  from shopping_items i where i.reminder_id = p_reminder_id and i.user_id = v_user_id;
  insert into shopping_items (reminder_id, user_id, label, position)
  values (p_reminder_id, v_user_id, btrim(p_label), v_position)
  returning id into v_item_id;
  return v_item_id;
end;
$$;

revoke all on function create_reminder(text, text, timestamptz, uuid, text[], boolean, text, text, date, text) from public, anon;
revoke all on function update_reminder(uuid, text, text, timestamptz, uuid, text[], boolean) from public, anon;
revoke all on function mark_shipped(uuid, text, text) from public, anon;
revoke all on function create_follow_up(uuid) from public, anon;
revoke all on function add_shopping_item(uuid, text) from public, anon;
grant execute on function create_reminder(text, text, timestamptz, uuid, text[], boolean, text, text, date, text) to authenticated;
grant execute on function update_reminder(uuid, text, text, timestamptz, uuid, text[], boolean) to authenticated;
grant execute on function mark_shipped(uuid, text, text) to authenticated;
grant execute on function create_follow_up(uuid) to authenticated;
grant execute on function add_shopping_item(uuid, text) to authenticated;

-- Enable row-change events for both clients. REPLICA IDENTITY FULL gives
-- DELETE subscribers the previous row fields needed to identify the record.
alter table reminders replica identity full;
alter table orders replica identity full;
alter table shopping_items replica identity full;
alter table work_details replica identity full;
alter table sidegig_details replica identity full;
alter table contexts replica identity full;
do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Expected Supabase publication supabase_realtime is missing';
  end if;
  foreach v_table in array array['reminders','orders','shopping_items','work_details','sidegig_details','contexts'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;

commit;

-- Rollback (run manually only if this migration must be reverted):
-- begin;
-- Before applying this migration, capture the existing publication membership:
-- select schemaname, tablename from pg_publication_tables where pubname = 'supabase_realtime';
-- Also capture existing replica identity settings for the six tables below.
-- select n.nspname, c.relname, c.relreplident from pg_class c
-- join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relname in ('reminders','orders','shopping_items','work_details','sidegig_details','contexts');
-- On rollback, drop from supabase_realtime only tables absent from that captured set.
-- This project baseline had none of the six tables in the publication, so the following
-- is safe only while that baseline remains true:
-- alter publication supabase_realtime drop table reminders, orders, shopping_items, work_details, sidegig_details, contexts;
-- Restore each replica identity to its captured setting; DEFAULT below matches the current baseline.
-- alter table reminders replica identity default;
-- alter table orders replica identity default;
-- alter table shopping_items replica identity default;
-- alter table work_details replica identity default;
-- alter table sidegig_details replica identity default;
-- alter table contexts replica identity default;
-- drop function add_shopping_item(uuid, text);
-- drop function create_follow_up(uuid);
-- drop function mark_shipped(uuid, text, text);
-- drop function update_reminder(uuid, text, text, timestamptz, uuid, text[], boolean);
-- drop function create_reminder(text, text, timestamptz, uuid, text[], boolean, text, text, date, text);
-- drop table local_schedules;
-- drop table device_tokens;
-- alter table contexts drop constraint contexts_default_channel_check;
-- alter table contexts add constraint contexts_default_channel_check check (default_channel in ('email', 'whatsapp'));
-- alter table notifications drop constraint notifications_channel_check;
-- alter table notifications add constraint notifications_channel_check check (channel in ('email', 'whatsapp'));
-- drop policy notifications_select_own on notifications;
-- create policy notifications_select_own on notifications for select using (auth.uid() = user_id);
-- drop policy notifications_insert_own on notifications;
-- create policy notifications_insert_own on notifications for insert with check (auth.uid() = user_id);
-- drop policy notifications_update_own on notifications;
-- create policy notifications_update_own on notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- drop policy notifications_delete_own on notifications;
-- create policy notifications_delete_own on notifications for delete using (auth.uid() = user_id);
-- drop policy reminders_insert_own on reminders;
-- create policy reminders_insert_own on reminders for insert with check (auth.uid() = user_id);
-- drop policy reminders_update_own on reminders;
-- create policy reminders_update_own on reminders for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- drop policy orders_select_own on orders;
-- create policy orders_select_own on orders for select using (auth.uid() = user_id);
-- drop policy orders_insert_own on orders;
-- create policy orders_insert_own on orders for insert with check (auth.uid() = user_id);
-- drop policy orders_update_own on orders;
-- create policy orders_update_own on orders for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- drop policy orders_delete_own on orders;
-- create policy orders_delete_own on orders for delete using (auth.uid() = user_id);
-- drop policy work_details_select_own on work_details;
-- create policy work_details_select_own on work_details for select using (auth.uid() = user_id);
-- drop policy work_details_insert_own on work_details;
-- create policy work_details_insert_own on work_details for insert with check (auth.uid() = user_id);
-- drop policy work_details_update_own on work_details;
-- create policy work_details_update_own on work_details for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- drop policy work_details_delete_own on work_details;
-- create policy work_details_delete_own on work_details for delete using (auth.uid() = user_id);
-- drop policy sidegig_details_select_own on sidegig_details;
-- create policy sidegig_details_select_own on sidegig_details for select using (auth.uid() = user_id);
-- drop policy sidegig_details_insert_own on sidegig_details;
-- create policy sidegig_details_insert_own on sidegig_details for insert with check (auth.uid() = user_id);
-- drop policy sidegig_details_update_own on sidegig_details;
-- create policy sidegig_details_update_own on sidegig_details for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- drop policy sidegig_details_delete_own on sidegig_details;
-- create policy sidegig_details_delete_own on sidegig_details for delete using (auth.uid() = user_id);
-- drop policy shopping_items_select_own on shopping_items;
-- create policy shopping_items_select_own on shopping_items for select using (auth.uid() = user_id);
-- drop policy shopping_items_insert_own on shopping_items;
-- create policy shopping_items_insert_own on shopping_items for insert with check (auth.uid() = user_id);
-- drop policy shopping_items_update_own on shopping_items;
-- create policy shopping_items_update_own on shopping_items for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- drop policy shopping_items_delete_own on shopping_items;
-- create policy shopping_items_delete_own on shopping_items for delete using (auth.uid() = user_id);
-- commit;
