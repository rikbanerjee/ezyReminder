import type { ReminderForDelivery, SendResult } from "../types.ts";

/**
 * WhatsApp adapter (Twilio, pre-approved template messages) —
 * PLAN.md §4.1. v1.5 — implemented in Phase 5, after email + Slack.
 */
export interface SendWhatsAppInput {
  reminder: ReminderForDelivery;
  to: string;
}

export async function sendWhatsApp(_input: SendWhatsAppInput): Promise<SendResult> {
  throw new Error("sendWhatsApp is not implemented yet (Phase 5).");
}
