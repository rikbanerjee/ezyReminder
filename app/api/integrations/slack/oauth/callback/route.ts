import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

const STATE_COOKIE = "slack_oauth_state";

interface SlackOAuthResponse {
  ok: boolean;
  error?: string;
  access_token?: string;
  team?: { id: string; name?: string };
  authed_user?: { id: string };
}

/**
 * Slack OAuth callback (PLAN.md §4.1). Exchanges the code for a bot token
 * and stores it against the *currently signed-in ezyReminder user* — the
 * Supabase session cookie carries identity here, `state` is CSRF-only.
 */
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const state = searchParams.get("state");

  const cookieStore = await cookies();
  const expectedState = cookieStore.get(STATE_COOKIE)?.value;
  cookieStore.delete(STATE_COOKIE);

  if (!code || !state || !expectedState || state !== expectedState) {
    return NextResponse.redirect(`${origin}/settings?slack=error`);
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.redirect(`${origin}/login`);

  const clientId = process.env.SLACK_CLIENT_ID;
  const clientSecret = process.env.SLACK_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    return NextResponse.redirect(`${origin}/settings?slack=not_configured`);
  }

  const redirectUri = new URL("/api/integrations/slack/oauth/callback", origin).toString();
  const tokenRes = await fetch("https://slack.com/api/oauth.v2.access", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      code,
      redirect_uri: redirectUri,
    }),
  });
  const data = (await tokenRes.json()) as SlackOAuthResponse;

  if (!data.ok || !data.access_token || !data.team?.id || !data.authed_user?.id) {
    return NextResponse.redirect(`${origin}/settings?slack=error`);
  }

  const { error } = await supabase.from("slack_integrations").upsert({
    user_id: user.id,
    team_id: data.team.id,
    team_name: data.team.name ?? null,
    bot_token: data.access_token,
    slack_user_id: data.authed_user.id,
  });

  if (error) return NextResponse.redirect(`${origin}/settings?slack=error`);

  return NextResponse.redirect(`${origin}/settings?slack=connected`);
}
