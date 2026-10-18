"use client";

import { createContext, useContext, type ReactNode } from "react";
import { Target } from "lucide-react";
import type { HomeReminder } from "@/components/home/types";
import { whenLabel } from "@/lib/focus-plan";
import { FocusTimesSettingsRow, TodayFocus } from "./focus-card";
import { OccurrenceView, PlanView, TimeEditView, TimesView } from "./focus-plan-sheets";
import { AfterView, ChooseView, ReviewView, SessionView, SetupView } from "./focus-session-sheets";
import { FocusSheet } from "./focus-sheet";
import { FBtn } from "./focus-ui";
import { isFocusEligible, subjectOfReminder, useFocusController, type FocusController, type Mode } from "./use-focus-controller";

const FocusContext = createContext<FocusController | null>(null);

function sheetTitle(c: FocusController, mode: Mode): string {
  switch (mode) {
    case "choose": return "Today's focus";
    case "setup": return "Focus on this";
    case "session": return c.timer?.state === "awaiting_finish" ? "Time is up" : c.timer?.state === "paused" ? "Paused" : "In focus";
    case "review": return "How did it go?";
    case "after": return "Session saved";
    case "occ": return c.occurrence ? whenLabel(c.occurrence.localDate, c.occurrence.startTime) : "Focus time";
    case "plan": return "Work on this";
    case "times": return "Your focus times";
    case "timeedit": return c.timeEdit?.isNew ? "New focus time" : "Edit focus time";
  }
}

/** One sheet at a time; modes swap inside the open sheet. All drafts live in the controller, not here. */
function FocusSheetHost({ c, mode }: { c: FocusController; mode: Mode }) {
  const inlineReviewError = mode === "review" && c.review.failed;
  return <FocusSheet title={sheetTitle(c, mode)} scrollKey={mode} onClose={() => c.go(null)} onBack={mode === "timeedit" ? () => c.go("times") : undefined}>
    {c.loadError && <div className="mb-4 rounded-xl border border-hairline p-3" role="alert"><p className="text-[13px] text-danger">{c.loadError}</p><FBtn className="mt-2" onClick={() => void c.reload()}>Retry loading Focus</FBtn></div>}
    {c.mutationError && !inlineReviewError && mode !== "after" && <p role="alert" className="mb-3 text-[13px] text-danger">{c.mutationError}</p>}
    {mode === "choose" && <ChooseView c={c} />}
    {mode === "setup" && <SetupView c={c} />}
    {mode === "session" && <SessionView c={c} />}
    {mode === "review" && <ReviewView c={c} />}
    {mode === "after" && <AfterView c={c} />}
    {mode === "occ" && <OccurrenceView c={c} />}
    {mode === "plan" && <PlanView c={c} />}
    {mode === "times" && <TimesView c={c} />}
    {mode === "timeedit" && <TimeEditView c={c} />}
  </FocusSheet>;
}

/**
 * Mount once per page that shows Focus. `reminders` are the open/snoozed reminders the chooser can offer
 * (the Settings page passes none; it only needs the Focus times sheet).
 */
export function FocusProvider({ reminders, onOpenReminder, children }: { reminders: HomeReminder[]; onOpenReminder?: (reminder: HomeReminder) => void; children: ReactNode }) {
  const c = useFocusController({ reminders, onOpenReminder });
  return <FocusContext.Provider value={c}>
    {children}
    <div className="sr-only" role="status" aria-live="polite">{c.announcement}</div>
    {c.mode && <FocusSheetHost c={c} mode={c.mode} />}
  </FocusContext.Provider>;
}

/** Today's focus card, missed recovery and Your focus times; `activeOnly` shows just a running session (other tabs). */
export function FocusCard({ activeOnly = false }: { activeOnly?: boolean }) {
  const c = useContext(FocusContext);
  return c ? <TodayFocus c={c} activeOnly={activeOnly} /> : null;
}

/** Settings -> Focus -> Focus times. */
export function FocusSettingsSection() {
  const c = useContext(FocusContext);
  return c ? <FocusTimesSettingsRow c={c} /> : null;
}

/** Reminder sheet row: Focus on this / Work on this (Work and Side Gig only). */
export function FocusEntry({ reminder, onOpen }: { reminder: HomeReminder; onOpen?: () => void }) {
  const c = useContext(FocusContext);
  if (!c || !isFocusEligible(reminder)) return null;
  const planned = c.hasTimes ? c.plannedFor(reminder.id) : null;
  return <div className="mt-4 border-t border-hairline pt-3">
    <p className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-text-2">Focus</p>
    <div className="flex flex-wrap gap-2">
      <FBtn grow onClick={() => { onOpen?.(); c.open(reminder); }}><Target className="size-4" aria-hidden />Focus on this</FBtn>
      {c.hasTimes && <FBtn grow onClick={() => { onOpen?.(); c.openPlan(subjectOfReminder(reminder)); }}>Work on this</FBtn>}
    </div>
    {c.hasTimes && <p className="mt-2 text-[12px] text-text-2">{planned ? `Planned: ${whenLabel(planned.local_date, planned.start_time)} · ${planned.planned_minutes} min` : "Not planned yet"}</p>}
  </div>;
}
