-- easyReminder — Shopping context + checklist items (PLAN.md §3.1, §8, DESIGN.md §2/§4.2.1)

-- ─────────────────────────────────────────────────────────────────────────
-- shopping_items — children of a Shopping-context reminder; the reminder's
-- title is the list name (e.g. "Costco run"), items are the checklist.
-- ─────────────────────────────────────────────────────────────────────────
create table shopping_items (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references reminders (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  label text not null,
  checked boolean not null default false,
  position int not null,
  created_at timestamptz not null default now()
);

create index shopping_items_reminder_idx on shopping_items (reminder_id, position);

comment on table shopping_items is 'Checklist items for a Shopping-context reminder (PLAN.md §3.1). Each add/check/delete is an instant write, no batch save.';

alter table shopping_items enable row level security;

create policy "shopping_items_select_own" on shopping_items for select using (auth.uid() = user_id);
create policy "shopping_items_insert_own" on shopping_items for insert with check (auth.uid() = user_id);
create policy "shopping_items_update_own" on shopping_items for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "shopping_items_delete_own" on shopping_items for delete using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- Seed Shopping alongside Work/Side Gig/Social for new users (extends the
-- 0001_init.sql trigger function — same trigger, no need to redefine it).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function handle_new_user_contexts()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.contexts (user_id, name, slug, color, default_channel, quiet_hours)
  values
    (new.id, 'Work', 'work', '#3478F6', 'slack', '{"start": "18:00", "end": "08:00"}'::jsonb),
    (new.id, 'Side Gig', 'sidegig', '#F5A623', 'email', '{"start": "21:00", "end": "08:00"}'::jsonb),
    (new.id, 'Social', 'social', '#34C759', 'whatsapp', '{"start": "22:00", "end": "09:00"}'::jsonb),
    (new.id, 'Shopping', 'shopping', '#AF52DE', 'email', '{}'::jsonb);
  return new;
end;
$$;

-- Backfill Shopping for users created before this migration.
insert into contexts (user_id, name, slug, color, default_channel, quiet_hours)
select u.id, 'Shopping', 'shopping', '#AF52DE', 'email', '{}'::jsonb
from auth.users u
where not exists (
  select 1 from contexts c where c.user_id = u.id and c.slug = 'shopping'
);
