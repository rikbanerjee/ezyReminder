# Hosted migration status

Verified 2026-10-18 on linked project `ezyReminder` (`ojfmtxcrfmyygwfjibwk`).

Rik explicitly authorized applying database migrations in this chat. The reviewed dry run identified only 0010–0012 as missing; 0001–0009 and 0013 were already applied. All three isolated PostgreSQL suites (shipment edits, Home maintenance, Focus) passed before the push. A fixed snapshot was applied with `supabase db push --linked --include-all --yes`.

Hosted migration history now contains every version 0001–0014. Do not edit or reapply these files; use the next unused number, starting with 0015.

Verified after application:

- `edit_order_reminder`, Home RPCs, and Focus RPCs exist, allow authenticated execution, and deny anonymous execution.
- `home_maintenance`, `home_service_records`, `focus_highlights`, and `focus_sessions` have RLS enabled and participate in Supabase Realtime.
- Existing `notification-sweep` cron job 1 is active on `*/5 * * * *`; this rollout did not modify the scheduler.
- No sample reminders, service records, focus sessions, or provider test emails were created.

Web/iOS deployment and real authenticated phone/browser delivery/sync checks remain separate release steps.

Applied file SHA-256 values (source verified identical to the applied snapshot):

| Migration | SHA-256 |
|---|---|
| `0010_edit_order_reminder.sql` | `10436d084eecc28a3bda9b20048571a5edd430c9bff4a7349ec102177e88ea90` |
| `0011_home_maintenance.sql` | `ce04cf7200f3e0bf7bd298b6ccd8bda59ec9c36c54737dbad37d98afa6836ece` |
| `0012_focus_sessions.sql` | `d86c9010a2d01fe88de910367872e61ccd35f03353055f5387d78dd121437bdf` |

## Contextual Home update — 2026-10-18

Applied `0014_contextual_home_tasks.sql` using the migration authorization already given in this chat. The dry run contained only 0014. Verified the new JSON detail columns, day-interval column, authenticated-only `save_home_task` RPC, retained RLS, recorded migration version, and active five-minute scheduler. Existing category/history rows were not rewritten or deleted. The old save RPC remains available.

Local checks: full 149-test Flutter suite, Flutter analysis, production web build, TypeScript/scoped lint, shared-template generation check, and extended Home SQL tests pass. SQL coverage includes legacy filter data, vehicle/history snapshots, metadata validation, cross-user ownership, rollback, weekly/DST intervals, and bills retaining scheduled due dates after early payment. UI previews use sample data; no live task records or provider emails were created.

Client deployment and signed-in device smoke tests remain separate release steps.

Applied 0014 SHA-256: `04ef5573c81b9e2fbbff69881b79a6f58bbdd0813250078756ef91b0dc672fcf`.

## Focus preferences and Focus times — written locally, NOT applied (2026-10-18)

`0015_focus_preferences.sql` (remembered duration, `get_focus_dashboard_v2`) and `0016_focus_times.sql` (Focus times, assignments, `focus_sessions.assignment_id`, review/cancel triggers, dashboard v2 replacement) are written and tested only against isolated PGlite (`npm run test:focus-times:db`). They have **not** been applied to hosted Supabase; hosted history still ends at 0014. Applying them is a separate step that needs Rik's explicit authorization. Do not edit 0001–0014.

`0017_focus_intent_restore.sql` (optional intended outcome on `start_assigned_focus`, `restore_focus_time`, dashboard `focus_api: 17`) is also local only and covered by the same suite. Apply 0015–0017 together, in order.

## Focus preferences, Focus times, planned intents and restore — applied 2026-10-18

Rik explicitly authorized applying 0015–0017 in this chat. Before the push, `migration list --linked` showed hosted history ending at 0014 with only 0015–0017 pending, and the focus-times, Focus, Home, edit-order, email auto-snooze and iOS foundation SQL suites passed on isolated PGlite. `supabase db push --linked --dry-run` listed exactly 0015, 0016 and 0017; `supabase db push --linked --yes` applied them in order with no errors. Hosted history now contains every version 0001–0017. Next unused number: 0018.

Verified after application:

- `save_focus_preferences`, `get_focus_dashboard_v2`, `save_focus_time`, `archive_focus_time`, `restore_focus_time`, `assign_focus_work`, `skip_focus_work` and `start_assigned_focus(uuid,uuid,integer,text)` allow authenticated execution and deny anonymous execution; the three-argument `start_assigned_focus` is gone and three-argument REST calls resolve to the new one. Trigger and helper functions are not executable by clients.
- `focus_preferences`, `focus_times` and `focus_assignments` have RLS enabled, no anonymous SELECT, and are in `supabase_realtime`. `focus_sessions.assignment_id` exists; the review and cancel triggers are enabled.
- PostgREST sees the new RPCs (signed-out calls return 42501, not PGRST202).
- `notification-sweep` cron is still active on `*/5 * * * *`; this rollout did not touch the scheduler.
- The new tables were empty after the push. No sample data, sessions or provider emails were created.

Applied file SHA-256 values:

| Migration | SHA-256 |
|---|---|
| `0015_focus_preferences.sql` | `730518f36db0d4d6fb3293bf034a13b5494b4f8ea6bee7946567882e1872b776` |
| `0016_focus_times.sql` | `47dc09c7c751df222c0416035256429c3a9096d4c132b391863852e1f67fed90` |
| `0017_focus_intent_restore.sql` | `3e04f283e2611b2b6280f345d5b6666b2aee50c1129cfb64eb385fd7f9fa9dc2` |

Web/iOS release and the signed-in web↔phone handoff remain separate steps.


## Side Gig experience — local only, NOT applied (2026-10-19)

`0018_sidegig_experience.sql` is implemented and verified against isolated PostgreSQL. Hosted status remains the last verified 0001–0017 checkpoint above; this implementation did not query, change or push the hosted database. Existing migrations are unchanged. The next unused local migration number is 0019.

0018 adds work restart/waiting state, independent follow-up/payment obligations, action history, a retry ledger, owner-checked atomic `sidegig_mutate` and `get_sidegig_dashboard` RPCs, typed compatibility for `create_follow_up`, reminder/Focus guards, RLS and Realtime. Its collection follow-up trigger pauses the payment reminder's delivery timestamp (as well as channels), preserves the expected date and restores the prior snooze/channels when closed. This uses existing notification enqueue/claim behavior; empty channels alone would inherit the context default and would not pause delivery.

Local verification: the complete migration chain applies; Side Gig SQL passes ownership, rollback/retries, independent shipping/payment outcomes, receipt history after reminder deletion, account deletion and the actual enqueue/claim delivery hold regression. Focus times, Focus, Home and iOS foundation SQL suites also pass. Web production and iOS simulator builds pass; all 245 Flutter tests pass.

Before release, recheck hosted migration history and the exact 0018 diff, apply only the pending migration with release authorization, verify RPC/table ACLs, triggers and Realtime, then deploy the web and signed iOS clients. Authenticated cross-device and provider-delivery checks remain release acceptance work. No sample records or provider messages were created in hosted Supabase during implementation.

## Side Gig experience — applied 2026-10-19

Rik authorized applying 0018 after the new Side Gig tab failed to load on hosted (`get_sidegig_dashboard` returned PGRST202). Hosted history was 0001–0017 and the dry run contained only 0018. The isolated Side Gig SQL suite passed before the push, and the migration was applied with `supabase db push --linked --yes`.

Verified after application: hosted history ends at 0018. `get_sidegig_dashboard`, `sidegig_mutate` and `create_follow_up` allow authenticated execution and deny anonymous execution. `sidegig_work_state`, `sidegig_obligations`, `sidegig_activity` and `sidegig_operations` have RLS enabled, and the first three are in Supabase Realtime. The reminder, Focus assignment, Focus session and collection delivery triggers exist. The five-minute `notification-sweep` cron job 1 is still active and was not changed. No sample records were created.

Applied 0018 SHA-256: `f34db65f88c75eac16fb505bc8e40c61df592d58ef67bb60c53813d128160ad3`. The next unused migration number is 0019.
