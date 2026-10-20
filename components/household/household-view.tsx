"use client";
import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, ChevronRight } from "lucide-react";
import { createReminder } from "@/app/actions";
import { BottomDock } from "@/components/bottom-dock";
import { ReminderSheet } from "@/components/home/reminder-sheet";
import { ShoppingChecklist } from "@/components/home/shopping-checklist";
import type { HomeContext, HomeReminder } from "@/components/home/types";
import { MaintenanceSheet } from "./maintenance-sheet";
import { homeCategoryIcons, homeSectionIcons } from "./home-icons";
import {
  HOME_CATEGORIES,
  HOME_SECTIONS,
  HOME_HISTORY,
  homeCategory,
  homeSection,
  homeTemplate,
  repeatLabel,
  repeatValue,
  taskSummary,
  type HomeCategory,
  type HomeSection,
  type MaintenanceItem,
  type ServiceRecord,
} from "@/lib/household";
import { relativeDue } from "@/lib/dates";
import { cn } from "@/lib/utils";
const icons = homeCategoryIcons;
const sectionIcons = homeSectionIcons;
export function HouseholdView({
  contexts,
  shopping,
  maintenance,
  records,
  shipSoonCount,
  openId,
  loadError,
}: {
  contexts: HomeContext[];
  shopping: HomeReminder[];
  maintenance: MaintenanceItem[];
  records: ServiceRecord[];
  shipSoonCount: number;
  openId?: string;
  loadError?: string;
}) {
  const router = useRouter();
  const initialItem = maintenance.find((m) => m.reminder_id === openId);
  const [section, setSection] = useState<HomeSection>(
    initialItem ? homeSection(initialItem.category) : "care",
  );
  const [editing, setEditing] = useState<{
    item?: MaintenanceItem;
    category: HomeCategory;
  } | null>(() =>
    initialItem
      ? { item: initialItem, category: homeCategory(initialItem.category) }
      : null,
  );
  const openedId = useRef(openId);
  useEffect(() => {
    if (openId === openedId.current) return;
    const item = maintenance.find((m) => m.reminder_id === openId);
    if (item) {
      setEditing({ item, category: homeCategory(item.category) });
      setSection(homeSection(item.category));
    }
    openedId.current = openId;
  }, [openId, maintenance]);
  const [list, setList] = useState<HomeReminder | null>(null);
  const [listName, setListName] = useState("");
  const [error, setError] = useState("");
  const [pending, start] = useTransition();
  const [historyCategory, setHistoryCategory] = useState("all");
  const categories = HOME_CATEGORIES.filter((c) => c.section === section);
  const history = records.filter(
    (r) =>
      homeSection(r.category) === section &&
      (historyCategory === "all" ||
        homeCategory(r.category) === historyCategory),
  );
  const close = () => {
    setEditing(null);
    router.replace("/home", { scroll: false });
    router.refresh();
  };
  function addList() {
    if (!listName.trim()) {
      setError("Give your shopping list a name.");
      return;
    }
    const context = contexts.find((c) => c.slug === "shopping");
    if (!context) {
      setError("Shopping context is unavailable.");
      return;
    }
    setError("");
    start(async () => {
      try {
        const r = await createReminder({
          title: listName,
          contextId: context.id,
          dueAt: null,
          channels: [],
          isOrder: false,
        });
        if (!r.ok) {
          setError(r.error);
          return;
        }
        setListName("");
        router.refresh();
      } catch {
        setError("Could not create the list. Try again.");
      }
    });
  }
  function chooseSection(key: HomeSection) {
    setSection(key);
    setHistoryCategory("all");
  }
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="px-4 pb-4">
        <p className="mb-3 text-[15px] text-text-2">
          A little less to remember, in the sections you need.
        </p>
        <div
          role="tablist"
          aria-label="Home sections"
          className="flex gap-2 overflow-x-auto pb-1"
        >
          {HOME_SECTIONS.map((s) => {
            const Icon = sectionIcons[s.key];
            return (
              <button
                key={s.key}
                role="tab"
                id={`home-tab-${s.key}`}
                aria-selected={section === s.key}
                aria-controls="home-section-panel"
                onClick={() => chooseSection(s.key)}
                className={cn(
                  "flex min-h-11 shrink-0 items-center gap-1.5 rounded-full border px-3 text-[13px] font-semibold shadow-card transition-colors duration-150",
                  section === s.key
                    ? s.key === "groceries"
                      ? "border-shopping/30 bg-shopping/10 text-shopping"
                      : "border-social/30 bg-social/10 text-social"
                    : "border-hairline bg-surface text-text-2",
                )}
              >
                <Icon className="size-4" />
                {s.label}
              </button>
            );
          })}
        </div>
      </div>
      <div
        id="home-section-panel"
        role="tabpanel"
        aria-labelledby={`home-tab-${section}`}
        className="min-h-0 flex-1 space-y-6 overflow-y-auto px-4 pb-6"
      >
        {section === "groceries" ? (
          <section>
            <h2 className="mb-2 text-[13px] font-semibold uppercase tracking-wide text-text-2">
              Grocery & shopping lists
            </h2>
            <form
              className="flex gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                addList();
              }}
            >
              <input
                aria-label="Shopping list name"
                aria-invalid={!!error}
                value={listName}
                onChange={(e) => setListName(e.target.value)}
                placeholder="New list, e.g. Weekly groceries"
                className={`min-h-11 min-w-0 flex-1 rounded-xl border bg-surface px-3 text-[15px] shadow-card ${error ? "border-danger" : "border-hairline"}`}
              />
              <button
                disabled={pending}
                aria-label="Create shopping list"
                className="grid size-11 place-items-center rounded-xl bg-shopping text-white disabled:opacity-50"
              >
                <Plus className="size-5" />
              </button>
            </form>
            {error && (
              <p role="alert" className="mt-2 text-sm text-danger">
                {error}
              </p>
            )}
            {!shopping.length && (
              <p className="py-3 text-sm text-text-2">
                Make a grocery list, then check off each item as you shop.
              </p>
            )}
            {shopping.map((r) => (
              <div
                key={r.id}
                className="mt-3 rounded-xl border border-hairline bg-surface p-3 shadow-card"
              >
                <button
                  className="flex min-h-11 w-full items-center justify-between text-left font-semibold"
                  onClick={() => setList(r)}
                >
                  {r.title}
                  <ChevronRight className="size-4 text-text-2" />
                </button>
                <ShoppingChecklist
                  reminderId={r.id}
                  initialItems={r.shoppingItems}
                />
              </div>
            ))}
          </section>
        ) : (
          <>
            <section>
              <h2 className="mb-2 text-[13px] font-semibold uppercase tracking-wide text-text-2">
                {HOME_SECTIONS.find((s) => s.key === section)?.heading}
              </h2>
              {loadError && (
                <p role="alert" className="mb-3 text-sm text-danger">
                  {loadError}
                </p>
              )}
              <div className="space-y-3">
                {categories.map((c) => {
                  const Icon = icons[c.key];
                  const items = maintenance
                    .filter(
                      (m) =>
                        homeCategory(m.category) === c.key &&
                        m.status !== "done" &&
                        m.status !== "cancelled",
                    )
                    .sort((a, b) =>
                      (a.snoozed_until ?? a.due_at ?? "").localeCompare(
                        b.snoozed_until ?? b.due_at ?? "",
                      ),
                    );
                  return (
                    <div
                      key={c.key}
                      className="rounded-xl border border-hairline bg-surface p-3 shadow-card"
                    >
                      <div className="flex items-center gap-3">
                        <Icon className="size-5 shrink-0 text-social" />
                        <div className="min-w-0 flex-1">
                          <h3 className="text-[17px] font-semibold">
                            {c.label}
                          </h3>
                          <p className="text-[13px] text-text-2">{c.hint}</p>
                        </div>
                        <button
                          disabled={!!loadError}
                          className="grid size-11 shrink-0 place-items-center rounded-full text-social hover:bg-muted disabled:opacity-40"
                          aria-label={`Add ${c.label}`}
                          onClick={() => setEditing({ category: c.key })}
                        >
                          <Plus className="size-5" />
                        </button>
                      </div>
                      {items.map((m) => {
                        const due = m.snoozed_until ?? m.due_at;
                        return (
                          <button
                            key={m.reminder_id}
                            className="mt-3 flex min-h-[52px] w-full items-center justify-between gap-2 border-t border-hairline pt-3 text-left"
                            onClick={() =>
                              setEditing({ item: m, category: c.key })
                            }
                          >
                            <span className="min-w-0">
                              <span className="block truncate font-semibold">
                                {m.title}
                              </span>
                              <span className="block text-[13px] text-text-2">
                                {taskSummary(m) || c.assetLabel} ·{" "}
                                {repeatValue(m) === "off"
                                  ? "One time"
                                  : repeatLabel(repeatValue(m))}
                              </span>
                              <span
                                className={`text-[13px] ${due && new Date(due) < new Date() ? "text-danger" : "text-text-2"}`}
                              >
                                {due ? relativeDue(new Date(due)) : "No date"}
                              </span>
                            </span>
                            <ChevronRight className="size-4 shrink-0 text-text-2" />
                          </button>
                        );
                      })}
                      {!items.length && (
                        <p className="pt-2 text-sm text-text-2">
                          Add a reminder when you need one.
                        </p>
                      )}
                    </div>
                  );
                })}
              </div>
            </section>
            <section>
              <h2 className="mb-2 text-[13px] font-semibold uppercase tracking-wide text-text-2">
                {HOME_HISTORY[section]?.history} · {history.length}
              </h2>
              {categories.length > 1 && (
                <>
                  <label className="sr-only" htmlFor="history-category">
                    Filter history
                  </label>
                  <select
                    id="history-category"
                    value={historyCategory}
                    onChange={(e) => setHistoryCategory(e.target.value)}
                    className="mb-3 min-h-11 w-full rounded-xl border border-hairline bg-surface px-3"
                  >
                    <option value="all">All home care</option>
                    {categories.map((c) => (
                      <option key={c.key} value={c.key}>
                        {c.label}
                      </option>
                    ))}
                  </select>
                </>
              )}
              {!history.length && (
                <p className="text-sm text-text-2">
                  {HOME_HISTORY[section]?.empty}
                </p>
              )}
              <div className="space-y-2">
                {history.map((r) => (
                  <article
                    key={r.id}
                    className="rounded-xl border border-hairline bg-surface p-3 shadow-card"
                  >
                    <h3 className="font-semibold">{r.title}</h3>
                    <p className="text-[13px] text-text-2">
                      {taskSummary(r)}
                      {taskSummary(r) && " · "}
                      {new Date(r.serviced_at).toLocaleDateString()}
                    </p>
                    {homeTemplate(r.category).fields.map(
                      (f) =>
                        r.details?.[f.key] && (
                          <p
                            key={f.key}
                            className="mt-1 text-[13px] text-text-2"
                          >
                            {f.label}: {r.details[f.key]}
                          </p>
                        ),
                    )}
                    {r.notes && (
                      <p className="mt-2 whitespace-pre-wrap text-[15px]">
                        {r.notes}
                      </p>
                    )}
                  </article>
                ))}
              </div>
            </section>
          </>
        )}
      </div>
      <BottomDock activeTab="home" shipSoonCount={shipSoonCount} />
      {editing && (
        <MaintenanceSheet
          item={editing.item}
          category={editing.category}
          onClose={close}
        />
      )}
      {list && (
        <ReminderSheet
          reminder={list}
          contexts={contexts}
          onClose={() => {
            setList(null);
            router.refresh();
          }}
        />
      )}
    </div>
  );
}
