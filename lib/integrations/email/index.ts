import type { ReminderForDelivery, SendResult } from "../types.ts";

/**
 * Resend email adapter (PLAN.md §4.1) — plain REST call (no SDK) so this
 * file has zero Node-specific imports and can be reused verbatim from the
 * Deno notification-sweep edge function.
 */

export interface SendEmailInput {
  apiKey: string;
  from: string;
  to: string;
  reminder: ReminderForDelivery;
}

function renderEmail(reminder: ReminderForDelivery): { subject: string; html: string } {
  const due = reminder.dueAt
    ? new Date(reminder.dueAt).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })
    : null;
  const subject = `Reminder: ${reminder.title}`;
  const html = `
    <div style="font-family: -apple-system, sans-serif; font-size: 15px; color: #111;">
      <p style="font-size: 17px; font-weight: 600; margin: 0 0 8px;">${escapeHtml(reminder.title)}</p>
      <p style="color: #666; margin: 0 0 4px;">${escapeHtml(reminder.contextName)}${due ? ` · due ${escapeHtml(due)}` : ""}</p>
      ${reminder.notes ? `<p style="margin-top: 12px;">${escapeHtml(reminder.notes)}</p>` : ""}
    </div>
  `.trim();
  return { subject, html };
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

export async function sendEmail(input: SendEmailInput): Promise<SendResult> {
  const { subject, html } = renderEmail(input.reminder);

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${input.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: input.from, to: [input.to], subject, html }),
  });

  if (!res.ok) {
    const body = await res.text();
    return { ok: false, error: `Resend ${res.status}: ${body.slice(0, 300)}` };
  }

  const data = (await res.json()) as { id: string };
  return { ok: true, providerMessageId: data.id };
}
