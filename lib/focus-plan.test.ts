import assert from "node:assert/strict";
import { test } from "node:test";
import type { FocusAssignment, FocusTime } from "./supabase/types.ts";
import {
  clock12, daysLabel, deadlineFor, groupOccurrences, minutesDraft, missedNextTarget, missedTasks, monthGrid, monthIsPast,
  oneOffTarget, othersInTarget, overBudget, parseMinutes, planOptions, selectCard, shortDate, splitOccurrences, startsAfterDeadline,
  stepMonth, validateTimeDraft, whenLabel, zonedParts,
} from "./focus-plan.ts";

const TZ = "America/New_York";
// The prototype's clock: Fri Oct 23, 2026 1:10 PM EDT.
const NOW = new Date("2026-10-23T17:10:00Z");

const time = (id: string, over: Partial<FocusTime>): FocusTime => ({
  id, label: null, context_slug: "sidegig", weekdays: [4], start_time: "19:00:00", budget_minutes: 30, enabled: true, updated_at: "2026-10-01T00:00:00Z", ...over,
});
const shop = time("ft1", { label: "Shop time" });
const sat = time("ft2", { label: "Saturday mornings", weekdays: [6], start_time: "09:00:00", budget_minutes: 60 });
const lunch = time("ft3", { label: "Lunch focus", context_slug: "work", weekdays: [1, 2, 3, 4, 5], start_time: "12:30:00" });
const times = [shop, sat, lunch];

let seq = 0;
const task = (over: Partial<FocusAssignment>): FocusAssignment => ({
  id: `a${++seq}`, reminder_id: `r${seq}`, reminder_title: `Task ${seq}`, context_slug: "sidegig", focus_time_id: "ft1", focus_time_label: "Shop time",
  local_date: "2026-10-29", start_time: "19:00:00", planned_minutes: 15, position: 0, state: "planned", moved_to: null,
  updated_at: "2026-10-20T00:00:00Z", due_at: null, ship_by: null, ...over,
});

test("formatting follows the prototype strings", () => {
  assert.equal(clock12("19:00:00"), "7 PM");
  assert.equal(clock12("12:30"), "12:30 PM");
  assert.equal(clock12("00:05"), "12:05 AM");
  assert.equal(whenLabel("2026-10-29", "19:00:00"), "Thursday · 7 PM");
  assert.equal(shortDate("2026-10-24"), "Sat, Oct 24");
  assert.equal(daysLabel([5, 3, 4, 2, 1]), "Weekdays");
  assert.equal(daysLabel([7, 6]), "Weekends");
  assert.equal(daysLabel([4]), "Thursday");
  assert.equal(daysLabel([7, 1]), "Mon, Sun");
  assert.deepEqual(zonedParts(NOW, TZ), { localDate: "2026-10-23", time: "13:10" });
});

test("assignments group into occurrences ordered by start, tasks by position value (gaps allowed)", () => {
  const list = [
    task({ id: "c", position: 7, planned_minutes: 10 }),
    task({ id: "a", position: 0, planned_minutes: 15 }),
    task({ id: "b", position: 3, planned_minutes: 10 }),
    task({ id: "sat", focus_time_id: "ft2", focus_time_label: "Saturday mornings", local_date: "2026-10-24", start_time: "09:00:00", planned_minutes: 20 }),
    task({ id: "done", state: "in_progress" }),
    task({ id: "gone", state: "skipped" }),
  ];
  const occurrences = groupOccurrences(list, times, TZ);
  assert.deepEqual(occurrences.map((o) => o.key), ["ft2|2026-10-24|09:00:00", "ft1|2026-10-29|19:00:00"]);
  const thursday = occurrences[1];
  assert.deepEqual(thursday.tasks.map((t) => t.id), ["a", "b", "c"]);
  assert.equal(thursday.plannedMinutes, 35);
  assert.equal(thursday.budgetMinutes, 30);
  assert.equal(overBudget(thursday), true);
  assert.equal(overBudget(occurrences[0]), false);
  assert.equal(thursday.label, "Shop time");
  assert.equal(thursday.startsAt.toISOString(), "2026-10-29T23:00:00.000Z");
});

test("one-off and archived-time assignments group by their own date/time with no budget", () => {
  const oneOff = task({ focus_time_id: null, focus_time_label: null, local_date: "2026-10-26", start_time: "18:30:00" });
  const archived = task({ focus_time_id: "gone", focus_time_label: "Old", local_date: "2026-10-26", start_time: "18:30:00" });
  const occurrences = groupOccurrences([oneOff, archived], times, TZ);
  assert.equal(occurrences.length, 2);
  for (const occurrence of occurrences) assert.equal(occurrence.budgetMinutes, 0);
  assert.equal(occurrences.find((o) => o.focusTimeId === "gone")!.label, "Old");
  assert.equal(overBudget(occurrences[0]), false);
});

test("missed wiring: start + max(budget, planned) must pass; oldest first and tasks flattened", () => {
  const old = task({ id: "m1", focus_time_id: "ft2", local_date: "2026-10-17", start_time: "09:00:00", planned_minutes: 20 });
  const lastThursday = task({ id: "m2", local_date: "2026-10-22", planned_minutes: 10 });
  const justEnded = task({ id: "edge", focus_time_id: "ft3", context_slug: "work", local_date: "2026-10-23", start_time: "12:30:00", planned_minutes: 10 });
  const upcoming = task({ id: "u1" });
  const groups = groupOccurrences([upcoming, lastThursday, old], times, TZ);
  const split = splitOccurrences(groups, NOW, TZ);
  assert.deepEqual(missedTasks(split.missed).map((m) => m.task.id), ["m1", "m2"]);
  assert.deepEqual(split.upcoming.map((o) => o.tasks[0].id), ["u1"]);
  // Fri 12:30 lunch focus with a 30 min budget ended at 13:00, so it is missed at 13:10 but not at 12:59.
  const lunchGroup = groupOccurrences([justEnded], times, TZ);
  assert.equal(splitOccurrences(lunchGroup, NOW, TZ).missed.length, 1);
  assert.equal(splitOccurrences(lunchGroup, new Date("2026-10-23T16:59:00Z"), TZ).missed.length, 0);
  // Over-planned occurrences stay open until start + planned total.
  const heavy = [task({ id: "h1", focus_time_id: "ft3", context_slug: "work", local_date: "2026-10-23", start_time: "12:30:00", planned_minutes: 40 }),
    task({ id: "h2", focus_time_id: "ft3", context_slug: "work", local_date: "2026-10-23", start_time: "12:30:00", planned_minutes: 30 })];
  assert.equal(splitOccurrences(groupOccurrences(heavy, times, TZ), NOW, TZ).missed.length, 0);
});

test("card priority: session, then highlight, then up next, then empty", () => {
  assert.equal(selectCard({ timer: "awaiting_finish", highlightReady: true, hasUpcoming: true }), "timeup");
  assert.equal(selectCard({ timer: "paused", highlightReady: true, hasUpcoming: true }), "paused");
  assert.equal(selectCard({ timer: "running", highlightReady: false, hasUpcoming: false }), "running");
  assert.equal(selectCard({ timer: null, highlightReady: true, hasUpcoming: true }), "highlight");
  assert.equal(selectCard({ timer: null, highlightReady: false, hasUpcoming: true }), "upnext");
  assert.equal(selectCard({ timer: null, highlightReady: false, hasUpcoming: false }), "empty");
  assert.equal(selectCard({ timer: "finished", highlightReady: false, hasUpcoming: false }), "empty");
});

test("Work on this offers the next 4 occurrences of enabled times in the reminder's context", () => {
  const work = planOptions(times, "work", NOW, TZ);
  // Fri lunch focus (12:30-13:00) already ended at 13:10.
  assert.deepEqual(work.map((o) => o.localDate), ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29"]);
  const gig = planOptions(times, "sidegig", NOW, TZ);
  assert.deepEqual(gig.map((o) => `${o.focusTimeId}@${o.localDate}`), ["ft2@2026-10-24", "ft1@2026-10-29", "ft2@2026-10-31", "ft1@2026-11-05"]);
  assert.equal(planOptions([{ ...shop, enabled: false }], "sidegig", NOW, TZ).length, 0);
  assert.equal(planOptions([], "work", NOW, TZ).length, 0);
});

test("others in a target occurrence exclude the reminder being planned and one-offs", () => {
  const target = planOptions(times, "sidegig", NOW, TZ).find((o) => o.key === "ft1|2026-10-29")!;
  const list = [task({ reminder_id: "self" }), task({ id: "other", reminder_id: "other", position: 2 }), task({ focus_time_id: null, local_date: "2026-10-29" })];
  assert.deepEqual(othersInTarget(list, target, "self").map((t) => t.id), ["other"]);
  assert.deepEqual(othersInTarget(list, oneOffTarget("2026-10-29", "19:00", TZ), "self"), []);
});

test("deadlines: ship-by covers the whole day, due is compared to the exact instant", () => {
  const ship = deadlineFor({ dueAt: "2026-10-20T00:00:00Z", shipBy: "2026-10-27" }, TZ)!;
  assert.equal(ship.text, "Ship by Tue, Oct 27");
  assert.equal(startsAfterDeadline(oneOffTarget("2026-10-27", "23:30", TZ).startsAt, ship), false);
  assert.equal(startsAfterDeadline(oneOffTarget("2026-10-28", "00:00", TZ).startsAt, ship), true);
  const due = deadlineFor({ dueAt: "2026-10-27T14:00:00Z", shipBy: null }, TZ)!;
  assert.equal(due.text, "Due Tue, Oct 27 · 10 AM");
  assert.equal(startsAfterDeadline(oneOffTarget("2026-10-27", "10:30", TZ).startsAt, due), true);
  assert.equal(startsAfterDeadline(oneOffTarget("2026-10-27", "09:30", TZ).startsAt, due), false);
  assert.equal(deadlineFor({ dueAt: null, shipBy: null }, TZ), null);
  assert.equal(startsAfterDeadline(new Date(), null), false);
});

test("missed 'Next {weekday}' resolves strictly after the missed date and keeps a still-valid focus time", () => {
  const missed = task({ focus_time_id: "ft2", local_date: "2026-10-17", start_time: "09:00:00" });
  assert.deepEqual(missedNextTarget(missed, times), { focusTimeId: "ft2", localDate: "2026-10-24", startTime: "09:00:00", weekday: "Saturday" });
  // Focus time no longer runs on that weekday, or was archived: becomes a one-off at the original time.
  assert.equal(missedNextTarget(missed, [{ ...sat, weekdays: [3] }]).focusTimeId, null);
  assert.deepEqual(missedNextTarget(missed, []), { focusTimeId: null, localDate: "2026-10-24", startTime: "09:00:00", weekday: "Saturday" });
  assert.equal(missedNextTarget(task({ focus_time_id: null, local_date: "2026-10-22" }), times).localDate, "2026-10-29");
});

test("minutes parsing and chip drafts", () => {
  assert.equal(parseMinutes("25", ""), 25);
  assert.equal(parseMinutes("custom", " 45 "), 45);
  for (const bad of ["", "0", "181", "1.5", "-3", "abc"]) assert.equal(parseMinutes("custom", bad), null);
  assert.deepEqual(minutesDraft(25, ["10", "25", "50"]), { mins: "25", custom: "" });
  assert.deepEqual(minutesDraft(20, ["10", "25", "50"]), { mins: "custom", custom: "20" });
});

test("calendar grid is Sunday-first and past months are not browsable", () => {
  const october = monthGrid(2026, 9);
  assert.equal(october.offset, 4); // Oct 1, 2026 is a Thursday
  assert.equal(october.days.length, 31);
  assert.equal(october.days[22].localDate, "2026-10-23");
  assert.deepEqual(stepMonth(2026, 11, 1), { year: 2027, month0: 0 });
  assert.deepEqual(stepMonth(2026, 0, -1), { year: 2025, month0: 11 });
  assert.equal(monthIsPast(2026, 8, "2026-10-23"), true);
  assert.equal(monthIsPast(2026, 9, "2026-10-23"), false);
});

test("focus time form validation reports each missing field", () => {
  assert.deepEqual(validateTimeDraft({ days: [], mins: "30", custom: "", ctx: null }), { days: "Choose at least one day.", ctx: "Choose Work or Side Gig." });
  assert.deepEqual(validateTimeDraft({ days: [1], mins: "custom", custom: "200", ctx: "work" }), { mins: "Choose a whole number from 1 to 180 minutes." });
  assert.deepEqual(validateTimeDraft({ days: [1], mins: "15", custom: "", ctx: "sidegig" }), {});
});
