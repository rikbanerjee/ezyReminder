import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import vm from "node:vm";
import { transform } from "esbuild";

const handlerPath = new URL("./index.ts", import.meta.url);
const functionSource = await readFile(handlerPath, "utf8");
const compiled = await transform(functionSource, { loader: "ts", format: "cjs", target: "node22" });

function createHarness({ authResponse, deleteResponse, env = {} } = {}) {
  const calls = { clients: [], getUser: [], deleteUser: [] };
  let handler;
  const values = {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_ANON_KEY: "test-anon-key",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-test-secret",
    ...env,
  };
  const supabaseModule = {
    createClient(url, key, options) {
      calls.clients.push({ url, key, options });
      if (key === values.SUPABASE_ANON_KEY) {
        return {
          auth: {
            getUser: async (...args) => {
              calls.getUser.push(args);
              return authResponse ?? { data: { user: { id: "verified-user-id" } }, error: null };
            },
          },
        };
      }
      return {
        auth: {
          admin: {
            deleteUser: async (...args) => {
              calls.deleteUser.push(args);
              return deleteResponse ?? { error: null };
            },
          },
        },
      };
    },
  };
  const compiledModule = { exports: {} };
  const context = vm.createContext({
    module: compiledModule,
    exports: compiledModule.exports,
    require: (name) => {
      assert.equal(name, "npm:@supabase/supabase-js@2.110.7");
      return supabaseModule;
    },
    Response,
    Deno: {
      env: { get: (name) => values[name] },
      serve: (registered) => { handler = registered; },
    },
  });
  new vm.Script(compiled.code, { filename: handlerPath.pathname }).runInContext(context);
  assert.equal(typeof handler, "function", "Edge Function should register a request handler");
  return { handler, calls };
}

function request(method, { token, body } = {}) {
  const headers = new Headers();
  if (token !== undefined) headers.set("Authorization", token);
  if (body !== undefined) headers.set("Content-Type", "application/json");
  return new Request("https://edge.test/delete-account", {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function json(response) { return response.json(); }

test("OPTIONS returns CORS preflight response without creating a Supabase client", async () => {
  const { handler, calls } = createHarness();
  const response = await handler(request("OPTIONS"));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
  assert.match(response.headers.get("Access-Control-Allow-Methods"), /POST/);
  assert.equal(calls.clients.length, 0);
});

test("non-POST methods are rejected with CORS headers and no auth or deletion calls", async () => {
  const { handler, calls } = createHarness();
  const response = await handler(request("DELETE", { token: "Bearer valid-token" }));
  assert.equal(response.status, 405);
  assert.deepEqual(await json(response), { error: "Method not allowed" });
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
  assert.equal(calls.clients.length, 0);
  assert.equal(calls.deleteUser.length, 0);
});

test("missing bearer token returns a generic error without contacting Supabase", async () => {
  const { handler, calls } = createHarness();
  const response = await handler(request("POST"));
  assert.equal(response.status, 401);
  assert.deepEqual(await json(response), { error: "Unable to delete account" });
  assert.equal(calls.clients.length, 0);
});

test("invalid bearer token is verified by Auth and never reaches admin deletion", async () => {
  const { handler, calls } = createHarness({
    authResponse: { data: { user: null }, error: { message: "private auth provider detail" } },
  });
  const response = await handler(request("POST", { token: "Bearer expired-token" }));
  assert.equal(response.status, 401);
  const responseText = await response.text();
  assert.deepEqual(JSON.parse(responseText), { error: "Unable to delete account" });
  assert.deepEqual(calls.getUser, [["expired-token"]]);
  assert.equal(calls.deleteUser.length, 0);
  assert.doesNotMatch(responseText, /private auth provider detail|server-only-test-secret/);
});

test("Auth returning no user never reaches admin deletion", async () => {
  const { handler, calls } = createHarness({ authResponse: { data: { user: null }, error: null } });
  const response = await handler(request("POST", { token: "Bearer token-without-user" }));
  assert.equal(response.status, 401);
  assert.deepEqual(await json(response), { error: "Unable to delete account" });
  assert.equal(calls.deleteUser.length, 0);
});

test("authenticates the explicit bearer token and deletes only the verified user despite a malicious body", async () => {
  const { handler, calls } = createHarness({
    authResponse: { data: { user: { id: "verified-user-id" } }, error: null },
  });
  const response = await handler(request("POST", {
    token: "Bearer caller-token",
    body: { user_id: "attacker-selected-user-id", id: "other-user-id" },
  }));
  assert.equal(response.status, 200);
  assert.deepEqual(await json(response), { ok: true });
  assert.deepEqual(calls.getUser, [["caller-token"]]);
  assert.deepEqual(calls.deleteUser, [["verified-user-id"]]);
  assert.equal(calls.clients[0].key, "test-anon-key");
  assert.equal(calls.clients[1].key, "server-only-test-secret");
});

test("admin deletion failures return a generic error without leaking server details", async () => {
  const { handler, calls } = createHarness({
    deleteResponse: { error: { message: "secret admin deletion diagnostic" } },
  });
  const response = await handler(request("POST", { token: "Bearer caller-token" }));
  const responseText = await response.text();
  assert.equal(response.status, 500);
  assert.deepEqual(JSON.parse(responseText), { error: "Unable to delete account" });
  assert.deepEqual(calls.deleteUser, [["verified-user-id"]]);
  assert.doesNotMatch(responseText, /secret admin deletion diagnostic|server-only-test-secret/);
});

test("missing server configuration fails generically before Auth or admin calls", async () => {
  const { handler, calls } = createHarness({ env: { SUPABASE_SERVICE_ROLE_KEY: undefined } });
  const response = await handler(request("POST", { token: "Bearer caller-token" }));
  assert.equal(response.status, 401);
  assert.deepEqual(await json(response), { error: "Unable to delete account" });
  assert.equal(calls.clients.length, 0);
});
