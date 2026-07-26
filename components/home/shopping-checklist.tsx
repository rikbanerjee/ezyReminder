"use client";

import { useRef, useState } from "react";
import { Plus, X } from "lucide-react";
import { toast } from "sonner";
import { addShoppingItem, toggleShoppingItem, deleteShoppingItem } from "@/app/actions";
import type { HomeShoppingItem } from "./types";
import { cn } from "@/lib/utils";

/**
 * Shopping-context checklist (DESIGN.md §4.2.1) — always-focused "Add item…"
 * input, Enter appends optimistically; every check/delete is its own
 * instant write. No Save step.
 */
export function ShoppingChecklist({ reminderId, initialItems }: { reminderId: string; initialItems: HomeShoppingItem[] }) {
  const [items, setItems] = useState(initialItems);
  const [draft, setDraft] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  function addItem() {
    const label = draft.trim();
    if (!label) return;
    const tempId = `temp-${Date.now()}`;
    setItems((prev) => [...prev, { id: tempId, label, checked: false }]);
    setDraft("");
    inputRef.current?.focus();

    addShoppingItem(reminderId, label).then((res) => {
      if (!res.ok) {
        toast.error("Couldn't add item", { description: res.error });
        setItems((prev) => prev.filter((i) => i.id !== tempId));
        return;
      }
      setItems((prev) => prev.map((i) => (i.id === tempId ? { ...i, id: res.id } : i)));
    });
  }

  function toggle(item: HomeShoppingItem) {
    const nextChecked = !item.checked;
    setItems((prev) => prev.map((i) => (i.id === item.id ? { ...i, checked: nextChecked } : i)));
    toggleShoppingItem(item.id, nextChecked).then((res) => {
      if (!res.ok) {
        toast.error("Couldn't update item", { description: res.error });
        setItems((prev) => prev.map((i) => (i.id === item.id ? { ...i, checked: !nextChecked } : i)));
      }
    });
  }

  function remove(item: HomeShoppingItem) {
    setItems((prev) => prev.filter((i) => i.id !== item.id));
    deleteShoppingItem(item.id).then((res) => {
      if (!res.ok) {
        toast.error("Couldn't remove item", { description: res.error });
        setItems((prev) => [...prev, item]);
      }
    });
  }

  return (
    // min-h matches the "save the list first" placeholder shown before a
    // reminder exists (reminder-sheet.tsx) — keeps the sheet the same
    // minimum height in both create and edit mode so the date popover
    // never gets clipped, regardless of how many items are in the list.
    <div className="mt-3 min-h-[220px]">
      {/* Enter still adds (fast path for typing multiple items in a row),
          but a visible + button is the discoverable affordance — relying
          on the keyboard's return key alone wasn't obvious enough. */}
      <div className="flex items-center gap-2">
        <input
          ref={inputRef}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              addItem();
            }
          }}
          placeholder="Add item…"
          autoFocus
          className="h-10 w-full min-w-0 flex-1 rounded-lg border border-input bg-transparent px-3 text-[15px] outline-none placeholder:text-text-2"
        />
        <button
          type="button"
          onClick={addItem}
          disabled={!draft.trim()}
          aria-label="Add item"
          className="grid size-10 shrink-0 place-items-center rounded-lg bg-work text-white disabled:opacity-40"
        >
          <Plus className="size-4" strokeWidth={2.5} />
        </button>
      </div>

      {items.length > 0 && (
        <ul className="mt-2 divide-y divide-hairline rounded-lg border border-hairline">
          {items.map((item) => (
            <li key={item.id} className="flex items-center gap-2 px-3 py-2">
              <button
                type="button"
                onClick={() => toggle(item)}
                aria-label={item.checked ? "Mark as not done" : "Mark as done"}
                className={cn(
                  "flex size-5 shrink-0 items-center justify-center rounded-full border-2 text-[11px]",
                  item.checked ? "border-work bg-work text-white" : "border-text-2 text-transparent",
                )}
              >
                ✓
              </button>
              <span className={cn("flex-1 text-[15px]", item.checked && "text-text-2 line-through")}>{item.label}</span>
              <button
                type="button"
                onClick={() => remove(item)}
                aria-label="Remove item"
                className="shrink-0 rounded-md p-1 text-text-2 hover:bg-muted"
              >
                <X className="size-3.5" />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
