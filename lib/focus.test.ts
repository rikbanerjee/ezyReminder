import assert from "node:assert/strict";
import { test } from "node:test";
import { focusLocalDate, getFocusTimer } from "./focus.ts";

const running = {
  duration_minutes: 25, elapsed_seconds: 60.5,
  last_resumed_at: "2026-10-18T12:00:00Z", paused_at: null, finished_at: null,
};

test("focus countdown uses persisted timestamps across refresh and background suspension", () => {
  assert.deepEqual(getFocusTimer(running, new Date("2026-10-18T12:10:00.250Z")), {
    elapsedSeconds: 660.75, remainingSeconds: 840, state: "running",
  });
  assert.deepEqual(getFocusTimer(running, new Date("2026-10-18T14:00:00Z")), {
    elapsedSeconds: 1500, remainingSeconds: 0, state: "awaiting_finish",
  });
});

test("pause excludes time away and resumed countdown includes prior active segments", () => {
  const paused = { ...running, elapsed_seconds: 660.75, last_resumed_at: null, paused_at: "2026-10-18T12:10:00Z" };
  assert.deepEqual(getFocusTimer(paused, new Date("2026-10-19T12:00:00Z")), {
    elapsedSeconds: 660.75, remainingSeconds: 840, state: "paused",
  });
  const resumed = { ...paused, paused_at: null, last_resumed_at: "2026-10-19T12:00:00Z" };
  assert.equal(getFocusTimer(resumed, new Date("2026-10-19T12:05:00Z")).remainingSeconds, 540);
});

test("timer expiry waits for user outcome; finishing freezes the actual active duration", () => {
  const pausedExpired = { ...running, elapsed_seconds: 1500, paused_at: "2026-10-18T12:25:00Z", last_resumed_at: null };
  assert.equal(getFocusTimer(pausedExpired).state, "awaiting_finish");
  const finished = { ...running, elapsed_seconds: 124.25, last_resumed_at: null, finished_at: "2026-10-18T12:01:03.750Z" };
  assert.deepEqual(getFocusTimer(finished, new Date("2026-11-18T12:00:00Z")), {
    elapsedSeconds: 124.25, remainingSeconds: 1376, state: "finished",
  });
});

test("clock skew cannot subtract accumulated work", () => {
  assert.equal(getFocusTimer(running, new Date("2026-10-18T11:00:00Z")).elapsedSeconds, 60.5);
});

test("highlight date follows account timezone across midnight, DST and year rollover", () => {
  assert.equal(focusLocalDate(new Date("2026-10-18T00:30:00Z"), "America/New_York"), "2026-10-17");
  assert.equal(focusLocalDate(new Date("2026-10-18T23:30:00Z"), "Asia/Kolkata"), "2026-10-19");
  assert.equal(focusLocalDate(new Date("2026-11-01T05:30:00Z"), "America/New_York"), "2026-11-01");
  assert.equal(focusLocalDate(new Date("2026-11-01T06:30:00Z"), "America/New_York"), "2026-11-01");
  assert.equal(focusLocalDate(new Date("2027-01-01T01:00:00Z"), "America/Los_Angeles"), "2026-12-31");
});
