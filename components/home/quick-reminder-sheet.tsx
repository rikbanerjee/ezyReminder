"use client";

import { useRef, useState, useTransition } from "react";
import { toast } from "sonner";
import { createReminder } from "@/app/actions";
import { FocusSheet } from "@/components/focus/focus-sheet";
import { useFocus } from "@/components/focus/focus-provider";
import { focusOccurrenceStart } from "@/lib/focus";
import { DateTimePicker } from "./date-time-picker";
import type { HomeContext, HomeReminder } from "./types";

/** Capture stays small for every context. Extra details belong to editing. */
export function QuickReminderSheet({ contexts, initialTitle = "", onClose, onCreated }: {
  contexts: HomeContext[];
  initialTitle?: string;
  onClose: () => void;
  onCreated: (reminder: HomeReminder) => void;
}) {
  const focus = useFocus();
  const zone = focus?.tz ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [title, setTitle] = useState(initialTitle);
  const [contextId, setContextId] = useState("");
  const [when, setWhen] = useState("");
  const [attempted, setAttempted] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [discard, setDiscard] = useState(false);
  const [pending, startTransition] = useTransition();
  const locked = useRef(false);
  const dirty = !!(title || contextId || when);
  const input = "mt-1.5 min-h-11 w-full rounded-xl border border-hairline bg-background px-3 py-2.5 text-[15px] font-normal";

  function save() {
    setAttempted(true);
    if (locked.current || !title.trim() || !contextId) return;
    locked.current = true;
    setError(null);
    startTransition(async () => {
      try {
        const context = contexts.find(c => c.id === contextId)!;
        const dueAt = when ? focusOccurrenceStart(when.slice(0, 10), when.slice(11, 16), zone).toISOString() : null;
        const result = await createReminder({ title: title.trim(), contextId, dueAt, notes: null, channels: [], isOrder: false, order: null });
        if (!result.ok) throw Error(result.error);
        toast.success("Reminder saved");
        onCreated({ id: result.id, title: title.trim(), context, due_at: dueAt, notes: null, channels: [], status: "open", snoozed_until: null, is_order: false, order: null, workDetails: null, sidegigDetails: null, shoppingItems: [], failedNotificationId: null });
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : "Could not save. Your reminder is still here. Try again.");
      } finally {
        locked.current = false;
      }
    });
  }

  return <FocusSheet title="New reminder" onClose={onClose} canClose={() => {
    if (pending) return false;
    if (dirty) { setDiscard(true); return false; }
    return true;
  }}>
    <form onSubmit={e => { e.preventDefault(); save(); }}>
      <fieldset disabled={pending}>
      <label className="mt-4 block text-[13px] font-semibold">What do you need to remember?
        <input data-sheet-autofocus value={title} onChange={e => setTitle(e.target.value)} maxLength={180} placeholder="A reminder…" className={input} aria-invalid={attempted && !title.trim()} />
      </label>
      {attempted && !title.trim() && <p className="mt-1 text-[12px] text-danger">Title required</p>}
      <label className="mt-4 block text-[13px] font-semibold">Context
        <select value={contextId} onChange={e => setContextId(e.target.value)} className={input} aria-invalid={attempted && !contextId}>
          <option value="" disabled>Choose a context</option>
          {contexts.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      </label>
      {attempted && !contextId && <p className="mt-1 text-[12px] text-danger">Choose a context</p>}
      <div className="mt-4"><p className="mb-1.5 text-[13px] font-semibold">When (optional)</p><DateTimePicker value={when} onChange={setWhen} /></div>
      {error && <p role="alert" className="mt-3 text-[13px] text-danger">{error}</p>}
      <button type="submit" disabled={pending} className="mt-5 min-h-11 w-full rounded-xl bg-foreground px-3 py-2.5 text-[14px] font-semibold text-background">{pending ? "Saving…" : "Save reminder"}</button>
      </fieldset>
    </form>
    {discard && <div role="alert" className="mt-4 rounded-xl border border-hairline p-3"><p className="text-[14px] font-semibold">Discard this reminder?</p><div className="mt-3 flex gap-3"><button className="min-h-11 text-[14px] font-semibold" onClick={() => setDiscard(false)}>Keep editing</button><button className="min-h-11 text-[14px] text-danger" onClick={onClose}>Discard</button></div></div>}
  </FocusSheet>;
}
