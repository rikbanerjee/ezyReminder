/**
 * Quiet-hours resolution (PLAN.md §4.1: "Quiet hours per context are
 * respected by every channel"). Pure, Intl-only — no Node/Deno-specific
 * APIs — so this file is imported unchanged by both Next.js server code
 * and the Deno notification-sweep edge function (relative imports only,
 * no "@/" aliases, so it resolves outside the Next.js module graph too).
 */

export interface QuietHours {
  start?: string; // "HH:MM" local wall-clock
  end?: string; // "HH:MM" local wall-clock, may be earlier than start (wraps midnight)
}

function offsetMsForZone(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(date);

  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  const asUTC = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
  return asUTC - date.getTime();
}

function localParts(date: Date, timeZone: string): { y: number; mo: number; d: number; h: number; m: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).formatToParts(date);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  return { y: get("year"), mo: get("month"), d: get("day"), h: get("hour"), m: get("minute") };
}

/** Convert a local wall-clock date+time in `timeZone` to a UTC instant. */
function localToUTC(y: number, mo: number, d: number, h: number, m: number, timeZone: string, near: Date): Date {
  const offset = offsetMsForZone(near, timeZone);
  return new Date(Date.UTC(y, mo - 1, d, h, m, 0) - offset);
}

function parseHM(hm: string): { h: number; m: number } {
  const [h, m] = hm.split(":").map(Number);
  return { h: h || 0, m: m || 0 };
}

/** True if `now` falls inside the quiet window (local time). No window = never quiet. */
export function isQuietNow(quietHours: QuietHours | null | undefined, timeZone: string, now: Date = new Date()): boolean {
  if (!quietHours?.start || !quietHours?.end) return false;
  const start = parseHM(quietHours.start);
  const end = parseHM(quietHours.end);
  const startMin = start.h * 60 + start.m;
  const endMin = end.h * 60 + end.m;
  if (startMin === endMin) return false;

  const { h, m } = localParts(now, timeZone);
  const curMin = h * 60 + m;

  if (startMin < endMin) {
    return curMin >= startMin && curMin < endMin;
  }
  // Wraps midnight, e.g. start 18:00, end 08:00.
  return curMin >= startMin || curMin < endMin;
}

/**
 * The next UTC instant `end` occurs, assuming we're currently inside the
 * quiet window. Used to defer a notification's scheduled_for.
 */
export function nextAllowedTime(quietHours: QuietHours, timeZone: string, now: Date = new Date()): Date {
  const end = parseHM(quietHours.end ?? "00:00");
  const today = localParts(now, timeZone);

  let candidate = localToUTC(today.y, today.mo, today.d, end.h, end.m, timeZone, now);
  if (candidate.getTime() <= now.getTime()) {
    // End time already passed today (local) — try tomorrow's local date.
    const tomorrow = new Date(Date.UTC(today.y, today.mo - 1, today.d + 1, 12));
    candidate = localToUTC(tomorrow.getUTCFullYear(), tomorrow.getUTCMonth() + 1, tomorrow.getUTCDate(), end.h, end.m, timeZone, now);
  }
  return candidate;
}
