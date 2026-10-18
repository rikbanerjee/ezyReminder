"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Target, Pause, Play, ChevronRight } from "lucide-react";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import type { FocusState } from "@/lib/supabase/types";
import { focusLocalDate, getFocusTimer } from "@/lib/focus";
import { fetchFocusNextStep, fetchFocusState, focusError } from "@/lib/focus-client";
import type { HomeReminder } from "@/components/home/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { FocusSheet } from "./focus-sheet";

type Mode = "choose" | "setup" | "session" | "review";
type Outcome = "finished" | "progress" | "interrupted";
const FocusContext = createContext<{ open: (reminder?: HomeReminder) => void; card: ReactNode; hasSession: boolean } | null>(null);
const touch = "min-h-11";
const eligible = (reminder: HomeReminder) => ["open", "snoozed"].includes(reminder.status) && ["work", "sidegig"].includes(reminder.context?.slug ?? "");
const contextName = (slug: string) => slug === "work" ? "Work" : "Side Gig";
const contextColor = (slug: string) => slug === "sidegig" ? "var(--sidegig)" : "var(--work)";
function timeLabel(seconds: number) { return `${Math.floor(seconds / 60).toString().padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`; }

/** State lives above both sheets so Realtime/RSC refreshes never reset an in-progress draft. */
export function FocusProvider({ reminders, children }: { reminders: HomeReminder[]; children: ReactNode }) {
  const supabase = useMemo(() => createClient(), []);
  const [state, setState] = useState<FocusState | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [mutationError, setMutationError] = useState<string | null>(null);
  const [mode, setMode] = useState<Mode | null>(null);
  const [chosen, setChosen] = useState<HomeReminder | null>(null);
  const [duration, setDuration] = useState("25");
  const [custom, setCustom] = useState("25");
  const [intended, setIntended] = useState("");
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [outcomeAttempted, setOutcomeAttempted] = useState(false);
  const [nextStep, setNextStep] = useState("");
  const [previousNextStep, setPreviousNextStep] = useState<string | null>(null);
  const [nextStepError, setNextStepError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [now, setNow] = useState(Date.now());
  const offset = useRef(0);
  const requestId = useRef(0);
  const startId = useRef<string | null>(null);
  const lastActiveId = useRef<string | null>(null);
  const mounted = useRef(true);
  const mutationLock = useRef(false);

  const reload = useCallback(async () => {
    const id = ++requestId.current;
    try {
      const fresh = await fetchFocusState(supabase);
      if (!mounted.current || id !== requestId.current) return null;
      offset.current = new Date(fresh.server_now).getTime() - Date.now();
      setState(fresh);
      setLoadError(null);
      setNow(Date.now());
      return fresh;
    } catch (error) {
      if (mounted.current && id === requestId.current) setLoadError(focusError(error));
      return null;
    } finally {
      if (mounted.current && id === requestId.current) setLoading(false);
    }
  }, [supabase]);

  useEffect(() => {
    mounted.current = true;
    void reload();
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let refreshTimer: ReturnType<typeof setTimeout> | null = null;
    let userId: string | null = null;
    const refresh = () => {
      if (refreshTimer) clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => { void reload(); }, 120);
    };
    const subscribe = (id: string | null) => {
      if (id === userId) return;
      userId = id;
      if (channel) void supabase.removeChannel(channel);
      if (!id) { setState(null); return; }
      channel = supabase.channel(`focus-${id}`)
        .on("postgres_changes", { event: "*", schema: "public", table: "focus_highlights", filter: `user_id=eq.${id}` }, refresh)
        .on("postgres_changes", { event: "*", schema: "public", table: "focus_sessions", filter: `user_id=eq.${id}` }, refresh)
        .on("postgres_changes", { event: "*", schema: "public", table: "user_settings", filter: `user_id=eq.${id}` }, refresh)
        .subscribe((status) => { if (status === "SUBSCRIBED") refresh(); });
    };
    const auth = supabase.auth.onAuthStateChange((_event, session) => { subscribe(session?.user.id ?? null); refresh(); });
    void supabase.auth.getSession().then(({ data }) => { if (mounted.current) subscribe(data.session?.user.id ?? null); });
    const visible = () => { if (document.visibilityState === "visible") refresh(); };
    window.addEventListener("focus", refresh);
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", visible);
    return () => {
      mounted.current = false;
      auth.data.subscription.unsubscribe();
      if (channel) void supabase.removeChannel(channel);
      if (refreshTimer) clearTimeout(refreshTimer);
      window.removeEventListener("focus", refresh);
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [reload, supabase]);

  const session = state?.active_session ?? null;
  const sessionId = session?.id ?? null;
  const hasSession = session !== null;
  const timer = session ? getFocusTimer(session, new Date(now + offset.current)) : null;
  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), hasSession ? 1000 : 30000);
    return () => clearInterval(interval);
  }, [sessionId, hasSession]);
  useEffect(() => {
    if (state && focusLocalDate(new Date(now + offset.current), state.timezone) !== state.local_date) void reload();
  }, [now, state, reload]);
  useEffect(() => {
    if (sessionId !== lastActiveId.current) {
      lastActiveId.current = sessionId;
      setOutcome(null);
      setOutcomeAttempted(false);
      setNextStep("");
    }
    // A session ended on another client; don't leave a stale review form open.
    if (state && !hasSession && (mode === "session" || mode === "review")) setMode(null);
  }, [sessionId, hasSession, state, mode]);

  const loadNextStep = useCallback(async (id: string) => {
    setNextStepError(null);
    try { setPreviousNextStep(await fetchFocusNextStep(supabase, id)); }
    catch (error) { setNextStepError(focusError(error)); }
  }, [supabase]);
  useEffect(() => {
    if (!chosen) return;
    let cancelled = false;
    setPreviousNextStep(null);
    setNextStepError(null);
    void fetchFocusNextStep(supabase, chosen.id).then((value) => { if (!cancelled) setPreviousNextStep(value); })
      .catch((error) => { if (!cancelled) setNextStepError(focusError(error)); });
    return () => { cancelled = true; };
  }, [chosen, supabase]);

  function open(reminder?: HomeReminder) {
    setMutationError(null);
    if (session) { setMode(timer?.state === "awaiting_finish" ? "review" : "session"); return; }
    if (reminder && eligible(reminder)) {
      if (chosen?.id !== reminder.id) { setIntended(""); startId.current = null; }
      setChosen({ ...reminder });
      setMode("setup");
    } else { setQuery(""); setMode("choose"); }
  }

  async function mutate(action: () => PromiseLike<{ error: unknown }>, onSuccess?: (fresh: FocusState) => void) {
    if (mutationLock.current) return;
    mutationLock.current = true;
    setBusy(true);
    setMutationError(null);
    try {
      const { error } = await action();
      if (error) throw error;
      const fresh = await reload();
      if (!fresh) setMutationError("Your change may have saved. Retry loading Focus before trying again.");
      else onSuccess?.(fresh);
    } catch (error) {
      setMutationError(focusError(error));
      // Concurrent clients can make an expected-updated-at stale. Recover the latest session.
      await reload();
    } finally { mutationLock.current = false; setBusy(false); }
  }

  const candidates = reminders.filter(eligible);
  const highlighted = candidates.find((reminder) => reminder.id === state?.highlight?.reminder_id);
  const selectedColor = contextColor(session?.context_slug ?? chosen?.context?.slug ?? state?.highlight?.context_slug ?? "work");
  const minutes = Number(duration === "custom" ? custom : duration);
  const validDuration = Number.isInteger(minutes) && minutes >= 1 && minutes <= 180;
  const choiceList = candidates.filter((reminder) => reminder.title.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));

  const card = (
    <section aria-labelledby="today-focus-heading">
      <h2 id="today-focus-heading" className="px-1 pb-1.5 pt-1 text-[13px] font-semibold uppercase tracking-wide text-text-2">Today&apos;s focus</h2>
      <div className="rounded-xl border border-hairline bg-surface p-3 shadow-card">
        {loadError ? <div role="alert"><p className="text-[13px] text-danger">{loadError}</p><Button variant="outline" className={cn("mt-2", touch)} onClick={() => void reload()}>Retry loading Focus</Button></div>
          : loading ? <p className="py-2 text-[14px] text-text-2" role="status">Loading focus…</p>
          : session ? <>
            <p className="text-[12px] font-medium" style={{ color: contextColor(session.context_slug) }}>{contextName(session.context_slug)} · {timer?.state === "paused" ? "Paused" : timer?.state === "awaiting_finish" ? "Time is up" : "In focus"}</p>
            <p className="mt-1 break-words text-[17px] font-semibold">{session.reminder_title}</p>
            <div className="mt-2 flex items-center justify-between gap-2"><span className="text-[26px] font-semibold tabular-nums" role="timer" aria-label="Focus time remaining">{timeLabel(timer?.remainingSeconds ?? 0)}</span><Button variant="outline" className={touch} onClick={() => open()}>{timer?.state === "awaiting_finish" ? "Review session" : "Open session"}<ChevronRight className="size-4" /></Button></div>
          </> : state?.highlight ? <>
            <p className="text-[12px] font-medium" style={{ color: contextColor(state.highlight.context_slug) }}>{contextName(state.highlight.context_slug)}</p>
            <p className="mt-1 break-words text-[17px] font-semibold">{highlighted?.title ?? state.highlight.reminder_title}</p>
            {highlighted?.due_at && <p className="mt-1 text-[13px] text-text-2">Due {new Date(highlighted.due_at).toLocaleString(undefined, { timeZone: state.timezone, dateStyle: "medium", timeStyle: "short" })}</p>}
            {!highlighted && <p className="mt-1 text-[13px] text-text-2">This reminder is no longer available for focus. Choose another reminder.</p>}
            <div className="mt-2 flex flex-wrap gap-2"><Button className={touch} style={{ backgroundColor: `color-mix(in srgb, ${contextColor(state.highlight.context_slug)} 18%, var(--surface))`, color: "var(--foreground)" }} disabled={!highlighted} onClick={() => open(highlighted)}>Start focus</Button><Button variant="ghost" className={touch} onClick={() => { setQuery(""); setMode("choose"); }}>Change</Button></div>
          </> : <>
            <p className="text-[17px] font-semibold">What matters most today?</p>
            <p className="mt-1 text-[13px] text-text-2">Choose one Work or Side Gig reminder.</p>
            <Button variant="outline" className={cn("mt-2", touch)} onClick={() => { setQuery(""); setMode("choose"); }}><Target className="size-4" />Choose a reminder</Button>
          </>}
      </div>
    </section>
  );

  return <FocusContext.Provider value={{ open, card, hasSession }}>
    {children}
    {mode && <FocusSheet title={mode === "choose" ? "Today's focus" : mode === "setup" ? "Start focus" : mode === "review" ? "How did it go?" : "Focus session"} onClose={() => setMode(null)}>
      {loadError && <div className="mb-4 rounded-xl border border-hairline p-3" role="alert"><p className="text-[13px] text-danger">{loadError}</p><Button variant="outline" className={cn("mt-2", touch)} onClick={() => void reload()}>Retry loading Focus</Button></div>}
      {mutationError && <p role="alert" className="mb-3 text-[13px] text-danger">{mutationError}</p>}
      {mode === "choose" && <>
        <p className="mb-3 text-[14px] text-text-2">One reminder for today. Its deadline stays the same.</p>
        <Input aria-label="Search Work and Side Gig reminders" placeholder="Search reminders…" value={query} onChange={(event) => setQuery(event.target.value)} className={cn("mb-3", touch)} />
        <div className="divide-y divide-hairline rounded-xl border border-hairline">
          {choiceList.map((reminder) => <button key={reminder.id} type="button" disabled={busy || !!loadError || !!session} className="flex min-h-[52px] w-full items-center gap-3 px-3 py-3 text-left focus-visible:outline-2 focus-visible:outline-work disabled:opacity-50" onClick={() => void mutate(() => supabase.rpc("set_focus_highlight", { p_reminder_id: reminder.id }), () => setMode(null))}>
            <span className="size-2 shrink-0 rounded-full" style={{ backgroundColor: contextColor(reminder.context!.slug) }} /><span className="min-w-0 flex-1 break-words text-[15px] font-medium">{reminder.title}<span className="mt-0.5 block text-[12px] font-normal text-text-2">{reminder.context!.name}</span></span><ChevronRight className="size-4 shrink-0 text-text-2" />
          </button>)}
          {choiceList.length === 0 && <p className="p-4 text-[14px] text-text-2">{candidates.length ? "No matching reminders." : "Add a Work or Side Gig reminder to choose your focus."}</p>}
        </div>
        {session && <Button className={cn("mt-3", touch)} onClick={() => setMode("session")}>Open current session</Button>}
      </>}
      {mode === "setup" && chosen && <>
        <FocusTitle title={chosen.title} slug={chosen.context?.slug ?? "work"} />
        {previousNextStep && <div className="mb-4 rounded-xl bg-background p-3"><p className="text-[12px] font-semibold text-text-2">Last next step</p><p className="mt-1 whitespace-pre-wrap break-words text-[14px]">{previousNextStep}</p></div>}
        {nextStepError && <div className="mb-3"><p role="alert" className="text-[13px] text-danger">Couldn&apos;t load your last next step. {nextStepError}</p><Button variant="ghost" className={touch} onClick={() => void loadNextStep(chosen.id)}>Retry next step</Button></div>}
        <fieldset><legend className="mb-2 text-[13px] font-medium text-text-2">How long?</legend><div className="flex flex-wrap gap-2">{["10", "25", "50", "custom"].map((value) => <button key={value} type="button" aria-pressed={duration === value} onClick={() => { setDuration(value); startId.current = null; }} className={cn("min-h-11 rounded-full border px-3 text-[13px] font-semibold shadow-card focus-visible:outline-2 focus-visible:outline-work", duration === value ? "border-transparent text-foreground" : "border-hairline bg-surface text-text-2")} style={duration === value ? { backgroundColor: `color-mix(in srgb, ${selectedColor} 18%, var(--surface))` } : undefined}>{value === "custom" ? "Custom" : `${value} min`}</button>)}</div></fieldset>
        {duration === "custom" && <label className="mt-3 block text-[13px] text-text-2">Minutes (1–180)<Input type="number" min={1} max={180} step={1} inputMode="numeric" value={custom} onChange={(event) => { setCustom(event.target.value); startId.current = null; }} className={cn("mt-1", touch)} aria-invalid={!validDuration} /></label>}
        <label className="mt-4 block text-[13px] text-text-2">What would you like to get done? <span>(optional)</span><textarea maxLength={500} rows={2} value={intended} onChange={(event) => { setIntended(event.target.value); startId.current = null; }} className="mt-1 w-full resize-y rounded-xl border border-hairline bg-background p-3 text-[15px] text-foreground outline-work" placeholder="A small, clear outcome…" /></label>
        {!validDuration && <p role="alert" className="mt-1 text-[13px] text-danger">Choose a whole number from 1 to 180 minutes.</p>}
        <Button className={cn("mt-4 w-full", touch)} style={{ backgroundColor: `color-mix(in srgb, ${selectedColor} 18%, var(--surface))`, color: "var(--foreground)" }} disabled={busy || loading || !!loadError || !validDuration || !eligible(chosen)} onClick={() => {
          startId.current ??= crypto.randomUUID();
          void mutate(() => supabase.rpc("start_focus_session", { p_id: startId.current!, p_reminder_id: chosen.id, p_duration_minutes: minutes, p_intended_outcome: intended.trim() || null }), (fresh) => { if (fresh.active_session) { setMode("session"); startId.current = null; } });
        }}>{busy ? "Starting…" : "Start now"}</Button>
      </>}
      {(mode === "session" || mode === "review") && session && <>
        <FocusTitle title={session.reminder_title} slug={session.context_slug} />
        {session.intended_outcome && <p className="mb-4 whitespace-pre-wrap break-words text-[14px] text-text-2">{session.intended_outcome}</p>}
        <div className="text-center"><p className="text-[52px] font-semibold leading-tight tabular-nums" role="timer" aria-label="Focus time remaining">{timeLabel(timer?.remainingSeconds ?? 0)}</p><p className="mb-5 mt-1 text-[14px] text-text-2" aria-live="polite">{timer?.state === "awaiting_finish" ? "Time is up. Ready to review?" : timer?.state === "paused" ? "Paused" : "One thing at a time."}</p></div>
        {mode === "session" && <div className="flex flex-wrap gap-2">
          {timer?.state !== "awaiting_finish" && <Button variant="outline" className={cn("flex-1", touch)} disabled={busy || !!loadError} onClick={() => void mutate(() => supabase.rpc(timer?.state === "paused" ? "resume_focus_session" : "pause_focus_session", { p_id: session.id, p_expected_updated_at: session.updated_at }))}>{timer?.state === "paused" ? <Play className="size-4" /> : <Pause className="size-4" />}{timer?.state === "paused" ? "Resume" : "Pause"}</Button>}
          <Button className={cn("flex-1", touch)} style={{ backgroundColor: `color-mix(in srgb, ${selectedColor} 18%, var(--surface))`, color: "var(--foreground)" }} onClick={() => setMode("review")}>{timer?.state === "awaiting_finish" ? "Review session" : "End session"}</Button>
        </div>}
        {mode === "review" && <>
          <fieldset><legend className="mb-2 text-[13px] font-medium text-text-2">How did this session go?</legend><div className="flex flex-col gap-2">{([["finished", "Finished what I intended"], ["progress", "Made progress"], ["interrupted", "Got interrupted"]] as const).map(([value, label]) => <button key={value} type="button" aria-pressed={outcome === value} onClick={() => setOutcome(value)} className={cn("min-h-11 rounded-xl border px-3 py-2 text-left text-[14px] font-medium focus-visible:outline-2 focus-visible:outline-work", outcome === value ? "border-transparent text-foreground" : "border-hairline")} style={outcome === value ? { backgroundColor: `color-mix(in srgb, ${selectedColor} 18%, var(--surface))` } : undefined}>{label}</button>)}</div></fieldset>
          {outcomeAttempted && !outcome && <p role="alert" className="mt-2 text-[13px] text-danger">Choose how your session went.</p>}
          <label className="mt-4 block text-[13px] text-text-2">Next step <span>(optional)</span><textarea maxLength={1000} rows={2} value={nextStep} onChange={(event) => setNextStep(event.target.value)} className="mt-1 w-full resize-y rounded-xl border border-hairline bg-background p-3 text-[15px] text-foreground outline-work" placeholder="Where will you pick up next time?" /></label>
          <p className="mt-1 text-[12px] text-text-2">This saves your session. Your reminder stays as it is.</p>
          <Button className={cn("mt-4 w-full", touch)} style={{ backgroundColor: `color-mix(in srgb, ${selectedColor} 18%, var(--surface))`, color: "var(--foreground)" }} disabled={busy || !!loadError} onClick={() => { setOutcomeAttempted(true); if (!outcome) return; void mutate(() => supabase.rpc("finish_focus_session", { p_id: session.id, p_expected_updated_at: session.updated_at, p_outcome: outcome!, p_next_step: nextStep.trim() || null }), () => { setMode(null); toast.success("Focus session saved"); }); }}>{busy ? "Saving…" : "Save session"}</Button>
          {timer?.state !== "awaiting_finish" && <Button variant="ghost" className={cn("mt-1 w-full", touch)} onClick={() => setMode("session")}>Back to session</Button>}
        </>}
      </>}
    </FocusSheet>}
  </FocusContext.Provider>;
}

function FocusTitle({ title, slug }: { title: string; slug: string }) {
  return <div className="mb-4"><p className="text-[12px] font-semibold" style={{ color: contextColor(slug) }}>{contextName(slug)}</p><p className="mt-1 break-words text-[17px] font-semibold">{title}</p></div>;
}

export function FocusCard({ activeOnly = false }: { activeOnly?: boolean }) {
  const focus = useContext(FocusContext);
  return focus && (!activeOnly || focus.hasSession) ? focus.card : null;
}

export function FocusEntry({ reminder, onOpen }: { reminder: HomeReminder; onOpen?: () => void }) {
  const focus = useContext(FocusContext);
  if (!focus || !eligible(reminder)) return null;
  return <div className="mt-4 border-t border-hairline pt-3"><Button variant="outline" className={cn("w-full", touch)} onClick={() => { onOpen?.(); focus.open(reminder); }}><Target className="size-4" />Focus on this</Button></div>;
}
