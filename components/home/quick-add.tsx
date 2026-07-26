"use client";

import { useEffect, useRef } from "react";
import { Plus } from "lucide-react";

/**
 * Docked quick-add trigger (DESIGN.md §3/§5.1, revised 2026-07 per direct
 * feedback): tapping *anywhere* on the bar opens the full create sheet —
 * it's a trigger, not a text field. Shorthand/inline parsing was tried and
 * replaced; the full form (context, date/time, order/work/side-gig panels)
 * is the one creation path now.
 */
export function QuickAdd({
  initialValue,
  autoFocus,
  onOpenCreateSheet,
}: {
  initialValue?: string;
  autoFocus?: boolean;
  /** Opens the create sheet, optionally pre-filling the title (share-target hand-off). */
  onOpenCreateSheet: (initialTitle?: string) => void;
}) {
  const opened = useRef(false);

  // Share-target / "New reminder" shortcut hand-off (MOBILE.md Stage 1) —
  // arriving with a prefill opens the sheet immediately, pre-filled.
  useEffect(() => {
    if (autoFocus && !opened.current) {
      opened.current = true;
      onOpenCreateSheet(initialValue);
    }
  }, [autoFocus, initialValue, onOpenCreateSheet]);

  return (
    <button
      type="button"
      onClick={() => onOpenCreateSheet()}
      className="flex h-11 w-full items-center gap-2 rounded-2xl bg-surface px-3 text-left shadow-float"
    >
      <span className="grid size-6 shrink-0 place-items-center rounded-full text-work">
        <Plus className="size-4" strokeWidth={2.5} />
      </span>
      <span className="truncate text-[15px] text-text-2">
        {initialValue || "Remind me to…"}
      </span>
    </button>
  );
}
