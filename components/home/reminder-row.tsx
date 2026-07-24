"use client";

import { useState, useTransition } from "react";
import { Check, Truck, AlarmClock, Trash2, Mail, MessageSquare, MessageCircle, TriangleAlert, RotateCw } from "lucide-react";
import { toast } from "sonner";
import {
  completeReminder,
  reopenReminder,
  snoozeReminder,
  deleteReminder,
  retryNotification,
} from "@/app/actions";
import { effectiveDue, type HomeReminder } from "./types";
import { relativeDue, bucketFor, snoozeTarget } from "@/lib/dates";
import type { Channel } from "@/lib/supabase/types";
import { cn } from "@/lib/utils";

const CHANNEL_ICON: Record<Channel, typeof Mail> = {
  email: Mail,
  slack: MessageSquare,
  whatsapp: MessageCircle,
};

const SNOOZE_PRESETS = [
  { key: "1h", label: "1 hour" },
  { key: "tonight", label: "Tonight" },
  { key: "tomorrow", label: "Tomorrow" },
  { key: "nextweek", label: "Next week" },
] as const;

export function ReminderRow({ reminder, onOpen }: { reminder: HomeReminder; onOpen: () => void }) {
  const [pending, startTransition] = useTransition();
  const [menuOpen, setMenuOpen] = useState(false);

  const done = reminder.status === "done";
  const due = effectiveDue(reminder);
  const overdue = !done && bucketFor(due) === "overdue";
  const context = reminder.context;

  // Channels shown: explicit override, else the context default.
  const channels =
    reminder.channels.length > 0
      ? reminder.channels
      : context
        ? [context.default_channel]
        : [];

  function run(fn: () => Promise<{ ok: boolean; error?: string }>, failMsg: string) {
    startTransition(async () => {
      const res = await fn();
      if (!res.ok) toast.error(failMsg, { description: res.error });
    });
  }

  function toggleComplete() {
    if (done) {
      run(() => reopenReminder(reminder.id), "Couldn't reopen");
    } else {
      run(() => completeReminder(reminder.id), "Couldn't complete");
      if (typeof navigator !== "undefined" && navigator.vibrate) navigator.vibrate(10);
    }
  }

  function doSnooze(preset: (typeof SNOOZE_PRESETS)[number]["key"]) {
    setMenuOpen(false);
    const until = snoozeTarget(preset).toISOString();
    run(() => snoozeReminder(reminder.id, until), "Couldn't snooze");
  }

  function retry() {
    if (!reminder.failedNotificationId) return;
    run(() => retryNotification(reminder.failedNotificationId!), "Retry failed");
  }

  return (
    <div
      className={cn(
        "group relative flex items-center gap-3 py-2.5 pl-1 pr-1",
        pending && "opacity-50",
      )}
    >
      {/* Completion ring — context-colored outline, fills on complete */}
      <button
        type="button"
        onClick={toggleComplete}
        aria-label={done ? "Reopen" : "Complete"}
        className="grid size-[22px] shrink-0 place-items-center rounded-full border-2 transition-colors"
        style={{
          borderColor: context?.color ?? "var(--text-2)",
          backgroundColor: done ? (context?.color ?? "var(--text-2)") : "transparent",
        }}
      >
        {done && <Check className="size-3 text-white" strokeWidth={3} />}
      </button>

      {/* Title + meta — tap to open the detail sheet (div, not button: it
          contains the nested "delivery failed" retry button) */}
      <div
        role="button"
        tabIndex={0}
        onClick={onOpen}
        onKeyDown={(e) => (e.key === "Enter" || e.key === " ") && onOpen()}
        className="min-w-0 flex-1 cursor-pointer text-left"
      >
        <div
          className={cn(
            "truncate text-[15px] font-medium leading-tight",
            done && "text-text-2 line-through",
          )}
        >
          {reminder.title}
        </div>
        <div className="mt-0.5 flex items-center gap-1.5 text-[13px] text-text-2">
          {due && (
            <span className={cn(overdue && "font-medium text-danger")}>
              {relativeDue(due)}
            </span>
          )}
          {due && context && <span aria-hidden>·</span>}
          {context && <span>{context.name}</span>}
          {reminder.failedNotificationId && (
            <>
              <span aria-hidden>·</span>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  retry();
                }}
                disabled={pending}
                className="inline-flex items-center gap-1 font-medium text-danger"
              >
                <TriangleAlert className="size-3" />
                Delivery failed
                <RotateCw className="size-3" />
              </button>
            </>
          )}
        </div>
      </div>

      {/* Right meta: order + channels */}
      <div className="flex shrink-0 items-center gap-1.5 text-text-2">
        {reminder.is_order && <Truck className="size-4" aria-label="Order" />}
        {channels.map((ch) => {
          const Icon = CHANNEL_ICON[ch];
          return <Icon key={ch} className="size-3.5 opacity-40" aria-label={ch} />;
        })}
      </div>

      {/* Actions (hover on desktop, always tappable on mobile) */}
      {!done && (
        <div className="relative flex shrink-0 items-center">
          <button
            type="button"
            onClick={() => setMenuOpen((o) => !o)}
            aria-label="Snooze"
            className="grid size-7 place-items-center rounded-md text-text-2 opacity-60 transition-opacity hover:bg-muted hover:opacity-100 focus-visible:opacity-100 aria-expanded:opacity-100"
            aria-expanded={menuOpen}
          >
            <AlarmClock className="size-4" />
          </button>

          {menuOpen && (
            <>
              <div
                className="fixed inset-0 z-10"
                onClick={() => setMenuOpen(false)}
                aria-hidden
              />
              <div className="absolute right-0 top-8 z-20 w-40 overflow-hidden rounded-lg border border-hairline bg-surface py-1 shadow-lg">
                <div className="px-3 py-1 text-[11px] font-semibold uppercase tracking-wide text-text-2">
                  Snooze
                </div>
                {SNOOZE_PRESETS.map((p) => (
                  <button
                    key={p.key}
                    type="button"
                    onClick={() => doSnooze(p.key)}
                    className="block w-full px-3 py-1.5 text-left text-sm hover:bg-muted"
                  >
                    {p.label}
                  </button>
                ))}
                <div className="my-1 h-px bg-hairline" />
                <button
                  type="button"
                  onClick={() => {
                    setMenuOpen(false);
                    run(() => deleteReminder(reminder.id), "Couldn't delete");
                  }}
                  className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm text-danger hover:bg-muted"
                >
                  <Trash2 className="size-3.5" />
                  Delete
                </button>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}
