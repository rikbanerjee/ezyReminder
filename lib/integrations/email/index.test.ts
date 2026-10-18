import assert from "node:assert/strict";
import { test } from "node:test";
import { sendEmail, type SendEmailInput } from "./index.ts";

const input: SendEmailInput = {
  apiKey: "test-only-key",
  from: "test@example.com",
  to: "fixture@example.com",
  idempotencyKey: "notification:fixture-id",
  reminder: { id: "fixture-id", title: "A & B <test>", notes: null, dueAt: null, contextName: "Work" },
};

test("delivery retries preserve the provider key and exact request body", async (t) => {
  const requests: RequestInit[] = [];
  t.mock.method(globalThis, "fetch", async (_url: string, init: RequestInit) => {
    requests.push(init);
    return Response.json({ id: "same-provider-message" });
  });
  assert.deepEqual(await sendEmail(input), { ok: true, providerMessageId: "same-provider-message" });
  assert.deepEqual(await sendEmail(input), { ok: true, providerMessageId: "same-provider-message" });
  assert.equal(requests.length, 2);
  for (const request of requests) {
    assert.equal(new Headers(request.headers).get("Idempotency-Key"), input.idempotencyKey);
    assert.ok(request.signal instanceof AbortSignal);
    assert.match(JSON.parse(String(request.body)).html, /A &amp; B &lt;test&gt;/);
  }
  assert.equal(requests[0].body, requests[1].body);
});

test("a new notification uses a different provider key", async (t) => {
  const keys: (string | null)[] = [];
  t.mock.method(globalThis, "fetch", async (_url: string, init: RequestInit) => {
    keys.push(new Headers(init.headers).get("Idempotency-Key"));
    return Response.json({ id: "provider-message" });
  });
  await sendEmail(input);
  await sendEmail({ ...input, idempotencyKey: "notification:next-occurrence" });
  assert.notEqual(keys[0], keys[1]);
});

test("an empty delivery identity prevents a provider call", async (t) => {
  const fetchMock = t.mock.method(globalThis, "fetch", async () => { throw new Error("Unexpected network call"); });
  assert.equal((await sendEmail({ ...input, idempotencyKey: "" })).ok, false);
  assert.equal(fetchMock.mock.callCount(), 0);
});

test("network errors remain retryable without escaping the delivery pipeline", async (t) => {
  t.mock.method(globalThis, "fetch", async () => { throw new Error("Network connection lost"); });
  assert.deepEqual(await sendEmail(input), { ok: false, error: "Email request failed or timed out." });
});

test("provider errors and malformed success responses are failures", async (t) => {
  const replies = [new Response("unavailable", { status: 503 }), Response.json({}), new Response("invalid JSON")];
  t.mock.method(globalThis, "fetch", async () => replies.shift()!);
  assert.equal((await sendEmail(input)).ok, false);
  assert.equal((await sendEmail(input)).ok, false);
  assert.equal((await sendEmail(input)).ok, false);
});
