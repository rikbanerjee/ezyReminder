# Notification duplicate fix — deployment and validation

Originally prepared 2026-10-15 on `ios-mvp`. On 2026-10-18, Rik approved applying 0008/0009/0013 and deploying the matching sweep. The rollout is now active; see [EMAIL_REPEAT.md](EMAIL_REPEAT.md) for verification. No test email was sent.

## Cause and fix

The old enqueue function used `scheduled_for` as the delivery identity, but quiet-hours deferral and retries changed that field. A later sweep could therefore enqueue the same due reminder again. There was also no unique database constraint to prevent concurrent duplicate inserts.

Migration `0009_notification_occurrences.sql` separates immutable `occurrence_at` from mutable `scheduled_for` (next eligible attempt). A partial unique index and `ON CONFLICT DO NOTHING` allow one canonical row per reminder, channel, and due occurrence. Duplicate and obsolete queue rows are retained for audit with `superseded_at`, and are not dispatched. Claiming still uses `FOR UPDATE SKIP LOCKED`. Prior attempted or delivered occurrences block creation of a fresh delivery identity even after completion and reopening; never-attempted superseded rows can be queued again.

The sweep checks current reminder state and the claimed row again before dispatch, defers the same row during quiet hours, checks persistence failures, and sends Resend the stable `notification:<notification-id>` idempotency key. Manual Retry now queues the same failed occurrence through the sweep; the button does not call the email provider directly.

`delivery_started_at` records the first attempted delivery before the HTTP request. Retries stop after 23 hours and require delivery confirmation, rather than risk sending again after the provider forgets the key. Resend documents a 24-hour idempotency retention window and requires the same payload: [Resend idempotency](https://www.resend.com/blog/engineering-idempotency-keys).

## Human deployment steps

1. Pause the existing cron job, preserving its schedule and command. In Supabase SQL Editor, first record the job's ID and original active state:

   ```sql
   select jobid, jobname, schedule, active
   from cron.job where jobname = 'notification-sweep';

   select cron.alter_job(jobid, active := false)
   from cron.job where jobname = 'notification-sweep';
   ```

   Confirm any already-started invocation has finished in the Edge Function logs. Pausing cron does not cancel an invocation in progress. The pause API is documented by [pg_cron](https://github.com/citusdata/pg_cron#altering-a-cron-job).

2. From the repository, inspect pending migrations, then apply them with your normal linked-project workflow:

   ```sh
   npx supabase db push --dry-run
   npx supabase db push
   ```

   Expected pending files are 0008 (channel guard), if still unapplied, and 0009 (this fix). Migrations 0001–0007 are already applied and must not be modified or reapplied.

3. Deploy the fixed sweep:

   ```sh
   npx supabase functions deploy notification-sweep --project-ref ojfmtxcrfmyygwfjibwk
   ```

   Deploy the updated web code as well so manual retries use `retry_notification`. Applying the migration before the runtime/web updates keeps the new RPC and columns available during rollout.

4. Re-enable only the job that was active before the maintenance pause, using the recorded job ID:

   ```sql
   select cron.alter_job(YOUR_JOB_ID, active := true);
   ```

   Do not create a second job or change the existing cadence to work around duplicate emails.

## Smoke test after deployment

- Create an email reminder due shortly, with quiet hours off. Expect one email and one canonical notification row across subsequent sweeps.
- Create a reminder due inside a short quiet window. Before the window ends, repeated sweeps should keep one canonical row with unchanged `occurrence_at` and deferred `scheduled_for`. Expect one delivery after the window ends.
- Snooze a reminder to a new time. The previous queued occurrence is superseded; the new due occurrence is delivered once.
- Complete a reminder before dispatch. Its queued occurrence is not delivered.
- Use Retry for a failed current occurrence. Expect the same notification ID/key to be queued, with quiet hours still respected.

Read-only diagnostic query (filter to the test reminder UUID):

```sql
select id, channel, occurrence_at, scheduled_for, status, attempt_count,
       delivery_started_at, sent_at, superseded_at, error
from notifications
where reminder_id = 'YOUR_TEST_REMINDER_UUID'
order by created_at;
```

## Limits and recovery

- Existing logs do not contain a perfect original due snapshot. For active reminders, the migration conservatively infers the current due time when it precedes both row creation and the moved schedule. A sent row wins over unsent duplicates. If a historical reminder was rescheduled backward to an already-past time, this inference can suppress that new occurrence. Review such rows during rollout; do not assume all historical occurrences can be reconstructed exactly.
- Rows left `sending` after a crash or a failed sent-status write are not automatically replayed. Check provider delivery history before recovery. No software can atomically commit an external email send and a Postgres update in the same transaction.
- After the 23-hour guard expires, the row stays failed with `delivery_confirmation_required`; automatic and manual retries are blocked. Verify provider history before intentionally creating a new reminder occurrence.
- Changing the email payload after an ambiguous provider attempt can produce an idempotency conflict. The same occurrence intentionally keeps its key to avoid duplicate mail.
- Local regression tests use mocked provider calls and an in-memory PostgreSQL runtime. They send no real emails and do not verify hosted cron or provider delivery.

## Local validation

- All 26 database migration/RLS/RPC checks passed against an in-memory PostgreSQL runtime.
- All 17 email adapter and sweep regression tests passed; the full Edge Function suite also passed.
- Shared date/quiet-hours fixtures, auth tests, TypeScript, lint, and the production build passed. Lint reports the existing unused WhatsApp stub parameter warning.

## Six-hour repeat follow-up (2026-10-18)

Migration 0013 now adds automatic six-hour snoozing after each successful email. It builds on 0009; see [EMAIL_REPEAT.md](EMAIL_REPEAT.md) for the confirmed hosted migration gap, targeted rollout, and tests. The old one-email-per-occurrence protection remains in place; automatic snoozing creates a new due occurrence after six hours.
