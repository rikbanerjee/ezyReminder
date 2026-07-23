/**
 * Client-side date helpers for the Today list. All grouping and formatting
 * runs in the browser so "today", "overdue", and relative chips resolve in
 * the user's local timezone (the server runs UTC — DESIGN.md §4.1).
 */

export type Bucket = "overdue" | "today" | "upcoming" | "nodate";

function startOfDay(d: Date): Date {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

/** Which section a reminder's effective due time belongs to, vs. now. */
export function bucketFor(due: Date | null, now: Date = new Date()): Bucket {
  if (!due) return "nodate";
  const todayStart = startOfDay(now);
  const tomorrowStart = new Date(todayStart);
  tomorrowStart.setDate(tomorrowStart.getDate() + 1);

  if (due.getTime() < now.getTime()) return "overdue";
  if (due < tomorrowStart) return "today";
  return "upcoming";
}

/** True if a timestamp falls on the local calendar day of `now`. */
export function isSameLocalDay(a: Date, now: Date = new Date()): boolean {
  return startOfDay(a).getTime() === startOfDay(now).getTime();
}

/**
 * Compact relative chip: "in 2h", "2h overdue", "Tue 6:00 PM", "Tomorrow 9 AM".
 * `overdue` styling is left to the caller (based on bucketFor).
 */
export function relativeDue(due: Date | null, now: Date = new Date()): string {
  if (!due) return "";

  const diffMs = due.getTime() - now.getTime();
  const past = diffMs < 0;
  const absMin = Math.round(Math.abs(diffMs) / 60000);

  // Within a day either direction → relative phrasing.
  if (absMin < 60) {
    const m = Math.max(1, absMin);
    return past ? `${m}m overdue` : `in ${m}m`;
  }
  if (absMin < 60 * 24 && isSameLocalDay(due, now)) {
    const h = Math.round(absMin / 60);
    return past ? `${h}h overdue` : `in ${h}h`;
  }

  // Otherwise an absolute label.
  const todayStart = startOfDay(now);
  const dueStart = startOfDay(due);
  const dayDiff = Math.round((dueStart.getTime() - todayStart.getTime()) / 86400000);

  const time = due.toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: due.getMinutes() ? "2-digit" : undefined,
  });

  if (dayDiff === 0) return time;
  if (dayDiff === 1) return `Tomorrow ${time}`;
  if (dayDiff === -1) return `Yesterday ${time}`;
  if (dayDiff > 1 && dayDiff < 7) {
    const wd = due.toLocaleDateString(undefined, { weekday: "short" });
    return `${wd} ${time}`;
  }

  const date = due.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  return `${date} ${time}`;
}

/** Snooze presets (DESIGN.md §4.1 swipe-left menu). Returns a target Date. */
export function snoozeTarget(preset: "1h" | "tonight" | "tomorrow" | "nextweek", now: Date = new Date()): Date {
  const t = new Date(now);
  switch (preset) {
    case "1h":
      t.setHours(t.getHours() + 1);
      return t;
    case "tonight":
      t.setHours(19, 0, 0, 0);
      if (t.getTime() <= now.getTime()) t.setDate(t.getDate() + 1);
      return t;
    case "tomorrow":
      t.setDate(t.getDate() + 1);
      t.setHours(9, 0, 0, 0);
      return t;
    case "nextweek":
      t.setDate(t.getDate() + 7);
      t.setHours(9, 0, 0, 0);
      return t;
  }
}
