-- Atomically edit a reminder and its existing order, including shipment-state
-- corrections. Ordinary reminder edits must not change shipped_at or status.
create or replace function public.edit_order_reminder(
  p_id uuid,
  p_title text,
  p_notes text,
  p_due_at timestamptz,
  p_context_id uuid,
  p_channels text[],
  p_order_ref text,
  p_recipient_name text,
  p_ship_by date,
  p_carrier text,
  p_tracking_number text,
  p_shipped boolean default null
) returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_reminder_status text;
  v_snoozed_until timestamptz;
  v_shipped_at timestamptz;
  v_order_found boolean;
  v_context_id uuid;
  v_title text := nullif(btrim(p_title), '');
  v_notes text := nullif(btrim(p_notes), '');
  v_order_ref text := nullif(btrim(p_order_ref), '');
  v_recipient_name text := nullif(btrim(p_recipient_name), '');
  v_carrier text := nullif(btrim(p_carrier), '');
  v_tracking_number text := nullif(btrim(p_tracking_number), '');
  v_tracking_limit integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if v_title is null then
    raise exception 'Reminder title is required' using errcode = '22023';
  end if;

  -- Lock parent first, then order, matching mark_shipped's lock order.
  select r.status, r.snoozed_until
    into v_reminder_status, v_snoozed_until
  from reminders r
  where r.id = p_id
    and r.user_id = v_user_id
    and r.is_order = true
  for update;
  if not found then
    raise exception 'Order reminder not found' using errcode = 'P0002';
  end if;

  select o.shipped_at
    into v_shipped_at
  from orders o
  where o.reminder_id = p_id
    and o.user_id = v_user_id
  for update;
  v_order_found := found;
  if not v_order_found then
    raise exception 'Order reminder not found' using errcode = 'P0002';
  end if;

  -- Lock and validate the destination context after the reminder and order.
  select c.id
    into v_context_id
  from contexts c
  where c.id = p_context_id
    and c.user_id = v_user_id
  for key share;
  if not found then
    raise exception 'Context not found' using errcode = '23503';
  end if;

  v_tracking_limit := case
    when upper(coalesce(v_carrier, '')) in ('UPS', 'USPS', 'FEDEX') then 34
    when upper(coalesce(v_carrier, '')) = 'DHL' then 39
    else 64
  end;
  if v_tracking_number is not null and char_length(v_tracking_number) > v_tracking_limit then
    raise exception 'Tracking number exceeds the limit for this carrier'
      using errcode = '22023';
  end if;

  update reminders
  set title = v_title,
      notes = v_notes,
      due_at = p_due_at,
      context_id = v_context_id,
      channels = coalesce(p_channels, '{}'::text[]),
      status = case
        when p_shipped is true then 'done'
        when p_shipped is false and v_shipped_at is not null then 'open'
        else v_reminder_status
      end,
      snoozed_until = case
        when p_shipped is true then null
        when p_shipped is false and v_shipped_at is not null then null
        else v_snoozed_until
      end
  where id = p_id
    and user_id = v_user_id;

  update orders
  set order_ref = v_order_ref,
      recipient_name = v_recipient_name,
      ship_by = p_ship_by,
      carrier = v_carrier,
      tracking_number = v_tracking_number,
      shipped_at = case
        when p_shipped is true then coalesce(v_shipped_at, now())
        when p_shipped is false then null
        else v_shipped_at
      end
  where reminder_id = p_id
    and user_id = v_user_id;

  return p_id;
end;
$$;

revoke all on function public.edit_order_reminder(
  uuid, text, text, timestamptz, uuid, text[], text, text, date, text, text, boolean
) from public, anon;
grant execute on function public.edit_order_reminder(
  uuid, text, text, timestamptz, uuid, text[], text, text, date, text, text, boolean
) to authenticated;

-- Rollback (manual only):
-- drop function public.edit_order_reminder(
--   uuid, text, text, timestamptz, uuid, text[], text, text, date, text, text, boolean
-- );
