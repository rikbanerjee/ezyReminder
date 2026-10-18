-- Durable notification occurrence identity. scheduled_for remains mutable for
-- quiet-hour deferrals and retry backoff; occurrence_at remains the immutable
-- reminder/channel/due-version key for the lifetime of the audit row.
-- Pause the human pg_cron invocation of the notification sweep before applying
-- this migration, then redeploy the sweep that is compatible with this schema.
begin;

lock table notifications in access exclusive mode;

alter table notifications add column occurrence_at timestamptz;
alter table notifications add column superseded_at timestamptz;
alter table notifications add column delivery_started_at timestamptz;

-- Historical outcomes and retry counters prove that a provider attempt began;
-- use creation time as a conservative age bound. Pending/retrying rows with no
-- attempts (for example, quiet-hour deferrals) remain eligible indefinitely.
update notifications
set delivery_started_at = created_at
where status in ('sent', 'sending', 'failed') or attempt_count > 0;

-- Existing rows initially identify their occurrence by the old scheduled_for
-- value. For active reminders, a moved schedule at or after creation is likely
-- a deferral/retry mutation of the reminder's current due version; fold those
-- rows into that version so the new unique key collapses retry duplicates.
-- This cannot distinguish a true reminder reschedule from an old deferred row
-- using the legacy schema alone. It intentionally favors the current due version
-- for active reminders; all old rows remain present as audit records.
update notifications set occurrence_at = scheduled_for;
update notifications n
set occurrence_at = coalesce(r.snoozed_until, r.due_at)
from reminders r
where r.id = n.reminder_id
  and r.status in ('open', 'snoozed')
  and coalesce(r.snoozed_until, r.due_at) is not null
  and coalesce(r.snoozed_until, r.due_at) <= n.created_at
  and coalesce(r.snoozed_until, r.due_at) <= n.scheduled_for;

-- Preserve every audit row; retain one active winner per inferred occurrence.
-- A sent row wins, then a sending row (avoids a potentially duplicate send),
-- then an exhausted failure; ties and all other statuses use earliest history.
with ranked as (
  select n.id,
    row_number() over (
      partition by n.reminder_id, n.channel, n.occurrence_at
      order by
        case
          when n.status = 'sent' then 0
          when n.status = 'sending' then 1
          when n.status = 'failed' and n.attempt_count >= 3 then 2
          else 3
        end,
        n.created_at,
        n.id
    ) as occurrence_rank
  from notifications n
)
update notifications n
set superseded_at = now()
from ranked r
where r.id = n.id and r.occurrence_rank > 1;

alter table notifications alter column occurrence_at set not null;

create or replace function preserve_notification_occurrence()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.occurrence_at := new.scheduled_for;
  elsif new.occurrence_at is distinct from old.occurrence_at then
    new.occurrence_at := old.occurrence_at;
  end if;
  if tg_op = 'UPDATE'
    and old.delivery_started_at is not null
    and new.delivery_started_at is distinct from old.delivery_started_at then
    new.delivery_started_at := old.delivery_started_at;
  end if;
  return new;
end;
$$;

create trigger notifications_preserve_occurrence
before insert or update on notifications
for each row execute function preserve_notification_occurrence();

create unique index notifications_active_occurrence_uidx
  on notifications (reminder_id, channel, occurrence_at)
  where superseded_at is null;
create index notifications_claim_active_idx
  on notifications (scheduled_for)
  where status in ('pending', 'retrying') and superseded_at is null;

create or replace function enqueue_due_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Retire queued occurrences when the reminder is completed/cancelled,
  -- rescheduled, or no longer routes through that channel. Sent and failed
  -- history stays attached to its original occurrence for audit/retry rules.
  update notifications n
  set superseded_at = now()
  from reminders r
  where r.id = n.reminder_id
    and n.superseded_at is null
    and n.status in ('pending', 'retrying')
    and (
      r.status not in ('open', 'snoozed')
      or coalesce(r.snoozed_until, r.due_at) is null
      or n.occurrence_at is distinct from coalesce(r.snoozed_until, r.due_at)
      or not (n.channel = any (
        case when cardinality(r.channels) > 0 then r.channels
          else array[(select c.default_channel from contexts c where c.id = r.context_id)]
        end
      ))
    );

  insert into notifications (user_id, reminder_id, channel, scheduled_for, occurrence_at)
  select distinct
    r.user_id,
    r.id,
    routed.channel,
    effective_due.due_at,
    effective_due.due_at
  from reminders r
  cross join lateral (
    select coalesce(r.snoozed_until, r.due_at) as due_at
  ) as effective_due
  cross join lateral unnest(
    case when cardinality(r.channels) > 0 then r.channels
      else array[(select c.default_channel from contexts c where c.id = r.context_id)]
    end
  ) as routed(channel)
  where r.status in ('open', 'snoozed')
    and effective_due.due_at is not null
    and effective_due.due_at <= now()
    -- A provider may have accepted an earlier attempt even if the row was
    -- later superseded. Never issue a new notification identity for that
    -- occurrence; the prior UUID is the provider idempotency key.
    and not exists (
      select 1
      from notifications history
      where history.reminder_id = r.id
        and history.channel = routed.channel
        and history.occurrence_at = effective_due.due_at
        and (
          history.status in ('sent', 'sending')
          or history.delivery_started_at is not null
        )
    )
  on conflict (reminder_id, channel, occurrence_at) where superseded_at is null
  do nothing;
end;
$$;

create or replace function claim_due_notifications(p_limit int default 25)
returns setof notifications
language plpgsql
security definer
set search_path = public
as $$
declare
  ids uuid[];
begin
  -- Resend's idempotency window is shorter than a possible manual retry delay.
  -- Stop automatic sends after 23 hours and require human confirmation.
  update notifications n
  set status = 'failed',
      error = 'delivery_confirmation_required',
      attempt_count = greatest(n.attempt_count, 3)
  where n.status in ('pending', 'retrying')
    and n.superseded_at is null
    and n.delivery_started_at <= now() - interval '23 hours';

  -- Keep claim safe when invoked without the normal enqueue-first sweep pass.
  update notifications n
  set superseded_at = now()
  from reminders r
  where r.id = n.reminder_id
    and n.superseded_at is null
    and n.status in ('pending', 'retrying')
    and (
      r.status not in ('open', 'snoozed')
      or coalesce(r.snoozed_until, r.due_at) is null
      or n.occurrence_at is distinct from coalesce(r.snoozed_until, r.due_at)
      or not (n.channel = any (
        case when cardinality(r.channels) > 0 then r.channels
          else array[(select c.default_channel from contexts c where c.id = r.context_id)]
        end
      ))
    );

  select array_agg(id) into ids from (
    select n.id
    from notifications n
    join reminders r on r.id = n.reminder_id
    where n.status in ('pending', 'retrying')
      and n.superseded_at is null
      and n.scheduled_for <= now()
      and r.status in ('open', 'snoozed')
      and n.occurrence_at = coalesce(r.snoozed_until, r.due_at)
      and n.channel = any (
        case when cardinality(r.channels) > 0 then r.channels
          else array[(select c.default_channel from contexts c where c.id = r.context_id)]
        end
      )
    order by n.scheduled_for
    for update of n skip locked
    limit p_limit
  ) t;

  if ids is null then
    return;
  end if;

  return query
    update notifications
    set status = 'sending', updated_at = now()
    where id = any(ids) and superseded_at is null
    returning *;
end;
$$;

create or replace function retry_notification(p_notification_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_notification_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  update notifications n
  set status = 'pending',
      scheduled_for = now(),
      attempt_count = 0,
      error = null
  where n.id = p_notification_id
    and n.user_id = v_user_id
    and n.status = 'failed'
    and n.superseded_at is null
    and (n.delivery_started_at is null or n.delivery_started_at > now() - interval '23 hours')
    and exists (
      select 1 from reminders r
      where r.id = n.reminder_id
        and r.user_id = v_user_id
        and r.status in ('open', 'snoozed')
        and coalesce(r.snoozed_until, r.due_at) = n.occurrence_at
        and n.channel = any (
          case when cardinality(r.channels) > 0 then r.channels
            else array[(select c.default_channel from contexts c where c.id = r.context_id)]
          end
        )
    )
  returning n.id into v_notification_id;

  if v_notification_id is null then
    raise exception 'Notification is not an eligible failed occurrence' using errcode = '55000';
  end if;
  return v_notification_id;
end;
$$;

revoke all on function retry_notification(uuid) from public, anon;
grant execute on function retry_notification(uuid) to authenticated;

-- Existing enqueue/claim grants are retained by CREATE OR REPLACE. The
-- service-role sweep remains the only caller of those cross-user functions.

commit;

-- Rollback (manual only; preserve notification audit rows):
-- begin;
-- drop function retry_notification(uuid);
-- -- Restore enqueue_due_notifications() from 0008 and claim_due_notifications(int)
-- -- from 0002 before removing occurrence columns/indexes; quiet-hours and
-- -- retry scheduling still use scheduled_for.
-- drop index notifications_claim_active_idx;
-- drop index notifications_active_occurrence_uidx;
-- drop trigger notifications_preserve_occurrence on notifications;
-- drop function preserve_notification_occurrence();
-- alter table notifications drop column superseded_at;
-- alter table notifications drop column occurrence_at;
-- alter table notifications drop column delivery_started_at;
-- commit;
