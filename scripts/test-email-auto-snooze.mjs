import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// npm install --prefix /tmp/ezy-sql-tests @electric-sql/pglite
// node scripts/test-email-auto-snooze.mjs /tmp/ezy-sql-tests/package.json
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(process.argv[2] ?? resolve(root, 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const user = '10000000-0000-4000-8000-000000000001';
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create table auth.users(id uuid primary key,email text);
create publication supabase_realtime;
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;`);
for (const name of (await readdir(resolve(root, 'supabase/migrations'))).sort()) {
  if (!/^\d{4}_.*\.sql$/.test(name) || name >= '0013_') continue;
  let sql = await readFile(resolve(root, 'supabase/migrations', name), 'utf8');
  if (name.startsWith('0001_')) sql = sql.replace(/create extension if not exists "pgcrypto";\s*/i, '');
  await db.exec(sql);
}
await db.exec(`grant usage on schema public,auth to authenticated,service_role;
grant select,insert,update,delete on all tables in schema public to authenticated,service_role;`);
await db.query('insert into auth.users(id,email) values ($1,$2)', [user, 'fixture@example.test']);
const context = (await one("select id from contexts where user_id=$1 and slug='work'", [user])).id;
const makeReminder = async (fields = {}) => (await one(`insert into reminders
(user_id,context_id,title,due_at,status,snoozed_until,channels)
values ($1,$2,'Email repeat fixture',coalesce($3::timestamptz,now()-interval '1 hour'),$4,$5,$6) returning *`,
[user, context, fields.due ?? null, fields.status ?? 'open', fields.snooze ?? null, fields.channels ?? ['email']])).id;
const load = (id) => one('select *,now() as db_now from reminders where id=$1', [id]);
const notification = async (id, fields = {}) => (await one(`insert into notifications
(user_id,reminder_id,channel,scheduled_for,status,sent_at,superseded_at)
select user_id,id,$2,coalesce($3::timestamptz,snoozed_until,due_at),$4,$5,$6 from reminders where id=$1 returning *`,
[id, fields.channel ?? 'email', fields.due ?? null, fields.status ?? 'pending', fields.sent ?? null, fields.superseded ?? null])).id;
const send = (id) => db.query("update notifications set status='sent',sent_at=now() where id=$1", [id]);
const nearSixHours = async (id) => {
  const r = await load(id);
  assert.equal(r.status, 'snoozed');
  const hours = (r.snoozed_until - r.db_now) / 3600000;
  assert.ok(hours > 5.99 && hours <= 6.001, `expected six hours, got ${hours}`);
  return r;
};
let checks = 0;

// Migration rollout: latest real send wins even if 0009 retired its duplicate row.
const legacy = await makeReminder();
await notification(legacy, { status: 'sent', sent: new Date(Date.now()-2*3600000) });
await notification(legacy, { status: 'sent', sent: new Date(Date.now()-3600000), superseded: new Date() });
const noRecent = await makeReminder();
await notification(noRecent, { status: 'sent', sent: new Date(Date.now()-7*3600000) });
const future = await makeReminder({ snooze: new Date(Date.now()+8*3600000), status: 'snoozed' });
await notification(future, { status: 'sent', sent: new Date(), due: new Date(Date.now()-3600000) });
await db.exec(await readFile(resolve(root, 'supabase/migrations/0013_email_auto_snooze.sql'), 'utf8'));
assert.equal((await load(legacy)).status, 'snoozed');
assert.ok(Math.abs(((await load(legacy)).snoozed_until-Date.now())/3600000-5)<0.01);
assert.equal((await load(noRecent)).status, 'open');
assert.ok((await load(future)).snoozed_until-Date.now()>7.9*3600000);
checks += 3;
// Isolate subsequent queue tests without deleting any notification audit rows.
await db.query("update reminders set status='done' where id=any($1::uuid[])", [[legacy,noRecent,future]]);

const id = await makeReminder();
const originalDue = (await load(id)).due_at.toISOString();
await db.exec('select enqueue_due_notifications(); select enqueue_due_notifications();');
let rows = (await db.query('select * from notifications where reminder_id=$1',[id])).rows;
assert.equal(rows.length,1); checks++;
const claimed = (await db.query('select * from claim_due_notifications(25)')).rows;
assert.equal(claimed.filter(n=>n.reminder_id===id).length,1);
await db.exec('set role service_role');
await send(rows[0].id);
await db.exec('reset role');
let r = await nearSixHours(id);
assert.equal(r.due_at.toISOString(), originalDue); checks++;
const firstSnooze = r.snoozed_until.toISOString();
await send(rows[0].id); // Rewriting sent must not slide the deadline again.
assert.equal((await load(id)).snoozed_until.toISOString(),firstSnooze); checks++;
for(let minute=0;minute<20;minute++) await db.exec('select enqueue_due_notifications(); select claim_due_notifications(25);');
assert.equal((await one('select count(*)::int n from notifications where reminder_id=$1',[id])).n,1); checks++;
// Simulate the next due occurrence without waiting six hours of wall time.
await db.query("update reminders set snoozed_until=now()-interval '1 minute' where id=$1",[id]);
await db.exec('select enqueue_due_notifications();');
rows=(await db.query('select * from notifications where reminder_id=$1 order by created_at',[id])).rows;
assert.equal(rows.length,2); assert.notEqual(rows[0].occurrence_at.toISOString(),rows[1].occurrence_at.toISOString());
await send(rows[1].id); await nearSixHours(id); checks++;
await db.query("update reminders set status='done' where id=$1",[id]);

for(const status of ['done','cancelled']) {
  const stopped=await makeReminder(); const n=await notification(stopped);
  await db.query('update reminders set status=$2 where id=$1',[stopped,status]); await send(n);
  assert.equal((await load(stopped)).status,status);
  assert.equal((await load(stopped)).snoozed_until,null); checks++;
}
const snoozed = await makeReminder(); const oldN = await notification(snoozed);
await db.query("update reminders set status='snoozed',snoozed_until=now()+interval '2 hours' where id=$1",[snoozed]);
const explicit=(await load(snoozed)).snoozed_until.toISOString();
await send(oldN); assert.equal((await load(snoozed)).snoozed_until.toISOString(),explicit); checks++;
const rescheduled = await makeReminder(); const stale=await notification(rescheduled);
await db.query("update reminders set due_at=now()+interval '1 day' where id=$1",[rescheduled]);
await send(stale); assert.equal((await load(rescheduled)).snoozed_until,null); checks++;
for(const state of ['pending','retrying','failed']) {
 const failed=await makeReminder(); const n=await notification(failed);
 await db.query('update notifications set status=$2 where id=$1',[n,state]);
 assert.equal((await load(failed)).snoozed_until,null); checks++;
 await db.query("update reminders set status='done' where id=$1",[failed]);
}
const whatsapp=await makeReminder({channels:['whatsapp']});
await send(await notification(whatsapp,{channel:'whatsapp'}));
assert.equal((await load(whatsapp)).snoozed_until,null); checks++;
const rerouted=await makeReminder(); const routeN=await notification(rerouted);
await db.query("update reminders set channels='{whatsapp}' where id=$1",[rerouted]);
await send(routeN); assert.equal((await load(rerouted)).snoozed_until,null); checks++;
const retired=await makeReminder(); await send(await notification(retired,{superseded:new Date()}));
assert.equal((await load(retired)).snoozed_until,null); checks++;
const fallback=await makeReminder({channels:[]}); await send(await notification(fallback));
await nearSixHours(fallback); checks++;
// If scheduling fails, the sent marker must roll back with it.
const rollback=await makeReminder(); const rollbackN=await notification(rollback);
await db.exec(`create function fixture_fail_snooze() returns trigger language plpgsql as $$
begin if new.title='Rollback fixture' and new.status='snoozed' then raise exception 'fixture'; end if; return new; end; $$;
create trigger fixture_failure before update on reminders for each row execute function fixture_fail_snooze();`);
await db.query("update reminders set title='Rollback fixture' where id=$1",[rollback]);
await assert.rejects(()=>send(rollbackN));
assert.equal((await one('select status from notifications where id=$1',[rollbackN])).status,'pending'); checks++;
console.log(`PASS ${checks} email repeat, six-hour snooze, occurrence, rollout and race/rollback checks (no provider calls)`);
await db.close();
