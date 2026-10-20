"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { Briefcase, BriefcaseBusiness, ChevronRight, House, ShoppingCart, Users } from "lucide-react";
import { FocusSheet } from "@/components/focus/focus-sheet";
import { useFocus } from "@/components/focus/focus-provider";
import { GigKindChooser } from "@/components/sidegig/gig-form";
import { SideGigSaveForm } from "@/components/sidegig/sidegig-work-sheet";
import { MaintenanceSheet } from "@/components/household/maintenance-sheet";
import { homeCategoryIcons, homeSectionIcons } from "@/components/household/home-icons";
import { ADD_DESTINATIONS, addStepFor, addStepParent, homeSectionStep, isAddForm, type AddSaved, type AddStep } from "@/lib/add-flow";
import { HOME_CATEGORIES, HOME_SECTIONS, homeSection, homeTemplate, type HomeCategory } from "@/lib/household";
import type { GigKind } from "@/lib/sidegig";
import { createClient } from "@/lib/supabase/client";
import { ReminderSheet } from "./reminder-sheet";
import type { HomeContext, HomeReminder } from "./types";

const destinationIcons = {
  work: [Briefcase, "text-work"],
  sidegig: [BriefcaseBusiness, "text-sidegig"],
  home: [House, "text-social"],
  social: [Users, "text-social"],
  shopping: [ShoppingCart, "text-shopping"],
} as const;
const categoriesIn = (section: string) => HOME_CATEGORIES.filter(c => c.section === section).map(c => c.key);

function ChoiceRow({ icon: Icon, color, label, description, onClick }: { icon: typeof House; color: string; label: string; description: string; onClick: () => void }) {
  return <button type="button" className="flex min-h-[76px] w-full items-center gap-3 border-b border-hairline py-3 text-left last:border-0" onClick={onClick}>
    <Icon className={`size-5 shrink-0 ${color}`} />
    <span className="min-w-0 flex-1"><b className="block text-[15px] font-semibold">{label}</b><span className="mt-1 block text-[13px] text-text-2">{description}</span></span>
    <ChevronRight className="size-4 shrink-0 text-text-2" />
  </button>;
}

/**
 * Today's Add (DESIGN.md §5.1): "What would you like to add?" opens the same
 * forms and atomic saves used inside Side Gig, Home and the reminder sheet.
 * Visited forms stay mounted while hidden, so Back keeps what was typed.
 */
export function TodayAddSheet({ contexts, initialTitle = "", onClose, onSaved, onShoppingCreated }: {
  contexts: HomeContext[];
  initialTitle?: string;
  onClose: () => void;
  onSaved: (saved: AddSaved) => void;
  onShoppingCreated: (reminder: HomeReminder) => void;
}) {
  const focus = useFocus();
  // Side Gig dates use the account timezone, like the server. Until Focus has
  // loaded it, read the setting rather than assume UTC.
  const [settingZone, setSettingZone] = useState<string | null>(null);
  const zone = focus?.data?.timezone ?? settingZone;
  useEffect(() => {
    if (zone) return;
    let live = true;
    void createClient().from("user_settings").select("timezone").maybeSingle()
      .then(({ data }) => { if (live) setSettingZone(data?.timezone ?? "UTC"); });
    return () => { live = false; };
  }, [zone]);
  const [step, setStep] = useState<AddStep>("root");
  const [mounted, setMounted] = useState<AddStep[]>([]);
  const [dirty, setDirty] = useState<ReadonlySet<AddStep>>(new Set());
  const [pending, setPending] = useState<AddStep | null>(null);
  const [discard, setDiscard] = useState(false);
  // Stable per-form callbacks: the embedded forms report edits from effects.
  const handlers = useRef(new Map<AddStep, { dirty: () => void; pending: (value: boolean) => void }>());
  const handlersFor = (key: AddStep) => {
    let h = handlers.current.get(key);
    if (!h) {
      h = {
        dirty: () => setDirty(d => d.has(key) ? d : new Set(d).add(key)),
        pending: value => setPending(current => value ? key : current === key ? null : current),
      };
      handlers.current.set(key, h);
    }
    return h;
  };
  const parent = addStepParent(step, homeSection, categoriesIn);
  const go = (next: AddStep) => {
    setDiscard(false);
    setStep(next);
    if (isAddForm(next)) setMounted(m => m.includes(next) ? m : [...m, next]);
  };
  const finish = (saved: AddSaved) => {
    onSaved(saved);
    if (saved.destination === "sidegig") void focus?.reload();
    onClose();
  };

  const title = step === "root" ? "What would you like to add?"
    : step === "sidegig" ? "Add to Side Gig"
    : step.startsWith("gig:") ? ({ work: "New task", order: "New order", followup: "New follow-up", payment: "Expected payment" } as Record<string, string>)[step.slice(4)]
    : step === "home" ? "Add to Home"
    : step.startsWith("home:") ? HOME_SECTIONS.find(s => s.key === step.slice(5))!.label
    : step.startsWith("task:") ? HOME_SECTIONS.find(s => s.key === homeSection(step.slice(5)))!.label
    : step.startsWith("list:") ? "New shopping list"
    : step === "form:work" ? "New Work reminder" : "New Social reminder";

  function form(key: AddStep): ReactNode {
    const h = handlersFor(key);
    if (key.startsWith("gig:")) {
      const kind = key.slice(4) as GigKind;
      if (!zone) return <p className="py-4 text-[14px] text-text-2">Loading…</p>;
      return <SideGigSaveForm kind={kind} initial={{ title: initialTitle, is_order: kind === "order" }} zone={zone} onDirty={h.dirty} onPendingChange={h.pending} onSaved={({ id, kind: saved }) => finish({ destination: "sidegig", kind: saved, id })} />;
    }
    if (key.startsWith("task:")) {
      const category = key.slice(5) as HomeCategory;
      return <MaintenanceSheet embedded category={category} initialTitle={initialTitle || undefined} onClose={onClose} onDirty={h.dirty} onPendingChange={h.pending} onSaved={id => finish({ destination: "home", category, noun: homeTemplate(category).noun, id })} />;
    }
    const slug = key.startsWith("list:") ? "shopping" : key.slice(5) as "work" | "social";
    const context = contexts.find(c => c.slug === slug);
    if (!context) return <p role="alert" className="py-4 text-[14px] text-danger">This context isn’t available. Check Settings → Contexts.</p>;
    return <ReminderSheet embedded reminder={null} contexts={contexts} initialContextId={context.id} initialTitle={initialTitle} onClose={onClose} onDirty={h.dirty} onPendingChange={h.pending}
      onSaved={({ id }) => { if (id && slug !== "shopping") finish({ destination: slug, id }); }}
      onCreated={reminder => { onShoppingCreated(reminder); onClose(); }} />;
  }

  return <FocusSheet title={title} scrollKey={step} onClose={onClose} onBack={parent && !pending ? () => go(parent) : undefined} canClose={() => {
    if (pending) return false;
    if (dirty.size) { setDiscard(true); return false; }
    return true;
  }}>
    {step === "root" && <div className="mt-1">{ADD_DESTINATIONS.map(d => <ChoiceRow key={d.key} icon={destinationIcons[d.key][0]} color={destinationIcons[d.key][1]} label={d.label} description={d.description} onClick={() => go(addStepFor(d.key))} />)}</div>}
    {step === "sidegig" && <div className="mt-1"><GigKindChooser onChoose={kind => go(`gig:${kind}`)} /></div>}
    {step === "home" && <div className="mt-1">{HOME_SECTIONS.map(s => <ChoiceRow key={s.key} icon={homeSectionIcons[s.key]} color={s.key === "groceries" ? "text-shopping" : "text-social"} label={s.label} description={s.hint} onClick={() => go(homeSectionStep(s.key, categoriesIn(s.key)))} />)}</div>}
    {step.startsWith("home:") && <div className="mt-1">{HOME_CATEGORIES.filter(c => c.section === step.slice(5)).map(c => <ChoiceRow key={c.key} icon={homeCategoryIcons[c.key]} color="text-social" label={c.label} description={c.hint} onClick={() => go(`task:${c.key}`)} />)}</div>}
    {mounted.map(key => <div key={key} hidden={key !== step} className="pb-1">{form(key)}</div>)}
    {discard && <div role="alert" className="mt-4 rounded-xl border border-hairline p-3">
      <p className="text-[14px] font-semibold">Discard what you’ve entered?</p>
      <div className="mt-3 flex gap-2">
        <button type="button" className="min-h-11 rounded-xl bg-foreground px-3 text-[14px] font-semibold text-background" onClick={() => setDiscard(false)}>Keep editing</button>
        <button type="button" className="min-h-11 rounded-xl border border-hairline px-3 text-[14px] font-semibold" onClick={onClose}>Discard</button>
      </div>
    </div>}
  </FocusSheet>;
}
