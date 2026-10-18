import type { FocusSession } from "./supabase/types.ts";

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
