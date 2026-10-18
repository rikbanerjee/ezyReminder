import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// One-time isolated runtime: npm install --prefix /tmp/ezy-sql-tests @electric-sql/pglite
// Run: node scripts/test-edit-order-reminder.mjs /tmp/ezy-sql-tests/package.json
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
const ctx = await one("select id from contexts where user_id=$1 and slug='work'",[a]);
const otherCtx = await one("select id from contexts where user_id=$1 and slug='sidegig'",[a]);
const bCtx = await one("select id from contexts where user_id=$1 and slug='work'",[b]);
await db.exec(await readFile(`${root}/supabase/migrations/0010_edit_order_reminder.sql`,'utf8'));

const createOrder = async (id,title='Order') => {
  await db.query('insert into reminders(id,user_id,context_id,title,is_order,status,snoozed_until) values ($1,$2,$3,$4,true,$5,$6)',[id,a,ctx.id,title,'open',null]);
  await db.query('insert into orders(reminder_id,user_id,tracking_number,shipped_at) values ($1,$2,$3,$4)',[id,a,null,null]);
};
const call = async (id, opts = {}) => {
  const args = [id, opts.title ?? '  Corrected order  ', opts.notes ?? '  Notes  ', opts.due ?? null,
    opts.context ?? ctx.id, opts.channels ?? ['email'], opts.orderRef ?? '  REF  ',
    opts.recipient ?? ' Buyer ', opts.shipBy ?? '2026-11-04', opts.carrier ?? 'UPS',
    opts.tracking ?? '  1Z123  ', opts.shipped ?? null];
  return db.query('select public.edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) as id',args);
};

await createOrder('30000000-0000-4000-8000-000000000001','Already shipped');
await db.query("update reminders set status='done' where id=$1",['30000000-0000-4000-8000-000000000001']);
const priorStamp = '2026-10-01T12:00:00Z';
await db.query('update orders set shipped_at=$1 where reminder_id=$2',[priorStamp,'30000000-0000-4000-8000-000000000001']);
await asUser(a, async () => {
  await call('30000000-0000-4000-8000-000000000001',{context:otherCtx.id,tracking:'   '});
});
let row = await one(`select r.title,r.notes,r.status,r.context_id,o.order_ref,o.recipient_name,o.ship_by,o.carrier,o.tracking_number,o.shipped_at
from reminders r join orders o on o.reminder_id=r.id where r.id=$1`,['30000000-0000-4000-8000-000000000001']);
assert.equal(row.title,'Corrected order'); assert.equal(row.notes,'Notes'); assert.equal(row.status,'done');
assert.equal(row.context_id,otherCtx.id); assert.equal(row.order_ref,'REF'); assert.equal(row.recipient_name,'Buyer');
assert.equal(row.tracking_number,null); assert.equal(row.shipped_at.toISOString(),new Date(priorStamp).toISOString());

await createOrder('30000000-0000-4000-8000-000000000002','Pending');
await asUser(a,async()=>call('30000000-0000-4000-8000-000000000002',{shipped:true}));
row=await one('select r.status,r.snoozed_until,o.shipped_at from reminders r join orders o on o.reminder_id=r.id where r.id=$1',['30000000-0000-4000-8000-000000000002']);
assert.equal(row.status,'done'); assert.equal(row.snoozed_until,null); assert.ok(row.shipped_at);
const trueStamp=row.shipped_at.toISOString();
await asUser(a,async()=>call('30000000-0000-4000-8000-000000000002',{shipped:true}));
row=await one('select shipped_at from orders where reminder_id=$1',['30000000-0000-4000-8000-000000000002']);
assert.equal(row.shipped_at.toISOString(),trueStamp,'mark shipped again preserves original timestamp');
await asUser(a,async()=>call('30000000-0000-4000-8000-000000000002',{shipped:false}));
row=await one('select r.status,r.snoozed_until,o.shipped_at from reminders r join orders o on o.reminder_id=r.id where r.id=$1',['30000000-0000-4000-8000-000000000002']);
assert.equal(row.status,'open'); assert.equal(row.snoozed_until,null); assert.equal(row.shipped_at,null);

await createOrder('30000000-0000-4000-8000-000000000003','Snoozed but unshipped');
const snooze='2026-10-20T12:00:00Z';
await db.query("update reminders set status='snoozed',snoozed_until=$1 where id=$2",[snooze,'30000000-0000-4000-8000-000000000003']);
await asUser(a,async()=>call('30000000-0000-4000-8000-000000000003',{shipped:false}));
row=await one('select r.status,r.snoozed_until,o.shipped_at from reminders r join orders o on o.reminder_id=r.id where r.id=$1',['30000000-0000-4000-8000-000000000003']);
assert.equal(row.status,'snoozed'); assert.equal(row.snoozed_until.toISOString(),new Date(snooze).toISOString()); assert.equal(row.shipped_at,null);

let carrierIndex = 0;
for (const [carrier, okLen, badLen] of [['UPS',34,35],['USPS',34,35],['FedEx',34,35],['DHL',39,40],['Other',64,65]]) {
  carrierIndex++;
  const orderId = `40000000-0000-4000-8000-${String(carrierIndex).padStart(12,'0')}`;
  await createOrder(orderId,carrier);
  const accepted='T'.repeat(okLen);
  await asUser(a,async()=>call(orderId,{carrier,tracking:accepted}));
  const stored=await one('select tracking_number from orders where reminder_id=$1',[orderId]);
  assert.equal(stored.tracking_number,accepted,`${carrier} max accepted`);
  await expectFailure('select edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',[
    orderId,'x',null,null,ctx.id,['email'],null,null,null,carrier,'T'.repeat(badLen),null,
  ]);
}

await createOrder('50000000-0000-4000-8000-000000000001','A');
await asUser(a,async()=>expectFailure('select edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',[
  '50000000-0000-4000-8000-000000000001','',null,null,ctx.id,[],null,null,null,null,null,null,
]));
await asUser(a,async()=>expectFailure('select edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',[
  '50000000-0000-4000-8000-000000000001','x',null,null,bCtx.id,[],null,null,null,null,null,null,
]));
await asUser(b,async()=>expectFailure('select edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',[
  '50000000-0000-4000-8000-000000000001','x',null,null,bCtx.id,[],null,null,null,null,null,null,
]));

await createOrder('50000000-0000-4000-8000-000000000002','Atomic before');
await db.exec(`create function public.fail_test_order_update() returns trigger language plpgsql as $$
begin if new.tracking_number='FAIL' then raise exception 'injected order write failure'; end if; return new; end $$;
create trigger fail_test_order_update before update on public.orders for each row execute function public.fail_test_order_update();`);
await asUser(a,async()=>expectFailure('select edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',[
  '50000000-0000-4000-8000-000000000002','Should roll back',null,null,ctx.id,[],null,null,null,'UPS','FAIL',true,
]));
row=await one('select r.title,r.status,o.tracking_number,o.shipped_at from reminders r join orders o on o.reminder_id=r.id where r.id=$1',['50000000-0000-4000-8000-000000000002']);
assert.equal(row.title,'Atomic before'); assert.equal(row.status,'open'); assert.equal(row.tracking_number,null); assert.equal(row.shipped_at,null);
await db.exec('drop trigger fail_test_order_update on public.orders; drop function public.fail_test_order_update();');
await db.exec('set role anon'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[a]);
await expectFailure('select edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',[
  '50000000-0000-4000-8000-000000000001','x',null,null,ctx.id,[],null,null,null,null,null,null,
]);
await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub','',false)");

const fn=await one("select prosecdef,proargnames,pg_get_function_arguments(oid) args from pg_proc where proname='edit_order_reminder'");
assert.equal(fn.prosecdef,false); assert.equal(fn.proargnames[11],'p_shipped'); assert.match(fn.args,/p_shipped boolean DEFAULT NULL/);
await expectFailure('select edit_order_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',[
  '50000000-0000-4000-8000-000000000001','x',null,null,ctx.id,[],null,null,null,null,null,
]);
console.log('PASS edit_order_reminder contract, state transitions, validation, ownership, and grants');
await db.close();
