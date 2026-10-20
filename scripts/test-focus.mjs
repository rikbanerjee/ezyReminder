import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Run against isolated embedded PostgreSQL (never hosted Supabase):
// npm install --prefix /tmp/ezy-focus-sql-tests @electric-sql/pglite
// node scripts/test-focus.mjs /tmp/ezy-focus-sql-tests/package.json
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(process.argv[2] ?? resolve(root, 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const a = '10000000-0000-4000-8000-000000000001';
const b = '20000000-0000-4000-8000-000000000002';
let sequence = 0;
const uuid = () => `30000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`;
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const fail = async (sql, params = [], pattern) => {
  await assert.rejects(() => db.query(sql, params), pattern, sql);
};
const asUser = async (id, fn, role = 'authenticated') => {
  await db.exec(`set role ${role}`);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]);
  try { return await fn(); } finally {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub','',false)");
  }
};
const state = () => one('select get_focus_state() as state').then((row) => row.state);
const start = (id, reminder, duration = 25, intent = null) => db.query('select start_focus_session($1,$2,$3,$4)', [id, reminder, duration, intent]);
const pause = (s) => db.query('select pause_focus_session($1,$2)', [s.id, s.updated_at]);
const resume = (s) => db.query('select resume_focus_session($1,$2)', [s.id, s.updated_at]);
const finish = (s, outcome = 'progress', step = null) => db.query('select finish_focus_session($1,$2,$3,$4)', [s.id, s.updated_at, outcome, step]);

await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create table auth.users(id uuid primary key,email text);
create publication supabase_realtime;
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;`);
for (const name of ['0001_init.sql','0002_delivery.sql','0003_context_panels.sql','0004_shopping.sql','0005_onboarding.sql','0006_remove_slack.sql','0007_ios_foundation.sql','0008_guard_notification_channels.sql','0009_notification_occurrences.sql','0010_edit_order_reminder.sql','0011_home_maintenance.sql']) {
  let sql = await readFile(`${root}/supabase/migrations/${name}`, 'utf8');
  if (name === '0001_init.sql') sql = sql.replace(/create extension if not exists "pgcrypto";\s*/i, '');
  await db.exec(sql);
}
await db.exec(`grant usage on schema public,auth to anon,authenticated,service_role;
grant select,insert,update,delete on all tables in schema public to authenticated,service_role;
grant usage,select on all sequences in schema public to authenticated,service_role;`);
await db.exec(await readFile(`${root}/supabase/migrations/0012_focus_sessions.sql`, 'utf8'));
await db.query('insert into auth.users(id,email) values ($1,$2),($3,$4)', [a,'a@example.com',b,'b@example.com']);
const makeReminder = async (user, slug, status = 'open') => {
  const context = await one('select id from contexts where user_id=$1 and slug=$2', [user,slug]);
  const id = uuid();
  await db.query('insert into reminders(id,user_id,context_id,title,status,due_at,channels) values($1,$2,$3,$4,$5,$6,$7)', [id,user,context.id,`${slug} reminder`,status,'2026-10-18T12:00:00Z',['email']]);
  return id;
};
const work = await makeReminder(a,'work');
const gig = await makeReminder(a,'sidegig','snoozed');
const social = await makeReminder(a,'social');
const shopping = await makeReminder(a,'shopping');
const done = await makeReminder(a,'work','done');
const cancelled = await makeReminder(a,'work','cancelled');
const foreign = await makeReminder(b,'work');
const baseline = await one('select to_jsonb(r) as value from reminders r where id=$1', [work]);
await db.query("update user_settings set timezone='Pacific/Kiritimati' where user_id=$1", [a]);

await asUser(a, async () => {
  let s = await state();
  assert.equal(s.timezone,'Pacific/Kiritimati');
  const expected = await one("select (clock_timestamp() at time zone 'Pacific/Kiritimati')::date::text as day");
  assert.equal(s.local_date,expected.day);
  assert.equal(s.highlight,null); assert.equal(s.active_session,null);
  for (const id of [social,shopping,done,cancelled,foreign]) {
    await fail('select set_focus_highlight($1)', [id], /open Work or Side Gig/);
    await assert.rejects(() => start(uuid(),id), /open Work or Side Gig/);
  }
  await db.query('select set_focus_highlight($1)',[work]);
  s = await state(); const originalHighlight = s.highlight;
  await db.query('select set_focus_highlight($1)',[work]);
  assert.deepEqual((await state()).highlight,originalHighlight,'duplicate highlight selection is a no-op');
  await db.query('select set_focus_highlight($1)',[gig]);
  assert.equal((await state()).highlight.reminder_id,gig);
  assert.equal((await one('select count(*)::int as n from focus_highlights')).n,1);
  await db.query('select set_focus_highlight(null)');
  assert.equal((await state()).highlight,null);
  await db.query('select set_focus_highlight($1)',[work]);

  for (const duration of [null,0,-1,181]) await assert.rejects(() => start(uuid(),work,duration), /1–180/);
  await assert.rejects(() => start(uuid(),work,25,'x'.repeat(501)), /500/);
  const token = uuid();
  await start(token,work,1,'  A small outcome  ');
  const running = (await state()).active_session;
  assert.equal(running.id,token); assert.equal(running.intended_outcome,'A small outcome');
  await start(token,work,1,'A small outcome');
  assert.deepEqual((await state()).active_session,running,'retry preserves original timestamps');
  await assert.rejects(() => start(uuid(),gig), /current focus session/);
  await pause(running); const paused = (await state()).active_session;
  assert.ok(paused.paused_at); assert.equal(paused.last_resumed_at,null);
  assert.ok(paused.elapsed_seconds >= 0); assert.ok(paused.elapsed_seconds < 60);
  await pause(running);
  assert.deepEqual((await state()).active_session,paused,'pause retry is idempotent');
  await resume(paused); const resumed = (await state()).active_session;
  assert.ok(resumed.last_resumed_at); assert.equal(resumed.paused_at,null);
  assert.equal(resumed.elapsed_seconds,paused.elapsed_seconds,'paused time excluded');
  await resume(paused);
  assert.deepEqual((await state()).active_session,resumed,'resume retry is idempotent');
  await assert.rejects(() => pause(running), /Session changed/,'stale pause cannot reverse a subsequent resume');
  await assert.rejects(() => finish(paused), /Session changed/,'stale finish cannot bypass a subsequent transition');
  await pause(resumed); const pausedAgain = (await state()).active_session;
  await assert.rejects(() => resume(paused), /Session changed/,'stale resume cannot reverse a subsequent pause');
  await assert.rejects(() => finish(pausedAgain,'bogus'), /Choose an outcome/);
  await assert.rejects(() => finish(pausedAgain,'progress','x'.repeat(1001)), /1000/);
  await finish(pausedAgain,'interrupted','  Open the draft next  ');
  assert.equal((await state()).active_session,null);
  let saved = await one('select to_jsonb(s) as value from focus_sessions s where id=$1',[token]);
  assert.equal(saved.value.outcome,'interrupted'); assert.equal(saved.value.next_step,'Open the draft next');
  assert.equal(saved.value.elapsed_seconds,pausedAgain.elapsed_seconds);
  const finishedCopy = saved.value;
  await finish(pausedAgain,'finished','Overwriting retry');
  saved = await one('select to_jsonb(s) as value from focus_sessions s where id=$1',[token]);
  assert.deepEqual(saved.value,finishedCopy,'finished session is immutable on retry');
  await start(token,work,1);
  assert.equal((await state()).active_session,null,'retry of old start does not resurrect history');
  await pause(pausedAgain); await resume(pausedAgain);
  assert.equal((await state()).active_session,null);
  await fail('update focus_sessions set elapsed_seconds=0 where id=$1',[token],/permission denied/);
  await fail('delete from focus_sessions where id=$1',[token],/permission denied/);
  await fail('insert into focus_highlights(user_id,local_date,reminder_title,context_slug) values($1,current_date,$2,$3)',[a,'Bypass','work'],/permission denied/);
});

assert.deepEqual((await one('select to_jsonb(r) as value from reminders r where id=$1',[work])).value,baseline.value,'focus never changes reminder fields');
await asUser(b, async () => {
  assert.equal((await one('select count(*)::int as n from focus_sessions')).n,0,'RLS hides another user session');
  assert.equal((await one('select count(*)::int as n from focus_highlights')).n,0);
  const existing = await one('select id from reminders where id=$1',[work]); assert.equal(existing,undefined);
  const first = await one('select id from focus_sessions limit 1'); assert.equal(first,undefined);
});
const prior = await one('select id from focus_sessions where user_id=$1 limit 1',[a]);
await asUser(b, async () => {
  for (const fn of ['pause_focus_session','resume_focus_session']) await fail(`select ${fn}($1,clock_timestamp())`,[prior.id],/Session not found/);
  await fail('select finish_focus_session($1,clock_timestamp(),$2,null)',[prior.id,'finished'],/Session not found/);
  await assert.rejects(() => start(prior.id,foreign),/Session not found/);
});

// Simulate a backgrounded tab reaching zero, without waiting in real time.
const expiredToken = uuid();
await asUser(a, () => start(expiredToken,work,1));
await db.query("update focus_sessions set started_at=clock_timestamp()-interval '2 hours',last_resumed_at=clock_timestamp()-interval '2 hours' where id=$1",[expiredToken]);
await asUser(a, async () => {
  const expired = (await state()).active_session;
  assert.equal(expired.id,expiredToken,'expiry alone does not finish the session');
  assert.equal(expired.finished_at,null);
  await assert.rejects(() => start(uuid(),work),/current focus session/);
  await pause(expired); const capped = (await state()).active_session;
  assert.equal(capped.elapsed_seconds,60,'active time caps at planned duration');
  await assert.rejects(() => resume(capped),/Time is up/);
  await finish(capped,'finished');
  assert.equal((await state()).active_session,null);
});

// Snapshot and active timer survive reminder deletion, and timezone day rollover.
const deletedToken = uuid();
await asUser(a, () => start(deletedToken,gig,180));
await db.query('delete from reminders where id=$1',[gig]);
await db.query("update user_settings set timezone='America/Adak' where user_id=$1",[a]);
await asUser(a, async () => {
  const changed = await state();
  assert.equal(changed.timezone,'America/Adak');
  assert.equal(changed.active_session.reminder_id,null);
  assert.equal(changed.active_session.reminder_title,'sidegig reminder');
  assert.equal(changed.active_session.id,deletedToken);
  await finish(changed.active_session,'progress','Pick up here');
});
await asUser(a, () => fail('select get_focus_state()',[],/permission denied/),'anon');
await asUser('', () => fail('select get_focus_state()',[],/Sign in required/));
await db.exec('drop index focus_sessions_reminder_history'); // independent index does not enforce single-session safety
const unfinishedOne=uuid(); const unfinishedTwo=uuid();
await asUser(a, () => start(unfinishedOne,work,25));
await fail(`insert into focus_sessions(id,user_id,reminder_id,reminder_title,context_slug,duration_minutes,started_at,last_resumed_at,updated_at)
values($1,$2,$3,'Duplicate','work',25,clock_timestamp(),clock_timestamp(),clock_timestamp())`,[unfinishedTwo,a,work],/focus_sessions_one_unfinished/);
const tables=await db.query("select tablename from pg_publication_tables where pubname='supabase_realtime' and tablename in ('focus_sessions','focus_highlights')");
assert.equal(tables.rows.length,2);
console.log('PASS focus SQL: account dates, eligibility, RLS/grants, idempotency, transitions/stale retries, history, expiry, deletion and reminder isolation');
await db.close();
