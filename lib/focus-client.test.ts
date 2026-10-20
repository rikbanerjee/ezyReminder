import assert from "node:assert/strict";
import { test } from "node:test";
import { fetchFocusDashboard } from "./focus-client.ts";

const base = { server_now: "2026-10-23T17:10:00Z", timezone: "UTC", local_date: "2026-10-23", highlight: null, active_session: null };
const fake = (v2: { data?: unknown; error?: { code: string } | null }) => ({
  rpc: async (name: string) => (name === "get_focus_dashboard_v2" ? { data: v2.data ?? null, error: v2.error ?? null } : { data: base, error: null }),
}) as unknown as Parameters<typeof fetchFocusDashboard>[0];
const v2 = { ...base, preferred_minutes: 25, focus_times: [], assignments: [] };

test("focus_api 17 enables planned intents and restore", async () => {
  assert.deepEqual((await fetchFocusDashboard(fake({ data: { ...v2, focus_api: 17 } }))).api, { preferences: true, times: true, intents: true });
});

test("0016 without 0017 keeps planned starts and archive as before", async () => {
  assert.deepEqual((await fetchFocusDashboard(fake({ data: v2 }))).api, { preferences: true, times: true, intents: false });
});

test("missing v2 falls back to the MVP with every flag off", async () => {
  assert.deepEqual((await fetchFocusDashboard(fake({ error: { code: "PGRST202" } }))).api, { preferences: false, times: false, intents: false });
});
