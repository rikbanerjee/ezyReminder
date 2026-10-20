import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const migrationDir = process.env.EZY_MIGRATION_DIR
  ? resolve(process.env.EZY_MIGRATION_DIR)
  : resolve(here, "../supabase/migrations");
const PGliteModule = process.env.EZY_SQL_RUNTIME
  ? createRequire(resolve(process.env.EZY_SQL_RUNTIME, "package.json"))("@electric-sql/pglite")
  : await import("@electric-sql/pglite");
const { PGlite } = PGliteModule;
const files = ["0001_init.sql", "0002_delivery.sql", "0003_context_panels.sql", "0004_shopping.sql", "0005_onboarding.sql", "0006_remove_slack.sql", "0007_ios_foundation.sql"];
const db = new PGlite();
const passed = [];
const ids = {
  a: "10000000-0000-4000-8000-000000000001",
  b: "20000000-0000-4000-8000-000000000002",
};

async function exec(sql) { return db.exec(sql); }
async function one(sql, params = []) { return (await db.query(sql, params)).rows[0]; }
async function expectError(label, sql, params = []) {
  let didThrow = false;
  try { await db.query(sql, params); } catch { didThrow = true; }
  assert.equal(didThrow, true, `${label} should fail`);
}
async function pass(label, fn) {
  await fn();
  passed.push(label);
  console.log(`PASS ${label}`);
}
async function asUser(id, fn) {
  await exec("set role authenticated");
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id]);
  try { return await fn(); }
  finally {
    await exec("reset role");
    await db.query("select set_config('request.jwt.claim.sub', '', false)");
  }
}

await exec(`
  create role anon;
  create role authenticated;
  create role service_role bypassrls;
  create schema auth;
  create table auth.users (id uuid primary key, email text);
  create publication supabase_realtime;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
`);
// PGlite does not provide pgcrypto; UUID generation is built into PostgreSQL 18.
for (const file of files) {
  let sql = await readFile(`${migrationDir}/${file}`, "utf8");
  if (file === "0001_init.sql") sql = sql.replace(/create extension if not exists "pgcrypto";\s*/i, "");
  await exec(sql);
  console.log(`MIGRATION ${file} passed`);
}
await exec(`grant usage on schema public, auth to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant select, insert, update, delete on auth.users to service_role;`);

await exec(`insert into auth.users(id,email) values ('${ids.a}','a@example.com'),('${ids.b}','b@example.com')`);
const aShopping = await one("select id from contexts where user_id=$1 and slug='shopping'", [ids.a]);
const aWork = await one("select id from contexts where user_id=$1 and slug='work'", [ids.a]);
const bWork = await one("select id from contexts where user_id=$1 and slug='work'", [ids.b]);

// Simulate rows and context defaults written by a production client before 0008.
await db.query("update contexts set default_channel='apns' where id=$1", [bWork.id]);
const legacyRows = await db.query(`
  insert into reminders(user_id,context_id,title,channels,due_at) values
    ($1,$2,'Legacy mixed channels',array['whatsapp','slack','email','whatsapp',null]::text[],now()-interval '1 minute'),
    ($1,$2,'Legacy invalid channels',array['slack',null]::text[],now()-interval '1 minute'),
    ($1,$2,'Legacy context default',array[]::text[],now()-interval '1 minute')
  returning id,title`, [ids.b,bWork.id]);
const legacyReminderIds = Object.fromEntries(legacyRows.rows.map((row) => [row.title, row.id]));
await exec(await readFile(`${migrationDir}/0008_guard_notification_channels.sql`, "utf8"));
console.log("MIGRATION 0008_guard_notification_channels.sql passed");

const historyRows = await db.query(`
  insert into reminders(user_id,context_id,title,channels,due_at) values
    ($1,$2,'History sent winner',array['email']::text[],now()-interval '20 minutes'),
    ($1,$2,'History sending winner',array['email']::text[],now()-interval '20 minutes'),
    ($1,$2,'History exhausted failure winner',array['email']::text[],now()-interval '20 minutes')
  returning id,title`, [ids.b,bWork.id]);
const historyReminderIds = Object.fromEntries(historyRows.rows.map((row) => [row.title, row.id]));
await db.query(`
  insert into notifications(user_id,reminder_id,channel,scheduled_for,status,attempt_count)
  values
    ($1,$2,'email',now()+interval '1 minute','pending',0),
    ($1,$2,'email',now()+interval '2 minutes','sending',1),
    ($1,$2,'email',now()+interval '3 minutes','sent',1),
    ($1,$3,'email',now()+interval '1 minute','pending',0),
    ($1,$3,'email',now()+interval '2 minutes','failed',3),
    ($1,$3,'email',now()+interval '3 minutes','sending',1),
    ($1,$4,'email',now()+interval '1 minute','pending',0),
    ($1,$4,'email',now()+interval '2 minutes','failed',3),
    ($1,$4,'email',now()+interval '3 minutes','failed',2)`,
  [ids.b, historyReminderIds["History sent winner"], historyReminderIds["History sending winner"], historyReminderIds["History exhausted failure winner"]]);
await exec(await readFile(`${migrationDir}/0009_notification_occurrences.sql`, "utf8"));
console.log("MIGRATION 0009_notification_occurrences.sql passed");

await pass("migrations 0001-0009 parse and apply with Supabase auth/publication scaffolding", async () => {
  const tables = await one("select count(*)::int as n from information_schema.tables where table_schema='public'");
  assert.ok(tables.n >= 10);
  const funcs = await one("select count(*)::int as n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_reminder','update_reminder','mark_shipped','create_follow_up','add_shopping_item','retry_notification')");
  assert.equal(funcs.n, 6);
});

await pass("0009 reconciles moved legacy timestamps, preserves audit rows, and ranks ambiguous duplicates safely", async () => {
  const expectedWinners = [
    ["History sent winner", "sent"],
    ["History sending winner", "sending"],
    ["History exhausted failure winner", "failed"],
  ];
  for (const [title, winnerStatus] of expectedWinners) {
    const reminderId = historyReminderIds[title];
    const reminder = await one("select due_at from reminders where id=$1", [reminderId]);
    const rows = await db.query("select status, occurrence_at, superseded_at, delivery_started_at from notifications where reminder_id=$1 order by id", [reminderId]);
    assert.equal(rows.rows.length, 3, "migration preserves every legacy audit row");
    assert.ok(rows.rows.every((row) => row.occurrence_at.getTime() === reminder.due_at.getTime()), "moved schedule versions fold to the current due occurrence");
    const active = rows.rows.filter((row) => row.superseded_at === null);
    assert.equal(active.length, 1);
    assert.equal(active[0].status, winnerStatus);
    assert.equal(rows.rows.filter((row) => row.superseded_at !== null).length, 2);
    assert.ok(active[0].delivery_started_at, "sent, sending, and failed history gets a conservative provider-start bound");
  }
});

await pass("0008 normalizes corrupt channels, preserves valid order, and leaves empty arrays for context defaults", async () => {
  const mixed = await one("select channels from reminders where id=$1", [legacyReminderIds["Legacy mixed channels"]]);
  const invalid = await one("select channels from reminders where id=$1", [legacyReminderIds["Legacy invalid channels"]]);
  const empty = await one("select channels from reminders where id=$1", [legacyReminderIds["Legacy context default"]]);
  assert.deepEqual(mixed.channels, ["whatsapp", "email"]);
  assert.deepEqual(invalid.channels, ["email"]);
  assert.deepEqual(empty.channels, []);
  assert.equal((await one("select default_channel from contexts where id=$1", [bWork.id])).default_channel, "apns");
});

await pass("authenticated role cannot bypass RLS and RPCs are security invoker", async () => {
  const role = await one("select rolsuper, rolbypassrls, rolcanlogin from pg_roles where rolname='authenticated'");
  assert.deepEqual(role, { rolsuper: false, rolbypassrls: false, rolcanlogin: false });
  const result = await db.query("select proname, prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_reminder','update_reminder','mark_shipped','create_follow_up','add_shopping_item','retry_notification')");
  assert.equal(result.rows.length, 6);
  assert.ok(result.rows.every((fn) => fn.prosecdef === false));
  const executable = await one("select has_function_privilege('anon','public.create_reminder(text,text,timestamptz,uuid,text[],boolean,text,text,date,text)','execute') as anon_can, has_function_privilege('authenticated','public.create_reminder(text,text,timestamptz,uuid,text[],boolean,text,text,date,text)','execute') as auth_can");
  assert.deepEqual(executable, { anon_can: false, auth_can: true });
  const retryExecutable = await one("select has_function_privilege('anon','public.retry_notification(uuid)','execute') as anon_can, has_function_privilege('authenticated','public.retry_notification(uuid)','execute') as auth_can");
  assert.deepEqual(retryExecutable, { anon_can: false, auth_can: true });
  await exec("set role anon");
  await expectError("anon cannot execute create_reminder", "select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", ["x",null,null,"00000000-0000-4000-8000-000000000001",[],false,null,null,null,null]);
  await exec("reset role");
});

let orderReminder;
await pass("authenticated user creates order and preserves explicit ship_by", async () => asUser(ids.a, async () => {
  orderReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Parcel", null, "2026-10-30T16:00:00Z", aWork.id, ["email"], true, "ORD-1", "Pat", "2026-11-12", "UPS"])).id;
  const order = await one("select ship_by, recipient_name from orders where reminder_id=$1", [orderReminder]);
  assert.equal(order.ship_by.toISOString().slice(0,10), "2026-11-12");
  assert.equal(order.recipient_name, "Pat");
}));

await pass("legacy direct inserts and updates with Slack channels are rejected", async () => asUser(ids.a, async () => {
  await expectError("direct reminder insert with legacy Slack channel", "insert into reminders(user_id,context_id,title,channels) values ($1,$2,'Legacy write',array['slack']::text[])", [ids.a,aWork.id]);
  await expectError("direct reminder update with legacy Slack channel", "update reminders set channels=array['email','slack']::text[] where id=$1", [orderReminder]);
  assert.deepEqual((await one("select channels from reminders where id=$1", [orderReminder])).channels, ["email"]);
}));

let occurrenceReminder;
let occurrenceNotification;
let changedOccurrenceNotification;
await pass("quiet-hour deferrals and retries mutate scheduled_for without creating another occurrence", async () => {
  await asUser(ids.a, async () => {
    occurrenceReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Occurrence stability",null,new Date(Date.now()-60*60*1000).toISOString(),aWork.id,["email","email"],false,null,null,null,null])).id;
  });
  await exec("set role service_role");
  try {
    await db.query("select enqueue_due_notifications()");
    occurrenceNotification = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [occurrenceReminder])).id;
    assert.equal((await one("select count(*)::int as n from notifications where reminder_id=$1", [occurrenceReminder])).n, 1, "duplicate channel values produce one notification occurrence");
    const initial = await one("select occurrence_at, scheduled_for from notifications where id=$1", [occurrenceNotification]);
    assert.equal(initial.occurrence_at.getTime(), initial.scheduled_for.getTime());

    await db.query("update notifications set scheduled_for=now()+interval '1 day', status='pending' where id=$1", [occurrenceNotification]);
    await db.query("select enqueue_due_notifications()");
    assert.equal((await one("select count(*)::int as n from notifications where reminder_id=$1", [occurrenceReminder])).n, 1, "quiet-hour deferral stays on the same occurrence");

    await db.query("update notifications set scheduled_for=now()-interval '1 minute', status='retrying', attempt_count=1, delivery_started_at=now() where id=$1", [occurrenceNotification]);
    await db.query("select enqueue_due_notifications()");
    assert.equal((await one("select count(*)::int as n from notifications where reminder_id=$1", [occurrenceReminder])).n, 1, "retry backoff stays on the same occurrence");

    await db.query("update notifications set occurrence_at=occurrence_at+interval '1 day' where id=$1", [occurrenceNotification]);
    const immutable = await one("select occurrence_at from notifications where id=$1", [occurrenceNotification]);
    assert.equal(immutable.occurrence_at.getTime(), initial.occurrence_at.getTime());
    await expectError("duplicate active occurrence is rejected by the unique index", "insert into notifications(user_id,reminder_id,channel,scheduled_for,occurrence_at) select user_id,reminder_id,channel,occurrence_at,occurrence_at from notifications where id=$1", [occurrenceNotification]);
  } finally {
    await exec("reset role");
  }
});

await pass("rescheduling creates a new occurrence and stale queued rows are superseded before claim", async () => {
  const newDue = new Date(Date.now()-10*60*1000).toISOString();
  await db.query("update reminders set due_at=$1 where id=$2", [newDue,occurrenceReminder]);
  await exec("set role service_role");
  try {
    const claimedBeforeEnqueue = await db.query("select * from claim_due_notifications(100)");
    assert.ok(!claimedBeforeEnqueue.rows.some((row) => row.id === occurrenceNotification), "stale occurrence must not be claimed");
    assert.ok((await one("select superseded_at from notifications where id=$1", [occurrenceNotification])).superseded_at);

    await db.query("select enqueue_due_notifications()");
    const rows = await db.query("select id, occurrence_at, superseded_at from notifications where reminder_id=$1", [occurrenceReminder]);
    assert.equal(rows.rows.length, 2, "new due version gets its own audit row");
    const current = rows.rows.find((row) => row.superseded_at === null);
    assert.ok(current);
    changedOccurrenceNotification = current.id;
    assert.equal(current.occurrence_at.toISOString(), newDue);
  } finally {
    await exec("reset role");
  }
});

await pass("service-role sweep succeeds after invalid writes are rejected, routes all users, and remains idempotent", async () => {
  const otherDueReminder = (await one("insert into reminders(user_id,context_id,title,channels,due_at) values ($1,$2,'Unaffected user reminder',array['email']::text[],now()-interval '1 minute') returning id", [ids.a,aWork.id])).id;
  await exec("set role service_role");
  try {
    await db.query("select enqueue_due_notifications()");
    const unaffected = await one("select user_id,channel from notifications where reminder_id=$1", [otherDueReminder]);
    assert.deepEqual(unaffected, { user_id: ids.a, channel: "email" });
    const afterFirstRun = await one("select count(*)::int as n from notifications where reminder_id = any($1::uuid[])", [Object.values(legacyReminderIds)]);
    assert.equal(afterFirstRun.n, 4, "mixed channels produce two rows and each other reminder produces one");
    const channels = await db.query("select reminder_id, channel from notifications where reminder_id = any($1::uuid[])", [Object.values(legacyReminderIds)]);
    const routed = Object.fromEntries(Object.values(legacyReminderIds).map((id) => [id, channels.rows.filter((row) => row.reminder_id === id).map((row) => row.channel).sort()]));
    assert.deepEqual(routed[legacyReminderIds["Legacy mixed channels"]], ["email", "whatsapp"]);
    assert.deepEqual(routed[legacyReminderIds["Legacy invalid channels"]], ["email"]);
    assert.deepEqual(routed[legacyReminderIds["Legacy context default"]], ["apns"]);
    await db.query("select enqueue_due_notifications()");
    const afterSecondRun = await one("select count(*)::int as n from notifications where reminder_id = any($1::uuid[])", [Object.values(legacyReminderIds)]);
    assert.equal(afterSecondRun.n, afterFirstRun.n);
  } finally {
    await exec("reset role");
  }
});

let completedOccurrence;
let cancelledOccurrence;
await pass("completed and cancelled reminders are superseded and never claimed", async () => {
  let completedReminder;
  let cancelledReminder;
  await asUser(ids.a, async () => {
    completedReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Complete before delivery",null,new Date(Date.now()-2*60*60*1000).toISOString(),aWork.id,["email"],false,null,null,null,null])).id;
    cancelledReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Cancel before delivery",null,new Date(Date.now()-2*60*60*1000).toISOString(),aWork.id,["email"],false,null,null,null,null])).id;
  });
  await exec("set role service_role");
  try {
    await db.query("select enqueue_due_notifications()");
    completedOccurrence = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [completedReminder])).id;
    cancelledOccurrence = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [cancelledReminder])).id;
    await db.query("update reminders set status='done' where id=$1", [completedReminder]);
    await db.query("update reminders set status='cancelled' where id=$1", [cancelledReminder]);
    const claimed = await db.query("select * from claim_due_notifications(100)");
    assert.ok(!claimed.rows.some((row) => row.id === completedOccurrence));
    assert.ok(!claimed.rows.some((row) => row.id === cancelledOccurrence));
    assert.ok((await one("select superseded_at from notifications where id=$1", [completedOccurrence])).superseded_at);
    assert.ok((await one("select superseded_at from notifications where id=$1", [cancelledOccurrence])).superseded_at);
  } finally {
    await exec("reset role");
  }
});

await pass("manual retry requeues only a current failed occurrence and rejects queued, sending, sent, stale, and cross-user rows", async () => {
  let retryReminder;
  let retryRow;
  await asUser(ids.a, async () => {
    retryReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Retry this delivery",null,new Date(Date.now()-2*60*60*1000).toISOString(),aWork.id,["email"],false,null,null,null,null])).id;
  });
  await exec("set role service_role");
  try {
    await db.query("select enqueue_due_notifications()");
    retryRow = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [retryReminder])).id;
    await db.query("update notifications set status='failed', attempt_count=3, delivery_started_at=now(), error='provider unavailable' where id=$1", [retryRow]);
    await db.query("select enqueue_due_notifications()");
    assert.equal((await one("select count(*)::int as n from notifications where reminder_id=$1", [retryReminder])).n, 1, "failed occurrence is not automatically requeued");

    await db.query("update notifications set status='sent', sent_at=now() where id=$1", [changedOccurrenceNotification]);
    await db.query("select enqueue_due_notifications()");
    assert.equal((await one("select count(*)::int as n from notifications where reminder_id=$1", [occurrenceReminder])).n, 2, "sent occurrence is not automatically requeued");
  } finally {
    await exec("reset role");
  }

  const foreignNotification = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [historyReminderIds["History sent winner"]])).id;
  await asUser(ids.a, async () => {
    assert.equal((await one("select retry_notification($1) as id", [retryRow])).id, retryRow);
    const queued = await one("select status, attempt_count, scheduled_for from notifications where id=$1", [retryRow]);
    assert.equal(queued.status, "pending"); assert.equal(queued.attempt_count, 0); assert.ok(queued.scheduled_for.getTime() <= Date.now()+1000);
    await expectError("already queued notification cannot retry twice", "select retry_notification($1)", [retryRow]);
    await expectError("sent notification cannot retry", "select retry_notification($1)", [changedOccurrenceNotification]);
    await expectError("superseded notification cannot retry", "select retry_notification($1)", [occurrenceNotification]);
    await expectError("another user's notification cannot retry", "select retry_notification($1)", [foreignNotification]);
  });

  await exec("set role service_role");
  try {
    await db.query("update notifications set status='sending' where id=$1", [retryRow]);
  } finally {
    await exec("reset role");
  }
  await asUser(ids.a, async () => {
    await expectError("sending notification cannot retry", "select retry_notification($1)", [retryRow]);
  });
});

await pass("expired provider attempts are quarantined while never-attempted old quiet deferrals remain claimable", async () => {
  let expiredReminder;
  let quietReminder;
  await asUser(ids.a, async () => {
    expiredReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Expired provider attempt",null,new Date(Date.now()-26*60*60*1000).toISOString(),aWork.id,["email"],false,null,null,null,null])).id;
    quietReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Old quiet defer without provider attempt",null,new Date(Date.now()-26*60*60*1000).toISOString(),aWork.id,["email"],false,null,null,null,null])).id;
  });
  await exec("set role service_role");
  let expiredNotification;
  let quietNotification;
  try {
    await db.query("select enqueue_due_notifications()");
    expiredNotification = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [expiredReminder])).id;
    quietNotification = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [quietReminder])).id;
    await db.query("update notifications set status='retrying', attempt_count=1, scheduled_for=now()-interval '1 minute', delivery_started_at=now()-interval '24 hours' where id=$1", [expiredNotification]);
    await db.query("update notifications set scheduled_for=now()-interval '25 hours', status='pending' where id=$1", [quietNotification]);
    const claimed = await db.query("select * from claim_due_notifications(100)");
    assert.ok(!claimed.rows.some((row) => row.id === expiredNotification), "old provider attempt needs human confirmation");
    assert.ok(claimed.rows.some((row) => row.id === quietNotification), "quiet-only deferral without a provider attempt remains sendable");
  } finally {
    await exec("reset role");
  }

  const expired = await one("select status, attempt_count, error, superseded_at, delivery_started_at from notifications where id=$1", [expiredNotification]);
  assert.equal(expired.status, "failed"); assert.ok(expired.attempt_count >= 3); assert.equal(expired.error, "delivery_confirmation_required"); assert.equal(expired.superseded_at, null); assert.ok(expired.delivery_started_at);
  await exec("set role service_role");
  try {
    await db.query("select enqueue_due_notifications()");
    assert.equal((await one("select count(*)::int as n from notifications where reminder_id=$1", [expiredReminder])).n, 1, "quarantined occurrence cannot be automatically recreated");
  } finally {
    await exec("reset role");
  }
  await asUser(ids.a, async () => {
    await expectError("expired provider attempt cannot be manually retried", "select retry_notification($1)", [expiredNotification]);
  });
});

await pass("reopening a superseded occurrence respects provider history while allowing never-attempted work", async () => {
  let attemptedReminder;
  let quietReminder;
  await asUser(ids.a, async () => {
    attemptedReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Attempted then completed",null,new Date(Date.now()-60*60*1000).toISOString(),aWork.id,["email"],false,null,null,null,null])).id;
    quietReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Quiet then completed",null,new Date(Date.now()-60*60*1000).toISOString(),aWork.id,["email"],false,null,null,null,null])).id;
  });

  await exec("set role service_role");
  let attemptedId;
  let quietId;
  try {
    await db.query("select enqueue_due_notifications()");
    attemptedId = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [attemptedReminder])).id;
    quietId = (await one("select id from notifications where reminder_id=$1 and superseded_at is null", [quietReminder])).id;
    await db.query("update notifications set status='retrying', delivery_started_at=now() where id=$1", [attemptedId]);
  } finally {
    await exec("reset role");
  }

  await asUser(ids.a, async () => {
    await db.query("update reminders set status='done' where id = any($1::uuid[])", [[attemptedReminder,quietReminder]]);
  });
  await exec("set role service_role");
  try {
    await db.query("select enqueue_due_notifications()");
  } finally {
    await exec("reset role");
  }
  await asUser(ids.a, async () => {
    await db.query("update reminders set status='open' where id = any($1::uuid[])", [[attemptedReminder,quietReminder]]);
  });
  await exec("set role service_role");
  try {
    await db.query("select enqueue_due_notifications()");
  } finally {
    await exec("reset role");
  }

  const attemptedRows = await db.query("select id, superseded_at from notifications where reminder_id=$1 order by created_at", [attemptedReminder]);
  assert.equal(attemptedRows.rows.length, 1, "potentially accepted occurrence must not get a fresh provider idempotency key");
  assert.equal(attemptedRows.rows[0].id, attemptedId);
  assert.ok(attemptedRows.rows[0].superseded_at);
  const quietRows = await db.query("select id, superseded_at, delivery_started_at from notifications where reminder_id=$1 order by created_at", [quietReminder]);
  assert.equal(quietRows.rows.length, 2, "never-attempted superseded occurrence can be requeued on reopen");
  assert.equal(quietRows.rows[0].id, quietId);
  assert.ok(quietRows.rows[0].superseded_at);
  assert.equal(quietRows.rows[0].delivery_started_at, null);
  assert.equal(quietRows.rows.filter((row) => row.superseded_at === null).length, 1);
});

const bReminder = (await one("insert into reminders(user_id,context_id,title,is_order) values ($1,$2,'B order',true) returning id", [ids.b,bWork.id])).id;
const bDevice = (await one("insert into device_tokens(user_id,token,environment) values ($1,'token-b','sandbox') returning id", [ids.b])).id;
let aDevice;
await pass("owner can register a device and acknowledge a local schedule", async () => asUser(ids.a, async () => {
  aDevice = (await one("insert into device_tokens(user_id,token,environment) values ($1,'token-a','sandbox') returning id", [ids.a])).id;
  await db.query("insert into local_schedules(user_id,reminder_id,device_token_id,fire_at) values ($1,$2,$3,now())", [ids.a,orderReminder,aDevice]);
  assert.equal((await one("select count(*)::int as n from local_schedules where reminder_id=$1", [orderReminder])).n, 1);
}));

let ownNotification;
await pass("authenticated notification writes stay parent-owned while service role retains sweep writes", async () => {
  await asUser(ids.a, async () => {
    ownNotification = (await one("insert into notifications(user_id,reminder_id,channel,scheduled_for) values ($1,$2,'email',now()) returning id", [ids.a,orderReminder])).id;
    await expectError("notification insert targeting another user's reminder", "insert into notifications(user_id,reminder_id,channel,scheduled_for) values ($1,$2,'email',now())", [ids.a,bReminder]);
    await expectError("notification update targeting another user's reminder", "update notifications set reminder_id=$1 where id=$2", [bReminder,ownNotification]);
    assert.equal((await one("select reminder_id from notifications where id=$1", [ownNotification])).reminder_id, orderReminder);
  });

  await exec("set role service_role");
  try {
    const serverNotification = (await one("insert into notifications(user_id,reminder_id,channel,scheduled_for) values ($1,$2,'email',now()) returning id", [ids.b,bReminder])).id;
    assert.ok(serverNotification, "service role sweep insert should succeed");
  } finally {
    await exec("reset role");
  }
});

await pass("updating an enabled order preserves explicit ship_by; toggling off deletes the order", async () => asUser(ids.a, async () => {
  await db.query("select update_reminder($1,$2,$3,$4,$5,$6,$7)", [orderReminder,"Parcel revised",null,"2026-10-31T16:00:00Z",aWork.id,["email"],true]);
  assert.equal((await one("select ship_by::text as ship_by from orders where reminder_id=$1", [orderReminder])).ship_by, "2026-11-12");
  await db.query("select update_reminder($1,$2,$3,$4,$5,$6,$7)", [orderReminder,"Parcel revised",null,"2026-10-31T16:00:00Z",aWork.id,["email"],false]);
  assert.equal(await one("select count(*)::int as n from orders where reminder_id=$1", [orderReminder]).then(x=>x.n), 0);
  await db.query("select update_reminder($1,$2,$3,$4,$5,$6,$7)", [orderReminder,"Parcel revised",null,"2026-10-31T16:00:00Z",aWork.id,["email"],true]);
  assert.equal((await one("select ship_by::text as ship_by from orders where reminder_id=$1", [orderReminder])).ship_by, "2026-10-31");
}));

await pass("mark_shipped updates the order and reminder", async () => asUser(ids.a, async () => {
  await db.query("select mark_shipped($1,$2,$3)", [orderReminder,"1Z999","UPS"]);
  const row = await one("select r.status,o.tracking_number,o.shipped_at from reminders r join orders o on o.reminder_id=r.id where r.id=$1", [orderReminder]);
  assert.equal(row.status, "done"); assert.equal(row.tracking_number, "1Z999"); assert.ok(row.shipped_at);
}));

await exec(`create function test_fail_order_insert() returns trigger language plpgsql as $$ begin raise exception 'injected order failure'; end $$;
  create trigger test_fail_order_insert before insert on orders for each row execute function test_fail_order_insert();`);
await pass("create_reminder rolls back its reminder when order insertion fails", async () => asUser(ids.a, async () => {
  const before = (await one("select count(*)::int as n from reminders where user_id=$1 and title='Rollback order'", [ids.a])).n;
  await expectError("injected order insertion failure", "select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", ["Rollback order",null,null,aWork.id,[],true,null,null,null,null]);
  const after = (await one("select count(*)::int as n from reminders where user_id=$1 and title='Rollback order'", [ids.a])).n;
  assert.equal(after, before, "failed RPC must not leave an orphan reminder");
}));
await exec("drop trigger test_fail_order_insert on orders; drop function test_fail_order_insert();");

await exec("create function test_fail_reminder_update() returns trigger language plpgsql as $$ begin raise exception 'injected reminder failure'; end $$; create trigger test_fail_reminder_update before update on reminders for each row execute function test_fail_reminder_update();");
await pass("mark_shipped rolls back its order update when reminder completion fails", async () => asUser(ids.a, async () => {
  const rollbackReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Rollback ship",null,"2026-12-01T12:00:00Z",aWork.id,[],true,null,null,null,null])).id;
  await expectError("injected reminder completion failure", "select mark_shipped($1,$2,$3)", [rollbackReminder,"TRACK","UPS"]);
  const state = await one("select r.status, o.shipped_at, o.tracking_number from reminders r join orders o on o.reminder_id=r.id where r.id=$1", [rollbackReminder]);
  assert.equal(state.status, "open"); assert.equal(state.shipped_at, null); assert.equal(state.tracking_number, null);
}));
await exec("drop trigger test_fail_reminder_update on reminders; drop function test_fail_reminder_update();");

await pass("follow-up creates same-context reminder with expected prefix", async () => asUser(ids.a, async () => {
  const id = (await one("select create_follow_up($1) as id", [orderReminder])).id;
  const row = await one("select title,context_id from reminders where id=$1", [id]);
  assert.equal(row.title, "Follow up: Parcel revised"); assert.equal(row.context_id, aWork.id);
}));

let shoppingReminder;
await pass("shopping add/delete/add allocates the next max position", async () => asUser(ids.a, async () => {
  shoppingReminder = (await one("select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id", ["Market",null,null,aShopping.id,[],false,null,null,null,null])).id;
  const first = (await one("select add_shopping_item($1,$2) as id", [shoppingReminder,"Oats"])).id;
  await db.query("select add_shopping_item($1,$2)", [shoppingReminder,"Milk"]);
  await db.query("delete from shopping_items where id=$1", [first]);
  const third = (await one("select add_shopping_item($1,$2) as id", [shoppingReminder,"Bread"])).id;
  assert.equal((await one("select position from shopping_items where id=$1", [third])).position, 2);
}));

await pass("RLS limits reminder visibility to caller", async () => asUser(ids.a, async () => {
  await db.query("insert into reminders(user_id,context_id,title) values ($1,$2,'A private')", [ids.a,aWork.id]);
  const visible = await one("select count(*)::int as n from reminders");
  assert.ok(visible.n >= 1);
  await exec("reset role");
  await asUser(ids.b, async () => {
    assert.ok((await one("select count(*)::int as n from reminders")).n > 0, "B should see seeded reminders");
    assert.equal((await one("select count(*)::int as n from reminders where user_id <> auth.uid()")).n, 0, "B must not see A's reminders");
  });
  await exec("set role authenticated");
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [ids.a]);
}));

await pass("cross-user context RPC and direct reminder writes are rejected", async () => asUser(ids.a, async () => {
  await expectError("create_reminder with another user's context", "select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", ["bad",null,null,bWork.id,[],false,null,null,null,null]);
  await expectError("direct reminder insert with another user's context", "insert into reminders(user_id,context_id,title) values ($1,$2,'bad')", [ids.a,bWork.id]);
}));

await pass("hostile child and local schedule writes are rejected", async () => asUser(ids.a, async () => {
  await expectError("orders linked to another user's reminder", "insert into orders(reminder_id,user_id) values ($1,$2)", [bReminder,ids.a]);
  await expectError("shopping item attached across users", "insert into shopping_items(reminder_id,user_id,label,position) values ($1,$2,'bad',0)", [bReminder,ids.a]);
  await expectError("own reminder paired with another user's device", "insert into local_schedules(user_id,reminder_id,device_token_id,fire_at) values ($1,$2,$3,now())", [ids.a,orderReminder,bDevice]);
  await expectError("another user's reminder paired with own device", "insert into local_schedules(user_id,reminder_id,device_token_id,fire_at) values ($1,$2,$3,now())", [ids.a,bReminder,aDevice]);
}));

await pass("unauthenticated and missing record RPC targets fail", async () => {
  await expectError("unauthenticated create_reminder", "select create_reminder($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", ["x",null,null,aWork.id,[],false,null,null,null,null]);
  await asUser(ids.a, async () => {
    await expectError("missing reminder update", "select update_reminder($1,$2,$3,$4,$5,$6,$7)", ["ffffffff-ffff-4fff-8fff-ffffffffffff","x",null,null,aWork.id,[],false]);
    await expectError("cross-user reminder update", "select update_reminder($1,$2,$3,$4,$5,$6,$7)", [bReminder,"x",null,null,aWork.id,[],false]);
    await expectError("follow-up another user's reminder", "select create_follow_up($1)", [bReminder]);
    await expectError("missing ship target", "select mark_shipped($1,$2,$3)", ["ffffffff-ffff-4fff-8fff-ffffffffffff",null,null]);
    await expectError("cross-user ship target", "select mark_shipped($1,$2,$3)", [bReminder,"TRACK","UPS"]);
    await expectError("cross-user shopping target", "select add_shopping_item($1,$2)", [bReminder,"Item"]);
  });
});

await pass("admin auth.users deletion cascades user data", async () => {
  await exec("set role service_role");
  await db.query("delete from auth.users where id=$1", [ids.a]);
  await exec("reset role");
  for (const table of ["contexts","reminders","orders","notifications","user_settings","device_tokens","local_schedules","shopping_items","work_details","sidegig_details"]) {
    const row = await one(`select count(*)::int as n from ${table} where user_id=$1`, [ids.a]);
    assert.equal(row.n, 0, `${table} should cascade`);
  }
});

console.log(`\n${passed.length} checks passed.`);
await db.close();
