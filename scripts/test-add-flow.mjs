import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Today's Add flow (DESIGN.md §5.1) against isolated embedded PostgreSQL
// (never hosted Supabase): each destination's existing RPC writes one
// canonical record that Today, Side Gig, Ship Queue and Home all read.
// npm install --prefix /tmp/ezy-sidegig-sql @electric-sql/pglite
// node scripts/test-add-flow.mjs /tmp/ezy-sidegig-sql/package.json
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(process.argv[2] ?? resolve(root, 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const a = '10000000-0000-4000-8000-000000000001';
const b = '20000000-0000-4000-8000-000000000002';
let sequence = 0;
const uuid = () => `30000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`;
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const asUser = async (id, fn, role = 'authenticated') => {
  await db.exec(`set role ${role}`);
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
const migrations = (await readdir(`${root}/supabase/migrations`)).filter((n) => /^\d{4}_.*\.sql$/.test(n)).sort();
for (const name of migrations) {
  let sql = await readFile(`${root}/supabase/migrations/${name}`, 'utf8');
  if (name.startsWith('0001_')) sql = sql.replace(/create extension if not exists "pgcrypto";\s*/i, '');
  await db.exec(sql);
  if (name.startsWith('0011_')) {
    await db.exec(`grant usage on schema public,auth to anon,authenticated,service_role;
grant select,insert,update,delete on all tables in schema public to authenticated,service_role;
grant usage,select on all sequences in schema public to authenticated,service_role;`);
  }
}
await db.query('insert into auth.users(id,email) values ($1,$2),($3,$4)', [a,'a@example.com',b,'b@example.com']);
const config = JSON.parse(await readFile(`${root}/design/home-templates.json`, 'utf8'));
const mutate=(action,id,payload={},op=uuid())=>one('select sidegig_mutate($1,$2,$3,$4) id',[op,action,id,payload]);
const dashboard=()=>one('select get_sidegig_dashboard() d').then(r=>r.d);
// The Today feed (lib/home-data.ts): open/snoozed reminders under RLS.
const today=()=>db.query("select id,title,status,is_order,tags,context_id from reminders where status in ('open','snoozed')").then(r=>r.rows);

await asUser(a,async()=>{
  const sidegig=(await one("select id from contexts where user_id=$1 and slug='sidegig'",[a])).id;

  // Today → Side Gig → Task: a title alone is enough; the client owns the ID.
  const task=uuid(), op=uuid();
  await mutate('save_work',task,{title:'Draft client proposal',minutes:15},op);
  await mutate('save_work',task,{title:'Draft client proposal',minutes:15},op); // a repeated submit is a no-op
  assert.equal((await one('select count(*)::int n from reminders where id=$1',[task])).n,1,'one canonical reminder');
  const row=(await today()).find(r=>r.id===task);
  assert.ok(row,'Today lists the task immediately');
  assert.equal(row.context_id,sidegig);
  let item=(await dashboard()).items.find(r=>r.reminder_id===task);
  assert.equal(item?.kind,'work','Side Gig Work lists the same record before enrichment');
  assert.equal(item.status,'open');

  // Editing from either view updates that ID; completing from Today closes it in Side Gig.
  await mutate('save_work',task,{title:'Send client proposal',next_step:'Attach pricing',minutes:20});
  item=(await dashboard()).items.find(r=>r.reminder_id===task);
  assert.equal(item.title,'Send client proposal');
  assert.equal(item.next_step,'Attach pricing');
  assert.equal((await today()).find(r=>r.id===task).title,'Send client proposal');
  await db.query("update reminders set status='done',snoozed_until=null where id=$1",[task]); // completeReminder
  assert.equal((await dashboard()).items.find(r=>r.reminder_id===task).status,'done');
  assert.ok(!(await today()).some(r=>r.id===task));

  // Today → Side Gig → Order: also a Ship Queue order.
  const order=uuid();
  await mutate('save_work',order,{title:'Ship mug to Sam',is_order:true,minutes:15});
  assert.equal((await dashboard()).items.find(r=>r.reminder_id===order)?.kind,'order');
  assert.equal((await one('select count(*)::int n from orders where reminder_id=$1',[order])).n,1);
  assert.equal((await today()).find(r=>r.id===order)?.is_order,true);

  // Follow-up and expected payment keep their own records and reminders.
  const payment=uuid();
  await mutate('save_payment',payment,{title:'Invoice 12',due_at:'2099-11-01T14:00:00Z',amount:'120.00',currency:'USD'});
  const paid=(await dashboard()).items.find(r=>r.id===payment);
  assert.equal(paid.kind,'payment');
  assert.ok((await today()).some(r=>r.id===paid.reminder_id),'the payment reminder is on Today');

  // Today → Home → Bill pay: save_home_task files it under Bill pay, as a Social reminder.
  const bill=(await one("select save_home_task(null,'Electricity','',$1,'bill','City Power',1,'{email}',$2,null) id",['2099-11-05T14:00:00Z',{amount:'85.50',currency:'USD'}])).id;
  const home=await one('select category,details from home_maintenance where reminder_id=$1',[bill]);
  assert.equal(config.templates[home.category].section,'bills','Home shows it in Bill pay');
  assert.deepEqual(home.details,{amount:'85.50',currency:'USD'});
  const billRow=(await today()).find(r=>r.id===bill);
  assert.ok(billRow,'Today lists the bill');
  assert.equal((await one('select slug from contexts where id=$1',[billRow.context_id])).slug,'social','Home is a view, not a fifth context');
});
// Another account (with its own onboarding examples) sees none of it.
await asUser(b,async()=>{
  assert.equal((await one('select count(*)::int n from reminders where user_id<>$1',[b])).n,0);
  assert.equal((await one('select count(*)::int n from home_maintenance')).n,0);
  assert.ok(!(await dashboard()).items.some(r=>r.title==='Ship mug to Sam'));
});
console.log('PASS Today Add flow SQL: one canonical record per destination, visible in Today, Side Gig, Ship Queue and Home; edits/completion shared; repeat submits idempotent; owner-only.');
