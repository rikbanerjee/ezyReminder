# Build Prompt — Native Google Sign-In (alongside the existing OAuth redirect)

Paste everything below into your coding agent.

---

Read `CLAUDE.md` and `PLAN.md` §4.0 (Auth) first — Auth is Supabase-only (magic-link + Google), don't relitigate that. This prompt adds a **second** Google sign-in path; it does not replace the first one yet.

## Why

The current Google button (`app/(auth)/login/page.tsx`, `handleGoogleSignIn`) calls `supabase.auth.signInWithOAuth({ provider: "google" })`, which redirects the browser to Google and back through Supabase's own domain (`https://<project-ref>.supabase.co/auth/v1/callback`). Google's account-chooser screen shows that literal redirect domain ("Choose an account to continue to ojfmtxcrfmyygwfjibwk.supabase.co") — this is Google's anti-phishing UX, not a configurable label, so no branding setting fixes it.

The fix is Google Identity Services (GIS) — a client-side button/credential flow scoped to the site's own origin (no redirect through Supabase's domain at all). It returns a signed ID token directly to page JS, which gets handed to Supabase via `supabase.auth.signInWithIdToken(...)`. This is a documented, first-class Supabase Auth method, not a workaround.

## Explicit requirement: both buttons present, side by side

Do **not** remove or replace the existing `signInWithOAuth` Google button in this pass. Add the new GIS-based button as a **second, separate option** on the same login page. Label them so they're distinguishable during testing (e.g. "Continue with Google" for the existing one, "Continue with Google (new)" for the GIS one — final copy up to you, just make them visually distinct enough to A/B by eye). Once the new flow is confirmed working end-to-end in production, we'll come back and retire the old one and its now-unused redirect plumbing — that's a follow-up, not part of this task.

## Steps

### 1. Google Cloud Console (tell me what you need me to do here — you can't do this part)
On the **same** OAuth 2.0 Web Client already used for `signInWithOAuth` (don't create a new client): add these to **Authorized JavaScript origins** (not redirect URIs — this flow doesn't use one):
- `http://localhost:3001`
- the Vercel production URL (e.g. `https://ezyreminder.vercel.app`)
- any Vercel preview URL pattern you want to support (optional, can skip for now)

Also confirm the OAuth consent screen's **App name** is set to "ezyReminder" (this is what shows in the GIS popup instead of the Supabase domain).

Give me the exact Client ID value to confirm, and tell me explicitly once you've saved these in the Google Cloud Console — the app change below depends on it.

### 2. Env var
Add `NEXT_PUBLIC_GOOGLE_CLIENT_ID` to `.env.example` (with setup comment) and note in your summary that I need to add the real value to `.env.local` and Vercel's env vars. This is the same Client ID as the existing `SLACK_CLIENT_ID`-style pattern in `.env.example` — public, safe to expose, not a secret.

### 3. Load the Google Identity Services script
Use `next/script` in `app/(auth)/login/page.tsx` (or a small child component) to load `https://accounts.google.com/gsi/client` with `strategy="afterInteractive"`.

### 4. New component: `components/auth/google-native-button.tsx`
Client component that:
- On mount (once the GIS script has loaded — poll/callback for `window.google`), calls `google.accounts.id.initialize({ client_id: process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID!, callback: handleCredentialResponse })`.
- Renders the button via `google.accounts.id.renderButton(containerRef.current, { theme: "outline", size: "large", width: ... })` into a `<div ref={containerRef} />` — this is Google's own rendered button, not a custom-styled one; don't try to reskin it with our `Button` component, GIS doesn't support that.
- `handleCredentialResponse(response)`: `response.credential` is the JWT. Call:
  ```ts
  const supabase = createClient();
  const { error } = await supabase.auth.signInWithIdToken({
    provider: "google",
    token: response.credential,
  });
  ```
  On success, Supabase sets the session client-side — redirect to `/` (`router.push("/")` or `window.location.href = "/"`). On error, toast it the same way `handleGoogleSignIn` does today.

### 5. Wire it into the login page
In `app/(auth)/login/page.tsx`, add `<GoogleNativeButton />` right below (or above — your call) the existing `handleGoogleSignIn` button, inside the same `CardContent`, both visible together. Keep the existing "or" divider and email form exactly as they are.

## Acceptance criteria
- Both Google buttons render on `/login` simultaneously; neither is hidden behind a flag.
- Clicking the existing button still works exactly as before (full-page redirect through Supabase's domain, unaffected by this change).
- Clicking the new GIS button shows Google's account chooser **without** navigating away from the page (it's an inline popup/credential flow) — verify the consent screen references the app/site, not `*.supabase.co`.
- Successful sign-in via the new button lands the user on `/` with a real Supabase session (confirm via `supabase.auth.getUser()` returning the signed-in user, e.g. check the "Signed in as …" footer text on the Today screen).
- `npx tsc --noEmit` and `npx eslint .` both clean.

## Explicitly out of scope for this pass
- Removing `signInWithOAuth`, the old `handleGoogleSignIn` function, or the `/auth/callback` route — all stay untouched.
- Any change to the magic-link email flow.
- Updating PLAN.md/CLAUDE.md's Auth section — hold off until we've decided to retire the old flow; note in your summary that this doc update is pending.
