import type { Channel, ReminderStatus } from "@/lib/supabase/types";

export interface HomeContext {
  id: string;
  slug: string;
  name: string;
  color: string;
  default_channel: Channel;
}

export interface HomeOrder {
  orderRef: string | null;
  recipientName: string | null;
  shipBy: string | null; // "YYYY-MM-DD"
  carrier: string | null;
  trackingNumber: string | null;
  shippedAt: string | null;
}

export interface HomeWorkDetails {
  managerName: string | null;
  departmentResource: string | null;
  projectName: string | null;
}

export interface HomeSidegigDetails {
  initiativeName: string | null;
  clientName: string | null;
}

export interface HomeShoppingItem {
  id: string;
  label: string;
  checked: boolean;
}

export interface HomeReminder {
  id: string;
  title: string;
  notes: string | null;
  due_at: string | null;
  snoozed_until: string | null;
  status: ReminderStatus;
  channels: Channel[];
  is_order: boolean;
  context: HomeContext | null;
  /** Most recent failed delivery for this reminder, if any — powers the ⚠ + retry. */
  failedNotificationId: string | null;
  order: HomeOrder | null;
  workDetails: HomeWorkDetails | null;
  sidegigDetails: HomeSidegigDetails | null;
  /** Shopping-context reminders only (DESIGN.md §4.2.1) — the checklist. */
  shoppingItems: HomeShoppingItem[];
}

/** Shopping-context reminders only — count of unchecked items for the row/badge. */
export function shoppingItemsLeft(r: HomeReminder): number {
  return r.shoppingItems.filter((i) => !i.checked).length;
}

/** Effective due time: a snoozed reminder surfaces at its snooze target. */
export function effectiveDue(r: HomeReminder): Date | null {
  const iso = r.snoozed_until ?? r.due_at;
  return iso ? new Date(iso) : null;
}
