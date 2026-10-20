"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronDown, Search } from "lucide-react";
import { QuickAdd } from "./quick-add";
import { ReminderRow } from "./reminder-row";
import { QuickReminderSheet } from "./quick-reminder-sheet";
import { TodayAddSheet } from "./today-add-sheet";
import { toast } from "sonner";
import { addConfirmation } from "@/lib/add-flow";
import { SideGigEditSheet } from "@/components/sidegig/sidegig-edit-sheet";
import { ReminderSheet } from "./reminder-sheet";
import { effectiveDue, type HomeContext, type HomeReminder } from "./types";
import { bucketFor, type Bucket } from "@/lib/dates";
import { cn } from "@/lib/utils";
import { BottomDock } from "@/components/bottom-dock";
import { FocusCard, FocusProvider } from "@/components/focus/focus-provider";

interface HomeViewProps {
  contexts: HomeContext[];
  reminders: HomeReminder[]; // open + snoozed
  doneToday: HomeReminder[];
  composePrefill?: string;
  composeAutoFocus?: boolean;
  activeTab: "today" | "all";
  shipSoonCount: number;
  showSearch?: boolean;
  /** Small text rendered at the end of the scrollable area, e.g. "Signed in as…". */
  footer?: string;
  openReminderId?: string;
  openReminder?: HomeReminder;
}

type SectionKey = Bucket;

const SECTION_ORDER: { key: SectionKey; label: string; danger?: boolean }[] = [
  { key: "overdue", label: "Overdue", danger: true },
  { key: "today", label: "Today" },
  { key: "upcoming", label: "Upcoming" },
  { key: "nodate", label: "Someday" },
];

export function HomeView({
  contexts,
  reminders,
  doneToday,
  composePrefill,
  composeAutoFocus,
  activeTab,
  shipSoonCount,
  showSearch,
  footer,
  openReminderId,
  openReminder,
}: HomeViewProps) {
  const router = useRouter();
  const openedId = useRef<string | null>(null);
  const [activeSlug, setActiveSlug] = useState<string | null>(null);
  const [showDone, setShowDone] = useState(false);
  const [selected, setSelected] = useState<HomeReminder | null>(null);
  // null = closed; otherwise the create sheet is open, pre-filled with this title.
  const [creatingNew, setCreatingNew] = useState<string | null>(null);
  const [scrollToOrderPanel, setScrollToOrderPanel] = useState(false);
  const [query, setQuery] = useState("");

  useEffect(() => {
    if (!openReminderId) {
      openedId.current = null;
      return;
    }
    if (!openReminder || openReminder.id !== openReminderId || openedId.current === openReminderId) return;
    openedId.current = openReminderId;
    if (openReminder.tags?.some((t) => t.startsWith("sidegig:"))) { router.replace(`/side-gig?open=${openReminder.id}`); return; }
    if (openReminder.tags?.some((t) => t.startsWith("home:"))) { router.replace(`/home?open=${openReminder.id}`); return; }
    setSelected(openReminder);
    setScrollToOrderPanel(false);
  }, [openReminderId, openReminder, router]);

  const closeSelected = () => {
    setSelected(null);
    if (typeof window !== "undefined" && new URLSearchParams(window.location.search).has("open")) {
      // Remove the one-shot deep-link parameter so a later refresh cannot reopen a dismissed sheet.
      router.replace("/", { scroll: false });
    }
  };

  const visible = useMemo(() => {
    const bySlug = activeTab === "all" && activeSlug ? reminders.filter((r) => r.context?.slug === activeSlug) : reminders;
    const q = query.trim().toLowerCase();
    return q ? bySlug.filter((r) => r.title.toLowerCase().includes(q)) : bySlug;
  }, [reminders, activeTab, activeSlug, query]);

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

  const visibleDone = useMemo(() => {
    const bySlug = activeTab === "all" && activeSlug ? doneToday.filter((r) => r.context?.slug === activeSlug) : doneToday;
    const q = query.trim().toLowerCase();
    return q ? bySlug.filter((r) => r.title.toLowerCase().includes(q)) : bySlug;
  }, [doneToday, activeTab, activeSlug, query]);

  const totalVisible = visible.length;

  return (
    // Outer: no overflow/position of its own — just the flex column that
    // lets the scroll area (below) grow/shrink while the sheet and dock
    // stay normal, non-scrolling siblings after it (DESIGN.md §3). This is
    // what makes the dock "frozen" at the bottom of the frame instead of
    // sitting wherever short content happens to end.
    <FocusProvider reminders={reminders} onOpenReminder={(reminder) => { setSelected(reminder); setScrollToOrderPanel(reminder.is_order); }}>
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-1 pb-4 pt-1">
        {/* Context filter pills */}
        {activeTab==="all"&&<div className="-mx-1 flex shrink-0 gap-1.5 overflow-x-auto px-1 pb-0.5">
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
        </div>}

        {showSearch && (
        <div className="flex h-10 shrink-0 items-center gap-2 rounded-xl border border-hairline bg-surface px-3 shadow-card">
          <Search className="size-4 shrink-0 text-text-2" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search reminders…"
            className="h-full w-full bg-transparent text-[15px] outline-none placeholder:text-text-2"
          />
        </div>
      )}

      {/* Today keeps Focus available before, during and after a session. */}
      <FocusCard activeOnly={activeTab !== "today"} />

      {totalVisible === 0 && visibleDone.length === 0 ? (
        <p className="px-1 py-8 text-center text-[15px] text-text-2">
          All clear. Add a reminder when something comes to mind.
        </p>
      ) : (
        SECTION_ORDER.map(({ key, label, danger }) => {
          const rows = grouped[key];
          return (
            <div key={key} className="contents">
              {rows.length > 0 && (
                <section>
                  <SectionHeader label={label} count={rows.length} danger={danger} />
                  <div className="divide-y divide-hairline rounded-xl border border-hairline bg-surface px-3 shadow-card">
                    {rows.map((r) => (
                      <ReminderRow key={r.id} reminder={r} onOpen={() => { if (r.tags?.some((t) => t.startsWith("sidegig:"))) router.push(`/side-gig?open=${r.id}`); else if (r.tags?.some((t) => t.startsWith("home:"))) router.push(`/home?open=${r.id}`); else setSelected(r); setScrollToOrderPanel(false); }} />
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
            <div className="divide-y divide-hairline rounded-xl border border-hairline bg-surface px-3 shadow-card">
              {visibleDone.map((r) => (
                <ReminderRow key={r.id} reminder={r} onOpen={() => { if (r.tags?.some((t) => t.startsWith("sidegig:"))) router.push(`/side-gig?open=${r.id}`); else if (r.tags?.some((t) => t.startsWith("home:"))) router.push(`/home?open=${r.id}`); else setSelected(r); setScrollToOrderPanel(false); }} />
              ))}
            </div>
          )}
        </section>
      )}

      {footer && <p className="px-1 pt-2 text-[12px] text-text-2">{footer}</p>}
      </div>

      {selected && (selected.context?.slug==="sidegig" ? <SideGigEditSheet reminderId={selected.id} contexts={contexts} onClose={closeSelected}/> :
        <ReminderSheet
          reminder={selected}
          contexts={contexts}
          scrollToOrderPanel={scrollToOrderPanel}
          onClose={closeSelected}
        />
      )}

      {creatingNew !== null && activeTab === "today" && (
        <TodayAddSheet
          contexts={contexts}
          initialTitle={creatingNew}
          onClose={() => setCreatingNew(null)}
          onSaved={(saved) => {
            const { message, href } = addConfirmation(saved);
            toast.success(message, { action: { label: "View", onClick: () => router.push(href) } });
            router.refresh();
          }}
          onShoppingCreated={(created) => {
            // Shopping continues straight into its checklist editor.
            setSelected(created);
            router.refresh();
          }}
        />
      )}

      {creatingNew !== null && activeTab === "all" && (
        <QuickReminderSheet
          initialTitle={creatingNew}
          contexts={contexts}
          onClose={() => setCreatingNew(null)}
          onCreated={(created) => {
            // Shopping lists only (see ReminderSheet) — swap straight into
            // edit mode for the reminder just created instead of closing,
            // so the checklist is immediately usable.
            setCreatingNew(null);
            if(created.context?.slug==="shopping")setSelected(created);
            router.refresh();
          }}
        />
      )}

      <BottomDock activeTab={activeTab} shipSoonCount={shipSoonCount}>
        <QuickAdd
          initialValue={composePrefill}
          autoFocus={composeAutoFocus}
          onOpenCreateSheet={(title) => setCreatingNew(title ?? "")}
        />
      </BottomDock>
    </div>
    </FocusProvider>
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
      style={active && color ? { backgroundColor: color } : undefined}
      className={cn(
        "inline-flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1 text-[13px] font-medium shadow-card transition-colors",
        active && color && "border-transparent text-white",
        active && !color && "border-transparent bg-foreground text-background",
        !active && "border-hairline bg-surface text-text-2 hover:text-foreground",
      )}
    >
      {color && !active && (
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
