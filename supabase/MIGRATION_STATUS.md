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
