"use client";

import { useEffect, useRef, useState } from "react";
import { Plus, X } from "lucide-react";
import { toast } from "sonner";
import {
  addShoppingItem,
  toggleShoppingItem,
  deleteShoppingItem,
} from "@/app/actions";
import type { HomeShoppingItem } from "./types";
import { cn } from "@/lib/utils";

/**
 * Shopping-context checklist (DESIGN.md §4.2.1) — always-focused "Add item…"
 * input, Enter appends optimistically; every check/delete is its own
 * instant write. No Save step.
 */
export function ShoppingChecklist({
  reminderId,
  initialItems,
}: {
  reminderId: string;
  initialItems: HomeShoppingItem[];
}) {
  const [items, setItems] = useState(initialItems);
  const [draft, setDraft] = useState("");
  const [itemError, setItemError] = useState("");
  const pendingIds = useRef(new Set<string>());
  const [busyIds, setBusyIds] = useState(new Set<string>());
  const begin = (id: string) => {
    pendingIds.current.add(id);
    setBusyIds(new Set(pendingIds.current));
  };
  const end = (id: string) => {
    pendingIds.current.delete(id);
    setBusyIds(new Set(pendingIds.current));
  };
  useEffect(() => {
    setItems((prev) => {
      const local = new Map(prev.map((i) => [i.id, i]));
      const remoteIds = new Set(initialItems.map((i) => i.id));
      return [
        ...initialItems.flatMap((i) =>
          pendingIds.current.has(i.id)
            ? local.has(i.id)
              ? [local.get(i.id)!]
              : []
            : [i],
        ),
        ...prev.filter(
          (i) => pendingIds.current.has(i.id) && !remoteIds.has(i.id),
        ),
      ];
    });
  }, [initialItems]);
  const inputRef = useRef<HTMLInputElement>(null);

  function addItem() {
    const label = draft.trim();
    if (!label) {
      setItemError("Enter an item to add.");
      return;
    }
    setItemError("");
    const tempId = `temp-${crypto.randomUUID()}`;
    begin(tempId);
    setItems((prev) => [...prev, { id: tempId, label, checked: false }]);
    setDraft("");
    inputRef.current?.focus();

    addShoppingItem(reminderId, label)
      .catch(() => ({
        ok: false as const,
        error: "Check your connection and try again.",
      }))
      .then((res) => {
        end(tempId);
        if (!res.ok) {
          toast.error("Couldn't add item", { description: res.error });
          setItems((prev) => prev.filter((i) => i.id !== tempId));
          return;
        }
        setItems((prev) =>
          prev.some((i) => i.id === res.id)
            ? prev.filter((i) => i.id !== tempId)
            : prev.map((i) => (i.id === tempId ? { ...i, id: res.id } : i)),
        );
      });
  }

  function toggle(item: HomeShoppingItem) {
    if (pendingIds.current.has(item.id)) return;
    begin(item.id);
    const nextChecked = !item.checked;
    setItems((prev) =>
      prev.map((i) => (i.id === item.id ? { ...i, checked: nextChecked } : i)),
    );
    toggleShoppingItem(item.id, nextChecked)
      .catch(() => ({
        ok: false as const,
        error: "Check your connection and try again.",
      }))
      .then((res) => {
        end(item.id);
        if (!res.ok) {
          toast.error("Couldn't update item", { description: res.error });
          setItems((prev) =>
            prev.map((i) =>
              i.id === item.id ? { ...i, checked: !nextChecked } : i,
            ),
          );
        }
      });
  }

  function remove(item: HomeShoppingItem) {
    if (pendingIds.current.has(item.id)) return;
    begin(item.id);
    setItems((prev) => prev.filter((i) => i.id !== item.id));
    deleteShoppingItem(item.id)
      .catch(() => ({
        ok: false as const,
        error: "Check your connection and try again.",
      }))
      .then((res) => {
        end(item.id);
        if (!res.ok) {
          toast.error("Couldn't remove item", { description: res.error });
          setItems((prev) => [...prev, item]);
        }
      });
  }

  return (
    <div className="mt-3">
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
          // No autoFocus: this component mounts every time a shopping
          // reminder's sheet opens (create and edit both), and focusing
          // immediately popped the keyboard before the sheet had even
          // finished its slide-up, shoving the whole sheet upward on load.
          aria-label="Add shopping item"
          aria-invalid={!!itemError}
          className="h-11 w-full min-w-0 flex-1 rounded-lg border border-input bg-transparent px-3 text-[15px] outline-none placeholder:text-text-2"
        />
        <button
          type="button"
          onClick={addItem}
          aria-label="Add item"
          className="grid size-11 shrink-0 place-items-center rounded-lg bg-shopping text-white disabled:opacity-40"
        >
          <Plus className="size-4" strokeWidth={2.5} />
        </button>
      </div>

      {itemError && (
        <p role="alert" className="mt-1 text-sm text-danger">
          {itemError}
        </p>
      )}
      {items.length > 0 && (
        <ul className="mt-2 divide-y divide-hairline rounded-lg border border-hairline">
          {items.map((item) => (
            <li key={item.id} className="flex items-center gap-2 px-3 py-2">
              <button
                type="button"
                disabled={busyIds.has(item.id)}
                role="checkbox"
                aria-checked={item.checked}
                onClick={() => toggle(item)}
                aria-label={`${item.checked ? "Uncheck" : "Check"} ${item.label}`}
                className="grid size-11 shrink-0 place-items-center disabled:opacity-50"
              >
                <span
                  aria-hidden
                  className={cn(
                    "grid size-[22px] place-items-center rounded-md border-2 text-[13px]",
                    item.checked
                      ? "border-shopping bg-shopping text-white"
                      : "border-text-2 text-transparent",
                  )}
                >
                  ✓
                </span>
              </button>
              <span
                className={cn(
                  "flex-1 text-[15px]",
                  item.checked && "text-text-2 line-through",
                )}
              >
                {item.label}
              </span>
              <button
                type="button"
                disabled={busyIds.has(item.id)}
                onClick={() => remove(item)}
                aria-label={`Remove ${item.label}`}
                className="grid size-11 shrink-0 place-items-center rounded-md p-1 text-text-2 hover:bg-muted"
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
