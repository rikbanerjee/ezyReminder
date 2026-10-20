import type { FocusAssignment, FocusContextSlug, FocusTime } from "./supabase/types.ts";
import {
  addLocalDays, focusIsoWeekday, focusOccurrenceStart, isOccurrenceMissed, nextFocusOccurrences, nextWeekdayAfter,
  type FocusTimerState,
} from "./focus.ts";

// Pure presentation/planning logic for Focus times (DESIGN.md §9, FOCUS_IMPLEMENTATION_PLAN.md §13.4).
// All timezone arithmetic is delegated to lib/focus.ts; nothing here re-derives it.

const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const pad = (n: number) => String(n).padStart(2, "0");
const ymd = (localDate: string): [number, number, number] => {
  const [y, m, d] = localDate.split("-").map(Number);
  return [y, m, d];
};

// ----- formatting (calendar strings only; no timezone involved) -----

export const isoWeekdayName = (iso: number) => DAYS[iso % 7];
export const weekdayName = (localDate: string) => isoWeekdayName(focusIsoWeekday(localDate));
export function shortDate(localDate: string): string {
  const [, m, d] = ymd(localDate);
  return `${weekdayName(localDate).slice(0, 3)}, ${MONTHS[m - 1]} ${d}`;
}
export function monthDay(localDate: string): string {
  const [, m, d] = ymd(localDate);
  return `${MONTHS[m - 1]} ${d}`;
}
/** "19:00:00" -> "7 PM", "12:30" -> "12:30 PM". */
export function clock12(time: string): string {
  const [h, m = 0] = time.split(":").map(Number);
  return `${h % 12 || 12}${m ? `:${pad(m)}` : ""} ${h < 12 ? "AM" : "PM"}`;
}
/** "Thursday · 7 PM" */
export const whenLabel = (localDate: string, startTime: string) => `${weekdayName(localDate)} · ${clock12(startTime)}`;
export function daysLabel(days: number[]): string {
  const sorted = [...days].sort((a, b) => a - b);
  const key = sorted.join();
  if (key === "1,2,3,4,5") return "Weekdays";
  if (key === "6,7") return "Weekends";
  if (sorted.length === 1) return isoWeekdayName(sorted[0]);
  return sorted.map((n) => isoWeekdayName(n).slice(0, 3)).join(", ");
}
export const timeInput = (time: string) => time.slice(0, 5);

/** Account-local calendar date and "HH:MM" of an instant. */
export function zonedParts(instant: Date, timeZone: string): { localDate: string; time: string } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
  }).formatToParts(instant);
  const part = (type: string) => parts.find((value) => value.type === type)!.value;
  return { localDate: `${part("year")}-${part("month")}-${part("day")}`, time: `${part("hour")}:${part("minute")}` };
}

// ----- deadlines (planning never moves them) -----

export type Deadline = { kind: "due" | "ship"; at: Date; text: string };
/** Order ship-by (a date; the whole day counts) wins over the reminder's own due time. */
export function deadlineFor(input: { dueAt: string | null; shipBy: string | null }, timeZone: string): Deadline | null {
  if (input.shipBy) {
    const day = input.shipBy.slice(0, 10);
    return { kind: "ship", at: focusOccurrenceStart(addLocalDays(day, 1), "00:00:00", timeZone), text: `Ship by ${shortDate(day)}` };
  }
  if (!input.dueAt) return null;
  const at = new Date(input.dueAt);
  if (Number.isNaN(at.getTime())) return null;
  const { localDate, time } = zonedParts(at, timeZone);
  return { kind: "due", at, text: `Due ${shortDate(localDate)}${time === "23:59" ? "" : ` · ${clock12(time)}`}` };
}
/** A ship-by deadline is the first instant of the next day, so a start exactly then is already late. */
export const startsAfterDeadline = (startsAt: Date, deadline: Deadline | null) =>
  !!deadline && (deadline.kind === "ship" ? startsAt.getTime() >= deadline.at.getTime() : startsAt.getTime() > deadline.at.getTime());

// ----- minutes -----

/** Whole minutes 1-180 from a chip selection ("custom" reads the text field), else null. */
export function parseMinutes(selection: string, custom: string): number | null {
  if (selection !== "custom") return Number(selection);
  const text = custom.trim();
  const value = Number(text);
  return /^\d+$/.test(text) && value >= 1 && value <= 180 ? value : null;
}
/** Chip selection that shows `minutes`: a preset when it is one, otherwise Custom with the value filled in. */
export function minutesDraft(minutes: number, presets: string[]): { mins: string; custom: string } {
  return presets.includes(String(minutes)) ? { mins: String(minutes), custom: "" } : { mins: "custom", custom: String(minutes) };
}

// ----- occurrences -----

export type Occurrence = {
  key: string;
  focusTimeId: string | null;
  label: string | null;
  slug: FocusContextSlug;
  localDate: string;
  startTime: string;
  startsAt: Date;
  /** The focus time's "I usually have" minutes; 0 for one-offs and archived times. */
  budgetMinutes: number;
  plannedMinutes: number;
  tasks: FocusAssignment[];
};
export const occurrenceKey = (focusTimeId: string | null, localDate: string, startTime: string) => `${focusTimeId ?? "one"}|${localDate}|${startTime}`;
export const overBudget = (occurrence: Pick<Occurrence, "budgetMinutes" | "plannedMinutes">) =>
  occurrence.budgetMinutes > 0 && occurrence.plannedMinutes > occurrence.budgetMinutes;

/** Positions are 0-based and may have gaps: order by value, then arrival order. */
const byPosition = (a: FocusAssignment, b: FocusAssignment) => a.position - b.position;

/** Group planned assignments into occurrences, earliest first. In-progress/reviewed work is not "planned". */
export function groupOccurrences(assignments: FocusAssignment[], times: FocusTime[], timeZone: string): Occurrence[] {
  const groups = new Map<string, Occurrence>();
  for (const task of assignments) {
    if (task.state !== "planned") continue;
    const key = occurrenceKey(task.focus_time_id, task.local_date, task.start_time);
    let occurrence = groups.get(key);
    if (!occurrence) {
      const time = task.focus_time_id ? times.find((value) => value.id === task.focus_time_id) : undefined;
      occurrence = {
        key, focusTimeId: task.focus_time_id, label: time?.label ?? task.focus_time_label, slug: time?.context_slug ?? task.context_slug,
        localDate: task.local_date, startTime: task.start_time,
        startsAt: focusOccurrenceStart(task.local_date, task.start_time, timeZone),
        budgetMinutes: time?.budget_minutes ?? 0, plannedMinutes: 0, tasks: [],
      };
      groups.set(key, occurrence);
    }
    occurrence.tasks.push(task);
  }
  const out = [...groups.values()];
  for (const occurrence of out) {
    occurrence.tasks.sort(byPosition);
    occurrence.plannedMinutes = occurrence.tasks.reduce((sum, task) => sum + task.planned_minutes, 0);
  }
  return out.sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime() || a.key.localeCompare(b.key));
}

/** Missed = `start + max(budget, Σ planned)` has passed with work still planned (lib/focus.ts rule). */
export function splitOccurrences(occurrences: Occurrence[], now: Date, timeZone: string): { upcoming: Occurrence[]; missed: Occurrence[] } {
  const upcoming: Occurrence[] = [];
  const missed: Occurrence[] = [];
  for (const occurrence of occurrences) {
    const isMissed = isOccurrenceMissed(
      { localDate: occurrence.localDate, startTime: occurrence.startTime, budgetMinutes: occurrence.budgetMinutes },
      occurrence.tasks.map((task) => task.planned_minutes), now, timeZone,
    );
    (isMissed ? missed : upcoming).push(occurrence);
  }
  return { upcoming, missed };
}

/** Missed tasks flattened oldest first - the recovery card shows [0] and "+N more". */
export const missedTasks = (missed: Occurrence[]) => missed.flatMap((occurrence) => occurrence.tasks.map((task) => ({ task, occurrence })));

export type CardKind = "empty" | "highlight" | "upnext" | "running" | "paused" | "timeup";
/** Priority: unfinished session -> chosen highlight -> first planned task of the next occurrence -> empty. */
export function selectCard(input: { timer: FocusTimerState | null; highlightReady: boolean; hasUpcoming: boolean }): CardKind {
  if (input.timer === "awaiting_finish") return "timeup";
  if (input.timer === "paused") return "paused";
  if (input.timer === "running") return "running";
  if (input.highlightReady) return "highlight";
  return input.hasUpcoming ? "upnext" : "empty";
}

// ----- "Work on this" -----

export type PlanTarget = {
  key: string;
  focusTimeId: string | null;
  label: string | null;
  localDate: string;
  startTime: string;
  startsAt: Date;
  budgetMinutes: number;
};

/** Next 4 occurrences of enabled Focus times in the reminder's context. */
export function planOptions(times: FocusTime[], slug: FocusContextSlug, now: Date, timeZone: string, count = 4): PlanTarget[] {
  const out: PlanTarget[] = [];
  for (const time of times) {
    if (!time.enabled || time.context_slug !== slug) continue;
    for (const occurrence of nextFocusOccurrences(time, now, timeZone, count)) {
      out.push({
        key: `${time.id}|${occurrence.localDate}`, focusTimeId: time.id, label: time.label, localDate: occurrence.localDate,
        startTime: time.start_time, startsAt: occurrence.startsAt, budgetMinutes: time.budget_minutes,
      });
    }
  }
  return out.sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime() || a.key.localeCompare(b.key)).slice(0, count);
}
export function oneOffTarget(localDate: string, time: string, timeZone: string): PlanTarget {
  const startTime = `${timeInput(time)}:00`;
  return { key: `one|${localDate}|${startTime}`, focusTimeId: null, label: null, localDate, startTime, startsAt: focusOccurrenceStart(localDate, startTime, timeZone), budgetMinutes: 0 };
}
/** Other planned tasks already in the target's occurrence (shown as "Also planned here"). */
export function othersInTarget(assignments: FocusAssignment[], target: PlanTarget, reminderId: string): FocusAssignment[] {
  if (!target.focusTimeId) return [];
  return assignments.filter((task) => task.state === "planned" && task.focus_time_id === target.focusTimeId
    && task.local_date === target.localDate && task.start_time === target.startTime && task.reminder_id !== reminderId).sort(byPosition);
}

/** "Next Saturday": the same weekday strictly after the missed date, kept on its focus time when that still runs that day. */
export function missedNextTarget(task: FocusAssignment, times: FocusTime[]): { focusTimeId: string | null; localDate: string; startTime: string; weekday: string } {
  const weekday = focusIsoWeekday(task.local_date);
  const localDate = nextWeekdayAfter(task.local_date, weekday);
  const time = task.focus_time_id ? times.find((value) => value.id === task.focus_time_id) : undefined;
  const keepsTime = !!time && time.weekdays.includes(weekday);
  return { focusTimeId: keepsTime ? time.id : null, localDate, startTime: keepsTime ? time.start_time : task.start_time, weekday: isoWeekdayName(weekday) };
}

// ----- calendar picker (Sunday-first month grid) -----

export function monthGrid(year: number, month0: number): { offset: number; days: { n: number; localDate: string }[] } {
  const first = `${year}-${pad(month0 + 1)}-01`;
  const count = new Date(Date.UTC(year, month0 + 1, 0)).getUTCDate();
  return {
    offset: focusIsoWeekday(first) % 7,
    days: Array.from({ length: count }, (_, i) => ({ n: i + 1, localDate: `${year}-${pad(month0 + 1)}-${pad(i + 1)}` })),
  };
}
export function stepMonth(year: number, month0: number, delta: number): { year: number; month0: number } {
  const date = new Date(Date.UTC(year, month0 + delta, 1));
  return { year: date.getUTCFullYear(), month0: date.getUTCMonth() };
}
export const monthLabel = (year: number, month0: number) => `${["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][month0]} ${year}`;
/** Months wholly in the past cannot be browsed to. */
export const monthIsPast = (year: number, month0: number, todayLocalDate: string) => monthGrid(year, month0).days.at(-1)!.localDate < todayLocalDate;

// ----- focus time form -----

export function validateTimeDraft(input: { days: number[]; mins: string; custom: string; ctx: FocusContextSlug | null }): { days?: string; mins?: string; ctx?: string } {
  const errors: { days?: string; mins?: string; ctx?: string } = {};
  if (input.days.length === 0) errors.days = "Choose at least one day.";
  if (parseMinutes(input.mins, input.custom) === null) errors.mins = "Choose a whole number from 1 to 180 minutes.";
  if (!input.ctx) errors.ctx = "Choose Work or Side Gig.";
  return errors;
}
