import type { GigKind } from "./sidegig.ts";

/**
 * Today's Add flow (DESIGN.md §5.1): a doorway into the existing organized
 * creation experiences. Steps are plain strings so both clients and the
 * prototype share one graph; forms stay mounted when the user steps back.
 */
export type AddDestination = "work" | "sidegig" | "home" | "social" | "shopping";
export const ADD_DESTINATIONS: { key: AddDestination; label: string; description: string }[] = [
  { key: "work", label: "Work", description: "A work task or follow-up" },
  { key: "sidegig", label: "Side Gig", description: "Tasks, orders, follow-ups and expected payments" },
  { key: "home", label: "Home", description: "Home care, groceries, bills and study" },
  { key: "social", label: "Social", description: "A personal reminder" },
  { key: "shopping", label: "Shopping", description: "A shopping checklist" },
];
export const SIDEGIG_ADD_KINDS: [GigKind, string, string][] = [
  ["work", "Task", "A client deliverable or a small next step"],
  ["order", "Order", "A recipient, ship-by date and tracking"],
  ["followup", "Follow-up", "A reply or update to remember"],
  ["payment", "Expected payment", "Money to collect and when to check in"],
];

/**
 * root · sidegig · gig:<kind> · home · home:<section> · task:<category> ·
 * list:shopping · list:groceries · form:work · form:social
 */
export type AddStep = string;
export const isAddForm = (step: AddStep) => /^(gig|task|list|form):/.test(step);

export function addStepFor(destination: AddDestination): AddStep {
  return destination === "sidegig" || destination === "home" ? destination : destination === "shopping" ? "list:shopping" : `form:${destination}`;
}
/** A Home section with one category goes straight to its form; Groceries is a shopping list. */
export function homeSectionStep(section: string, categories: string[]): AddStep {
  if (section === "groceries") return "list:groceries";
  return categories.length === 1 ? `task:${categories[0]}` : `home:${section}`;
}
/** Back always returns to the chooser the user came from; root has no parent. */
export function addStepParent(step: AddStep, sectionOf: (category: string) => string, categoriesIn: (section: string) => string[]): AddStep | null {
  if (step === "root") return null;
  if (step.startsWith("gig:")) return "sidegig";
  if (step === "list:groceries" || step.startsWith("home:")) return "home";
  if (step.startsWith("task:")) {
    const section = sectionOf(step.slice(5));
    return categoriesIn(section).length === 1 ? "home" : `home:${section}`;
  }
  return "root";
}

export type AddSaved =
  | { destination: "work" | "social"; id: string }
  | { destination: "sidegig"; kind: GigKind; id: string }
  | { destination: "home"; category: string; noun: string; id: string };
/** Concise confirmation, and where View opens the saved item. */
export function addConfirmation(saved: AddSaved): { message: string; href: string } {
  if (saved.destination === "sidegig") {
    const [noun, section, place] = ({ work: ["Task", "work", "Side Gig"], order: ["Order", "orders", "Ship Queue"], followup: ["Follow-up", "followups", "Side Gig"], payment: ["Expected payment", "payments", "Side Gig"] } as const)[saved.kind];
    return { message: `${noun} added to ${place}`, href: `/side-gig?section=${section}&open=${saved.id}` };
  }
  if (saved.destination === "home") return { message: `${saved.noun} added to Home`, href: `/home?open=${saved.id}` };
  return { message: `${saved.destination === "work" ? "Work reminder" : "Reminder"} added to Today`, href: `/?open=${saved.id}` };
}
