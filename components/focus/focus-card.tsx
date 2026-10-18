"use client";

import { ChevronRight } from "lucide-react";
import { deadlineFor, monthDay, overBudget, shortDate, weekdayName, whenLabel, type Occurrence } from "@/lib/focus-plan";
import { CtxLine, ctxName, Dot, FBtn, Inset, ListCard, ListRow, Meta } from "./focus-ui";
import { subjectOfReminder, type FocusController } from "./use-focus-controller";

const heading = "px-1 pb-1.5 pt-1 text-[13px] font-semibold uppercase tracking-wide text-text-2";
const surface = "rounded-xl border border-hairline bg-surface p-3.5 leading-[1.2] shadow-card";
const timeLabel = (seconds: number) => `${Math.floor(seconds / 60).toString().padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`;

/** Today's focus card, missed recovery card and "Your focus times" (DESIGN.md §9). */
export function TodayFocus({ c, activeOnly }: { c: FocusController; activeOnly: boolean }) {
  if (activeOnly && !c.session) return null;
  const showMore = !activeOnly && !c.loading && !c.loadError;
  return <>
    <div className="flex flex-col gap-2.5">
      <section aria-labelledby="today-focus-heading">
        <h2 id="today-focus-heading" className={heading}>Today&apos;s focus</h2>
        <div className={surface} data-kind={c.cardKind}><CardBody c={c} /></div>
      </section>
      {showMore && c.missedList.length > 0 && <MissedCard c={c} />}
    </div>
    {showMore && c.hasTimes && <FocusTimesSection c={c} />}
  </>;
}

function StartRow({ c, minutes, onStart, onChange }: { c: FocusController; minutes: number; onStart: () => void; onChange: () => void }) {
  return <div className="mt-3 flex flex-wrap gap-2">
    <FBtn variant="primary" grow disabled={c.busy || !!c.loadError} onClick={onStart}>{c.busy ? "Starting…" : `Start ${minutes} min`}</FBtn>
    <FBtn variant="dur" onClick={onChange} aria-label={`Change length, currently ${minutes} minutes`}>{minutes} min</FBtn>
  </div>;
}

function CardBody({ c }: { c: FocusController }) {
  const { cardKind: kind, session, timer, tz } = c;
  if (c.loadError) return <div role="alert"><p className="text-[13px] text-danger">{c.loadError}</p><FBtn className="mt-2" onClick={() => void c.reload()}>Retry loading Focus</FBtn></div>;
  if (c.loading) return <p className="py-2 text-[14px] text-text-2" role="status">Loading focus…</p>;

  if (session && (kind === "running" || kind === "paused" || kind === "timeup")) {
    const label = kind === "paused" ? "Paused" : kind === "timeup" ? "Time is up" : "In focus";
    return <>
      <CtxLine slug={session.context_slug}>{ctxName(session.context_slug)} · {label}</CtxLine>
      <p className="mt-1.5 break-words text-[17px] font-semibold">{session.reminder_title}</p>
      {kind === "timeup" && <Meta>How did it go?</Meta>}
      <div className="mt-2 flex flex-wrap items-center justify-between gap-2.5">
        <span className={`text-[26px] font-semibold tabular-nums tracking-[.5px] ${kind === "paused" ? "text-text-2" : ""}`} role="timer" aria-label="Focus time remaining">{timeLabel(timer?.remainingSeconds ?? 0)}</span>
        <FBtn variant={kind === "timeup" ? "primary" : "outline"} onClick={c.openSession}>{kind === "timeup" ? "Review session" : "Open session"}</FBtn>
      </div>
    </>;
  }

  if (kind === "highlight" && c.highlightReminder) {
    const reminder = c.highlightReminder;
    const slug = reminder.context?.slug ?? "work";
    const due = deadlineFor({ dueAt: reminder.due_at, shipBy: reminder.order?.shipBy ?? null }, tz);
    const note = c.nextStepOf(reminder.id);
    return <>
      <div className="flex items-center justify-between gap-2">
        <CtxLine slug={slug} />
        <FBtn variant="ghost" className="-my-1.5 -mr-2.5" onClick={c.openChoose}>Change</FBtn>
      </div>
      <p className="mt-0.5 break-words text-[17px] font-semibold">{reminder.title}</p>
      {due && <Meta>{due.text}</Meta>}
      {note && <Inset label="Next step from last time">{note}</Inset>}
      <StartRow c={c} minutes={c.prefMinutes} onStart={c.startHighlight} onChange={() => c.openSetup(subjectOfReminder(reminder))} />
    </>;
  }

  if (kind === "upnext" && c.nextUp && c.upcoming[0]) {
    const task = c.nextUp;
    const occurrence = c.upcoming[0];
    const due = deadlineFor({ dueAt: task.due_at, shipBy: task.ship_by }, tz);
    const note = c.nextStepOf(task.reminder_id);
    return <>
      <CtxLine slug={task.context_slug}>Up next · {whenLabel(occurrence.localDate, occurrence.startTime)}</CtxLine>
      <p className="mt-1.5 break-words text-[17px] font-semibold">{task.reminder_title}</p>
      <Meta>{ctxName(task.context_slug)} · {task.planned_minutes} min planned · {shortDate(occurrence.localDate)}</Meta>
      {due && <Meta>{due.text}</Meta>}
      {note && <Inset label="Next step from last time">{note}</Inset>}
      <StartRow c={c} minutes={task.planned_minutes} onStart={c.startUpNext}
        onChange={() => c.openSetup(c.subjectOfTask(task), task)} />
      <FBtn variant="ghost" className="-ml-2.5 -mb-1.5 mt-0.5" disabled={c.busy || !task.reminder_id} onClick={() => task.reminder_id && c.setHighlight(task.reminder_id)}>Make today&apos;s focus</FBtn>
    </>;
  }

  return <>
    <p className="break-words text-[17px] font-semibold">What would you like to move forward?</p>
    <Meta>Choose one Work or Side Gig reminder.</Meta>
    <div className="mt-3 flex flex-wrap gap-2">
      <FBtn variant="primary" onClick={c.openChoose}>Choose a reminder</FBtn>
      {c.hasTimes && <FBtn variant="ghost" onClick={c.openTimes}>Set my focus times</FBtn>}
    </div>
  </>;
}

function MissedCard({ c }: { c: FocusController }) {
  const { task, occurrence } = c.missedList[0];
  const more = c.missedList.length - 1;
  const date = occurrence.localDate;
  const disabled = c.busy || !task.reminder_id;
  return <section aria-label="Missed focus time" className={surface}>
    <div className="flex items-baseline justify-between gap-2">
      <span className="text-[15px] font-semibold">Didn&apos;t get to this?</span>
      {more > 0 && <span className="text-[13px] font-semibold text-text-2">+{more} more</span>}
    </div>
    <p className="mt-1.5 break-words text-[17px] font-semibold">{task.reminder_title}</p>
    <Meta><Dot slug={task.context_slug} className="mr-1.5 align-middle" />{whenLabel(date, occurrence.startTime)} · {shortDate(date)} · {task.planned_minutes} min planned</Meta>
    <div className="mt-3 grid grid-cols-[repeat(auto-fit,minmax(140px,1fr))] gap-2">
      <FBtn variant="primary" disabled={disabled || !!c.session} onClick={() => c.missedStart(task)}>Start now</FBtn>
      <FBtn disabled={disabled} onClick={() => c.missedNext(task)}>Next {weekdayName(date)}</FBtn>
      <FBtn disabled={disabled} onClick={() => c.missedOther(task)}>Choose another time</FBtn>
      <FBtn variant="ghost" disabled={disabled} onClick={() => c.leaveUnscheduled(task)}>Leave unscheduled</FBtn>
    </div>
  </section>;
}

function OccurrenceRow({ occurrence, onOpen }: { occurrence: Occurrence; onOpen: () => void }) {
  const first = occurrence.tasks[0];
  return <ListRow slug={occurrence.slug} onClick={onOpen} title={whenLabel(occurrence.localDate, occurrence.startTime)} right={`${monthDay(occurrence.localDate)} ›`}
    sub={<><span className="block">{first.reminder_title} · {first.planned_minutes} min</span>
      {occurrence.tasks.length > 1 && <span className="block">{occurrence.tasks.length} tasks · {occurrence.plannedMinutes} min planned</span>}</>}
    hint={overBudget(occurrence) ? `${occurrence.plannedMinutes} min planned for ${occurrence.budgetMinutes} min available` : undefined} />;
}

/** Up to 3 populated occurrences. Empty occurrences are never listed. */
function FocusTimesSection({ c }: { c: FocusController }) {
  const hasTimes = c.times.length > 0;
  const rows = c.upcoming.slice(0, 3);
  if (!hasTimes && rows.length === 0 && c.cardKind === "empty") return null; // the empty card already offers "Set my focus times"
  return <section aria-labelledby="focus-times-heading">
    <div className="flex items-center justify-between">
      <h2 id="focus-times-heading" className={heading}>Your focus times</h2>
      {hasTimes && <button type="button" onClick={c.openTimes} className="-my-3 -mr-1 inline-flex min-h-11 items-center px-1 text-[13px] font-semibold text-text-2 focus-visible:outline-2 focus-visible:outline-work">Manage ›</button>}
    </div>
    {rows.length > 0 ? <ListCard className="shadow-card">{rows.map((occurrence) => <OccurrenceRow key={occurrence.key} occurrence={occurrence} onOpen={() => c.openOccurrence(occurrence.key)} />)}</ListCard>
      : <ListCard className="shadow-card"><button type="button" onClick={c.openTimes} className="flex min-h-11 w-full items-center justify-between px-3.5 py-3 text-left text-[15px] focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-work">
        <span>{hasTimes ? "Nothing planned yet" : "Set my focus times"}</span><span className="text-text-2">{hasTimes ? "Manage ›" : "›"}</span></button></ListCard>}
  </section>;
}

/** Settings -> Focus row. Hidden until the hosted database has Focus times. */
export function FocusTimesSettingsRow({ c }: { c: FocusController }) {
  if (!c.hasTimes) return null;
  const count = c.times.length;
  return <section className="rounded-xl border border-hairline bg-surface p-4">
    <h2 className="text-[15px] font-semibold">Focus</h2>
    <button type="button" onClick={c.openTimes} className="-mx-2 mt-1 flex min-h-11 w-[calc(100%+1rem)] items-center justify-between rounded-lg px-2 text-left text-[14px] focus-visible:outline-2 focus-visible:outline-work">
      <span>Focus times</span><span className="flex items-center gap-1 text-text-2">{count ? `${count} set up` : "None yet"}<ChevronRight className="size-4" /></span>
    </button>
  </section>;
}
