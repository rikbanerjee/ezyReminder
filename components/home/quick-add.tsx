"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { Plus, Truck, Calendar, Mail, MessageSquare, MessageCircle } from "lucide-react";
import { toast } from "sonner";
import { createReminder } from "@/app/actions";
import { parseQuickAdd } from "@/lib/parse/quick-add";
import type { Channel } from "@/lib/supabase/types";
import type { HomeContext } from "./types";
import { relativeDue } from "@/lib/dates";
import { cn } from "@/lib/utils";

const CHANNEL_ICON: Record<Channel, typeof Mail> = {
  email: Mail,
  slack: MessageSquare,
  whatsapp: MessageCircle,
};

export function QuickAdd({ contexts, initialValue, autoFocus }: { contexts: HomeContext[]; initialValue?: string; autoFocus?: boolean }) {
  const [value, setValue] = useState(initialValue ?? "");
  const [pending, startTransition] = useTransition();
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
    if (!parsed.title.trim() || pending) return;
    const payload = {
      title: parsed.title,
      dueAt: parsed.dueAt ? parsed.dueAt.toISOString() : null,
      contextSlug: parsed.contextSlug,
      isOrder: parsed.isOrder,
      channels: parsed.channels,
    };
    startTransition(async () => {
      const res = await createReminder(payload);
      if (res.ok) {
        setValue("");
        inputRef.current?.focus();
      } else {
        toast.error("Couldn't save", { description: res.error });
      }
    });
  }

  return (
    <div className="rounded-xl border border-hairline bg-surface p-2 shadow-sm">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
        className="flex items-center gap-2"
      >
        <Plus className="ml-1 size-4 shrink-0 text-text-2" />
        <input
          ref={inputRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="Add a reminder — try “ship mug order tue 6pm #sidegig #order @whatsapp”"
          className="h-8 w-full min-w-0 bg-transparent text-[15px] outline-none placeholder:text-text-2"
          autoComplete="off"
          enterKeyHint="done"
        />
        {value.trim() && (
          <button
            type="submit"
            disabled={pending || !parsed.title.trim()}
            className="shrink-0 rounded-lg bg-primary px-3 py-1 text-sm font-medium text-primary-foreground transition-opacity disabled:opacity-50"
          >
            Add
          </button>
        )}
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
    </div>
  );
}

function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-md bg-muted px-1.5 py-0.5",
        "text-[12px] font-medium capitalize text-text-2",
      )}
    >
      {children}
    </span>
  );
}
