// Supabase Edge Function — minute sweep for due reminders (PLAN.md §4.1,
// CLAUDE.md: "pg_cron -> Edge Function minute-sweep"). Deno runtime.
//
// Invoked every minute by pg_cron via pg_net (see the one-time SQL setup
// documented in supabase/functions/notification-sweep/CRON_SETUP.md).
// Auth: the request must carry `Authorization: Bearer <service_role_key>`
// (a valid project JWT), which Supabase's default verify_jwt gate accepts.
//
// Shares lib/quiet-hours.ts and lib/integrations/* with the Next.js app —
// those files use only fetch + Intl (no Node/Deno-specific APIs) and
// relative imports, so they resolve unchanged from here.

import { createClient } from "npm:@supabase/supabase-js@2.110.7";
import { isQuietNow, nextAllowedTime, type QuietHours } from "../../../lib/quiet-hours.ts";
import { sendEmail } from "../../../lib/integrations/email/index.ts";
import { sendSlackDm } from "../../../lib/integrations/slack/index.ts";
import type { ReminderForDelivery } from "../../../lib/integrations/types.ts";

const MAX_ATTEMPTS = 3;
const CLAIM_BATCH = 25;
const MAX_BATCHES = 5;

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const resendApiKey = Deno.env.get("RESEND_API_KEY");
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL");

const supabase = createClient(supabaseUrl, serviceRoleKey);

interface NotificationRow {
  id: string;
  user_id: string;
  reminder_id: string;
  channel: "email" | "slack" | "whatsapp";
  scheduled_for: string;
  attempt_count: number;
}

function backoffMinutes(attempt: number): number {
  return Math.pow(2, attempt); // 1, 2, 4 minutes
}

async function loadReminderContext(reminderId: string) {
  const { data, error } = await supabase
    .from("reminders")
    .select("id, title, notes, due_at, snoozed_until, user_id, context:contexts(name, quiet_hours)")
    .eq("id", reminderId)
    .single();
  if (error || !data) return null;
  return data as unknown as {
    id: string;
    title: string;
    notes: string | null;
    due_at: string | null;
    snoozed_until: string | null;
    user_id: string;
    context: { name: string; quiet_hours: QuietHours } | null;
  };
}

type ReminderContext = NonNullable<Awaited<ReturnType<typeof loadReminderContext>>>;

async function dispatch(
  n: NotificationRow,
  reminder: ReminderContext,
): Promise<{ ok: true; providerMessageId: string } | { ok: false; error: string }> {
  const delivery: ReminderForDelivery = {
    id: reminder.id,
    title: reminder.title,
    notes: reminder.notes,
    dueAt: reminder.snoozed_until ?? reminder.due_at,
    contextName: reminder.context?.name ?? "",
  };

  if (n.channel === "email") {
    if (!resendApiKey || !resendFromEmail) return { ok: false, error: "resend_not_configured" };
    const { data: userRes } = await supabase.auth.admin.getUserById(n.user_id);
    const to = userRes?.user?.email;
    if (!to) return { ok: false, error: "user_email_not_found" };
    return sendEmail({ apiKey: resendApiKey, from: resendFromEmail, to, reminder: delivery });
  }

  if (n.channel === "slack") {
    const { data: integration } = await supabase
      .from("slack_integrations")
      .select("bot_token, slack_user_id")
      .eq("user_id", n.user_id)
      .maybeSingle();
    if (!integration) return { ok: false, error: "slack_not_connected" };
    return sendSlackDm({ botToken: integration.bot_token, slackUserId: integration.slack_user_id, reminder: delivery });
  }

  return { ok: false, error: "whatsapp_not_implemented" };
}

async function maybeDeferForQuietHours(n: NotificationRow, reminder: ReminderContext): Promise<boolean> {
  const { data: settings } = await supabase.from("user_settings").select("timezone").eq("user_id", n.user_id).maybeSingle();
  const quietHours = reminder.context?.quiet_hours;
  const timezone = settings?.timezone ?? "UTC";

  if (!quietHours || !isQuietNow(quietHours, timezone)) return false;

  const deferredTo = nextAllowedTime(quietHours, timezone);
  await supabase
    .from("notifications")
    .update({ status: n.attempt_count > 0 ? "retrying" : "pending", scheduled_for: deferredTo.toISOString() })
    .eq("id", n.id);
  return true;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const { error: enqueueError } = await supabase.rpc("enqueue_due_notifications");
  if (enqueueError) {
    return Response.json({ ok: false, stage: "enqueue", error: enqueueError.message }, { status: 500 });
  }

  let processed = 0;
  let sent = 0;
  let deferred = 0;
  let failed = 0;

  for (let batch = 0; batch < MAX_BATCHES; batch++) {
    const { data: claimed, error: claimError } = await supabase.rpc("claim_due_notifications", { p_limit: CLAIM_BATCH });
    if (claimError) {
      return Response.json({ ok: false, stage: "claim", error: claimError.message, processed, sent, deferred, failed }, { status: 500 });
    }
    const rows = (claimed ?? []) as NotificationRow[];
    if (rows.length === 0) break;

    for (const n of rows) {
      processed++;

      const reminder = await loadReminderContext(n.reminder_id);
      if (!reminder) {
        failed++;
        await supabase
          .from("notifications")
          .update({ status: "failed", attempt_count: MAX_ATTEMPTS, error: "reminder_not_found" })
          .eq("id", n.id);
        continue;
      }

      const wasDeferred = await maybeDeferForQuietHours(n, reminder);
      if (wasDeferred) {
        deferred++;
        continue;
      }

      const result = await dispatch(n, reminder);
      if (result.ok) {
        sent++;
        await supabase
          .from("notifications")
          .update({ status: "sent", sent_at: new Date().toISOString(), provider_message_id: result.providerMessageId, error: null })
          .eq("id", n.id);
        continue;
      }

      const nextAttempt = n.attempt_count + 1;
      if (nextAttempt >= MAX_ATTEMPTS) {
        failed++;
        await supabase
          .from("notifications")
          .update({ status: "failed", attempt_count: nextAttempt, error: result.error })
          .eq("id", n.id);
      } else {
        const retryAt = new Date(Date.now() + backoffMinutes(nextAttempt) * 60_000);
        await supabase
          .from("notifications")
          .update({ status: "retrying", attempt_count: nextAttempt, scheduled_for: retryAt.toISOString(), error: result.error })
          .eq("id", n.id);
      }
    }

    if (rows.length < CLAIM_BATCH) break;
  }

  return Response.json({ ok: true, processed, sent, deferred, failed });
});
