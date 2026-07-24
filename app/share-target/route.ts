import { NextResponse } from "next/server";

/**
 * Web Share Target landing point (MOBILE.md Stage 1, manifest.ts
 * share_target). iOS/Android hand off shared content here as GET query
 * params; we fold them into one string and prefill the quick-add box
 * rather than silently creating a reminder — same "nothing feels magical"
 * principle as typed quick-add (DESIGN.md §5.1).
 */
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const title = searchParams.get("title")?.trim() ?? "";
  const text = searchParams.get("text")?.trim() ?? "";
  const url = searchParams.get("url")?.trim() ?? "";

  const prefill = [title, text, url].filter(Boolean).join(" ").trim();

  const redirectUrl = new URL("/", origin);
  redirectUrl.searchParams.set("compose", "1");
  if (prefill) redirectUrl.searchParams.set("prefill", prefill);

  return NextResponse.redirect(redirectUrl);
}
