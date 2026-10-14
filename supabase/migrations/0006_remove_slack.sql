-- ezyReminder — remove Slack as a delivery channel (decided 2026-10)
-- Delivery is now: on-device + APNs notifications (Flutter iOS app, coming)
-- with email as the fallback. Slack's OAuth routes and adapter are deleted;
-- this drops its table and moves any Slack-routed data onto email.

-- ─────────────────────────────────────────────────────────────────────────
-- Data: reroute Slack → email
-- ─────────────────────────────────────────────────────────────────────────
update contexts set default_channel = 'email' where default_channel = 'slack';

update reminders
set channels = case
  when 'email' = any (array_remove(channels, 'slack')) then array_remove(channels, 'slack')
  else array_append(array_remove(channels, 'slack'), 'email')
end
where 'slack' = any (channels);

-- Slack delivery history has no channel to point at any more.
delete from notifications where channel = 'slack';

-- ─────────────────────────────────────────────────────────────────────────
-- Constraints: Slack is no longer a valid channel
-- ─────────────────────────────────────────────────────────────────────────
alter table contexts drop constraint contexts_default_channel_check;
alter table contexts add constraint contexts_default_channel_check
  check (default_channel in ('email', 'whatsapp'));

alter table notifications drop constraint notifications_channel_check;
alter table notifications add constraint notifications_channel_check
  check (channel in ('email', 'whatsapp'));

drop table slack_integrations;

-- ─────────────────────────────────────────────────────────────────────────
-- New-user seed: Work defaults to email instead of Slack
-- ─────────────────────────────────────────────────────────────────────────
create or replace function handle_new_user_contexts()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  with new_contexts as (
    insert into public.contexts (user_id, name, slug, color, default_channel, quiet_hours)
    values
      (new.id, 'Work', 'work', '#3478F6', 'email', '{"start": "18:00", "end": "08:00"}'::jsonb),
      (new.id, 'Side Gig', 'sidegig', '#F5A623', 'email', '{"start": "21:00", "end": "08:00"}'::jsonb),
      (new.id, 'Social', 'social', '#34C759', 'whatsapp', '{"start": "22:00", "end": "09:00"}'::jsonb),
      (new.id, 'Shopping', 'shopping', '#AF52DE', 'email', '{}'::jsonb)
    returning id, slug
  )
  insert into public.reminders (user_id, context_id, title, notes, due_at, channels, is_order)
  select
    new.id,
    nc.id,
    case nc.slug
      when 'work' then 'Example: reply to your manager'
      when 'sidegig' then 'Example: ship-by date for an order'
      when 'social' then 'Example: text a friend back'
      when 'shopping' then 'Example: grocery run'
    end,
    'This is an example reminder — mark it done or delete it whenever.',
    now() + interval '2 hours',
    '{}'::text[],
    false
  from new_contexts nc;

  return new;
end;
$$;
