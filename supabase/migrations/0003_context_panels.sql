-- ezyReminder — context-specific detail panels (PLAN.md §3.1, DESIGN.md §4.2)
-- Same pattern as `orders`: optional 1:1 detail row, denormalized user_id
-- for a direct RLS check (no join needed), toggle-reveal in the sheet.

-- ─────────────────────────────────────────────────────────────────────────
-- work_details — "who do I follow up with / what project is this"
-- ─────────────────────────────────────────────────────────────────────────
create table work_details (
  reminder_id uuid primary key references reminders (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  manager_name text,
  department_resource text,
  project_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table work_details is 'Optional follow-up panel for Work-context reminders (PLAN.md §3.1).';

create trigger work_details_set_updated_at before update on work_details
  for each row execute function set_updated_at();

alter table work_details enable row level security;

create policy "work_details_select_own" on work_details for select using (auth.uid() = user_id);
create policy "work_details_insert_own" on work_details for insert with check (auth.uid() = user_id);
create policy "work_details_update_own" on work_details for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "work_details_delete_own" on work_details for delete using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- sidegig_details — lighter panel; only for non-order Side Gig reminders
-- (order-flagged reminders use `orders`, not this)
-- ─────────────────────────────────────────────────────────────────────────
create table sidegig_details (
  reminder_id uuid primary key references reminders (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  initiative_name text,
  client_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table sidegig_details is 'Optional initiative panel for non-order Side Gig reminders (PLAN.md §3.1).';

create trigger sidegig_details_set_updated_at before update on sidegig_details
  for each row execute function set_updated_at();

alter table sidegig_details enable row level security;

create policy "sidegig_details_select_own" on sidegig_details for select using (auth.uid() = user_id);
create policy "sidegig_details_insert_own" on sidegig_details for insert with check (auth.uid() = user_id);
create policy "sidegig_details_update_own" on sidegig_details for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "sidegig_details_delete_own" on sidegig_details for delete using (auth.uid() = user_id);
