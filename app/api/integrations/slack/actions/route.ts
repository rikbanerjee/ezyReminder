import { NextResponse } from "next/server";
import crypto from "node:crypto";
import { createServiceClient } from "@/lib/supabase/service";

interface SlackBlockActionsPayload {
  type: string;
  user: { id: string };
  actions: { action_id: string; value: string }[];
  response_url?: string;
}

function verifySlackSignature(rawBody: string, timestamp: string, signature: string, signingSecret: string): boolean {
  const age = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(age) || age > 60 * 5) return false;

  const base = `v0:${timestamp}:${rawBody}`;
  const expected = "v0=" + crypto.createHmac("sha256", signingSecret).update(base).digest("hex");

  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * Slack interactivity endpoint (PLAN.md §4.1): Done / Snooze 1h / Snooze 1d
 * buttons on a delivered reminder DM. No Supabase session exists here —
 * identity comes from the signed Slack payload's user id, resolved against
 * slack_integrations, and every mutation re-checks reminder ownership.
 */
export async function POST(request: Request) {
  const signingSecret = process.env.SLACK_SIGNING_SECRET;
  const timestamp = request.headers.get("x-slack-request-timestamp");
  const signature = request.headers.get("x-slack-signature");
  const rawBody = await request.text();

  if (!signingSecret || !timestamp || !signature || !verifySlackSignature(rawBody, timestamp, signature, signingSecret)) {
    return NextResponse.json({ error: "invalid signature" }, { status: 401 });
  }

  const payloadStr = new URLSearchParams(rawBody).get("payload");
  if (!payloadStr) return NextResponse.json({ error: "missing payload" }, { status: 400 });

  const payload = JSON.parse(payloadStr) as SlackBlockActionsPayload;
  const action = payload.actions?.[0];
  if (!action) return NextResponse.json({ ok: true });

  const supabase = createServiceClient();

  const { data: integration } = await supabase
    .from("slack_integrations")
    .select("user_id")
    .eq("slack_user_id", payload.user.id)
    .maybeSingle();

  if (!integration) return NextResponse.json({ ok: true });

  const reminderId = action.value;
  const { data: reminder } = await supabase
    .from("reminders")
    .select("id")
    .eq("id", reminderId)
    .eq("user_id", integration.user_id)
    .maybeSingle();

  if (!reminder) return NextResponse.json({ ok: true });

  let confirmation = "";

  if (action.action_id === "complete_reminder") {
    await supabase.from("reminders").update({ status: "done", snoozed_until: null }).eq("id", reminderId);
    confirmation = "Done ✅";
  } else if (action.action_id === "snooze_1h" || action.action_id === "snooze_1d") {
    const ms = action.action_id === "snooze_1h" ? 60 * 60_000 : 24 * 60 * 60_000;
    const snoozedUntil = new Date(Date.now() + ms).toISOString();
    await supabase.from("reminders").update({ status: "snoozed", snoozed_until: snoozedUntil }).eq("id", reminderId);
    confirmation = action.action_id === "snooze_1h" ? "Snoozed for 1 hour ⏰" : "Snoozed for 1 day ⏰";
  }

  if (confirmation && payload.response_url) {
    await fetch(payload.response_url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ replace_original: true, text: confirmation }),
    });
  }

  return NextResponse.json({ ok: true });
}
