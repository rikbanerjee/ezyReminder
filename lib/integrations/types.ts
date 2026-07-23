/**
 * Shared delivery types (PLAN.md §4.1). Relative imports only, no "@/"
 * aliases — this file (and the adapters next to it) are imported both from
 * Next.js and from the Deno notification-sweep edge function
 * (supabase/functions/notification-sweep), which can't resolve path
 * aliases or Node-specific APIs.
 */

export interface ReminderForDelivery {
  id: string;
  title: string;
  notes: string | null;
  dueAt: string | null;
  contextName: string;
}

export type SendResult =
  | { ok: true; providerMessageId: string }
  | { ok: false; error: string };
