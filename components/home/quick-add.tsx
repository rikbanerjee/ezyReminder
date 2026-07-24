"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { Plus, Truck, Calendar, Mail, MessageSquare, MessageCircle } from "lucide-react";
import { toast } from "sonner";
import { createReminder } from "@/app/actions";
import { parseQuickAdd } from "@/lib/parse/quick-add";
import type { Channel } from "@/lib/supabase/types";
import type { HomeContext, HomeReminder } from "./types";
import { relativeDue } from "@/lib/dates";
import { cn } from "@/lib/utils";

const CHANNEL_ICON: Record<Channel, typeof Mail> = {
  email: Mail,
  slack: MessageSquare,
  whatsapp: MessageCircle,
};

/**
 * The inline smart-parse quick-add box (DESIGN.md §5.1) — an input, not a
 * button that opens a form. The typed text *is* the title; there is no
 * separate mandatory title field to leave blank.
 */
export function QuickAdd({
  contexts,
  initialValue,
  autoFocus,
  onOfferDetails,
}: {
  contexts: HomeContext[];
  initialValue?: string;
  autoFocus?: boolean;
  /** Opens the detail sheet on a just-created reminder, pre-scrolled to the order panel. */
  onOfferDetails: (reminder: HomeReminder) => void;
}) {
  const [value, setValue] = useState(initialValue ?? "");
  const [pending, startTransition] = useTransition();
  const [shake, setShake] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // Share-target / "New reminder" shortcut hand-off (MOBILE.md Stage 1).
  useEffect(() => {
    if (autoFocus) inputRef.current?.focus();
  }, [autoFocus]);

  const parsed = useMemo(() => parseQuickAdd(value, contexts), [value, contexts]);
  const matchedContext = parsed.contextSlug
    ? contexts.find((c) => c.slug === parsed.contextSlug) ?? null
    : null;

  const hasChips = parsed.hasDate || matchedContext || parsed.isOrder || parsed.channels.length > 0;

  function submit() {
    if (!parsed.title.trim()) {
      setShake(true);
      window.setTimeout(() => setShake(false), 150);
      return;
    }
    if (pending) return;

    const dueAtIso = parsed.dueAt ? parsed.dueAt.toISOString() : null;
    const isOrder = parsed.isOrder;
    const channels = parsed.channels;
    const title = parsed.title;

    startTransition(async () => {
      const res = await createReminder({
        title,
        dueAt: dueAtIso,
        contextId: matchedContext?.id ?? null,
        isOrder,
        channels,
      });
      if (!res.ok) {
        toast.error("Couldn't save", { description: res.error });
        return;
      }
      setValue("");
      inputRef.current?.focus();

      const created: HomeReminder = {
        id: res.id,
        title,
        notes: null,
        due_at: dueAtIso,
        snoozed_until: null,
        status: "open",
        channels,
        is_order: isOrder,
        context: matchedContext ?? contexts.find((c) => c.slug === "sidegig") ?? contexts[0] ?? null,
        failedNotificationId: null,
        order: null,
        workDetails: null,
        sidegigDetails: null,
        shoppingItems: [],
      };

      if (isOrder) {
        toast.success("Added ✓", {
          description: "Add order details?",
          action: { label: "Add details", onClick: () => onOfferDetails(created) },
        });
      } else {
        toast.success("Added ✓");
      }
    });
  }

  return (
    <div className="rounded-2xl bg-surface p-2 shadow-float">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
        className={cn("flex items-center gap-2", shake && "animate-shake")}
      >
        <Plus className="ml-1 size-4 shrink-0 text-work" />
        <input
          ref={inputRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="Remind me to…"
          className="h-8 w-full min-w-0 bg-transparent text-[15px] outline-none placeholder:text-text-2"
          autoComplete="off"
          enterKeyHint="done"
          disabled={pending}
        />
      </form>

      {hasChips && (
        <div className="flex flex-wrap items-center gap-1.5 px-1 pb-1 pt-2">
          {matchedContext && (
            <Chip>
              <span
                className="size-2 rounded-full"
                style={{ backgroundColor: matchedContext.color }}
              />
              {matchedContext.name}
            </Chip>
          )}
          {parsed.hasDate && parsed.dueAt && (
            <Chip>
              <Calendar className="size-3" />
              {relativeDue(parsed.dueAt)}
            </Chip>
          )}
          {parsed.isOrder && (
            <Chip>
              <Truck className="size-3" />
              Order
            </Chip>
          )}
          {parsed.channels.map((ch) => {
            const Icon = CHANNEL_ICON[ch];
            return (
              <Chip key={ch}>
                <Icon className="size-3" />
                {ch}
              </Chip>
            );
          })}
        </div>
      )}

      {!hasChips && value.length === 0 && (
        <p className="px-2 pb-1 pt-1 text-[12px] text-text-2">
          Try: “ship mug order tue 6pm #gig #order @whatsapp” · Return to add
        </p>
      )}
    </div>
  );
}

function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-md bg-background px-1.5 py-0.5",
        "text-[12px] font-medium capitalize text-text-2",
      )}
    >
      {children}
    </span>
  );
}
