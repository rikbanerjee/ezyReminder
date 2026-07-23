import type { ReminderForDelivery, SendResult } from "../types.ts";

/**
 * Slack DM adapter (bot token, chat.postMessage + Block Kit buttons) —
 * PLAN.md §4.1. Sending a bot's chat.postMessage directly to a user id as
 * `channel` auto-opens the DM (no separate conversations.open call needed).
 * Buttons are handled by /api/integrations/slack/actions.
 */

export interface SendSlackDmInput {
  botToken: string;
  slackUserId: string;
  reminder: ReminderForDelivery;
}

function buildBlocks(reminder: ReminderForDelivery) {
  const due = reminder.dueAt
    ? new Date(reminder.dueAt).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })
    : null;

  return [
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: `*${reminder.title}*\n${reminder.contextName}${due ? ` · due ${due}` : ""}${reminder.notes ? `\n${reminder.notes}` : ""}`,
      },
    },
    {
      type: "actions",
      elements: [
        {
          type: "button",
          text: { type: "plain_text", text: "Done" },
          style: "primary",
          action_id: "complete_reminder",
          value: reminder.id,
        },
        {
          type: "button",
          text: { type: "plain_text", text: "Snooze 1h" },
          action_id: "snooze_1h",
          value: reminder.id,
        },
        {
          type: "button",
          text: { type: "plain_text", text: "Snooze 1d" },
          action_id: "snooze_1d",
          value: reminder.id,
        },
      ],
    },
  ];
}

export async function sendSlackDm(input: SendSlackDmInput): Promise<SendResult> {
  const res = await fetch("https://slack.com/api/chat.postMessage", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${input.botToken}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify({
      channel: input.slackUserId,
      text: `Reminder: ${input.reminder.title}`, // fallback for notifications
      blocks: buildBlocks(input.reminder),
    }),
  });

  const data = (await res.json()) as { ok: boolean; ts?: string; error?: string };
  if (!data.ok) return { ok: false, error: data.error ?? "unknown_slack_error" };
  return { ok: true, providerMessageId: data.ts ?? "" };
}
