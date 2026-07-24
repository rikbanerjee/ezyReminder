"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { ChevronDown, Truck, ChevronRight } from "lucide-react";
import { QuickAdd } from "./quick-add";
import { ReminderRow } from "./reminder-row";
import { ReminderSheet } from "./reminder-sheet";
import { effectiveDue, type HomeContext, type HomeReminder } from "./types";
import { bucketFor, type Bucket } from "@/lib/dates";
import { cn } from "@/lib/utils";

interface HomeViewProps {
  contexts: HomeContext[];
  reminders: HomeReminder[]; // open + snoozed
  doneToday: HomeReminder[];
  composePrefill?: string;
  composeAutoFocus?: boolean;
}

type SectionKey = Bucket;

const SECTION_ORDER: { key: SectionKey; label: string; danger?: boolean }[] = [
  { key: "overdue", label: "Overdue", danger: true },
  { key: "today", label: "Today" },
  { key: "upcoming", label: "Upcoming" },
  { key: "nodate", label: "Someday" },
];

function daysUntil(dateStr: string): number {
  const target = new Date(`${dateStr}T00:00:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((target.getTime() - today.getTime()) / 86_400_000);
}

export function HomeView({ contexts, reminders, doneToday, composePrefill, composeAutoFocus }: HomeViewProps) {
  const [activeSlug, setActiveSlug] = useState<string | null>(null);
  const [showDone, setShowDone] = useState(false);
  const [selected, setSelected] = useState<HomeReminder | null>(null);

  const visible = useMemo(
    () =>
      activeSlug
        ? reminders.filter((r) => r.context?.slug === activeSlug)
        : reminders,
    [reminders, activeSlug],
  );

  const shipSoon = useMemo(
    () =>
      visible
        .filter((r) => r.is_order && r.order?.shipBy && !r.order.shippedAt && daysUntil(r.order.shipBy) <= 3)
        .sort((a, b) => daysUntil(a.order!.shipBy!) - daysUntil(b.order!.shipBy!)),
    [visible],
  );

  const grouped = useMemo(() => {
    const groups: Record<SectionKey, HomeReminder[]> = {
      overdue: [],
      today: [],
      upcoming: [],
      nodate: [],
    };
    for (const r of visible) {
      groups[bucketFor(effectiveDue(r))].push(r);
    }
    // Sort each dated bucket by effective due ascending.
    for (const key of ["overdue", "today", "upcoming"] as const) {
      groups[key].sort(
        (a, b) =>
          (effectiveDue(a)?.getTime() ?? 0) - (effectiveDue(b)?.getTime() ?? 0),
      );
    }
    return groups;
  }, [visible]);

  const visibleDone = activeSlug
    ? doneToday.filter((r) => r.context?.slug === activeSlug)
    : doneToday;

  const totalVisible = visible.length;

  return (
    <div className="flex flex-col gap-4">
      {/* Context filter pills */}
      <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-0.5">
        <FilterPill
          active={activeSlug === null}
          onClick={() => setActiveSlug(null)}
          label="All"
        />
        {contexts.map((c) => (
          <FilterPill
            key={c.id}
            active={activeSlug === c.slug}
            onClick={() => setActiveSlug(c.slug)}
            label={c.name}
            color={c.color}
          />
        ))}
      </div>

      <QuickAdd contexts={contexts} initialValue={composePrefill} autoFocus={composeAutoFocus} />

      {totalVisible === 0 && visibleDone.length === 0 ? (
        <p className="px-1 py-8 text-center text-[15px] text-text-2">
          Nothing here yet. Add your first reminder above.
        </p>
      ) : (
        SECTION_ORDER.map(({ key, label, danger }) => {
          const rows = grouped[key];
          return (
            <div key={key} className="contents">
              {rows.length > 0 && (
                <section>
                  <SectionHeader label={label} count={rows.length} danger={danger} />
                  <div className="divide-y divide-hairline rounded-xl border border-hairline bg-surface px-3">
                    {rows.map((r) => (
                      <ReminderRow key={r.id} reminder={r} onOpen={() => setSelected(r)} />
                    ))}
                  </div>
                </section>
              )}
              {key === "today" && shipSoon.length > 0 && (
                <section>
                  <div className="flex items-center justify-between px-1 pb-1.5 pt-1">
                    <span className="flex items-center gap-1.5 text-[13px] font-semibold uppercase tracking-wide text-text-2">
                      <Truck className="size-3.5" />
                      Ship soon
                      <span className="text-text-2/70">{shipSoon.length}</span>
                    </span>
                    <Link href="/ship-queue" className="flex items-center text-[12px] text-text-2 hover:text-foreground">
                      Ship Queue
                      <ChevronRight className="size-3.5" />
                    </Link>
                  </div>
                  <div className="divide-y divide-hairline rounded-xl border border-hairline bg-surface px-3">
                    {shipSoon.map((r) => (
                      <ReminderRow key={r.id} reminder={r} onOpen={() => setSelected(r)} />
                    ))}
                  </div>
                </section>
              )}
            </div>
          );
        })
      )}

      {/* Done today — collapsed by default */}
      {visibleDone.length > 0 && (
        <section>
          <button
            type="button"
            onClick={() => setShowDone((s) => !s)}
            className="flex w-full items-center gap-1 px-1 pb-1.5 pt-1 text-[13px] font-semibold uppercase tracking-wide text-text-2"
          >
            <ChevronDown
              className={cn("size-3.5 transition-transform", !showDone && "-rotate-90")}
            />
            Done today
            <span className="text-text-2/70">{visibleDone.length}</span>
          </button>
          {showDone && (
            <div className="divide-y divide-hairline rounded-xl border border-hairline bg-surface px-3">
              {visibleDone.map((r) => (
                <ReminderRow key={r.id} reminder={r} onOpen={() => setSelected(r)} />
              ))}
            </div>
          )}
        </section>
      )}

      {selected && (
        <ReminderSheet reminder={selected} contexts={contexts} onClose={() => setSelected(null)} />
      )}
    </div>
  );
}

function FilterPill({
  active,
  onClick,
  label,
  color,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
  color?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "inline-flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1 text-[13px] font-medium transition-colors",
        active
          ? "border-transparent bg-foreground text-background"
          : "border-hairline bg-surface text-text-2 hover:text-foreground",
      )}
    >
      {color && (
        <span className="size-2 rounded-full" style={{ backgroundColor: color }} />
      )}
      {label}
    </button>
  );
}

function SectionHeader({
  label,
  count,
  danger,
}: {
  label: string;
  count: number;
  danger?: boolean;
}) {
  return (
    <div
      className={cn(
        "flex items-center gap-1.5 px-1 pb-1.5 pt-1 text-[13px] font-semibold uppercase tracking-wide",
        danger ? "text-danger" : "text-text-2",
      )}
    >
      {label}
      <span className={cn(danger ? "text-danger/70" : "text-text-2/70")}>{count}</span>
    </div>
  );
}
