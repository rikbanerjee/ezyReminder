import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Run against isolated embedded PostgreSQL (never hosted Supabase):
// npm install --prefix /tmp/ezy-focus-sql-tests @electric-sql/pglite
// node scripts/test-focus-times.mjs /tmp/ezy-focus-sql-tests/package.json
// Covers migrations 0015 (preferences, dashboard v2) and 0016 (focus times, assignments).
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(process.argv[2] ?? resolve(root, 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const a = '10000000-0000-4000-8000-000000000001';
const b = '20000000-0000-4000-8000-000000000002';
let sequence = 0;
const uuid = () => `30000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`;
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const fail = (sql, params, pattern) => assert.rejects(() => db.query(sql, params), pattern, sql);
const asUser = async (id, fn, role = 'authenticated') => {
  await db.exec(`set role ${role}`);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]);
  try { return await fn(); } finally {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub','',false)");
  }
};
const dash = () => one('select get_focus_dashboard_v2() as d').then((r) => r.d);
const pick = (o, key, fallback) => (key in o ? o[key] : fallback);
const save = (id, o = {}) => db.query('select save_focus_time($1,$2,$3,$4::smallint[],$5,$6,$7)',
  [id, pick(o, 'label', null), pick(o, 'context', 'work'), pick(o, 'days', [1, 2, 3, 4, 5, 6, 7]),
    pick(o, 'start', '19:00'), pick(o, 'budget', 30), pick(o, 'enabled', true)]);
const assign = (id, reminder, time, date, start = '19:00', minutes = 25) =>
  db.query('select assign_focus_work($1,$2,$3,$4,$5,$6)', [id, reminder, time, date, start, minutes]);
const startAssigned = (session, assignment, minutes = null) => db.query('select start_assigned_focus($1,$2,$3)', [session, assignment, minutes]);
const assignmentRow = (id) => one('select *, local_date::text as local_day from focus_assignments where id=$1', [id]);
const finishActive = async (outcome = 'progress', step = null) => {
  const s = (await dash()).active_session;
  await db.query('select finish_focus_session($1,$2,$3,$4)', [s.id, s.updated_at, outcome, step]);
  return s;
};

await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create table auth.users(id uuid primary key,email text);
create publication supabase_realtime;
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;`);
const migrations = (await readdir(`${root}/supabase/migrations`)).filter((n) => /^\d{4}_.*\.sql$/.test(n)).sort();
for (const name of migrations) {
  let sql = await readFile(`${root}/supabase/migrations/${name}`, 'utf8');
  if (name.startsWith('0001_')) sql = sql.replace(/create extension if not exists "pgcrypto";\s*/i, '');
  await db.exec(sql);
  if (name.startsWith('0011_')) { // mirror hosted default grants before the Focus migrations run
    await db.exec(`grant usage on schema public,auth to anon,authenticated,service_role;
grant select,insert,update,delete on all tables in schema public to authenticated,service_role;
grant usage,select on all sequences in schema public to authenticated,service_role;`);
  }
}
await db.query('insert into auth.users(id,email) values ($1,$2),($3,$4)', [a, 'a@example.com', b, 'b@example.com']);
await db.query("update user_settings set timezone='Pacific/Kiritimati' where user_id=$1", [a]); // UTC+14: account date can differ from UTC
const today = (await one("select (clock_timestamp() at time zone 'Pacific/Kiritimati')::date::text as d")).d;
const addDays = async (d, n) => (await one('select ($1::date + $2::int)::text as d', [d, n])).d;
const tomorrow = await addDays(today, 1);
const yesterday = await addDays(today, -1);
const makeReminder = async (user, slug, status = 'open', extra = {}) => {
  const context = await one('select id from contexts where user_id=$1 and slug=$2', [user, slug]);
  const id = uuid();
  await db.query('insert into reminders(id,user_id,context_id,title,status,due_at,channels) values($1,$2,$3,$4,$5,$6,$7)',
    [id, user, context.id, `${slug} ${id.slice(-3)}`, status, extra.due ?? '2026-10-18T12:00:00Z', ['email']]);
  return id;
};
const setStatus = (id, status) => db.query('update reminders set status=$2 where id=$1', [id, status]);

// ---------------------------------------------------------------- 0015 preferences + dashboard v2
const w = await makeReminder(a, 'work');
const g = await makeReminder(a, 'sidegig');
const foreignReminder = await makeReminder(b, 'work');
await asUser(a, async () => {
  let d = await dash();
  assert.equal(d.preferred_minutes, 25, 'default without a row');
  assert.equal(d.highlight_next_step, null); assert.equal(d.session_next_step, null);
  assert.deepEqual(d.focus_times, []); assert.deepEqual(d.assignments, []);
  for (const key of ['server_now', 'timezone', 'local_date', 'highlight', 'active_session']) assert.ok(key in d, key);
  for (const bad of [null, 0, 181, -5]) await fail('select save_focus_preferences($1)', [bad], /1–180/);
  assert.equal((await one('select save_focus_preferences(45) as v')).v, 45);
  assert.equal((await dash()).preferred_minutes, 45);
  assert.equal((await one('select save_focus_preferences(180) as v')).v, 180);
  await db.query('select save_focus_preferences(1)');
  assert.equal((await dash()).preferred_minutes, 1, 'upsert overwrites');
  assert.equal((await one('select count(*)::int as n from focus_preferences')).n, 1);
  await fail('update focus_preferences set preferred_minutes=99', [], /permission denied/);
  await fail('insert into focus_preferences(user_id,preferred_minutes) values($1,30)', [a], /permission denied/);

  // Next step: only the latest finished session counts; a blank latest note stays blank.
  await db.query('select set_focus_highlight($1)', [w]);
  const s1 = uuid(); await db.query('select start_focus_session($1,$2,10,null)', [s1, w]);
  assert.equal((await dash()).session_next_step, null, 'no finished session yet');
  await finishActive('progress', 'Draft the intro');
  d = await dash();
  assert.equal(d.highlight_next_step, 'Draft the intro');
  const s2 = uuid(); await db.query('select start_focus_session($1,$2,10,null)', [s2, w]);
  assert.equal((await dash()).session_next_step, 'Draft the intro', 'active session sees prior note');
  await finishActive('interrupted', '   ');
  d = await dash();
  assert.equal(d.highlight_next_step, null, 'latest blank note stays blank, never the older one');
  const s3 = uuid(); await db.query('select start_focus_session($1,$2,10,null)', [s3, g]);
  await finishActive('finished', 'Send invoice');
  await db.query('select set_focus_highlight($1)', [g]);
  d = await dash();
  assert.equal(d.highlight_next_step, 'Send invoice'); assert.notEqual(d.highlight_next_step, 'Draft the intro');
  await db.query('select set_focus_highlight($1)', [w]);
  assert.equal((await dash()).highlight_next_step, null, 'other reminders never leak notes');
  await db.query('select set_focus_highlight(null)');
});
await asUser(b, async () => {
  const d = await dash();
  assert.equal(d.preferred_minutes, 25, 'preferences are per user');
  assert.equal((await one('select count(*)::int as n from focus_preferences')).n, 0, 'RLS hides other preferences');
});

// ---------------------------------------------------------------- 0016 focus times
const ftThu = uuid(); const ftSat = uuid(); const ftGig = uuid();
await asUser(a, async () => {
  const bad = (o, pattern) => assert.rejects(() => save(uuid(), o), pattern, JSON.stringify(o));
  await bad({ days: [] }, /at least one weekday/); await bad({ days: [0] }, /weekday/); await bad({ days: [8] }, /weekday/);
  await bad({ days: [1, 1] }, /weekday/); await bad({ days: null }, /weekday/);
  await bad({ context: 'social' }, /Work or Side Gig/); await bad({ context: 'shopping' }, /Work or Side Gig/);
  await bad({ budget: 0 }, /1–180/); await bad({ budget: 181 }, /1–180/); await bad({ budget: null }, /1–180/);
  await bad({ label: 'x'.repeat(41) }, /40/); await bad({ start: null }, /start time/);
  await assert.rejects(() => save(null), /start time/);
  assert.equal((await one('select count(*)::int as n from focus_times')).n, 0, 'rejected saves leave nothing behind');

  await save(ftThu, { label: ' Thursday night ', days: [4], start: '19:00:45', budget: 35 });
  await save(ftSat, { days: [6, 4], start: '09:00', budget: 60 });
  await save(ftGig, { context: 'sidegig', days: [1, 2, 3, 4, 5, 6, 7], start: '06:30', enabled: false });
  const row = await one('select * from focus_times where id=$1', [ftThu]);
  assert.equal(row.label, 'Thursday night'); assert.equal(row.start_time, '19:00:00'); assert.equal(row.budget_minutes, 35);
  assert.deepEqual((await one('select weekdays from focus_times where id=$1', [ftSat])).weekdays, [4, 6], 'weekdays are stored sorted');
  assert.equal((await one('select label from focus_times where id=$1', [ftSat])).label, null);
  let d = await dash();
  assert.deepEqual(d.focus_times.map((t) => t.id), [ftGig, ftSat, ftThu], 'ordered by start time');
  assert.deepEqual(Object.keys(d.focus_times[0]).sort(),
    ['budget_minutes', 'context_slug', 'enabled', 'id', 'label', 'start_time', 'updated_at', 'weekdays']);
  assert.equal(d.focus_times[0].enabled, false, 'disabled (non-archived) times are still listed');
  await save(ftThu, { label: 'Thu', days: [4, 5], start: '20:00', budget: 40 });
  assert.equal((await one('select label,start_time,budget_minutes from focus_times where id=$1', [ftThu])).label, 'Thu');
  assert.equal((await one('select count(*)::int as n from focus_times')).n, 3, 'edit does not duplicate');
  await save(ftThu, { label: 'Thursday', days: [4], start: '19:00', budget: 30 });
  await fail('update focus_times set label=$1', ['x'], /permission denied/);
  await fail('delete from focus_times', [], /permission denied/);
});
await asUser(b, async () => {
  assert.equal((await one('select count(*)::int as n from focus_times')).n, 0, 'RLS hides focus times');
  await assert.rejects(() => save(ftThu), /Focus time not found/, 'cannot overwrite another user focus time');
  await fail('select archive_focus_time($1)', [ftThu], /Focus time not found/);
  assert.deepEqual((await dash()).focus_times, []);
});
assert.equal((await one('select label from focus_times where id=$1', [ftThu])).label, 'Thursday', 'cross-user attempts changed nothing');

// ---------------------------------------------------------------- assignments
const social = await makeReminder(a, 'social'); const shopping = await makeReminder(a, 'shopping');
const doneR = await makeReminder(a, 'work', 'done'); const cancelledR = await makeReminder(a, 'work', 'cancelled');
const bFt = uuid();
await asUser(b, () => save(bFt, { days: [1, 2, 3, 4, 5, 6, 7] }));
const nextIsoDay = async (iso, from = today) => (await one(
  `select d::date::text as d from generate_series($1::date, $1::date + 7, interval '1 day') d
   where extract(isodow from d)::int = $2 order by d limit 1`, [from, iso])).d;
const thursday = await nextIsoDay(4); const friday = await nextIsoDay(5);
const w2 = await makeReminder(a, 'work'); const w3 = await makeReminder(a, 'work'); const w4 = await makeReminder(a, 'work');
const ids = { a1: uuid(), a2: uuid(), a3: uuid(), a4: uuid() };
await asUser(a, async () => {
  for (const id of [social, shopping, doneR, cancelledR, foreignReminder])
    await assert.rejects(() => assign(uuid(), id, ftSat, thursday, '09:00'), /open Work or Side Gig/);
  await assert.rejects(() => assign(uuid(), w, bFt, today), /Focus time not found/, "another user's focus time");
  await assert.rejects(() => assign(uuid(), w, uuid(), today), /Focus time not found/);
  await assert.rejects(() => assign(uuid(), w, ftGig, thursday), /another context/, 'context mismatch');
  await assert.rejects(() => assign(uuid(), g, ftThu, thursday), /another context/, 'context mismatch (side gig into work time)');
  await assert.rejects(() => assign(uuid(), w, ftThu, friday), /not one of this focus time/, 'weekday not in the time');
  await assert.rejects(() => assign(uuid(), w, null, yesterday, '09:00'), /today or a later day/, 'past date in the account timezone');
  await assert.rejects(() => assign(uuid(), w, ftThu, thursday, '19:00', 0), /1–180/);
  await assert.rejects(() => assign(uuid(), w, ftThu, thursday, '19:00', 181), /1–180/);
  await assert.rejects(() => assign(uuid(), w, ftThu, null), /Choose a day/);
  await assert.rejects(() => assign(uuid(), w, null, today, null), /start time/);
  assert.equal((await one('select count(*)::int as n from focus_assignments')).n, 0);

  // account-timezone "today" is accepted even when it is still yesterday in UTC.
  await assign(ids.a1, w, null, today, '07:15:59', 20);
  let row = await assignmentRow(ids.a1);
  assert.equal(row.state, 'planned'); assert.equal(row.start_time, '07:15:00', 'one-off keeps the supplied time, minute precision');
  assert.equal(row.focus_time_id, null); assert.equal(row.position, 0); assert.equal(row.planned_minutes, 20);
  assert.equal(row.reminder_title, `work ${w.slice(-3)}`); assert.equal(row.context_slug, 'work');
  await assign(ids.a1, w, null, thursday, '10:00', 99); // idempotent retry: nothing changes
  assert.deepEqual(await assignmentRow(ids.a1), row, 'assign is idempotent on p_id');
  assert.equal((await one('select count(*)::int as n from focus_assignments')).n, 1);

  // Moving: old planned -> moved with moved_to; exactly one outstanding per reminder.
  await assign(ids.a2, w, ftThu, thursday, '03:00' /* ignored: the focus time is authoritative */, 30);
  row = await assignmentRow(ids.a2);
  assert.equal(row.start_time, '19:00:00'); assert.equal(row.focus_time_id, ftThu); assert.equal(row.local_day, thursday);
  const old = await assignmentRow(ids.a1);
  assert.equal(old.state, 'moved'); assert.equal(old.moved_to, ids.a2);
  assert.equal((await one("select count(*)::int as n from focus_assignments where reminder_id=$1 and state in ('planned','in_progress')", [w])).n, 1);
  // positions append within an occurrence (focus_time_id + date)
  await assign(ids.a3, w2, ftThu, thursday, '19:00', 15);
  await assign(ids.a4, w3, ftThu, thursday, '19:00', 10);
  assert.deepEqual((await db.query('select id,position from focus_assignments where focus_time_id=$1 and state=$2 order by position', [ftThu, 'planned'])).rows
    .map((r) => r.position), [0, 1, 2]);
  // moving within the same occurrence goes to the end
  const re = uuid(); await assign(re, w, ftThu, thursday, '19:00', 30);
  assert.equal((await assignmentRow(re)).position, 3);
  assert.equal((await assignmentRow(ids.a2)).state, 'moved'); assert.equal((await assignmentRow(ids.a2)).moved_to, re);
  ids.a2 = re;

  // dashboard v2 keys, ordering and deadline fields
  await db.query('update orders set ship_by=null where false'); // no-op, keeps the fixture explicit
  const d = await dash();
  assert.deepEqual(d.assignments.map((x) => x.id), [ids.a3, ids.a4, ids.a2], 'planned only, by date/time/position');
  assert.deepEqual(Object.keys(d.assignments[0]).sort(), ['context_slug', 'due_at', 'focus_time_id', 'focus_time_label', 'id',
    'local_date', 'moved_to', 'planned_minutes', 'position', 'reminder_id', 'reminder_title', 'ship_by', 'start_time', 'state', 'updated_at']);
  assert.equal(d.assignments[0].focus_time_label, 'Thursday'); assert.equal(d.assignments[0].local_date, thursday);
  assert.ok(d.assignments[0].due_at);
  for (const k of ['server_now', 'timezone', 'local_date', 'highlight', 'active_session', 'preferred_minutes', 'highlight_next_step', 'session_next_step', 'focus_times', 'assignments'])
    assert.ok(k in d, k);

  // skip: planned -> skipped, idempotent, no reminder side effects
  const before = (await one('select to_jsonb(r) as v from reminders r where id=$1', [w3])).v;
  await db.query('select skip_focus_work($1)', [ids.a4]); await db.query('select skip_focus_work($1)', [ids.a4]);
  assert.equal((await assignmentRow(ids.a4)).state, 'skipped');
  assert.deepEqual((await one('select to_jsonb(r) as v from reminders r where id=$1', [w3])).v, before);
  await assert.rejects(() => db.query('select skip_focus_work($1)', [uuid()]), /Assignment not found/);
  // a skipped reminder can be planned again
  ids.a4 = uuid(); await assign(ids.a4, w3, null, tomorrow, '08:00', 10);
  assert.equal((await assignmentRow(ids.a4)).state, 'planned');
  await fail('update focus_assignments set state=$1', ['reviewed'], /permission denied/);
  await fail('delete from focus_assignments', [], /permission denied/);
  await fail('insert into focus_assignments(id,user_id,reminder_title,context_slug,local_date,start_time,planned_minutes) values($1,$2,$3,$4,$5,$6,$7)',
    [uuid(), a, 'x', 'work', today, '09:00', 10], /permission denied/);
});
await asUser(b, async () => {
  assert.equal((await one('select count(*)::int as n from focus_assignments')).n, 0, 'RLS hides assignments');
  assert.deepEqual((await dash()).assignments, []);
  await assert.rejects(() => assign(ids.a2, foreignReminder, null, today, '09:00'), /Assignment not found/, "another user's assignment id");
  await assert.rejects(() => assign(uuid(), w, null, today, '09:00'), /open Work or Side Gig/, "another user's reminder");
  await assert.rejects(() => db.query('select skip_focus_work($1)', [ids.a2]), /Assignment not found/);
  await assert.rejects(() => startAssigned(uuid(), ids.a2), /Assignment not found/);
});
assert.equal((await assignmentRow(ids.a2)).state, 'planned', 'cross-user attempts changed nothing');

// ---------------------------------------------------------------- start_assigned_focus, trigger review, in-progress guard
const sessionOne = uuid();
await asUser(a, async () => {
  await assert.rejects(() => startAssigned(uuid(), ids.a2, 0), /1–180/);
  assert.equal(await one('select 1 from focus_sessions where finished_at is null'), undefined, 'rejected start leaves no session');
  await startAssigned(sessionOne, ids.a2, 20);
  let s = (await dash()).active_session;
  assert.equal(s.id, sessionOne); assert.equal(s.assignment_id, ids.a2); assert.equal(s.duration_minutes, 20); assert.equal(s.reminder_id, w);
  assert.equal((await assignmentRow(ids.a2)).state, 'in_progress');
  await startAssigned(sessionOne, ids.a2, 20);
  assert.deepEqual((await dash()).active_session, s, 'retry with the same session id is idempotent');
  assert.equal((await one('select count(*)::int as n from focus_sessions where assignment_id=$1', [ids.a2])).n, 1);
  // one-unfinished rule across both start paths
  await assert.rejects(() => startAssigned(uuid(), ids.a3), /current focus session/);
  await assert.rejects(() => db.query('select start_focus_session($1,$2,10,null)', [uuid(), w2]), /current focus session/);
  // in_progress blocks move and skip
  await assert.rejects(() => assign(uuid(), w, null, tomorrow, '09:00'), /Finish the current session first/);
  await assert.rejects(() => db.query('select skip_focus_work($1)', [ids.a2]), /Finish the current session first/);
  assert.equal((await assignmentRow(ids.a2)).state, 'in_progress');
  assert.equal((await dash()).assignments.find((x) => x.id === ids.a2).state, 'in_progress', 'in-progress stays on the dashboard');
  // an in-progress reminder completing keeps its assignment until the session is reviewed
  await setStatus(w, 'done');
  assert.equal((await assignmentRow(ids.a2)).state, 'in_progress');
  // finishing via the OLD finish RPC reviews the assignment
  await finishActive('finished', 'Ship it');
  assert.equal((await assignmentRow(ids.a2)).state, 'reviewed');
  assert.equal((await dash()).active_session, null);
  assert.ok(!(await dash()).assignments.some((x) => x.id === ids.a2));
  await assert.rejects(() => startAssigned(uuid(), ids.a2), /no longer available/, 'reviewed work cannot start again');
  await startAssigned(sessionOne, ids.a2, 20);
  assert.equal((await dash()).active_session, null, 'retrying an old start never resurrects a finished session');
  await db.query('select skip_focus_work($1)', [ids.a2]);
  assert.equal((await assignmentRow(ids.a2)).state, 'reviewed', 'skip on a resolved assignment is a no-op');
  // the reminder was completed during the session: assigning it again is refused
  await assert.rejects(() => assign(uuid(), w, null, tomorrow, '09:00'), /open Work or Side Gig/);
  await setStatus(w, 'open');

  // snoozed reminders remain eligible; null duration uses the planned minutes
  await setStatus(w2, 'snoozed');
  const sessionTwo = uuid(); await startAssigned(sessionTwo, ids.a3);
  s = (await dash()).active_session;
  assert.equal(s.duration_minutes, 15, 'null duration falls back to the planned minutes');
  assert.equal((await assignmentRow(ids.a3)).state, 'in_progress', 'snoozed reminders stay eligible');
  await finishActive('progress', null);
  assert.equal((await assignmentRow(ids.a3)).state, 'reviewed');
  // a second assignment of the same reminder is allowed once the previous one is resolved
  const again = uuid(); await assign(again, w2, null, tomorrow, '08:00', 10);
  assert.equal((await assignmentRow(again)).state, 'planned');
  // shipped/ordering deadline fields come through for orders
  const orderR = await makeReminder(a, 'sidegig');
  await db.query('update reminders set is_order=true where id=$1', [orderR]);
  await db.query('insert into orders(reminder_id,user_id,ship_by) values($1,$2,$3)', [orderR, a, '2026-12-24']);
  const orderA = uuid(); await assign(orderA, orderR, null, tomorrow, '10:00', 25);
  assert.equal((await dash()).assignments.find((x) => x.id === orderA).ship_by, '2026-12-24');
  await db.query('select skip_focus_work($1)', [orderA]);
});

// ---------------------------------------------------------------- reminder lifecycle triggers
const lifecycle = { done: await makeReminder(a, 'work'), cancelled: await makeReminder(a, 'sidegig'), social: await makeReminder(a, 'work'),
  deleted: await makeReminder(a, 'work'), snoozed: await makeReminder(a, 'work'), running: await makeReminder(a, 'work'), shopping: await makeReminder(a, 'sidegig') };
const lc = {};
await asUser(a, async () => {
  for (const [name, reminder] of Object.entries(lifecycle)) { lc[name] = uuid(); await assign(lc[name], reminder, null, tomorrow, '09:00', 10); }
  await startAssigned(uuid(), lc.running, 10);
});
await setStatus(lifecycle.done, 'done');
await setStatus(lifecycle.cancelled, 'cancelled');
await setStatus(lifecycle.snoozed, 'snoozed');
await db.query("update reminders set context_id=(select id from contexts where user_id=$1 and slug='social') where id=$2", [a, lifecycle.social]);
await db.query("update reminders set context_id=(select id from contexts where user_id=$1 and slug='shopping') where id=$2", [a, lifecycle.shopping]);
await db.query('update reminders set title=$2 where id=$1', [lifecycle.running, 'renamed']); // unrelated edit: untouched
const states = Object.fromEntries(await Promise.all(Object.entries(lc).map(async ([k, id]) => [k, (await assignmentRow(id)).state])));
assert.deepEqual(states, { done: 'cancelled', cancelled: 'cancelled', social: 'cancelled', deleted: 'planned', snoozed: 'planned', running: 'in_progress', shopping: 'cancelled' });
await db.query("update reminders set context_id=(select id from contexts where user_id=$1 and slug='sidegig') where id=$2", [a, lifecycle.running]);
assert.equal((await assignmentRow(lc.running)).state, 'in_progress', 'moving within Work/Side Gig keeps work');
await db.query('delete from reminders where id=$1', [lifecycle.deleted]);
const deleted = await assignmentRow(lc.deleted);
assert.equal(deleted.state, 'cancelled'); assert.equal(deleted.reminder_id, null); assert.equal(deleted.reminder_title.startsWith('work'), true, 'snapshot survives deletion');
await db.query('delete from reminders where id=$1', [lifecycle.running]);
const running = await assignmentRow(lc.running);
assert.equal(running.state, 'in_progress', 'deleting leaves the in-progress assignment');
assert.equal((await one('select reminder_id from focus_sessions where assignment_id=$1', [lc.running])).reminder_id, null);
await asUser(a, async () => {
  await finishActive('interrupted', null);
  assert.equal((await assignmentRow(lc.running)).state, 'reviewed');
});

// ---------------------------------------------------------------- archive + grants + sign-in + realtime
await asUser(a, async () => {
  const keep = uuid(); const wKeep = await makeReminder(a, 'work'); const saturday = await nextIsoDay(6);
  await assign(keep, wKeep, ftSat, saturday, '09:00', 30);
  await db.query('select archive_focus_time($1)', [ftSat]);
  const stamp = (await one('select archived_at,enabled from focus_times where id=$1', [ftSat]));
  assert.ok(stamp.archived_at); assert.equal(stamp.enabled, false);
  await db.query('select archive_focus_time($1)', [ftSat]); // idempotent
  assert.equal((await one('select archived_at from focus_times where id=$1', [ftSat])).archived_at.getTime(), stamp.archived_at.getTime());
  const d = await dash();
  assert.ok(!d.focus_times.some((t) => t.id === ftSat), 'archived time disappears from the list');
  const kept = d.assignments.find((x) => x.id === keep);
  assert.ok(kept && kept.state === 'planned' && kept.focus_time_id === ftSat, 'planned work stays visible and recoverable');
  await assert.rejects(() => assign(uuid(), wKeep, ftSat, saturday, '09:00'), /removed/);
  await assert.rejects(() => save(ftSat, { days: [6] }), /removed/);
  await db.query('select skip_focus_work($1)', [keep]); // recoverable: skip still works
  await assert.rejects(() => db.query('select archive_focus_time($1)', [uuid()]), /Focus time not found/);
});
const rpcs = ['save_focus_preferences(1)', 'get_focus_dashboard_v2()', "save_focus_time(gen_random_uuid(),null,'work','{1}'::smallint[],'09:00',30,true)",
  'archive_focus_time(gen_random_uuid())', "assign_focus_work(gen_random_uuid(),gen_random_uuid(),null,current_date,'09:00',10)",
  'skip_focus_work(gen_random_uuid())', 'start_assigned_focus(gen_random_uuid(),gen_random_uuid(),10)'];
for (const call of rpcs) {
  await asUser(a, () => fail(`select ${call}`, [], /permission denied/), 'anon');
  await asUser('', () => fail(`select ${call}`, [], /Sign in required/));
}
await asUser(a, () => fail('select focus_review_assignment()', [], /permission denied/));
await asUser(a, () => fail('select focus_cancel_planned_work()', [], /permission denied/));
await asUser(a, () => fail('select focus_weekdays_valid(array[1]::smallint[])', [], /permission denied/));
const published = await db.query("select tablename from pg_publication_tables where pubname='supabase_realtime' and tablename in ('focus_preferences','focus_times','focus_assignments')");
assert.equal(published.rows.length, 3);
for (const table of ['focus_preferences', 'focus_times', 'focus_assignments']) {
  const rls = await one("select relrowsecurity as on from pg_class where oid=$1::regclass", [`public.${table}`]);
  assert.equal(rls.on, true, `${table} RLS`);
  const fk = await one(`select count(*)::int as n from pg_constraint c where c.conrelid=$1::regclass and c.contype='f' and c.confrelid='auth.users'::regclass and c.confdeltype='c'`, [`public.${table}`]);
  assert.equal(fk.n, 1, `${table} cascades on auth.users delete`);
}
// user deletion cascades every new table
await db.query('delete from auth.users where id=$1', [a]);
for (const table of ['focus_preferences', 'focus_times', 'focus_assignments', 'focus_sessions'])
  assert.equal((await one(`select count(*)::int as n from ${table} where user_id=$1`, [a])).n, 0, `${table} cascade`);
console.log('PASS focus times SQL: preferences, dashboard v2, validation, cross-user denial, idempotent assign/start, moves, triggers, grants, realtime, cascades');
await db.close();
