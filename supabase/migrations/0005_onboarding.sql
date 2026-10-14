-- ezyReminder — first-run onboarding (LAUNCH.md §3.3)
-- New users landed on an empty Today screen with no path to a delivery
-- channel. Adds: onboarded_at gate (app/page.tsx redirects to /onboarding
-- until set) and one example reminder per context so the list isn't empty
-- while they decide how to be reminded.

alter table user_settings add column onboarded_at timestamptz;

comment on column user_settings.onboarded_at is 'Set once the first-run /onboarding screen is completed or skipped. Null gates new users into it (see app/page.tsx).';

-- Redefine (again) to also seed one example reminder per new context —
-- same trigger, no need to touch its registration.
create or replace function handle_new_user_contexts()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  with new_contexts as (
    insert into public.contexts (user_id, name, slug, color, default_channel, quiet_hours)
    values
      (new.id, 'Work', 'work', '#3478F6', 'slack', '{"start": "18:00", "end": "08:00"}'::jsonb),
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
