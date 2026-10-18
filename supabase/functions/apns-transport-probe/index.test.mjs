import assert from "node:assert/strict";
import { after, before, test } from "node:test";

const originalDeno = globalThis.Deno;
const originalFetch = globalThis.fetch;
const calls = { serve: null, clientOptions: [], requests: [], closed: 0 };
let serviceRoleKey = "test-service-role-key";
let fetchResult;

globalThis.Deno = {
  env: { get: (name) => name === "SUPABASE_SERVICE_ROLE_KEY" ? serviceRoleKey : undefined },
  serve: (handler) => { calls.serve = handler; },
  createHttpClient: (options) => {
    calls.clientOptions.push(options);
    return { close: () => { calls.closed += 1; } };
  },
};
globalThis.fetch = async (url, options) => {
  calls.requests.push({ url, options });
  if (fetchResult instanceof Error) throw fetchResult;
  return fetchResult;
};

await import(`./index.ts?test=${Date.now()}`);
const handler = calls.serve;
assert.equal(typeof handler, "function");

function request({ method = "POST", authorization = "Bearer test-service-role-key" } = {}) {
  return new Request("https://probe.example/functions/v1/apns-transport-probe", {
    method,
    headers: authorization ? { authorization } : {},
  });
}

function apnsResponse(status, reason, apnsId = "apns-probe-id") {
  return new Response(JSON.stringify({ reason }), {
    status,
    headers: apnsId ? { "apns-id": apnsId } : {},
  });
}

before(() => {
  calls.clientOptions.length = 0;
  calls.requests.length = 0;
  calls.closed = 0;
});

after(() => {
  globalThis.Deno = originalDeno;
  globalThis.fetch = originalFetch;
});

test("rejects non-POST and unauthorized requests without egress", async () => {
  const methodResponse = await handler(request({ method: "GET" }));
  assert.equal(methodResponse.status, 405);
  const authResponse = await handler(request({ authorization: "Bearer wrong" }));
  assert.equal(authResponse.status, 401);
  assert.equal(calls.requests.length, 0);
  assert.equal(calls.clientOptions.length, 0);
});

test("fails closed when the service-role secret is not configured", async () => {
  serviceRoleKey = undefined;
  const requestsBefore = calls.requests.length;
  const response = await handler(request());
  serviceRoleKey = "test-service-role-key";
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "probe_not_configured");
  assert.equal(calls.requests.length, requestsBefore);
  assert.equal(calls.clientOptions.length, 0);
});

test("requests HTTP/2 only with the fixed sandbox endpoint and no provider credentials", async () => {
  fetchResult = apnsResponse(403, "MissingProviderToken");
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ok: true,
    http2OnlyRequested: true,
    apnsStatus: 403,
    reason: "MissingProviderToken",
    apnsId: "apns-probe-id",
  });

  assert.deepEqual(calls.clientOptions.at(-1), { http1: false, http2: true });
  const call = calls.requests.at(-1);
  assert.equal(call.url,
    "https://api.sandbox.push.apple.com/3/device/0000000000000000000000000000000000000000000000000000000000000000");
  assert.equal(call.options.method, "POST");
  assert.equal(call.options.client !== undefined, true);
  assert.equal(call.options.signal instanceof AbortSignal, true);
  assert.equal(call.options.headers.authorization, undefined);
  assert.deepEqual(JSON.parse(call.options.body), { aps: { alert: "Transport probe" } });
  assert.equal(calls.closed, 1);
});

test("requires the expected reason and APNs request identifier", async (t) => {
  for (const [status, reason, apnsId] of [
    [403, "BadDeviceToken", "id"],
    [200, undefined, "id"],
    [403, "MissingProviderToken", null],
  ]) {
    await t.test(`${status} ${reason ?? "no reason"} ${apnsId ? "with id" : "without id"}`, async () => {
      fetchResult = apnsResponse(status, reason, apnsId);
      const closedBefore = calls.closed;
      const response = await handler(request());
      assert.equal(response.status, 502);
      assert.equal((await response.json()).ok, false);
      assert.equal(calls.closed, closedBefore + 1);
    });
  }
});

test("returns a generic failure and closes client on network errors", async () => {
  fetchResult = new Error("must not leak");
  const closedBefore = calls.closed;
  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { ok: false, error: "transport_probe_failed" });
  assert.equal(calls.closed, closedBefore + 1);
});

test("fails closed if the runtime lacks a custom HTTP client", async () => {
  const originalCreateHttpClient = Deno.createHttpClient;
  Deno.createHttpClient = undefined;
  const requestsBefore = calls.requests.length;
  const response = await handler(request());
  Deno.createHttpClient = originalCreateHttpClient;
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "http2_client_unsupported");
  assert.equal(calls.requests.length, requestsBefore);
});
