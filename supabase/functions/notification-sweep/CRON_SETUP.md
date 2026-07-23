# notification-sweep: setup & schedule

The sweep is a Supabase Edge Function, scheduled with `pg_cron`. Status as
of the last setup run:

- **Function**: deployed (`npx supabase functions deploy notification-sweep`)
- **Secrets set**: `RESEND_API_KEY`, `RESEND_FROM_EMAIL` (`reminder@thecustomhub.com`)
- **Cron job**: `notification-sweep`, schedule `*/5 * * * *` (every 5
  minutes). This is a placeholder cadence for pre-launch testing, not the
  real delivery SLA — see "Changing the schedule" below for when to
  tighten it to `* * * * *` (every minute, per PLAN.md §4.1).
- **Auth**: the service-role key is stored in Supabase Vault
  (`vault.secrets`, name `service_role_key`) and read via
  `vault.decrypted_secrets` inside the cron job body — never embedded as
  plaintext in `cron.job.command`, which is a persistent, queryable catalog
  table.

## Redeploying after code changes

Whenever `supabase/functions/notification-sweep/index.ts` or the shared
`lib/quiet-hours.ts` / `lib/integrations/*` files change:

```
npx supabase functions deploy notification-sweep
```

## Changing the schedule

Run this in the SQL editor (or `npx supabase db query --linked "<sql>"`) —
`cron.schedule` with an existing job name updates it in place, no need to
unschedule first:

```sql
select cron.schedule('notification-sweep', '<new schedule>', $$
  select net.http_post(
    url := 'https://ojfmtxcrfmyygwfjibwk.functions.supabase.co/notification-sweep',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
$$);
```

Common values for `<new schedule>`:
- `* * * * *` — every minute (the production target once close to launch)
- `*/15 * * * *` — every 15 minutes
- `0 */2 * * *` — every 2 hours (current placeholder)

## Checking it ran

```sql
select * from cron.job_run_details order by start_time desc limit 5;
```

## Rotating the service-role key

If the project's service-role key is ever rotated, update the Vault copy
(don't re-run `cron.schedule` — the job already references the secret by
name, not by value):

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'service_role_key'),
  '<new-service-role-key>'
);
```

## Pausing / removing

```sql
select cron.unschedule('notification-sweep');
```
