import type { Channel, ReminderStatus } from "@/lib/supabase/types";

export interface HomeContext {
  id: string;
  slug: string;
  name: string;
  color: string;
  default_channel: Channel;
}

export interface HomeReminder {
  id: string;
  title: string;
  due_at: string | null;
  snoozed_until: string | null;
  status: ReminderStatus;
  channels: Channel[];
  is_order: boolean;
  context: HomeContext | null;
  /** Most recent failed delivery for this reminder, if any — powers the ⚠ + retry. */
  failedNotificationId: string | null;
}

/** Effective due time: a snoozed reminder surfaces at its snooze target. */
export function effectiveDue(r: HomeReminder): Date | null {
  const iso = r.snoozed_until ?? r.due_at;
  return iso ? new Date(iso) : null;
}
