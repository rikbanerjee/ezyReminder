"use client";

import { useState } from "react";
import { CalendarDays } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Compact calendar + time popover with an explicit OK to confirm (per
 * direct feedback — replaces the native `<input type="datetime-local">`,
 * whose OS picker was too large and had no explicit confirm step). Value
 * format matches the existing "YYYY-MM-DDTHH:mm" local string the sheet
 * already stores in `dueLocal`. Follows the same manual backdrop+absolute
 * panel pattern already used for the row-level snooze menu, rather than
 * pulling in a calendar library.
 */

const WEEKDAYS = ["S", "M", "T", "W", "T", "F", "S"];

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function parseValue(v: string): Date | null {
  if (!v) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

function toValue(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function formatDisplay(v: string): string | null {
  const d = parseValue(v);
  if (!d) return null;
  return d.toLocaleString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

export function DateTimePicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [open, setOpen] = useState(false);
  const [viewMonth, setViewMonth] = useState(() => {
    const d = parseValue(value) ?? new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1);
  });
  const [selectedDay, setSelectedDay] = useState<Date | null>(() => parseValue(value));
  const [time, setTime] = useState(() => {
    const d = parseValue(value);
    return d ? `${pad(d.getHours())}:${pad(d.getMinutes())}` : "09:00";
  });

  function openPanel() {
    const d = parseValue(value);
    setViewMonth(new Date((d ?? new Date()).getFullYear(), (d ?? new Date()).getMonth(), 1));
    setSelectedDay(d);
    setTime(d ? `${pad(d.getHours())}:${pad(d.getMinutes())}` : "09:00");
    setOpen(true);
  }

  function confirm() {
    if (!selectedDay) {
      setOpen(false);
      return;
    }
    const [h, m] = time.split(":").map(Number);
    const d = new Date(selectedDay);
    d.setHours(h || 0, m || 0, 0, 0);
    onChange(toValue(d));
    setOpen(false);
  }

  function clearDate() {
    setSelectedDay(null);
    onChange("");
    setOpen(false);
  }

  const year = viewMonth.getFullYear();
  const month = viewMonth.getMonth();
  const firstDow = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const cells: (Date | null)[] = [];
  for (let i = 0; i < firstDow; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(year, month, d));

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  return (
    <div className="relative">
      <button
        type="button"
        onClick={openPanel}
        className="flex h-8 items-center gap-1.5 rounded-lg border border-input bg-transparent px-2 text-[13px]"
      >
        <CalendarDays className="size-3.5 shrink-0 text-text-2" />
        {formatDisplay(value) ?? <span className="text-text-2">Set date &amp; time</span>}
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-30" onClick={() => setOpen(false)} aria-hidden />
          {/* Deliberately compact — small cells, tight gaps (per feedback:
              "reduce the space of the calendar") rather than a full-size
              month view. right-0 (not left-0): this trigger sits mid-row,
              after the context select — anchoring the panel's left edge to
              the trigger meant it grew rightward past the sheet's edge and
              got clipped. Anchoring the right edge instead grows it
              leftward, back into the row's open space. */}
          <div className="absolute right-0 top-9 z-40 w-60 max-w-[calc(100vw-2.5rem)] rounded-xl border border-hairline bg-surface p-2.5 shadow-lg">
            <div className="flex items-center justify-between px-0.5">
              <button
                type="button"
                onClick={() => setViewMonth(new Date(year, month - 1, 1))}
                aria-label="Previous month"
                className="grid size-6 place-items-center rounded-md text-text-2 hover:bg-muted"
              >
                ‹
              </button>
              <span className="text-[12px] font-semibold">
                {viewMonth.toLocaleString(undefined, { month: "long", year: "numeric" })}
              </span>
              <button
                type="button"
                onClick={() => setViewMonth(new Date(year, month + 1, 1))}
                aria-label="Next month"
                className="grid size-6 place-items-center rounded-md text-text-2 hover:bg-muted"
              >
                ›
              </button>
            </div>

            <div className="mt-1.5 grid grid-cols-7">
              {WEEKDAYS.map((w, i) => (
                <span key={i} className="text-center text-[10px] font-medium text-text-2">
                  {w}
                </span>
              ))}
            </div>
            <div className="grid grid-cols-7 gap-y-0.5">
              {cells.map((d, i) => {
                if (!d) return <span key={i} />;
                const isSelected = !!selectedDay && d.toDateString() === selectedDay.toDateString();
                const isToday = d.toDateString() === today.toDateString();
                return (
                  <button
                    key={i}
                    type="button"
                    onClick={() => setSelectedDay(d)}
                    className={cn(
                      "mx-auto grid size-6 place-items-center rounded-full text-[11px] transition-colors",
                      isSelected
                        ? "bg-work font-semibold text-white"
                        : isToday
                          ? "font-semibold text-work"
                          : "text-foreground hover:bg-muted",
                    )}
                  >
                    {d.getDate()}
                  </button>
                );
              })}
            </div>

            <div className="mt-2 border-t border-hairline pt-2">
              <input
                type="time"
                value={time}
                onChange={(e) => setTime(e.target.value)}
                className="h-7 w-full rounded-lg border border-input bg-transparent px-2 text-[13px] outline-none"
              />
            </div>

            <div className="mt-2 flex items-center justify-between">
              <button type="button" onClick={clearDate} className="text-[12px] text-text-2 hover:text-foreground">
                No date
              </button>
              <button
                type="button"
                onClick={confirm}
                disabled={!selectedDay}
                className="rounded-lg bg-work px-4 py-1.5 text-[13px] font-semibold text-white disabled:opacity-40"
              >
                OK
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
