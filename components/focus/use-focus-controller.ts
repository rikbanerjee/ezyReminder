"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { completeReminder, reopenReminder } from "@/app/actions";
import type { HomeReminder } from "@/components/home/types";
import { getFocusTimer } from "@/lib/focus";
import { fetchFocusNextStep, focusError } from "@/lib/focus-client";
import {
  groupOccurrences, minutesDraft, missedNextTarget, missedTasks, monthIsPast, oneOffTarget, parseMinutes, planOptions, selectCard,
  shortDate, splitOccurrences, stepMonth, timeInput, validateTimeDraft, whenLabel, type Occurrence, type PlanTarget,
} from "@/lib/focus-plan";
import type { FocusAssignment, FocusContextSlug, FocusOutcome, FocusTime } from "@/lib/supabase/types";
import { useFocusDashboard } from "./use-focus-dashboard";

export type Mode = "choose" | "setup" | "session" | "review" | "after" | "occ" | "plan" | "times" | "timeedit";

/** What a sheet needs to know about a reminder, whether it came from the list or from a planned task. */
export type FocusSubject = { id: string; title: string; slug: FocusContextSlug; dueAt: string | null; shipBy: string | null; isOrder: boolean };
export type SetupDraft = { subject: FocusSubject; assignmentId: string | null; mins: string; custom: string; intended: string; tried: boolean };
export type ReviewDraft = { outcome: FocusOutcome | null; next: string; tried: boolean; failed: boolean };
export type PlanDraft = {
  subject: FocusSubject; sel: string | null; mins: string; custom: string; pickOpen: boolean;
  otherDate: string | null; otherTime: string; calY: number; calM: number; tried: boolean; pickError: string | null;
};
export type TimeDraft = {
  id: string; isNew: boolean; enabled: boolean; label: string; days: number[]; time: string; mins: string; custom: string;
  ctx: FocusContextSlug | null; timeOpen: boolean; err: { days?: string; mins?: string; ctx?: string };
};
export type SavedSession = { reminderId: string | null; title: string; slug: FocusContextSlug; outcome: FocusOutcome; mins: number; next: string };

export const isFocusEligible = (reminder: HomeReminder) => ["open", "snoozed"].includes(reminder.status) && ["work", "sidegig"].includes(reminder.context?.slug ?? "");
export const subjectOfReminder = (reminder: HomeReminder): FocusSubject => ({
  id: reminder.id, title: reminder.title, slug: (reminder.context?.slug ?? "work") as FocusContextSlug,
  dueAt: reminder.due_at, shipBy: reminder.order?.shipBy ?? null, isOrder: reminder.is_order,
});
const subjectOfTask = (task: FocusAssignment, reminders: HomeReminder[]): FocusSubject => ({
  id: task.reminder_id!, title: task.reminder_title, slug: task.context_slug, dueAt: task.due_at, shipBy: task.ship_by,
  isOrder: reminders.find((reminder) => reminder.id === task.reminder_id)?.is_order ?? task.ship_by !== null,
});
const SETUP_PRESETS = ["10", "25", "50"];

/**
 * All Focus state and actions. It lives in the provider, above every sheet, so Realtime/RSC refreshes
 * replace `data` but never reset a draft the person is typing into.
 */
export function useFocusController({ reminders, onOpenReminder }: { reminders: HomeReminder[]; onOpenReminder?: (reminder: HomeReminder) => void }) {
  const dash = useFocusDashboard();
  const { supabase, data, loading, loadError, reload, clock } = dash;

  const [mode, setModeState] = useState<Mode | null>(null);
  const [busy, setBusy] = useState(false);
  const [mutationError, setMutationError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [setup, setSetup] = useState<SetupDraft | null>(null);
  const [review, setReview] = useState<ReviewDraft>({ outcome: null, next: "", tried: false, failed: false });
  const [plan, setPlan] = useState<PlanDraft | null>(null);
  const [timeEdit, setTimeEdit] = useState<TimeDraft | null>(null);
  const [occKey, setOccKey] = useState<string | null>(null);
  const [saved, setSaved] = useState<SavedSession | null>(null);
  const [announcement, setAnnouncement] = useState("");
  const modeRef = useRef<Mode | null>(null);
  const lock = useRef(false);
  const intents = useRef(new Map<string, string>());
  const lastSessionId = useRef<string | null>(null);
  // Last saved next step per reminder, loaded only for what is on screen.
  const [nextSteps, setNextSteps] = useState<Record<string, string | null>>({});
  const [nextStepErrors, setNextStepErrors] = useState<Record<string, string>>({});
  const fetching = useRef(new Set<string>());

  // ----- derived -----
  const tz = data?.timezone ?? "UTC";
  const session = data?.active_session ?? null;
  const timer = session ? getFocusTimer(session, clock) : null;
  const hasTimes = data?.api.times ?? false;
  const hasPrefs = data?.api.preferences ?? false;
  const prefMinutes = data?.preferred_minutes ?? 25;
  const times = useMemo(() => data?.focus_times ?? [], [data]);
  const assignments = useMemo(() => data?.assignments ?? [], [data]);
  const occurrences = useMemo(() => groupOccurrences(assignments, times, tz), [assignments, times, tz]);
  const { upcoming, missed } = splitOccurrences(occurrences, clock, tz);
  const missedList = missedTasks(missed);
  const candidates = useMemo(() => reminders.filter(isFocusEligible), [reminders]);
  const highlight = data?.highlight ?? null;
  const highlightReminder = candidates.find((reminder) => reminder.id === highlight?.reminder_id) ?? null;
  const cardKind = selectCard({ timer: timer?.state ?? null, highlightReady: !!highlightReminder, hasUpcoming: upcoming.length > 0 });
  const nextUp = upcoming[0]?.tasks[0] ?? null;
  const reminderById = (id: string | null) => (id ? reminders.find((reminder) => reminder.id === id) ?? null : null);
  const plannedFor = (reminderId: string) => assignments.find((task) => task.state === "planned" && task.reminder_id === reminderId) ?? null;
  const occurrence = occKey ? occurrences.find((value) => value.key === occKey) ?? null : null;

  // ----- helpers -----
  const go = useCallback((next: Mode | null) => { modeRef.current = next; setMutationError(null); setModeState(next); }, []);
  const announce = useCallback((message: string) => { setAnnouncement(""); setTimeout(() => setAnnouncement(message), 50); }, []);
  const notify = useCallback((message: string, action?: { label: string; onClick: () => void }) => {
    toast(message, { position: modeRef.current ? "top-center" : "bottom-center", action });
  }, []);
  /** Same intent -> same operation id across retries; a changed intent gets a new one. Cleared on success. */
  const intentId = (key: string) => {
    let id = intents.current.get(key);
    if (!id) { id = crypto.randomUUID(); intents.current.set(key, id); }
    return id;
  };

  async function mutate(action: () => PromiseLike<{ error: unknown }>, onSuccess?: (fresh: NonNullable<typeof data>) => void, onError?: (error: unknown) => void) {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setMutationError(null);
    try {
      const { error } = await action();
      if (error) throw error;
      const fresh = await reload();
      if (!fresh) setMutationError("Your change may have saved. Retry loading Focus before trying again.");
      else onSuccess?.(fresh);
    } catch (error) {
      const message = focusError(error);
      setMutationError(message);
      if (!modeRef.current) toast.error(message);
      onError?.(error);
      // Concurrent clients can make an expected-updated-at stale. Recover the latest state.
      await reload();
    } finally { lock.current = false; setBusy(false); }
  }

  // ----- effects -----
  useEffect(() => {
    if (!data) return;
    const sessionId = data.active_session?.id ?? null;
    const reset = sessionId !== lastSessionId.current;
    lastSessionId.current = sessionId;
    // A session boundary may have changed any reminder's note; the dashboard re-seeds the two it knows.
    setNextSteps((previous) => {
      const next = reset ? {} : { ...previous };
      if (data.api.preferences) {
        if (data.highlight?.reminder_id) next[data.highlight.reminder_id] = data.highlight_next_step;
        if (data.active_session?.reminder_id) next[data.active_session.reminder_id] = data.session_next_step;
      }
      return next;
    });
  }, [data]);
  const sessionId = session?.id ?? null;
  useEffect(() => { setReview({ outcome: null, next: "", tried: false, failed: false }); }, [sessionId]);
  useEffect(() => {
    // A session ended on another client; don't leave a stale review form open.
    if (data && !session && (mode === "session" || mode === "review")) go(null);
  }, [data, session, mode, go]);
  const timerState = timer?.state;
  useEffect(() => { if (timerState === "awaiting_finish") announce("Time is up. How did it go?"); }, [timerState, announce]);

  const wanted = [
    cardKind === "highlight" ? highlightReminder?.id : null,
    cardKind === "upnext" ? nextUp?.reminder_id : null,
    session?.reminder_id,
    mode === "setup" ? setup?.subject.id : null,
    ...(mode === "occ" ? occurrence?.tasks.map((task) => task.reminder_id) ?? [] : []),
  ].filter((id): id is string => !!id && !(id in nextSteps) && !(id in nextStepErrors));
  const wantedKey = [...new Set(wanted)].join(",");
  useEffect(() => {
    for (const id of wantedKey ? wantedKey.split(",") : []) {
      if (fetching.current.has(id)) continue;
      fetching.current.add(id);
      fetchFocusNextStep(supabase, id)
        .then((value) => setNextSteps((previous) => ({ ...previous, [id]: value })))
        .catch((error) => setNextStepErrors((previous) => ({ ...previous, [id]: focusError(error) })))
        .finally(() => fetching.current.delete(id));
    }
  }, [wantedKey, supabase]);
  const nextStepOf = (id: string | null) => (id ? nextSteps[id] ?? null : null);
  const retryNextStep = (id: string) => setNextStepErrors((previous) => Object.fromEntries(Object.entries(previous).filter(([key]) => key !== id)));

  // ----- starting -----
  function startFree(subject: FocusSubject, minutes: number, intended: string | null, after?: () => PromiseLike<unknown>) {
    const key = `free|${subject.id}|${minutes}|${intended ?? ""}`;
    void mutate(async () => {
      const result = await supabase.rpc("start_focus_session", { p_id: intentId(key), p_reminder_id: subject.id, p_duration_minutes: minutes, p_intended_outcome: intended });
      if (!result.error) await after?.();
      return result;
    }, (fresh) => { intents.current.delete(key); announce(`Focus started, ${minutes} minutes`); if (fresh.active_session) go("session"); });
  }
  function startPlanned(task: FocusAssignment, minutes: number, after?: () => PromiseLike<unknown>) {
    const key = `assigned|${task.id}|${minutes}`;
    void mutate(async () => {
      const result = await supabase.rpc("start_assigned_focus", { p_session_id: intentId(key), p_assignment_id: task.id, p_duration_minutes: minutes });
      if (!result.error) await after?.();
      return result;
    }, (fresh) => { intents.current.delete(key); announce(`Focus started, ${minutes} minutes`); if (fresh.active_session) go("session"); });
  }
  const savePreference = (minutes: number) => async () => {
    if (hasPrefs && minutes !== prefMinutes) await supabase.rpc("save_focus_preferences", { p_preferred_minutes: minutes }).then(() => undefined, () => undefined);
  };

  function openSession() { go(timer?.state === "awaiting_finish" ? "review" : "session"); }
  function openChoose() { setQuery(""); go("choose"); }
  function openSetup(subject: FocusSubject, task?: FocusAssignment | null) {
    if (session) { openSession(); return; }
    const assignmentId = task?.id ?? null;
    const same = setup && setup.subject.id === subject.id && setup.assignmentId === assignmentId;
    setSetup(same ? setup : { subject, assignmentId, ...minutesDraft(task?.planned_minutes ?? prefMinutes, SETUP_PRESETS), intended: "", tried: false });
    go("setup");
  }
  /** Reminder sheet's "Focus on this": a custom reminder opens Setup; none opens the chooser. */
  function open(reminder?: HomeReminder) {
    if (session) { openSession(); return; }
    if (reminder && isFocusEligible(reminder)) openSetup(subjectOfReminder(reminder)); else openChoose();
  }
  function startHighlight() { if (highlightReminder) startFree(subjectOfReminder(highlightReminder), prefMinutes, null); }
  function startUpNext() { if (nextUp) startPlanned(nextUp, nextUp.planned_minutes); }
  function submitSetup() {
    if (!setup) return;
    const minutes = parseMinutes(setup.mins, setup.custom);
    if (minutes === null) { setSetup({ ...setup, tried: true }); return; }
    const task = setup.assignmentId ? assignments.find((value) => value.id === setup.assignmentId) : undefined;
    if (setup.assignmentId) startPlanned(task ?? ({ id: setup.assignmentId } as FocusAssignment), minutes, savePreference(minutes));
    else startFree(setup.subject, minutes, setup.intended.trim() || null, savePreference(minutes));
  }
  function setHighlight(reminderId: string) {
    void mutate(() => supabase.rpc("set_focus_highlight", { p_reminder_id: reminderId }), () => { go(null); notify("Today's focus set"); announce("Today's focus set"); });
  }

  // ----- session -----
  function toggleSession() {
    if (!session) return;
    const paused = timer?.state === "paused";
    void mutate(() => supabase.rpc(paused ? "resume_focus_session" : "pause_focus_session", { p_id: session.id, p_expected_updated_at: session.updated_at }),
      () => announce(paused ? "Session resumed" : "Session paused"));
  }
  function saveReview() {
    if (!session) return;
    if (!review.outcome) { setReview({ ...review, tried: true }); return; }
    const outcome = review.outcome;
    const next = review.next.trim();
    const snapshot: SavedSession = {
      reminderId: session.reminder_id, title: session.reminder_title, slug: session.context_slug, outcome, next,
      mins: Math.max(1, Math.round((timer?.elapsedSeconds ?? 0) / 60)),
    };
    setReview({ ...review, failed: false });
    void mutate(() => supabase.rpc("finish_focus_session", { p_id: session.id, p_expected_updated_at: session.updated_at, p_outcome: outcome, p_next_step: next || null }),
      () => { setSaved(snapshot); go("after"); announce("Session saved"); notify("Session saved"); },
      () => setReview((value) => ({ ...value, failed: true })));
  }
  function continueForTen() {
    const id = saved?.reminderId;
    if (id) startFree({ id, title: saved.title, slug: saved.slug, dueAt: null, shipBy: null, isOrder: false }, 10, saved.next || null);
  }
  async function markDone() {
    const id = saved?.reminderId;
    if (!id || lock.current) return;
    lock.current = true;
    setBusy(true);
    try {
      const result = await completeReminder(id);
      if (!result.ok) { setMutationError(result.error); return; }
      go(null);
      notify("Reminder marked done", { label: "Undo", onClick: () => { void reopenReminder(id); } });
    } catch (error) { setMutationError(focusError(error)); }
    finally { lock.current = false; setBusy(false); }
  }
  function markShipped() {
    const reminder = reminderById(saved?.reminderId ?? null);
    go(null);
    if (reminder) onOpenReminder?.(reminder);
  }

  // ----- planning -----
  function skip(task: FocusAssignment, message: string, afterSuccess?: (fresh: NonNullable<typeof data>) => void) {
    void mutate(() => supabase.rpc("skip_focus_work", { p_id: task.id }), (fresh) => { notify(message); afterSuccess?.(fresh); });
  }
  function openOccurrence(key: string) { setOccKey(key); go("occ"); }
  function skipInOccurrence(task: FocusAssignment) {
    skip(task, "Skipped · your reminder is unchanged", (fresh) => {
      if (!groupOccurrences(fresh.assignments, fresh.focus_times, fresh.timezone).some((value) => value.key === occKey)) go(null);
    });
  }
  function openPlan(subject: FocusSubject) {
    const [y, m] = (data?.local_date ?? "1970-01-01").split("-").map(Number);
    setPlan({ subject, sel: null, mins: "15", custom: "", pickOpen: false, otherDate: null, otherTime: "18:30", calY: y, calM: m - 1, tried: false, pickError: null });
    go("plan");
  }
  const patchPlan = (patch: Partial<PlanDraft>) => setPlan((value) => (value ? { ...value, ...patch } : value));
  function stepCalendar(delta: number) {
    if (!plan || !data) return;
    const next = stepMonth(plan.calY, plan.calM, delta);
    if (!monthIsPast(next.year, next.month0, data.local_date)) patchPlan({ calY: next.year, calM: next.month0 });
  }
  const planChoices: PlanTarget[] = plan ? planOptions(times, plan.subject.slug, clock, tz) : [];
  const planTarget: PlanTarget | null = !plan ? null
    : plan.sel === "other" ? (plan.otherDate ? oneOffTarget(plan.otherDate, plan.otherTime, tz) : null)
    : planChoices.find((option) => option.key === plan.sel) ?? null;
  function confirmPickedDay() {
    if (!plan) return;
    if (!plan.otherDate) { patchPlan({ pickError: "Choose a day first." }); return; }
    if (oneOffTarget(plan.otherDate, plan.otherTime || "18:30", tz).startsAt.getTime() <= clock.getTime()) { patchPlan({ pickError: "Choose a time that hasn't passed yet." }); return; }
    patchPlan({ pickOpen: false, pickError: null });
  }
  function savePlan() {
    if (!plan) return;
    const current = plannedFor(plan.subject.id);
    if (plan.sel === "none") {
      if (!current) { go(null); return; }
      skip(current, "Left unscheduled", () => go(null));
      return;
    }
    const minutes = parseMinutes(plan.mins, plan.custom);
    if (!planTarget || minutes === null) { patchPlan({ tried: true }); return; }
    if (plan.sel === "other" && planTarget.startsAt.getTime() <= clock.getTime()) { patchPlan({ pickOpen: true, pickError: "Choose a time that hasn't passed yet." }); return; }
    const target = planTarget;
    const key = `plan|${plan.subject.id}|${target.key}|${minutes}`;
    void mutate(() => supabase.rpc("assign_focus_work", {
      p_id: intentId(key), p_reminder_id: plan.subject.id, p_focus_time_id: target.focusTimeId, p_local_date: target.localDate,
      p_start_time: target.startTime, p_planned_minutes: minutes,
    }), () => {
      intents.current.delete(key);
      go(null);
      notify(`Planned for ${whenLabel(target.localDate, target.startTime)}${current ? " (moved)" : ""}`);
      announce("Plan saved");
    });
  }
  function missedStart(task: FocusAssignment) { startPlanned(task, task.planned_minutes); }
  function missedNext(task: FocusAssignment) {
    if (!task.reminder_id) return;
    const target = missedNextTarget(task, times);
    const key = `next|${task.id}`;
    void mutate(() => supabase.rpc("assign_focus_work", {
      p_id: intentId(key), p_reminder_id: task.reminder_id!, p_focus_time_id: target.focusTimeId, p_local_date: target.localDate,
      p_start_time: target.startTime, p_planned_minutes: task.planned_minutes,
    }), () => { intents.current.delete(key); notify(`Planned for ${whenLabel(target.localDate, target.startTime)} (${shortDate(target.localDate)})`); });
  }
  function missedOther(task: FocusAssignment) { if (task.reminder_id) openPlan(subjectOfTask(task, reminders)); }
  function leaveUnscheduled(task: FocusAssignment) { skip(task, "Left unscheduled"); }

  // ----- focus times -----
  function openTimes() { go("times"); }
  function editTime(time: FocusTime | null) {
    setTimeEdit(time ? {
      id: time.id, isNew: false, enabled: time.enabled, label: time.label ?? "", days: [...time.weekdays].sort((a, b) => a - b),
      time: timeInput(time.start_time), ...minutesDraft(time.budget_minutes, ["15", "30", "60"]), ctx: time.context_slug, timeOpen: false, err: {},
    } : { id: crypto.randomUUID(), isNew: true, enabled: true, label: "", days: [], time: "09:00", mins: "30", custom: "", ctx: null, timeOpen: false, err: {} });
    go("timeedit");
  }
  const patchTime = (patch: Partial<TimeDraft>) => setTimeEdit((value) => (value ? { ...value, ...patch } : value));
  function saveTime() {
    if (!timeEdit) return;
    const err = validateTimeDraft(timeEdit);
    const minutes = parseMinutes(timeEdit.mins, timeEdit.custom);
    if (Object.keys(err).length || minutes === null || !timeEdit.ctx) { patchTime({ err }); return; }
    const draft = timeEdit;
    void mutate(() => supabase.rpc("save_focus_time", {
      p_id: draft.id, p_label: draft.label.trim() || null, p_context_slug: draft.ctx!, p_weekdays: [...draft.days].sort((a, b) => a - b),
      p_start_time: `${draft.time}:00`, p_budget_minutes: minutes, p_enabled: draft.enabled,
    }), () => { go("times"); notify("Focus time saved"); announce("Focus time saved"); });
  }
  function archiveTime() {
    if (!timeEdit || timeEdit.isNew) return;
    const draft = timeEdit;
    const original = times.find((time) => time.id === draft.id);
    void mutate(() => supabase.rpc("archive_focus_time", { p_id: draft.id }), () => {
      go("times");
      // There is no unarchive RPC: Undo restores the time as a fresh one with the same settings.
      notify("Focus time archived · planned work stays", original ? {
        label: "Undo",
        onClick: () => void mutate(() => supabase.rpc("save_focus_time", {
          p_id: crypto.randomUUID(), p_label: original.label, p_context_slug: original.context_slug, p_weekdays: original.weekdays,
          p_start_time: original.start_time, p_budget_minutes: original.budget_minutes, p_enabled: original.enabled,
        }), () => notify("Focus time restored")),
      } : undefined);
    });
  }

  return {
    // data
    supabase, data, loading, loadError, reload, clock, tz, session, timer, hasTimes, hasPrefs, prefMinutes, times, assignments,
    occurrences, upcoming, missed, missedList, candidates, highlight, highlightReminder, cardKind, nextUp, occurrence,
    reminderById, plannedFor, subjectOfTask: (task: FocusAssignment) => subjectOfTask(task, reminders), nextStepOf, nextStepError: (id: string | null) => (id ? nextStepErrors[id] ?? null : null), retryNextStep,
    // sheet state
    mode, go, busy, mutationError, announcement, query, setQuery, setup, setSetup, review, setReview, plan, patchPlan, planChoices, planTarget,
    timeEdit, patchTime, saved,
    // actions
    open, openSession, openChoose, openSetup, startHighlight, startUpNext, submitSetup, setHighlight, toggleSession, saveReview, continueForTen,
    markDone, markShipped, openOccurrence, skipInOccurrence, startPlanned, openPlan, stepCalendar, confirmPickedDay, savePlan, missedStart,
    missedNext, missedOther, leaveUnscheduled, openTimes, editTime, saveTime, archiveTime, notify,
  };
}

export type FocusController = ReturnType<typeof useFocusController>;
export type { Occurrence };
