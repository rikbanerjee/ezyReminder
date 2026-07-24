"use client";

import { useEffect, useRef } from "react";
import { Plus } from "lucide-react";

/**
 * A trigger bar, not a text field — clicking it (or arriving via the
 * share-target/"New reminder" shortcut hand-off) opens the reminder sheet
 * so the right fields (context, date, channels, order) get set explicitly
 * rather than parsed from typed text.
 */
export function QuickAdd({
  initialValue,
  autoFocus,
  onOpen,
}: {
  initialValue?: string;
  autoFocus?: boolean;
  onOpen: (initialTitle?: string) => void;
}) {
  const opened = useRef(false);

  useEffect(() => {
    if (autoFocus && !opened.current) {
      opened.current = true;
      onOpen(initialValue);
    }
  }, [autoFocus, initialValue, onOpen]);

  return (
    <button
      type="button"
      onClick={() => onOpen(initialValue)}
      className="flex h-11 w-full items-center gap-2 rounded-xl border border-hairline bg-surface px-3 text-left shadow-sm"
    >
      <Plus className="size-4 shrink-0 text-text-2" />
      <span className="truncate text-[15px] text-text-2">
        {initialValue || "Add a reminder…"}
      </span>
    </button>
  );
}
