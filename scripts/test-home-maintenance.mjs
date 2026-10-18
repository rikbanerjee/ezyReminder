import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Run: node scripts/test-home-maintenance.mjs /tmp/ezy-ios-sql-check/package.json
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const runtimePackage = process.argv[2] ?? resolve(root, 'package.json');
const require = createRequire(runtimePackage);
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const a = '10000000-0000-4000-8000-000000000001';
const b = '20000000-0000-4000-8000-000000000002';
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const expectFailure = async (sql, params = []) => {
  let failed = false;
  try { await db.query(sql, params); } catch { failed = true; }
  assert.equal(failed, true, `expected failure: ${sql}`);
};
const asUser = async (id, fn) => {
  await db.exec('set role authenticated');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]);
  try { return await fn(); } finally {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub','',false)");
  }
};

await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create table auth.users(id uuid primary key,email text);
create publication supabase_realtime;
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;`);
for (const name of ['0001_init.sql','0002_delivery.sql','0003_context_panels.sql','0004_shopping.sql','0005_onboarding.sql','0006_remove_slack.sql','0007_ios_foundation.sql','0008_guard_notification_channels.sql','0009_notification_occurrences.sql']) {
  let sql = await readFile(`${root}/supabase/migrations/${name}`,'utf8');
  if (name === '0001_init.sql') sql = sql.replace(/create extension if not exists "pgcrypto";\s*/i,'');
  await db.exec(sql);
}
await db.exec(`grant usage on schema public,auth to anon,authenticated,service_role;
grant select,insert,update,delete on all tables in schema public to authenticated,service_role;
grant usage,select on all sequences in schema public to authenticated,service_role;`);
await db.query('insert into auth.users(id,email) values ($1,$2),($3,$4)',[a,'a@example.com',b,'b@example.com']);
await db.exec(await readFile(`${root}/supabase/migrations/0010_edit_order_reminder.sql`,'utf8'));

await db.exec(await readFile(`${root}/supabase/migrations/0011_home_maintenance.sql`,'utf8'));
const save = (args = {}) => one('select save_home_maintenance($1,$2,$3,$4,$5,$6,$7,$8) as id', [args.id ?? null, args.title ?? 'Change air filter', 'Filter size 20x20', '2026-11-01T14:00:00Z', args.category ?? 'filter', 'Upstairs HVAC', args.repeat === undefined ? 3 : args.repeat, args.channels ?? ['email']]);
const current = (id) => one('select * from reminders where id=$1', [id]);
const record = (r, serviced = '2026-01-31T14:00:00Z') => one('select record_home_service($1,$2,$3,$4) as id', [r.id, r.updated_at, serviced, 'Changed filter; part ABC']);
let recurring, single, before;
await db.query("update user_settings set timezone='America/New_York' where user_id=$1",[a]);
await asUser(a, async () => {
  recurring = (await save({ repeat: 1 })).id;
  before = await current(recurring);
  assert.deepEqual(before.tags, ['home:filter']);
  const social = await one("select id from contexts where slug='social' and user_id=auth.uid()");
  assert.equal(before.context_id, social.id);
  await record(before);
  const next = await current(recurring);
  assert.equal(next.status, 'open');
  assert.equal(next.due_at.toISOString(), '2026-02-28T14:00:00.000Z', 'month end must clamp');
  assert.equal(next.snoozed_until, null);
  const history = await one('select * from home_service_records where reminder_id=$1',[recurring]);
  assert.equal(history.notes,'Changed filter; part ABC');
  assert.equal(history.asset,'Upstairs HVAC');
  await expectFailure('select record_home_service($1,$2,$3,$4)',[before.id,before.updated_at,'2026-01-31T14:00:00Z','duplicate']);
  const count = await one('select count(*)::int as n from home_service_records where reminder_id=$1',[recurring]);
  assert.equal(count.n,1,'duplicate/stale service must not append history');
  // Preserve the local hour across daylight saving time.
  await record(next, '2026-02-15T14:00:00Z');
  assert.equal((await current(recurring)).due_at.toISOString(),'2026-03-15T13:00:00.000Z');
  single = (await save({repeat:null, category:'car', title:'Vehicle inspection'})).id;
  await record(await current(single));
  assert.equal((await current(single)).status,'done');
  await expectFailure('select record_home_service($1,$2,$3,$4)',[recurring,(await current(recurring)).updated_at,'2999-01-01','future']);
  for (const category of ['hvac','dryer','other']) await save({category});
  for (const args of [{title:' '},{category:'invalid'},{repeat:0},{repeat:121},{channels:[]},{channels:['whatsapp']}]) {
    await assert.rejects(()=>save(args));
  }
  const atomic = await one("select count(*)::int as n from reminders where tags=array['home:invalid']");
  assert.equal(atomic.n,0,'invalid detail insert must roll back parent reminder');
});
await asUser(b, async () => {
  assert.equal((await db.query('select * from home_maintenance where reminder_id=$1',[recurring])).rows.length,0);
  assert.equal((await db.query('select * from home_service_records')).rows.length,0);
  await assert.rejects(()=>save({id:recurring}));
  await expectFailure('select record_home_service($1,$2,$3,$4)',[recurring,before.updated_at,'2026-01-01','foreign']);
  await expectFailure("insert into home_maintenance(reminder_id,user_id,category) values($1,$2,'car')",[recurring,b]);
});
await asUser(a, async () => {
  await db.query('delete from reminders where id=$1',[single]);
  const record = await one("select * from home_service_records where title='Vehicle inspection'");
  assert.equal(record.reminder_id,null,'service history survives reminder deletion');
  assert.equal((await one('select count(*)::int as n from contexts')).n,4,'Home must preserve the four contexts');
});
await db.exec('set role anon');
await expectFailure('select save_home_maintenance(null,$1,null,now(),$2,$3,null,$4)',['No auth','car','Car',['email']]);
await db.exec('reset role');
// Upgrade existing Home data in place: no rewrite of legacy filter tasks/history.
await db.exec(await readFile(`${root}/supabase/migrations/0014_contextual_home_tasks.sql`,'utf8'));
const task = (args={}) => one('select save_home_task($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id', [args.id??null,args.title??'Home task','Contextual notes',args.due??'2026-01-31T14:00:00Z',args.category??'car',args.asset??'Family car',args.months??null,['email'],args.details??{},args.days??null]);
let bill,study,battery;
await asUser(a, async()=>{
  const legacy = await one('select category,details from home_maintenance where reminder_id=$1',[recurring]);
  assert.equal(legacy.category,'filter'); assert.deepEqual(legacy.details,{});
  const car=(await task({details:{make:'Toyota',model:'Camry'},months:6})).id;
  await record(await current(car));
  const snapshot=await one('select details from home_service_records where reminder_id=$1',[car]);
  assert.deepEqual(snapshot.details,{make:'Toyota',model:'Camry'});
  await task({id:car,details:{make:'Honda',model:'Civic'},months:6});
  assert.deepEqual((await one('select details from home_service_records where reminder_id=$1',[car])).details,snapshot.details,'history must retain vehicle snapshot after edits');
  bill=(await task({category:'bill',title:'Internet bill',asset:'Provider',months:1,details:{amount:'85.50',currency:'USD'}})).id;
  await record(await current(bill),'2026-01-20T14:00:00Z');
  assert.equal((await current(bill)).due_at.toISOString(),'2026-02-28T14:00:00.000Z','early payment must preserve billing due date');
  assert.deepEqual((await one('select details from home_service_records where reminder_id=$1',[bill])).details,{amount:'85.50',currency:'USD'});
  study=(await task({category:'study',title:'Math practice',asset:'Alex',due:'2026-03-06T14:00:00Z',days:7,details:{subject:'Math',teacher:'Ms Lee'}})).id;
  await record(await current(study),'2026-03-07T14:00:00Z');
  assert.equal((await current(study)).due_at.toISOString(),'2026-03-13T13:00:00.000Z','weekly study must preserve local hour and planned day through DST');
  battery=(await task({category:'battery',days:7,details:{battery_type:'USB-C'}})).id;
  await record(await current(battery),'2026-03-07T14:00:00Z');
  assert.equal((await current(battery)).due_at.toISOString(),'2026-03-14T13:00:00.000Z','battery interval starts from actual completion');
  await task({category:'hvac',details:{filter_size:'20 x 20 x 1'}});
  await task({id:study,category:'study',months:1,details:{subject:'Reading'}});
  assert.equal((await one('select repeat_days from home_maintenance where reminder_id=$1',[study])).repeat_days,null,'changing repeat units clears the old unit');
  for (const details of [{amount:'abc',currency:'USD'},{amount:'5.555',currency:'USD'},{amount:'-5',currency:'USD'},{amount:'5'},{currency:'US'},{make:'Toyota'}]) await assert.rejects(()=>task({category:'bill',details}));
  for (const details of [null,[],{make:42},{make:'x'.repeat(1001)},{password:'no'}]) {
    await expectFailure('select save_home_task(null,$1,null,now(),$2,$3,null,$4,$5,null)',['Invalid task','car','Car',['email'],details]);
  }
  await assert.rejects(()=>task({id:battery,category:'battery',days:7,months:1}));
  const after=await one('select repeat_days,repeat_months,details from home_maintenance where reminder_id=$1',[battery]);
  assert.equal(after.repeat_days,7);assert.equal(after.repeat_months,null);assert.deepEqual(after.details,{battery_type:'USB-C'});
  await assert.rejects(()=>task({days:0}));
  await assert.rejects(()=>task({days:3661}));
  assert.equal((await one('select count(*)::int as n from contexts')).n,4);
});
await asUser(b,async()=>{
  await assert.rejects(()=>task({id:battery,category:'battery',days:14,details:{battery_type:'AA'}}));
  assert.equal((await db.query('select * from home_service_records where reminder_id=$1',[bill])).rows.length,0);
});
await asUser(a,async()=>assert.equal((await one('select repeat_days from home_maintenance where reminder_id=$1',[battery])).repeat_days,7));
await db.exec('set role anon');
await expectFailure('select save_home_task(null,$1,null,now(),$2,$3,null,$4,$5,null)',['Anonymous','car','Car',['email'],{}]);
await db.exec('reset role');
await db.close();
console.log('PASS Home SQL: contextual fields, legacy data, ownership, atomic writes, detail snapshots, bill schedules, weekly repeats, month-end and DST.');
