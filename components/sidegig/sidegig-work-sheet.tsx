"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { FocusSheet } from "@/components/focus/focus-sheet";
import type { HomeContext } from "@/components/home/types";
import { createClient } from "@/lib/supabase/client";
import { gigDate, type GigItem, type GigKind, type GigPayload } from "@/lib/sidegig";
import { GigForm } from "./gig-form";

/**
 * The canonical Side Gig create/edit form and its atomic save. A retry reuses
 * the same record ID and, for unchanged answers, the same operation ID.
 */
export function SideGigSaveForm({ item, kind, initial, contexts, contextId, zone, onContextChange, onDirty, onPendingChange, onSaved }: {
  item?: GigItem;
  kind: GigKind;
  initial: GigPayload;
  contexts?: HomeContext[];
  contextId?: string;
  zone: string;
  onContextChange?: (id: string, draft: GigPayload) => void;
  onDirty: () => void;
  onPendingChange?: (pending: boolean) => void;
  onSaved: (result: { id: string; kind: GigKind; isOrder: boolean }) => void;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [id] = useState(() => item?.id ?? crypto.randomUUID());
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const operation = useRef<{ payload: string; id: string } | null>(null);
  const locked = useRef(false);
  const action = kind === "work" || kind === "order" ? "save_work" : `save_${kind}`;
  useEffect(() => { onPendingChange?.(pending); }, [pending, onPendingChange]);

  async function save(_: string, payload: GigPayload) {
    if (locked.current) return;
    locked.current = true;
    setPending(true);
    setError(null);
    const key = JSON.stringify(payload);
    if (operation.current?.payload !== key) operation.current = { payload: key, id: crypto.randomUUID() };
    try {
      const result = await supabase.rpc("sidegig_mutate", { p_operation_id: operation.current.id, p_action: action, p_id: id, p_data: payload });
      if (result.error) throw result.error;
      const isOrder = payload.is_order === true;
      onSaved({ id, kind: action === "save_work" ? (isOrder ? "order" : "work") : kind, isOrder });
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : typeof cause === "object" && cause && "message" in cause ? String(cause.message) : "Could not save. Your draft is still here. Try again.");
    } finally {
      locked.current = false;
      setPending(false);
    }
  }

  return <GigForm modal={{ type: "form", kind: item?.kind ?? kind, action, seed: { ...initial, id } }} item={item} zone={zone} today={gigDate(new Date().toISOString(), zone)} items={[]} busy={pending} error={error} onDirty={onDirty} onSave={(record, payload) => void save(record, payload)} contexts={item ? undefined : contexts} contextId={contextId} onContextChange={onContextChange ? (next, draft) => { if (!pending) onContextChange(next, { ...initial, ...draft }); } : undefined} />;
}

/** Full Side Gig task/order creation and editing in its own sheet. */
export function SideGigWorkSheet({ initial, contexts, contextId, zone, initiallyDirty, onContextChange, onClose, onSaved, item }: {
  item?: GigItem;
  initial: GigPayload;
  contexts: HomeContext[];
  contextId: string;
  zone: string;
  initiallyDirty: boolean;
  onContextChange?: (id: string, draft: GigPayload) => void;
  onClose: () => void;
  onSaved?: (result: { isOrder: boolean }) => void;
}) {
  const [dirty, setDirty] = useState(initiallyDirty);
  const [discard, setDiscard] = useState(false);
  const [pending, setPending] = useState(false);

  return <FocusSheet title={item ? "Edit details" : initial.is_order ? "New order" : "New task"} onClose={onClose} canClose={() => {
    if (pending) return false;
    if (dirty) { setDiscard(true); return false; }
    return true;
  }}>
    <SideGigSaveForm item={item} kind={item?.kind ?? (initial.is_order ? "order" : "work")} initial={initial} contexts={contexts} contextId={contextId} zone={zone} onContextChange={onContextChange} onDirty={() => setDirty(true)} onPendingChange={setPending} onSaved={({ isOrder }) => {
      setDirty(false);
      toast.success("Saved to Side Gig");
      onSaved?.({ isOrder });
      onClose();
    }} />
    {discard && <div className="mt-4 rounded-xl border border-hairline p-3" role="alert">
      <p className="text-[14px] font-semibold">Discard these changes?</p>
      <div className="mt-3 flex gap-2">
        <button className="min-h-11 rounded-xl bg-foreground px-3 text-[14px] font-semibold text-background" onClick={() => setDiscard(false)}>Keep editing</button>
        <button className="min-h-11 rounded-xl border border-hairline px-3 text-[14px] font-semibold" onClick={onClose}>Discard</button>
      </div>
    </div>}
  </FocusSheet>;
}
