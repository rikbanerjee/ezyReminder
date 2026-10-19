"use client";

import { Check, ChevronRight, Pause, Play, Truck } from "lucide-react";
import { deadlineFor, parseMinutes } from "@/lib/focus-plan";
import { Chip, Choice, CtxLine, ctxName, Dot, Err, FBtn, fInput, fTextarea, FocusBlock, Help, Inset, ListCard, Meta, Sub, Warn } from "./focus-ui";
import { subjectOfReminder, type FocusController, type FocusSubject } from "./use-focus-controller";
import { cn } from "@/lib/utils";

const OUTCOMES = [["finished", "Finished what I planned"], ["progress", "Made progress"], ["interrupted", "Got interrupted"]] as const;

export function DurChips({ values, selected, slug, label, onPick }: { values: string[]; selected: string; slug: string; label: string; onPick: (value: string) => void }) {
  return <div role="group" aria-label={label} className="flex flex-wrap gap-2">
    {values.map((value) => <Chip key={value} slug={slug} on={selected === value} onClick={() => onPick(value)}>{value === "custom" ? "Custom" : `${value} min`}</Chip>)}
  </div>;
}

/** Context, title and deadline of the reminder a sheet is about. */
export function ReminderBlock({ c, subject, extra }: { c: FocusController; subject: FocusSubject; extra?: React.ReactNode }) {
  const due = deadlineFor(subject, c.tz);
  return <div>
    <CtxLine slug={subject.slug}>{ctxName(subject.slug)}{subject.isOrder && <span className="inline-flex items-center gap-1"> · <Truck className="size-3.5" aria-hidden />Order</span>}</CtxLine>
    <p className="mt-1.5 break-words text-[17px] font-semibold">{subject.title}</p>
    {due && <Meta>{due.text}</Meta>}
    {extra}
  </div>;
}

export function ChooseView({ c }: { c: FocusController }) {
  const q = c.query.trim().toLocaleLowerCase();
  const rows = c.candidates.filter((reminder) => reminder.title.toLocaleLowerCase().includes(q));
  return <>
    <p className="mb-3 text-[14px] text-text-2">One reminder for today. Its deadline stays the same.</p>
    <input aria-label="Search Work and Side Gig reminders" placeholder="Search reminders…" value={c.query} onChange={(event) => c.setQuery(event.target.value)} className={fInput} />
    <ListCard className="mt-3">
      {rows.map((reminder) => <button key={reminder.id} type="button" disabled={c.busy || !!c.loadError || !!c.session} onClick={() => c.setHighlight(reminder.id)}
        className="flex min-h-[52px] w-full items-center gap-3 px-3.5 py-3 text-left focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-work disabled:opacity-50">
        <Dot slug={reminder.context!.slug} />
        <span className="min-w-0 flex-1 break-words text-[15px] font-medium">{reminder.title}<span className="mt-0.5 block text-[12px] font-normal text-text-2">{reminder.context!.name}</span></span>
        <ChevronRight className="size-4 shrink-0 text-text-2" aria-hidden />
      </button>)}
      {rows.length === 0 && <p className="p-4 text-[14px] text-text-2">{c.candidates.length ? "No matching reminders." : "Add a Work or Side Gig reminder to choose your focus."}</p>}
    </ListCard>
    {c.session && <FBtn block className="mt-3" onClick={c.openSession}>Open current session</FBtn>}
  </>;
}

export function SetupView({ c }: { c: FocusController }) {
  const d = c.setup;
  if (!d) return null;
  const minutes = parseMinutes(d.mins, d.custom);
  const bad = d.tried && minutes === null;
  const note = c.nextStepOf(d.subject.id);
  const noteError = c.nextStepError(d.subject.id);
  const patch = (value: Partial<typeof d>) => c.setSetup({ ...d, ...value, tried: false });
  return <>
    <ReminderBlock c={c} subject={d.subject} />
    {note && <Inset label="Next step from last time">{note}</Inset>}
    {noteError && <div className="mt-2.5"><Err>Couldn&apos;t load your last next step. {noteError}</Err><FBtn variant="ghost" onClick={() => c.retryNextStep(d.subject.id)}>Retry next step</FBtn></div>}
    <Sub id="focus-how-long">How long?</Sub>
    <DurChips values={["10", "25", "50", "custom"]} selected={d.mins} slug={d.subject.slug} label="How long?" onPick={(mins) => patch({ mins })} />
    {d.mins === "custom" && <>
      <Sub htmlFor="focus-custom">Minutes (1–180)</Sub>
      <input id="focus-custom" type="number" min={1} max={180} step={1} inputMode="numeric" value={d.custom} aria-invalid={bad} onChange={(event) => patch({ custom: event.target.value })} className={fInput} />
    </>}
    {bad && <Err>Choose a whole number from 1 to 180 minutes.</Err>}
    {c.hasPrefs && minutes !== null && minutes !== c.prefMinutes && <Help className="mt-2">Starting with {minutes} min saves it as your usual length.</Help>}
    {(!d.assignmentId || c.hasIntents) && <>
      <Sub htmlFor="focus-intended" optional>What could you finish in 10–15 minutes?</Sub>
      <textarea id="focus-intended" rows={2} maxLength={500} value={d.intended} onChange={(event) => patch({ intended: event.target.value })} placeholder="A small, clear outcome…" className={fTextarea} />
    </>}
    <FBtn variant="primary" block className="mt-4" disabled={c.busy || c.loading || !!c.loadError} onClick={c.submitSetup}>{c.busy ? "Starting…" : "Start now"}</FBtn>
  </>;
}

export function SessionView({ c }: { c: FocusController }) {
  const { session: s, timer } = c;
  if (!s) return <Meta>No session in progress.</Meta>;
  const state = timer?.state;
  const aim = s.intended_outcome ? ["Your focus", s.intended_outcome] : c.nextStepOf(s.reminder_id) ? ["Next step", c.nextStepOf(s.reminder_id)!] : null;
  const line = state === "awaiting_finish" ? "Time is up. Ready to review?" : state === "paused" ? "Paused" : "One thing at a time.";
  const seconds = timer?.remainingSeconds ?? 0;
  return <>
    <CtxLine slug={s.context_slug} />
    <p className="mt-1.5 break-words text-[22px] font-bold tracking-[-0.2px]">{s.reminder_title}</p>
    {aim && <FocusBlock slug={s.context_slug} label={aim[0]}>{aim[1]}</FocusBlock>}
    <p role="timer" aria-label="Focus time remaining" className={cn("mt-[22px] text-center text-[56px] font-light leading-[1.1] tracking-[1px] tabular-nums text-text-2", state === "awaiting_finish" && "font-semibold text-foreground", state === "paused" && "opacity-55")}>
      {`${Math.floor(seconds / 60).toString().padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`}
    </p>
    <p className="mb-[18px] mt-1 text-center text-[14px] text-text-2">{line}</p>
    <div className="flex flex-wrap gap-2">
      {state === "awaiting_finish"
        ? <FBtn variant="primary" grow onClick={() => c.go("review")}>Review session</FBtn>
        : <>
          <FBtn variant="primary" grow disabled={c.busy || !!c.loadError} onClick={c.toggleSession}>{state === "paused" ? <Play className="size-4" aria-hidden /> : <Pause className="size-4" aria-hidden />}{state === "paused" ? "Resume" : "Pause"}</FBtn>
          <FBtn grow onClick={() => c.go("review")}>End session</FBtn>
        </>}
    </div>
  </>;
}

export function ReviewView({ c }: { c: FocusController }) {
  const { session: s, timer, review: d } = c;
  if (!s) return null;
  const mins = Math.max(1, Math.round((timer?.elapsedSeconds ?? 0) / 60));
  return <>
    <CtxLine slug={s.context_slug}>{ctxName(s.context_slug)} · {mins} min</CtxLine>
    <p className="mt-1.5 break-words text-[17px] font-semibold">{s.reminder_title}</p>
    <div role="radiogroup" aria-label="How did this session go?" className="mt-3">
      {OUTCOMES.map(([value, label]) => <Choice key={value} on={d.outcome === value} slug={s.context_slug} onClick={() => c.setReview({ ...d, outcome: value, tried: false })}>{label}</Choice>)}
    </div>
    {d.tried && !d.outcome && <Err>Choose how the session went.</Err>}
    <label htmlFor="focus-next-step" className="mb-1.5 mt-5 block text-[17px] font-semibold">Where will you start next time?</label>
    <textarea id="focus-next-step" rows={3} maxLength={1000} value={d.next} onChange={(event) => c.setReview({ ...d, next: event.target.value })} placeholder="A small, clear next action…" className={fTextarea} />
    <Help>Optional. It appears on your card when you come back.</Help>
    {d.failed && <Warn title="Couldn't save your session" actions={<FBtn variant="primary" disabled={c.busy} onClick={c.saveReview}>Retry</FBtn>}>Your answers are still here.</Warn>}
    <Help className="mt-3">This saves your session. Your reminder stays as it is.</Help>
    <FBtn variant="primary" block className="mt-3" disabled={c.busy || !!c.loadError} onClick={c.saveReview}>{c.busy ? "Saving…" : "Save session"}</FBtn>
    {timer?.state !== "awaiting_finish" && <FBtn variant="ghost" block className="mt-1" onClick={() => c.go("session")}>Back to session</FBtn>}
  </>;
}

/** After saving: continue / another focus time / done, plus a separate, explicit "Mark reminder done". */
export function AfterView({ c }: { c: FocusController }) {
  const l = c.saved;
  if (!l) return null;
  const reminder = c.reminderById(l.reminderId);
  const startable = !!reminder && c.candidates.some((value) => value.id === reminder.id);
  const label = OUTCOMES.find(([value]) => value === l.outcome)![1];
  return <>
    <div className="mx-auto mb-2 mt-1.5 grid size-14 place-items-center rounded-full text-social" style={{ backgroundColor: "color-mix(in srgb, var(--social) 16%, var(--surface))" }}><Check className="size-7" aria-hidden /></div>
    <div className="text-center"><p className="break-words text-[17px] font-semibold">{l.title}</p><Meta>{label} · {l.mins} min</Meta></div>
    {l.next && <Inset label="Next time">{l.next}</Inset>}
    {c.mutationError && <Err>{c.mutationError}</Err>}
    <div className="mt-4 flex flex-col gap-2">
      {startable && <FBtn variant="primary" block disabled={c.busy || !!c.session} onClick={c.continueForTen}>{c.busy ? "Starting…" : "Continue for 10 min"}</FBtn>}
      {startable && c.hasTimes && c.times.length > 0 && <FBtn block onClick={() => reminder && c.openPlan(subjectOfReminder(reminder))}>Choose another focus time</FBtn>}
      <FBtn variant={startable ? "ghost" : "primary"} block onClick={() => c.go(null)}>I&apos;m done for now</FBtn>
    </div>
    {l.outcome === "finished" && reminder && <div className="mt-[18px] border-t border-hairline pt-3.5">
      <Help className="mb-2.5 mt-0">Your reminder is still open. Finishing it is a separate step.</Help>
      {reminder.is_order
        ? <FBtn block onClick={c.markShipped}>Mark shipped</FBtn>
        : <FBtn block disabled={c.busy} onClick={() => void c.markDone()}>Mark reminder done</FBtn>}
    </div>}
  </>;
}
