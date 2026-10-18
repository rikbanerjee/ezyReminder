-- After a successful email, repeat only after six hours until completion.
-- Requires 0009's durable occurrence identity and matching sweep deployment.
-- Pause cron and let any in-flight sweep finish before applying pending fixes.
begin;

create or replace function public.auto_snooze_after_email()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.channel <> 'email' or new.status <> 'sent' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'sent' then
    return new;
  end if;
  if new.superseded_at is not null then
    return new;
  end if;

  -- The notification result and the next reminder time commit together.
  -- A completion, explicit snooze, reschedule or channel change made while the
  -- provider request was in flight wins over automatic snoozing. The row lock
  -- taken by UPDATE serializes competing delivery completions.
  update reminders r
  set status = 'snoozed',
      snoozed_until = clock_timestamp() + interval '6 hours'
  where r.id = new.reminder_id
    and r.user_id = new.user_id
    and r.status in ('open', 'snoozed')
    and coalesce(r.snoozed_until, r.due_at) = new.occurrence_at
    and coalesce(r.snoozed_until, r.due_at) <= now()
    and 'email' = any (
      case when cardinality(r.channels) > 0 then r.channels
        else array[(select c.default_channel from contexts c where c.id = r.context_id)]
      end
    );
  return new;
end;
$$;

revoke all on function public.auto_snooze_after_email() from public, anon, authenticated;
create trigger notifications_auto_snooze_email
  after insert or update of status on public.notifications
  for each row execute function public.auto_snooze_after_email();

-- Stop an already-running repeat storm without waiting for one more email.
-- Retain the original due date. Anchor to the most recent successful delivery
-- of this exact occurrence, including duplicate audit rows retired by 0009.
-- Never override a future explicit snooze, a new due version, or completion.
with latest_sent as (
  select r.id, max(coalesce(n.sent_at, n.updated_at, n.created_at)) as last_sent_at
  from reminders r
  join notifications n on n.reminder_id = r.id and n.user_id = r.user_id
    and n.occurrence_at = coalesce(r.snoozed_until, r.due_at)
  where r.status in ('open', 'snoozed')
    and coalesce(r.snoozed_until, r.due_at) <= now()
    and n.channel = 'email' and n.status = 'sent'
    and coalesce(n.sent_at, n.updated_at, n.created_at) <= now()
    and 'email' = any (
      case when cardinality(r.channels) > 0 then r.channels
        else array[(select c.default_channel from contexts c where c.id = r.context_id)]
      end
    )
  group by r.id
)
update reminders r
set status = 'snoozed', snoozed_until = s.last_sent_at + interval '6 hours'
from latest_sent s
where r.id = s.id and s.last_sent_at > now() - interval '6 hours';

-- Retire old queued work for the reminders just moved to their next occurrence.
update notifications n
set superseded_at = now()
from reminders r
where r.id = n.reminder_id and r.user_id = n.user_id
  and n.status in ('pending', 'retrying') and n.superseded_at is null
  and n.occurrence_at is distinct from coalesce(r.snoozed_until, r.due_at);

commit;

-- Rollback (manual only):
-- drop trigger notifications_auto_snooze_email on public.notifications;
-- drop function public.auto_snooze_after_email();
-- Existing automatic snoozes remain until they expire or the user edits them.
