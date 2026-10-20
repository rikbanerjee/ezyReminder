"use client";

import { Clock, ChevronRight, ChevronUp } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import {
  clock12, daysLabel, deadlineFor, monthGrid, monthLabel, othersInTarget, overBudget, parseMinutes, shortDate, startsAfterDeadline, whenLabel,
} from "@/lib/focus-plan";
import { Chip, Choice, ChoiceText, CtxLine, ctxName, Err, FBtn, fInput, Help, Inset, ListCard, ListRow, Meta, Sub, Warn } from "./focus-ui";
import { DurChips, ReminderBlock } from "./focus-session-sheets";
import type { FocusController } from "./use-focus-controller";
import { cn } from "@/lib/utils";

/** Ordered tasks of one occurrence, a Start per task and Skip. Nothing starts on its own. */
export function OccurrenceView({ c }: { c: FocusController }) {
  const o = c.occurrence;
  if (!o) return <Meta>Nothing planned here.</Meta>;
  const running = !!c.session;
  return <>
    <CtxLine slug={o.slug}>{ctxName(o.slug)} · {shortDate(o.localDate)}{o.label ? ` · ${o.label}` : ""}</CtxLine>
    <Meta>{o.tasks.length} task{o.tasks.length > 1 ? "s" : ""} · {o.plannedMinutes} min planned</Meta>
    {overBudget(o) && <Meta>{o.plannedMinutes} min planned for {o.budgetMinutes} min available</Meta>}
    <ol aria-label="Planned tasks in order" className="mt-3.5 divide-y divide-hairline overflow-hidden rounded-xl border border-hairline">
      {o.tasks.map((task, index) => {
        const due = deadlineFor({ dueAt: task.due_at, shipBy: task.ship_by }, c.tz);
        const note = c.nextStepOf(task.reminder_id);
        return <li key={task.id} className="px-3.5 py-3">
          <div className="flex items-start gap-2 text-[16px] font-semibold">
            <span aria-hidden className="mt-px grid size-[22px] shrink-0 place-items-center rounded-full bg-background text-[12px] font-bold text-text-2">{index + 1}</span>
            <span className="min-w-0 break-words">{task.reminder_title}</span>
          </div>
          <div className="ml-[30px] mt-0.5 break-words text-[13px] text-text-2">{task.planned_minutes} min{due ? ` · ${due.text}` : ""}</div>
          {note && <div className="ml-[30px] mt-0.5 break-words text-[13px] text-text-2">Next: {note}</div>}
          <div className="ml-[30px] mt-2 flex flex-wrap gap-2">
            <FBtn variant="primary" disabled={running || c.busy} onClick={() => c.startPlanned(task, task.planned_minutes)}>Start {task.planned_minutes} min</FBtn>
            <FBtn variant="ghost" disabled={c.busy} onClick={() => c.skipInOccurrence(task)}>Skip</FBtn>
          </div>
        </li>;
      })}
    </ol>
    {running
      ? <Help className="mt-2">A session is already in progress. <button type="button" className="underline underline-offset-2" onClick={c.openSession}>Open it</button> before starting another.</Help>
      : <Help className="mt-2">Skip leaves the reminder as it is. Nothing starts on its own.</Help>}
  </>;
}

function DayPicker({ c }: { c: FocusController }) {
  const d = c.plan!;
  const grid = monthGrid(d.calY, d.calM);
  const today = c.data?.local_date ?? "";
  return <div role="group" aria-label="Pick another day" className="mt-2 rounded-[14px] bg-background px-3 pb-3 pt-2.5">
    <div className="flex items-center justify-between">
      <button type="button" aria-label="Previous month" onClick={() => c.stepCalendar(-1)} className="size-11 rounded-xl text-[22px] focus-visible:outline-2 focus-visible:outline-work">‹</button>
      <b className="text-[15px]">{monthLabel(d.calY, d.calM)}</b>
      <button type="button" aria-label="Next month" onClick={() => c.stepCalendar(1)} className="size-11 rounded-xl text-[22px] focus-visible:outline-2 focus-visible:outline-work">›</button>
    </div>
    <div className="grid grid-cols-7 gap-0.5">
      {["S", "M", "T", "W", "T", "F", "S"].map((letter, index) => <span key={index} aria-hidden className="py-1 text-center text-[11px] font-semibold text-text-2">{letter}</span>)}
      {Array.from({ length: grid.offset }, (_, index) => <span key={`gap-${index}`} />)}
      {grid.days.map((day) => {
        const on = d.otherDate === day.localDate;
        return <button key={day.localDate} type="button" disabled={day.localDate < today} aria-pressed={on} aria-label={`${monthLabel(d.calY, d.calM).split(" ")[0]} ${day.n}`}
          onClick={() => c.patchPlan({ otherDate: day.localDate, pickError: null })}
          className={cn("min-h-11 rounded-xl text-[14px] focus-visible:outline-2 focus-visible:outline-work disabled:opacity-30", on && "bg-foreground font-bold text-background")}>{day.n}</button>;
      })}
    </div>
    <div className="my-2.5 flex items-center gap-2.5 text-[13px] font-semibold text-text-2">
      <label htmlFor="focus-pick-time">Time</label>
      <input id="focus-pick-time" type="time" value={d.otherTime} onChange={(event) => c.patchPlan({ otherTime: event.target.value, pickError: null })} className={cn(fInput, "flex-1")} />
    </div>
    {d.pickError && <Err>{d.pickError}</Err>}
    <FBtn variant="primary" block onClick={c.confirmPickedDay}>OK</FBtn>
  </div>;
}

/** "Work on this": plan a reminder into a Focus time (or a one-off day). */
export function PlanView({ c }: { c: FocusController }) {
  const d = c.plan;
  if (!d) return null;
  const { subject } = d;
  const slug = subject.slug;
  const current = c.plannedFor(subject.id);
  const target = c.planTarget;
  const minutes = parseMinutes(d.mins, d.custom);
  const deadline = deadlineFor(subject, c.tz);
  const warn = !!target && startsAfterDeadline(target.startsAt, deadline);
  const otherDay = d.otherDate && !d.pickOpen ? `${shortDate(d.otherDate)} · ${clock12(d.otherTime)}` : "Choose a date and time";

  let summary = null;
  if (target?.focusTimeId) {
    const others = othersInTarget(c.assignments, target, subject.id);
    const used = others.reduce((sum, task) => sum + task.planned_minutes, 0) + (minutes ?? 0);
    summary = <Meta className="mt-2">
      {others.length > 0 && <>Also planned here: {others.map((task) => `${task.reminder_title} · ${task.planned_minutes} min`).join(", ")}.<br /></>}
      {others.length + 1} task{others.length ? "s" : ""} · {used} min planned{used > target.budgetMinutes ? ` — ${used} min planned for ${target.budgetMinutes} min available` : ""}
    </Meta>;
  }
  const saveLabel = c.busy ? "Saving…" : "Save plan";
  return <>
    <ReminderBlock c={c} subject={subject} />
    {current && <Inset label="Currently planned">{whenLabel(current.local_date, current.start_time)} · {current.planned_minutes} min. Choosing another time moves it.</Inset>}
    <Sub id="focus-when">When</Sub>
    <div role="radiogroup" aria-labelledby="focus-when">
      {c.planChoices.map((option) => <Choice key={option.key} on={d.sel === option.key} slug={slug} onClick={() => c.patchPlan({ sel: option.key, pickOpen: false })}>
        <ChoiceText title={whenLabel(option.localDate, option.startTime)} sub={`${shortDate(option.localDate)}${option.label ? ` · ${option.label}` : ""}`} />
      </Choice>)}
      <Choice on={d.sel === "other"} slug={slug} aria-expanded={d.sel === "other" && d.pickOpen} onClick={() => c.patchPlan({ sel: "other", pickOpen: d.sel === "other" ? !d.pickOpen : true, pickError: null })}>
        <ChoiceText title="Pick another day" sub={otherDay} />
        {d.pickOpen && d.sel === "other" ? <ChevronUp className="ml-auto size-4 text-text-2" aria-hidden /> : <ChevronRight className="ml-auto size-4 text-text-2" aria-hidden />}
      </Choice>
      {d.sel === "other" && d.pickOpen && <DayPicker c={c} />}
      <Choice on={d.sel === "none"} slug={slug} onClick={() => c.patchPlan({ sel: "none", pickOpen: false })}><ChoiceText title="Keep unscheduled" sub="No focus time for now" /></Choice>
    </div>
    {c.planChoices.length === 0 && <Help className="mt-2">You haven&apos;t set up a {ctxName(slug)} focus time yet. <button type="button" className="underline underline-offset-2" onClick={c.openTimes}>Set my focus times</button></Help>}
    {target && <>
      <Sub>Planned minutes</Sub>
      <DurChips values={["10", "15", "25", "custom"]} selected={d.mins} slug={slug} label="Planned minutes" onPick={(mins) => c.patchPlan({ mins, tried: false })} />
      {d.mins === "custom" && <input type="number" min={1} max={180} step={1} inputMode="numeric" aria-label="Planned minutes, 1 to 180" value={d.custom} aria-invalid={d.tried && minutes === null}
        onChange={(event) => c.patchPlan({ custom: event.target.value, tried: false })} className={cn(fInput, "mt-2")} />}
      {d.tried && minutes === null && <Err>Choose a whole number from 1 to 180 minutes.</Err>}
      {summary}
    </>}
    {warn && deadline
      ? <Warn title={`This is after the ${deadline.kind === "ship" ? "ship-by" : "due"} time`}
        actions={<>
          <FBtn onClick={() => { c.patchPlan({ sel: null, pickOpen: false }); document.getElementById("focus-sheet")?.scrollTo({ top: 0 }); }}>Choose an earlier time</FBtn>
          <FBtn variant="primary" disabled={c.busy} onClick={c.savePlan}>{c.busy ? "Saving…" : "Plan it anyway"}</FBtn>
        </>}>{deadline.text}. Your deadline stays the same.</Warn>
      : <>
        {d.tried && !target && d.sel !== "none" && <Err>{d.sel === "other" ? "Choose a day and time, then tap OK." : "Choose when you'd like to work on this."}</Err>}
        <FBtn variant="primary" block className="mt-4" disabled={c.busy} onClick={c.savePlan}>{saveLabel}</FBtn>
      </>}
  </>;
}

function TimezoneNote({ c, prefix }: { c: FocusController; prefix: string }) {
  const router = useRouter();
  const pathname = usePathname();
  return <p className="mt-1.5 text-[12px] text-text-2">{prefix} {c.tz}. <button type="button" className="underline underline-offset-2" onClick={() => { if (pathname === "/settings") c.go(null); else router.push("/settings"); }}>Change in Settings</button></p>;
}

export function TimesView({ c }: { c: FocusController }) {
  return <>
    {c.times.length > 0
      ? <ListCard className="mt-1.5">{c.times.map((time) => <ListRow key={time.id} compact slug={time.context_slug} onClick={() => c.editTime(time)}
        title={time.label || daysLabel(time.weekdays)} sub={`${daysLabel(time.weekdays)} · ${clock12(time.start_time)} · ${time.budget_minutes} min`} />)}</ListCard>
      : <p className="mt-1.5 text-[14px] text-text-2">Pick the weekly times you can focus, then plan reminders into them. Nothing starts on its own.</p>}
    <TimezoneNote c={c} prefix="Times use your account timezone," />
    <FBtn variant="primary" block className="mt-4" onClick={() => c.editTime(null)}>Add a focus time</FBtn>
  </>;
}

const WEEKDAYS = [[1, "Mon", "Monday"], [2, "Tue", "Tuesday"], [3, "Wed", "Wednesday"], [4, "Thu", "Thursday"], [5, "Fri", "Friday"], [6, "Sat", "Saturday"], [7, "Sun", "Sunday"]] as const;

export function TimeEditView({ c }: { c: FocusController }) {
  const d = c.timeEdit;
  if (!d) return null;
  const tint = d.ctx ?? "work";
  const clear = (key: keyof typeof d.err) => ({ ...d.err, [key]: undefined });
  return <>
    <Sub htmlFor="focus-time-label" optional>Name</Sub>
    <input id="focus-time-label" maxLength={40} value={d.label} placeholder="e.g. Shop time" onChange={(event) => c.patchTime({ label: event.target.value })} className={fInput} />
    <Sub id="focus-days">Days</Sub>
    <div role="group" aria-labelledby="focus-days" className="grid grid-cols-[repeat(auto-fit,minmax(44px,1fr))] gap-1.5">
      {WEEKDAYS.map(([n, short, full]) => <Chip key={n} slug={tint} on={d.days.includes(n)} aria-label={full} className="rounded-xl px-0"
        onClick={() => c.patchTime({ days: d.days.includes(n) ? d.days.filter((day) => day !== n) : [...d.days, n], err: clear("days") })}>{short}</Chip>)}
    </div>
    {d.err.days && <Err>{d.err.days}</Err>}
    <Sub>Time</Sub>
    <Chip aria-pressed={undefined} aria-expanded={d.timeOpen} onClick={() => c.patchTime({ timeOpen: !d.timeOpen })}><Clock className="size-3.5" aria-hidden />{clock12(d.time)}</Chip>
    {d.timeOpen && <div className="mt-2 rounded-[14px] bg-background px-3 pb-3 pt-2.5">
      <div className="mb-3 flex items-center gap-2.5 text-[13px] font-semibold text-text-2">
        <label htmlFor="focus-time-start">Start time</label>
        <input id="focus-time-start" type="time" value={d.time} onChange={(event) => event.target.value && c.patchTime({ time: event.target.value })} className={cn(fInput, "flex-1")} />
      </div>
      <FBtn variant="primary" block onClick={() => c.patchTime({ timeOpen: false })}>OK</FBtn>
    </div>}
    <TimezoneNote c={c} prefix="Account timezone:" />
    <Sub id="focus-have">I usually have</Sub>
    <DurChips values={["15", "30", "60", "custom"]} selected={d.mins} slug={tint} label="I usually have" onPick={(mins) => c.patchTime({ mins, err: clear("mins") })} />
    {d.mins === "custom" && <input type="number" min={1} max={180} step={1} inputMode="numeric" aria-label="Minutes available, 1 to 180" value={d.custom} aria-invalid={!!d.err.mins}
      onChange={(event) => c.patchTime({ custom: event.target.value, err: clear("mins") })} className={cn(fInput, "mt-2")} />}
    {d.err.mins && <Err>{d.err.mins}</Err>}
    <Sub id="focus-for">For</Sub>
    <div role="radiogroup" aria-labelledby="focus-for" className="flex gap-2">
      {(["work", "sidegig"] as const).map((slug) => <Chip key={slug} slug={slug} on={d.ctx === slug} role="radio" aria-pressed={undefined} aria-checked={d.ctx === slug} className="flex-1 rounded-xl"
        onClick={() => c.patchTime({ ctx: slug, err: clear("ctx") })}><span aria-hidden className="size-2 rounded-full" style={{ backgroundColor: `var(--${slug})` }} />{ctxName(slug)}</Chip>)}
    </div>
    {d.err.ctx && <Err>{d.err.ctx}</Err>}
    <Help>Changes apply to future choices. Work you&apos;ve already planned keeps its time.</Help>
    <FBtn variant="primary" block className="mt-4" disabled={c.busy} onClick={c.saveTime}>{c.busy ? "Saving…" : "Save focus time"}</FBtn>
    {!d.isNew && <FBtn variant="ghost" danger block className="mt-1" disabled={c.busy} onClick={c.archiveTime}>Archive</FBtn>}
  </>;
}
