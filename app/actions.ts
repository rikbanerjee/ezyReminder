"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { Channel } from "@/lib/supabase/types";
import { sendEmail } from "@/lib/integrations/email";
import { sendSlackDm } from "@/lib/integrations/slack";
import type { ReminderForDelivery } from "@/lib/integrations/types";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

/** Payload the quick-add box sends after client-side smart-parse. */
export interface CreateReminderInput {
  title: string;
  dueAt: string | null; // ISO
  contextSlug: string | null;
  isOrder: boolean;
  channels: Channel[];
}

export type ActionResult = { ok: true } | { ok: false; error: string };

async function requireUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  return { supabase, user };
}

export async function createReminder(input: CreateReminderInput): Promise<ActionResult> {
  const title = input.title.trim();
  if (!title) return { ok: false, error: "A reminder needs some text." };

  const { supabase, user } = await requireUser();

  // Resolve the context: matched slug, else fall back to Side Gig / first.
  const { data: contexts, error: ctxErr } = await supabase
    .from("contexts")
    .select("id, slug")
    .order("name");

  if (ctxErr) return { ok: false, error: ctxErr.message };
  if (!contexts || contexts.length === 0) {
    return { ok: false, error: "No contexts found for your account." };
  }

  const context =
    (input.contextSlug && contexts.find((c) => c.slug === input.contextSlug)) ||
    contexts.find((c) => c.slug === "sidegig") ||
    contexts[0];

  const { error } = await supabase.from("reminders").insert({
    user_id: user.id,
    context_id: context.id,
    title,
    due_at: input.dueAt,
    channels: input.channels ?? [],
    is_order: input.isOrder,
    created_by: "ui",
  });

  if (error) return { ok: false, error: error.message };

  revalidatePath("/");
  return { ok: true };
}

export async function completeReminder(id: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("reminders")
    .update({ status: "done", snoozed_until: null })
    .eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  return { ok: true };
}

export async function reopenReminder(id: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("reminders")
    .update({ status: "open", snoozed_until: null })
    .eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  return { ok: true };
}

export async function snoozeReminder(id: string, until: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("reminders")
    .update({ status: "snoozed", snoozed_until: until })
    .eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  return { ok: true };
}

export async function deleteReminder(id: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase.from("reminders").delete().eq("id", id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/");
  return { ok: true };
}

/** Manual re-send from the "delivery failed" indicator on a reminder row. */
export async function retryNotification(id: string): Promise<ActionResult> {
  const { supabase, user } = await requireUser();

  const { data: notification } = await supabase
    .from("notifications")
    .select("id, reminder_id, channel")
    .eq("id", id)
    .single();
  if (!notification) return { ok: false, error: "Notification not found." };

  const { data: reminder } = await supabase
    .from("reminders")
    .select("id, title, notes, due_at, snoozed_until, context:contexts(name)")
    .eq("id", notification.reminder_id)
    .single();
  if (!reminder) return { ok: false, error: "Reminder not found." };

  const delivery: ReminderForDelivery = {
    id: reminder.id,
    title: reminder.title,
    notes: reminder.notes,
    dueAt: reminder.snoozed_until ?? reminder.due_at,
    contextName: (reminder.context as unknown as { name: string } | null)?.name ?? "",
  };

  const result = await (async () => {
    if (notification.channel === "email") {
      const apiKey = process.env.RESEND_API_KEY;
      const from = process.env.RESEND_FROM_EMAIL;
      if (!apiKey || !from || !user.email) return { ok: false as const, error: "Email delivery isn't configured yet." };
      return sendEmail({ apiKey, from, to: user.email, reminder: delivery });
    }
    if (notification.channel === "slack") {
      const { data: integration } = await supabase
        .from("slack_integrations")
        .select("bot_token, slack_user_id")
        .eq("user_id", user.id)
        .maybeSingle();
      if (!integration) return { ok: false as const, error: "Slack isn't connected." };
      return sendSlackDm({ botToken: integration.bot_token, slackUserId: integration.slack_user_id, reminder: delivery });
    }
    return { ok: false as const, error: "WhatsApp delivery isn't available yet." };
  })();

  if (result.ok) {
    await supabase
      .from("notifications")
      .update({ status: "sent", sent_at: new Date().toISOString(), provider_message_id: result.providerMessageId, error: null })
      .eq("id", id);
    revalidatePath("/");
    return { ok: true };
  }

  await supabase.from("notifications").update({ status: "failed", error: result.error }).eq("id", id);
  return { ok: false, error: result.error };
}

export async function updateTimezone(timezone: string): Promise<ActionResult> {
  const { supabase, user } = await requireUser();
  const { error } = await supabase.from("user_settings").upsert({ user_id: user.id, timezone });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/settings");
  return { ok: true };
}

export async function updateQuietHours(contextId: string, start: string, end: string): Promise<ActionResult> {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("contexts")
    .update({ quiet_hours: { start, end } })
    .eq("id", contextId);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/settings");
  return { ok: true };
}

export async function disconnectSlack(): Promise<ActionResult> {
  const { supabase, user } = await requireUser();
  const { error } = await supabase.from("slack_integrations").delete().eq("user_id", user.id);
  if (error) return { ok: false, error: error.message };
  revalidatePath("/settings");
  return { ok: true };
}
