import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import vm from "node:vm";
import { transform } from "esbuild";

const handlerPath = new URL("./index.ts", import.meta.url);
const source = await readFile(handlerPath, "utf8");
const compiled = await transform(source, { loader: "ts", format: "cjs", target: "node22" });
const due = "2026-10-15T16:00:00.000Z";

function createHarness({ notification = {}, reminder = {}, currentReminder = {}, claimCount = 1, claimResponses = 1, settings = {}, recipientEmail = "r@example.com", fetchImpl, writeError, quiet = false } = {}) {
  const calls = { sent: [], updates: [], fetches: 0, claims: 0 };
  const row = { id: "notification-1", user_id: "user-1", reminder_id: "reminder-1", channel: "email", scheduled_for: due, attempt_count: 0, occurrence_at: due, superseded_at: null, delivery_started_at: null, status: "sending", ...notification };
  const reminderRow = { id: "reminder-1", title: "Call Sam", notes: null, due_at: due, snoozed_until: null, user_id: "user-1", status: "open", channels: ["email"], context: { name: "Work", quiet_hours: quiet ? { start: "00:00", end: "23:59" } : null }, ...reminder };
  let handler;
  const client = {
    rpc: async (name) => {
      if (name === "enqueue_due_notifications") return { error: null };
      calls.claims++;
      if (calls.claims > claimResponses) return { data: [], error: null };
      row.status = "sending";
      return { data: Array.from({ length: claimCount }, (_, i) => ({ ...row, id: `notification-${i + 1}` })), error: null };
    },
    from(table) {
      let selected = ""; let id = null;
      const builder = {
        select(columns) { selected = columns; return builder; },
        eq(column, value) { if (column === "id") id = value; return builder; },
        single: async () => table === "notifications"
          ? { data: { status: row.status, superseded_at: row.superseded_at, delivery_started_at: row.delivery_started_at }, error: null }
          : selected.startsWith("status,") ? { data: { ...reminderRow, ...currentReminder }, error: null } : { data: reminderRow, error: null },
        maybeSingle: async () => ({ data: settings, error: null }),
        update(values) {
          calls.updates.push({ table, id, values });
          return { eq: async () => {
            const fails = writeError === true || (writeError != null && writeError === values.status);
            if (!fails && table === "notifications") Object.assign(row, values);
            return { error: fails ? { message: "write failed" } : null };
          } };
        },
      };
      return builder;
    },
    auth: { admin: { getUserById: async () => ({ data: { user: { email: recipientEmail } } }) } },
  };
  const context = vm.createContext({
    module: { exports: {} }, exports: {}, Response, Date,
    require(name) {
      if (name === "npm:@supabase/supabase-js@2.110.7") return { createClient: () => client };
      if (name.endsWith("lib/quiet-hours.ts")) return { isQuietNow: () => quiet, nextAllowedTime: () => new Date(Date.now() + 60_000) };
      if (name.endsWith("lib/integrations/email/index.ts")) return { sendEmail: async (input) => {
        calls.sent.push(input);
        if (fetchImpl) return fetchImpl(input);
        return { ok: true, providerMessageId: "provider-1" };
      } };
      return {};
    },
    Deno: { env: { get: (name) => ({ SUPABASE_URL: "https://example.test", SUPABASE_SERVICE_ROLE_KEY: "service", RESEND_API_KEY: "key", RESEND_FROM_EMAIL: "from@example.com" })[name] }, serve: (fn) => { handler = fn; } },
  });
  new vm.Script(compiled.code).runInContext(context);
  return { handler, calls, row };
}

const post = () => new Request("https://edge.test/sweep", { method: "POST" });
const payload = (response) => response.json();

test("stale, completed, cancelled, and superseded notifications never send", async () => {
  for (const { notification, reminder } of [
    { reminder: { due_at: "2026-10-15T17:00:00.000Z" } },
    { reminder: { status: "done" } },
    { reminder: { status: "cancelled" } },
    { reminder: { status: "snoozed", snoozed_until: "2026-10-15T17:00:00.000Z" } },
    { notification: { superseded_at: due } },
  ]) {
    const { handler, calls } = createHarness({ notification, reminder });
    await handler(post());
    assert.equal(calls.sent.length, 0);
  }
});

test("snoozed reminders dispatch when their effective due matches the occurrence", async () => {
  const { handler, calls } = createHarness({ reminder: { status: "snoozed", snoozed_until: due } });
  await handler(post());
  assert.equal(calls.sent.length, 1);
});

test("quiet hours defer the row without dispatching", async () => {
  const { handler, calls } = createHarness({ quiet: true });
  await handler(post());
  await handler(post());
  assert.equal(calls.sent.length, 0);
  assert.equal(calls.updates.filter((call) => call.values.scheduled_for).length, 1);
});

test("provider exceptions schedule bounded retry with the same idempotency key", async () => {
  const { handler, calls, row } = createHarness({ fetchImpl: async () => { throw new Error("network reset"); } });
  const response = await handler(post());
  const result = await payload(response);
  assert.equal(result.sent, 0);
  assert.equal(calls.sent[0].idempotencyKey, "notification:notification-1");
  assert.equal(calls.updates.at(-1).values.status, "retrying");
  assert.equal(calls.updates.at(-1).values.attempt_count, 1);
  assert.equal(calls.updates.find((call) => call.values.delivery_started_at)?.values.delivery_started_at, row.delivery_started_at);
});

test("an accepted request with a lost response retries using its persisted key and timestamp", async () => {
  let attempts = 0;
  const { handler, calls, row } = createHarness({ claimResponses: 2, fetchImpl: async () => {
    attempts++;
    return attempts === 1 ? { ok: false, error: "network response lost" } : { ok: true, providerMessageId: "accepted-1" };
  } });
  await handler(post());
  const originalStart = row.delivery_started_at;
  await handler(post());
  assert.equal(attempts, 2);
  assert.deepEqual(calls.sent.map((call) => call.idempotencyKey), ["notification:notification-1", "notification:notification-1"]);
  assert.equal(row.delivery_started_at, originalStart);
  assert.equal(calls.updates.at(-1).values.status, "sent");
});

test("expired idempotency window fails for confirmation without contacting the provider", async () => {
  const { handler, calls } = createHarness({ notification: { delivery_started_at: "2020-01-01T00:00:00.000Z" } });
  await handler(post());
  assert.equal(calls.sent.length, 0);
  assert.equal(calls.updates.at(-1).values.error, "delivery_confirmation_required");
});

test("failure to persist delivery start prevents the first provider request", async () => {
  const { handler, calls } = createHarness({ writeError: true });
  await assert.rejects(() => handler(post()), /notification_update_failed/);
  assert.equal(calls.sent.length, 0);
});

test("successful delivery is marked sent and counts only after persistence", async () => {
  const { handler, calls } = createHarness();
  const response = await handler(post());
  assert.equal((await payload(response)).sent, 1);
  assert.equal(calls.updates.at(-1).values.status, "sent");
  await handler(post());
  assert.equal(calls.sent.length, 1);
});

test("failed persistence never reports a successful send", async () => {
  const { handler, calls } = createHarness({ writeError: "sent" });
  await assert.rejects(() => handler(post()), /notification_update_failed/);
  assert.equal(calls.sent.length, 1);
  assert.equal(calls.updates.some((call) => call.values.status === "sent"), true);
});

test("rescheduling between reminder reads suppresses the old occurrence", async () => {
  const { handler, calls } = createHarness({ currentReminder: { due_at: "2026-10-15T17:00:00.000Z" } });
  await handler(post());
  assert.equal(calls.sent.length, 0);
  assert.equal(calls.updates.at(-1).values.error, "reminder_due_changed");
});

test("removing a channel after claim suppresses its delivery", async () => {
  const { handler, calls } = createHarness({ currentReminder: { channels: ["whatsapp"] } });
  await handler(post());
  assert.equal(calls.sent.length, 0);
  assert.equal(calls.updates.at(-1).values.error, "reminder_channel_changed");
});

test("missing recipient preflight does not start the provider safety window", async () => {
  const { handler, calls, row } = createHarness({ recipientEmail: null });
  await handler(post());
  assert.equal(calls.sent.length, 0);
  assert.equal(row.delivery_started_at, null);
  assert.equal(row.error, "user_email_not_found");
});
