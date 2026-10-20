"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { GigDashboard } from "@/lib/sidegig";
import type { HomeContext } from "@/components/home/types";
import { FocusSheet } from "@/components/focus/focus-sheet";
import { useFocus } from "@/components/focus/focus-provider";
import { SideGigWorkSheet } from "./sidegig-work-sheet";

/** Opening Side Gig work from Today always loads the canonical editor. */
export function SideGigEditSheet({ reminderId, contexts, onClose }: { reminderId: string; contexts: HomeContext[]; onClose: () => void }) {
  const supabase = useMemo(() => createClient(), []);
  const focus = useFocus();
  const [dashboard, setDashboard] = useState<GigDashboard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    try {
      const result = await supabase.rpc("get_sidegig_dashboard");
      if (result.error) throw result.error;
      setDashboard(result.data);
      setError(null);
    } catch {
      setError("Could not load Side Gig details. Please try again.");
    }
  }, [supabase]);
  useEffect(() => { void load(); }, [load]);
  const item = dashboard?.items.find(r => r.reminder_id === reminderId && (r.kind === "work" || r.kind === "order"));
  if (!item) return <FocusSheet title="Side Gig details" onClose={onClose}>
    <p role={error ? "alert" : "status"} className="py-5 text-[14px] text-text-2">{error ?? (dashboard ? "This reminder is no longer available." : "Loading details…")}</p>
    {error && <button className="min-h-11 text-[14px] font-semibold" onClick={() => void load()}>Try again</button>}
  </FocusSheet>;
  return <SideGigWorkSheet item={item} initial={{}} contexts={contexts} contextId={contexts.find(c => c.slug === "sidegig")?.id ?? ""} zone={dashboard!.timezone} initiallyDirty={false} onClose={onClose} onSaved={() => { void focus?.reload(); }} />;
}
