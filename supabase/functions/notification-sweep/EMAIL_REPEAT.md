# Six-hour overdue email repeat

Requested by Rik on 2026-10-18. After a successful email, the reminder becomes
`snoozed` until six hours after the successful delivery is recorded. Its original
`due_at` stays unchanged. The next due occurrence gets a new notification identity,
then another six-hour snooze on success. Complete/cancel stops repeats; explicit
snoozes, due-date changes, and removing email routing take precedence. Quiet hours
can delay the next email beyond six hours. Provider failures retain their bounded
retry policy; they do not count as a successful reminder or start the six-hour delay.

`0013_email_auto_snooze.sql` installs a database trigger so recording `sent` and
moving the reminder happen in one transaction. Rewriting an already-sent row does
not extend its snooze again. If completion or rescheduling happens during provider
I/O, the trigger checks the current status and occurrence before changing it.
Recent successful emails for an already-overdue occurrence are backfilled to
`last_sent_at + 6 hours` so rollout need not send another email first. Duplicate
history is preserved. Queued work for superseded occurrences is retired.

## Hosted diagnosis and rollout

Read-only pre-deployment checks on 2026-10-18 confirmed hosted migration history stopped at 0007;
the earlier duplicate-email fix (0009) has not been applied. Cron job 1,
`notification-sweep`, is active on `*/5 * * * *`. The aggregate notification log
contained 109 sent rows created in the preceding 24 hours. The mutable schedule
identity in the legacy enqueue function can recreate a reminder after a retry or
quiet-hours deferral; 0009 adds durable identity, uniqueness, and stale-work guards.
The new six-hour repeat behavior requires 0013 as well.

FLUTTER_IOS_PROMPT.md reserves hosted migrations and deployments for Rik unless he
explicitly authorizes this session. Do not claim the email problem is fixed live
until both database and sweep deployment have been verified.

1. Pause the existing sweep cron job and preserve its active state and schedule.
   Let in-flight invocations finish. See DEDUPLICATION.md for pause/resume SQL.
2. Apply **0008_guard_notification_channels.sql**, **0009_notification_occurrences.sql**,
   and **0013_email_auto_snooze.sql**, in that order, using a linked-project migration
   workflow. Do not reapply anything already recorded in hosted migration history.
   Deploy the matching local `notification-sweep` and shared email adapter.
3. Resume the same cron job with its original schedule/active state. A global
   six-hour cron interval would delay new reminders, so repeat timing belongs to
   each reminder's `snoozed_until`, not the scheduler cadence.
4. Read migration history and confirm the trigger is present. Check aggregate
   queue state and the original cron schedule. A real email smoke test is a
   separate explicitly authorized action; automated tests send no provider mail.

Other pending files (0010 shipping, 0011 Home, 0012 Focus) are unrelated to this
notification fix. A dry run against an isolated linked workspace containing only
0001–0009 and 0013 confirmed that only 0008, 0009, and 0013 would apply. Its prepared
session path is `/private/tmp/ezy-notification-six-hour-rollout`; review its file
contents against the repository before using it. Do not blindly push all migrations
from the main checkout merely to fix email delivery.

## Local verification

- `node scripts/test-email-auto-snooze.mjs /private/tmp/ezy-ios-sql-check/package.json`:
  20 PostgreSQL checks pass, including repeat cycles, repeated sweeps, migration
  backfill, explicit snooze/completion races, failed sends, channel changes,
  original due-date preservation, and rollback if scheduling fails. See the
  script header for an isolated PGlite installation command on a fresh machine.
- `npm run test:notifications`: all 17 email adapter/sweep tests pass.
- `npm run test:shared`: shared date/quiet-hours fixtures pass in all tested zones.

No hosted writes or provider test emails were performed during preparation.

## Activated on 2026-10-18

Rik explicitly approved this rollout in chat. Cron job 1 was paused after confirming no recent sending notifications or queued sweep HTTP requests. All three migrations passed a hosted transaction preflight that was rolled back, then 0008, 0009, and 0013 were permanently applied from the isolated workspace. The matching `notification-sweep` and its shared email adapter were deployed with the Supabase API bundler.

Hosted checks confirmed the trigger is enabled, zero duplicate active occurrences, zero currently eligible queue rows, and one existing reminder snoozed until 2026-10-18 19:05:16 UTC (3:05:16 PM America/New_York), based on its latest successful email. The authenticated GET health check returned the expected 405 without sending any email. Cron was restored active on its original `*/5 * * * *` schedule. No provider test email was sent.

Hosted history is now 0001–0009 plus 0013; 0010–0012 remain unapplied. Future deployment of those older-numbered app migrations requires a reviewed `db push --include-all --dry-run` / `db push --include-all` workflow, because 0013 is already recorded. Do not edit or reapply the applied notification migrations.
