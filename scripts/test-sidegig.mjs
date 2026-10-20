import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Run against isolated embedded PostgreSQL (never hosted Supabase):
// npm install --prefix /tmp/ezy-sidegig-sql @electric-sql/pglite
// node scripts/test-sidegig.mjs /tmp/ezy-sidegig-sql/package.json
// Applies the complete migration chain, including Side Gig 0018.
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
await db.query('insert into auth.users(id,email) values ($1,$2),($3,$4)', [a,'a@example.com',b,'b@example.com']);
const mutate=(action,id,payload={},op=uuid())=>one('select sidegig_mutate($1,$2,$3,$4) id',[op,action,id,payload]);
const dashboard=()=>one('select get_sidegig_dashboard() d').then(r=>r.d);
let workId=uuid(),orderId=uuid(),paymentId=uuid(),followId=uuid(),workReminder;
const future='2099-10-22T14:00:00Z';
await asUser(a,async()=>{
  // Capture through the existing generic RPC, then enrich that exact record.
  const ctx=(await one("select id from contexts where user_id=$1 and slug='sidegig'",[a])).id;
  const captured=(await one("select create_reminder(p_title=>'Quick capture',p_notes=>null,p_context_id=>$1,p_due_at=>null,p_channels=>'{}'::text[],p_is_order=>false,p_order_ref=>null,p_recipient_name=>null,p_ship_by=>null,p_carrier=>null) id",[ctx])).id;
  const capturedItem=(await dashboard()).items.find(x=>x.reminder_id===captured);
  assert.ok(capturedItem,'plain capture appears in Side Gig before enrichment');
  assert.equal(capturedItem.context_slug,'sidegig');
  assert.equal(capturedItem.kind,'work');
  assert.equal(capturedItem.status,'open');
  await mutate('save_work',captured,{title:'Quick capture',next_step:'Pack the sample',minutes:15});
  assert.deepEqual((await one('select channels from reminders where id=$1',[captured])).channels,[],'editing keeps context-inherited delivery');
  await mutate('save_work',captured,{title:'Quick capture',is_order:true,ship_by:'2099-10-22',channels:[],minutes:15});
  assert.equal((await one('select is_order from reminders where id=$1',[captured])).is_order,true);
  assert.equal((await one('select count(*)::int n from orders where reminder_id=$1',[captured])).n,1,'turning capture into an order keeps its ID');
  assert.equal((await dashboard()).items.filter(x=>x.reminder_id===captured).length,1);
  await assert.rejects(()=>mutate('save_work',captured,{title:'Quick capture',channels:['invalid']}));
  const work={title:'Client proposal',due_at:future,next_step:'Compare pricing',minutes:15};
  const op=uuid();await mutate('save_work',workId,work,op);await mutate('save_work',workId,work,op);
  await assert.rejects(()=>mutate('save_work',workId,{...work,title:'Different'},op));
  assert.equal((await one('select count(*)::int n from reminders where id=$1',[workId])).n,1);
  await mutate('save_work',orderId,{title:'Ship mugs',is_order:true,ship_by:'2099-10-23',person:'Sarah',reference:'Order 42'});
  await mutate('save_payment',paymentId,{title:'Mug balance',due_at:future,amount:'320.10',currency:'USD',related_id:orderId});
  await mutate('save_followup',followId,{title:'Await approval',due_at:future,related_id:workId,block_work:true});
  let d=await dashboard();assert.equal(d.items.find(x=>x.id===workId).waiting,true);
  workReminder=d.items.find(x=>x.id===followId).reminder_id;
  await fail('select start_focus_session($1,$2,15,null)',[uuid(),workId]);
  await fail('select start_focus_session($1,$2,15,null)',[uuid(),workReminder]);
  await mutate('contact',followId,{due_at:'2099-10-24T14:00:00Z',notes:'Checked in'});
  d=await dashboard();assert.equal(d.items.find(x=>x.id===followId).activity.length,1);
  assert.equal(new Date(d.items.find(x=>x.id===workId).due_at).toISOString(),future.replace('Z','.000Z'));
  await mutate('resolve',followId,{unblock:true});assert.equal((await dashboard()).items.find(x=>x.id===workId).waiting,false);
  const shipOp=uuid();await mutate('ship',orderId,{tracking:'DEMO',carrier:'USPS'},shipOp);
  const shipped=(await dashboard()).items.find(x=>x.id===orderId).shipped_at;
  await mutate('ship',orderId,{tracking:'DEMO',carrier:'USPS'},shipOp);
  assert.equal((await dashboard()).items.find(x=>x.id===orderId).shipped_at,shipped);
  assert.equal((await dashboard()).items.find(x=>x.id===paymentId).status,'open');
  const legacy1=(await one('select create_follow_up($1) id',[orderId])).id;
  const legacy2=(await one('select create_follow_up($1) id',[orderId])).id;
  assert.equal(legacy1,legacy2,'legacy buyer follow-ups reuse the open commitment');
  assert.ok((await dashboard()).items.some(x=>x.kind==='followup'&&x.reminder_id===legacy1));
  const pr=(await dashboard()).items.find(x=>x.id===paymentId).reminder_id;
  // Exercise actual enqueue/claim fallback behavior, including an already queued
  // payment and an empty channel list that otherwise inherits context email.
  const past='2026-01-01T14:00:00Z';
  await mutate('save_payment',paymentId,{title:'Mug balance',due_at:past,amount:'320.10',currency:'USD',related_id:orderId});
  await db.exec('reset role');
  await db.exec('select enqueue_due_notifications()');
  await db.exec('set role authenticated');
  assert.ok((await db.query('select id from notifications where reminder_id=$1 and superseded_at is null',[pr])).rows.length);
  const collection=uuid();
  await mutate('save_followup',collection,{title:'Collect balance',due_at:future,related_payment_id:paymentId});
  assert.equal((await one('select due_at from reminders where id=$1',[pr])).due_at,null);
  assert.equal(new Date((await dashboard()).items.find(x=>x.id===paymentId).due_at).toISOString(),new Date(past).toISOString(),'expected date stays independent of its delivery hold');
  await db.exec('reset role');
  await db.exec('select enqueue_due_notifications()');
  const heldClaim=(await db.query('select * from claim_due_notifications(25)')).rows;
  assert.ok(!heldClaim.some(n=>n.reminder_id===pr),'collection hold prevents claiming payment via the context fallback');
  await db.exec('set role authenticated');
  // Editing an expected date cannot accidentally release delivery while held.
  await mutate('save_payment',paymentId,{title:'Mug balance',due_at:future,amount:'320.10',currency:'USD',related_id:orderId});
  assert.equal((await one('select due_at from reminders where id=$1',[pr])).due_at,null);
  assert.deepEqual((await one('select channels from reminders where id=$1',[pr])).channels,[],'collection follow-up is the only delivery source');
  await mutate('resolve',collection,{});
  assert.deepEqual((await one('select channels from reminders where id=$1',[pr])).channels,['email'],'closing the follow-up restores prior channels');
  assert.equal(new Date((await one('select due_at from reminders where id=$1',[pr])).due_at).toISOString(),new Date(future).toISOString(),'closing restores the latest expected date for delivery');
  await mutate('save_work',workId,{title:'Client proposal',due_at:future,next_step:'',minutes:15});
  assert.equal((await dashboard()).items.find(x=>x.id===workId).next_step,null,'clearing a current next step stays blank');
  assert.ok((await dashboard()).items.find(x=>x.id===orderId).due_at,'ship-by without a reminder time still schedules delivery');

  await fail("update reminders set status='done' where id=$1",[pr]);
  await mutate('receive',paymentId,{received_on:'2026-01-01',notes:'Transfer confirmed'});
  d=await dashboard();assert.equal(d.items.find(x=>x.id===paymentId).status,'received');
  assert.equal(d.items.find(x=>x.id===paymentId).amount,'320.10');
  assert.equal(d.items.find(x=>x.id===orderId).shipped_at,shipped);
  assert.equal(d.items.find(x=>x.id===workId).status,'open');
  await mutate('shipping',orderId,{tracking:'CORRECTED',carrier:'USPS'});
  assert.equal((await dashboard()).items.find(x=>x.id===orderId).shipped_at,shipped);
  for(const amount of ['-1','1.001','0','bad'])await assert.rejects(()=>mutate('save_payment',uuid(),{title:'Invalid',due_at:future,amount,currency:'USD'}));
  await assert.rejects(()=>mutate('save_payment',uuid(),{title:'No currency',due_at:future,amount:'1'}));
  await assert.rejects(()=>mutate('save_followup',uuid(),{title:'No date'}));
  await db.query('delete from reminders where id=$1',[pr]);
  assert.equal((await dashboard()).items.find(x=>x.id===paymentId).status,'received','receipt history survives reminder deletion');
});
await asUser(b,async()=>{
  assert.equal((await dashboard()).items.some(x=>x.id===orderId),false);
  await assert.rejects(()=>mutate('save_work',workId,{title:'Foreign'}));
  await assert.rejects(()=>mutate('receive',paymentId,{received_on:'2026-01-01'}));
  await assert.rejects(()=>mutate('save_followup',uuid(),{title:'Foreign relation',due_at:future,related_id:workId}));
  assert.equal((await db.query('select * from sidegig_activity')).rows.length,0);
  await fail('insert into sidegig_work_state(reminder_id,user_id) values($1,$2)',[workId,b]);
});
for(const fn of ['sidegig_reminder_guard()','sidegig_focus_guard()','sidegig_collection_delivery()']) {
  assert.equal((await one("select has_function_privilege('authenticated',$1,'execute') allowed",[fn])).allowed,false,'internal helpers are not executable by clients');
}
await asUser(null,()=>fail('select get_sidegig_dashboard()',[]),'anon');
await asUser(null,()=>fail('select sidegig_mutate($1,$2,$3,$4)',[uuid(),'save_work',uuid(),{title:'Anonymous'}]),'anon');
await db.query('delete from auth.users where id=$1',[a]);
assert.equal((await one('select count(*)::int n from sidegig_operations where user_id=$1',[a])).n,0);
await db.close();
console.log('PASS Side Gig SQL: atomic writes, retries, ownership, waiting, Focus guards, shipment/payment independence, receipt history, exact money and account deletion.');
