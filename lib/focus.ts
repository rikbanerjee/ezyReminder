import type { FocusSession, FocusTime } from "./supabase/types.ts";

export type FocusTimerState = "running" | "paused" | "awaiting_finish" | "finished";

/** Calendar key in the account timezone, independent of the device timezone. */
export function focusLocalDate(now: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const part = (type: string) => parts.find((value) => value.type === type)!.value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}

/** Timestamp-derived countdown: browser suspension and rerenders cannot lose time. */
export function getFocusTimer(session: Pick<FocusSession,
  "duration_minutes" | "elapsed_seconds" | "last_resumed_at" | "finished_at" | "paused_at"
>, now: Date = new Date()): { elapsedSeconds: number; remainingSeconds: number; state: FocusTimerState } {
  const duration = session.duration_minutes * 60;
  const runningSeconds = session.last_resumed_at && !session.finished_at
    ? Math.max(0, (now.getTime() - new Date(session.last_resumed_at).getTime()) / 1000)
    : 0;
  const elapsedSeconds = Math.min(duration, Math.max(0, session.elapsed_seconds + runningSeconds));
  const remainingSeconds = Math.max(0, Math.ceil(duration - elapsedSeconds));
  const state: FocusTimerState = session.finished_at ? "finished"
    : remainingSeconds === 0 ? "awaiting_finish"
    : session.paused_at ? "paused" : "running";
  return { elapsedSeconds, remainingSeconds, state };
}

// ---------------------------------------------------------------------------------------------
// Focus time occurrences (migration 0016). Occurrences are derived, never stored: an occurrence is
// (focus_time_id, local_date) and its UTC start comes from the account timezone. The Dart port in
// mobile/ must pass the same cases in design/focus-time-fixtures.json.
// ---------------------------------------------------------------------------------------------

export type FocusTimeSchedule = Pick<FocusTime, "weekdays" | "start_time" | "budget_minutes">;
export type FocusOccurrence = { localDate: string; startsAt: Date; endsAt: Date };

const DAY_MS = 86_400_000;

/** Wall-clock offset of `timeZone` at an instant, in ms (local - UTC). */
function zoneOffsetMs(instantMs: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone, hourCycle: "h23", year: "numeric", month: "numeric", day: "numeric",
    hour: "numeric", minute: "numeric", second: "numeric",
  }).formatToParts(new Date(instantMs));
  const n = (type: string) => Number(parts.find((part) => part.type === type)!.value);
  const local = Date.UTC(n("year"), n("month") - 1, n("day"), n("hour"), n("minute"), n("second"));
  return local - Math.floor(instantMs / 1000) * 1000;
}

function parseLocalDate(localDate: string): [number, number, number] {
  const [y, m, d] = localDate.split("-").map(Number);
  return [y, m, d];
}

/** Calendar arithmetic on a YYYY-MM-DD key (no timezone involved). */
export function addLocalDays(localDate: string, days: number): string {
  const [y, m, d] = parseLocalDate(localDate);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** ISO weekday of a YYYY-MM-DD key: 1 = Monday .. 7 = Sunday. */
export function focusIsoWeekday(localDate: string): number {
  const [y, m, d] = parseLocalDate(localDate);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay() || 7;
}

/** First date strictly after `localDate` that falls on `isoWeekday` ("Next Saturday" after a missed Saturday is +7). */
export function nextWeekdayAfter(localDate: string, isoWeekday: number): string {
  const delta = ((isoWeekday - focusIsoWeekday(localDate) + 6) % 7) + 1; // 1..7
  return addLocalDays(localDate, delta);
}

/**
 * UTC instant of a wall-clock time on an account-local date. A time inside a spring-forward gap
 * shifts forward by the gap (02:30 -> 03:30); a repeated autumn time resolves to its first instance.
 */
export function focusOccurrenceStart(localDate: string, startTime: string, timeZone: string): Date {
  const [y, m, d] = parseLocalDate(localDate);
  const [hh = 0, mm = 0, ss = 0] = startTime.split(":").map(Number);
  const wall = Date.UTC(y, m - 1, d, hh, mm, ss);
  const before = zoneOffsetMs(wall - DAY_MS, timeZone);
  const after = zoneOffsetMs(wall + DAY_MS, timeZone);
  const valid = [...new Set([wall - before, wall - after])].filter((utc) => zoneOffsetMs(utc, timeZone) === wall - utc);
  if (valid.length > 0) return new Date(Math.min(...valid));
  return new Date(wall - before); // gap: keep the pre-transition offset, landing after the gap
}

/**
 * Upcoming weekly occurrences on or after today's account-local date whose start has not yet passed
 * its budget (an occurrence in progress stays listed until start + budget).
 */
export function nextFocusOccurrences(
  time: FocusTimeSchedule, now: Date, timeZone: string, count: number,
): FocusOccurrence[] {
  const out: FocusOccurrence[] = [];
  if (count <= 0 || time.weekdays.length === 0) return out;
  const today = focusLocalDate(now, timeZone);
  for (let i = 0; i < count * 7 + 7 && out.length < count; i++) {
    const localDate = addLocalDays(today, i);
    if (!time.weekdays.includes(focusIsoWeekday(localDate))) continue;
    const startsAt = focusOccurrenceStart(localDate, time.start_time, timeZone);
    const endsAt = new Date(startsAt.getTime() + time.budget_minutes * 60_000);
    if (endsAt.getTime() > now.getTime()) out.push({ localDate, startsAt, endsAt });
  }
  return out;
}

/**
 * Missed = still has planned work and `start + max(budget, sum(planned))` has passed. Use
 * `budgetMinutes: 0` for one-off assignments. Not a failure; it only drives the recovery card.
 */
export function isOccurrenceMissed(
  occurrence: { localDate: string; startTime: string; budgetMinutes: number },
  plannedMinutes: number[], now: Date, timeZone: string,
): boolean {
  if (plannedMinutes.length === 0) return false;
  const total = plannedMinutes.reduce((sum, minutes) => sum + minutes, 0);
  const startsAt = focusOccurrenceStart(occurrence.localDate, occurrence.startTime, timeZone);
  return now.getTime() >= startsAt.getTime() + Math.max(occurrence.budgetMinutes, total) * 60_000;
}
