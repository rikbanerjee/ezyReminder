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
import type { ReminderForDelivery } from "../../../lib/integrations/types.ts";

const MAX_ATTEMPTS = 3;
const IDEMPOTENCY_SAFETY_WINDOW_MS = 23 * 60 * 60 * 1000;
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
  channel: "email" | "whatsapp";
  scheduled_for: string;
  attempt_count: number;
  occurrence_at: string;
  superseded_at: string | null;
  delivery_started_at: string | null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 300) : String(error).slice(0, 300);
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
    if (!n.delivery_started_at) {
      // Start the safety window only after preflight, immediately before provider I/O.
      const deliveryStartedAt = new Date().toISOString();
      await updateNotification(n.id, { delivery_started_at: deliveryStartedAt });
      n.delivery_started_at = deliveryStartedAt;
    }
    return sendEmail({ apiKey: resendApiKey, from: resendFromEmail, to, reminder: delivery, idempotencyKey: `notification:${n.id}` });
  }

  return { ok: false, error: "whatsapp_not_implemented" };
}

async function maybeDeferForQuietHours(n: NotificationRow, reminder: ReminderContext): Promise<boolean> {
  const { data: settings, error: settingsError } = await supabase.from("user_settings").select("timezone").eq("user_id", n.user_id).maybeSingle();
  if (settingsError) throw new Error(`settings_read_failed: ${errorMessage(settingsError)}`);
  const quietHours = reminder.context?.quiet_hours;
  const timezone = settings?.timezone ?? "UTC";

  if (!quietHours || !isQuietNow(quietHours, timezone)) return false;

  const deferredTo = nextAllowedTime(quietHours, timezone);
  const { error } = await supabase
    .from("notifications")
    .update({ status: n.attempt_count > 0 ? "retrying" : "pending", scheduled_for: deferredTo.toISOString() })
    .eq("id", n.id);
  if (error) throw new Error(`quiet_hours_update_failed: ${errorMessage(error)}`);
  return true;
}

async function updateNotification(id: string, values: Record<string, unknown>): Promise<void> {
  const { error } = await supabase.from("notifications").update(values).eq("id", id);
  if (error) throw new Error(`notification_update_failed: ${errorMessage(error)}`);
}

async function isDispatchable(n: NotificationRow): Promise<boolean> {
  const { data, error } = await supabase.from("notifications").select("status, superseded_at, delivery_started_at").eq("id", n.id).single();
  if (error) throw new Error(`notification_read_failed: ${errorMessage(error)}`);
  if (!data || data.status !== "sending" || data.superseded_at != null) return false;
  n.delivery_started_at = data.delivery_started_at;
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

      try {
        if (!await isDispatchable(n)) continue;

        const reminder = await loadReminderContext(n.reminder_id);
        if (!reminder) {
          failed++;
          await updateNotification(n.id, { status: "failed", attempt_count: MAX_ATTEMPTS, error: "reminder_not_found" });
          continue;
        }

        const { data: currentReminder, error: statusError } = await supabase.from("reminders").select("status, due_at, snoozed_until, channels, context:contexts(default_channel)").eq("id", n.reminder_id).single();
        if (statusError) throw new Error(`reminder_status_read_failed: ${errorMessage(statusError)}`);
        if (!currentReminder || !["open", "snoozed"].includes(currentReminder.status)) {
          await updateNotification(n.id, { status: "failed", superseded_at: new Date().toISOString(), error: "reminder_not_open" });
          continue;
        }

        const effectiveDue = currentReminder.snoozed_until ?? currentReminder.due_at;
        if (!effectiveDue || new Date(effectiveDue).getTime() !== new Date(n.occurrence_at).getTime()) {
          await updateNotification(n.id, { status: "failed", superseded_at: new Date().toISOString(), error: "reminder_due_changed" });
          continue;
        }

        const routeContext = currentReminder.context as unknown as { default_channel: string } | null;
        const channels = currentReminder.channels?.length ? currentReminder.channels : [routeContext?.default_channel];
        if (!channels.includes(n.channel)) {
          await updateNotification(n.id, { status: "failed", superseded_at: new Date().toISOString(), error: "reminder_channel_changed" });
          continue;
        }

        const wasDeferred = await maybeDeferForQuietHours(n, reminder);
        if (wasDeferred) {
          deferred++;
          continue;
        }

        if (n.delivery_started_at && Date.now() - new Date(n.delivery_started_at).getTime() >= IDEMPOTENCY_SAFETY_WINDOW_MS) {
          failed++;
          await updateNotification(n.id, { status: "failed", attempt_count: MAX_ATTEMPTS, error: "delivery_confirmation_required" });
          continue;
        }
        const result = await dispatch(n, reminder);
        if (result.ok) {
          // Keep the row sending if persistence fails: retrying it could deliver twice.
          await updateNotification(n.id, { status: "sent", sent_at: new Date().toISOString(), provider_message_id: result.providerMessageId, error: null });
          sent++;
          continue;
        }

        const nextAttempt = n.attempt_count + 1;
        if (nextAttempt >= MAX_ATTEMPTS) {
          failed++;
          await updateNotification(n.id, { status: "failed", attempt_count: nextAttempt, error: result.error });
        } else {
          const retryAt = new Date(Date.now() + backoffMinutes(nextAttempt) * 60_000);
          await updateNotification(n.id, { status: "retrying", attempt_count: nextAttempt, scheduled_for: retryAt.toISOString(), error: result.error });
        }
      } catch (error) {
        // Network/provider exceptions and persistence failures are contained per row.
        // If delivery may have succeeded, leave status as sending to avoid duplicate mail.
        const message = errorMessage(error);
        if (message.startsWith("notification_update_failed")) throw error;
        const nextAttempt = n.attempt_count + 1;
        if (nextAttempt < MAX_ATTEMPTS) {
          const retryAt = new Date(Date.now() + backoffMinutes(nextAttempt) * 60_000);
          await updateNotification(n.id, { status: "retrying", attempt_count: nextAttempt, scheduled_for: retryAt.toISOString(), error: message });
        } else {
          await updateNotification(n.id, { status: "failed", attempt_count: nextAttempt, error: message });
          failed++;
        }
      }
    }

    if (rows.length < CLAIM_BATCH) break;
  }

  return Response.json({ ok: true, processed, sent, deferred, failed });
});
