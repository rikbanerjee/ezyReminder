> **On hold (2026-10):** Slack has been removed and iPhone notifications now come from the Flutter app (MOBILE.md §3). Don't paste this prompt as-is; its Slack and channel-default instructions are obsolete.

# Build Prompt — ezyReminder Web Push (channel: `push`)

Paste everything below into your coding agent.

---

You are working in the **ezyReminder** repo — Next.js 15 (App Router) + TypeScript + Tailwind v4 + shadcn/ui on Supabase, deployed to Vercel. Read `CLAUDE.md`, `PLAN.md`, `DESIGN.md`, and `MOBILE.md` before making product or architecture decisions and do not re-ask for context that's in them.

**Current state:** Phases 0–2 are done. The delivery pipeline is live and working: `enqueue_due_notifications()` fans a due reminder out into one `notifications` row per channel, `claim_due_notifications()` claims them with `FOR UPDATE SKIP LOCKED`, and the Deno edge function `supabase/functions/notification-sweep/index.ts` runs every minute via pg_cron, defers on quiet hours, dispatches, and retries with exponential backoff. Email (Resend) and Slack DM adapters exist under `lib/integrations/`. A serwist service worker (`app/sw.ts`) and a web app manifest (`app/manifest.ts`) are already shipped.

**Your task:** add **Web Push as a fourth delivery channel (`push`)**, and make it the default channel for every context. Push is the free, zero-setup channel that makes the app usable for someone who doesn't live in Slack. Email stays as the reliable fallback.

## Channel strategy (this supersedes the current PLAN.md/CLAUDE.md channel ordering — update those docs as part of this task)

- **v1 channels: Web Push + Email.** Push is the default for all four contexts; email is the fallback when push isn't available or fails.
- **Slack drops to v1.5.** Do not delete the adapter, the OAuth routes, the `slack_integrations` table, or the interface — leave them working. Just stop treating Slack as a default and de-emphasize it in Settings (move it under a "More channels" disclosure).
- **WhatsApp/SMS: not planned.** Twilio costs money per message and this is a personal-scale app. Leave `lib/integrations/whatsapp/` as the stub it is; remove it from onboarding and default-channel pickers so nobody can select a channel that will never fire.

## Hard requirements & invariants (do not violate)

- **Adapters stay Node-free.** `lib/integrations/*` and `lib/quiet-hours.ts` are imported *verbatim* by both Next.js and the Deno edge function. Use only `fetch`, `Intl`, and **WebCrypto** (`globalThis.crypto.subtle`). Relative imports with explicit `.ts` extensions — no `@/` aliases, no `node:` imports, **no `npm:web-push`**. Implement VAPID and payload encryption yourself (spec below); it's ~150 lines and keeps the shared-module convention intact.
- **The sweep stays idempotent.** Reuse the existing claim/dedupe machinery. Don't add a parallel scheduler.
- **Quiet hours must be respected**, and on push they **defer, not suppress** — a reminder due inside the quiet window fires at `nextAllowedTime()`. The existing `maybeDeferForQuietHours` already does this generically; make sure push flows through it unchanged.
- **RLS by `user_id` on the new table.** Single-user today, multi-user-safe always.
- **Never schedule notifications client-side.** Service workers can't be woken on a timer and the Notification Triggers API doesn't exist. All timing comes from the server sweep. The service worker only *renders* what the server pushes.
- **UI must match `DESIGN.md` and `design/prototype.html`.** Use existing CSS variables (`surface`, `text-2`, `hairline`, `work`/`sidegig`/`social`/`shopping`, `danger`, `primary`, `muted`). Mobile-first, dark mode must work.
- **No new runtime dependencies.** Everything here is WebCrypto + the Push API.
- Keep it typed — extend the hand-written `Database`/`Channel` types in `lib/supabase/types.ts`; don't loosen to `any`.

## Platform reality to encode in the UI (don't paper over it)

- **iOS 16.4+ only supports Web Push when the app is installed to the Home Screen.** In mobile Safari, `Notification` and `PushManager` may not exist at all until installed. Detect standalone mode with `window.matchMedia("(display-mode: standalone)").matches || (navigator as any).standalone === true`.
- `Notification.requestPermission()` **must** be called from a user gesture. Never call it on mount.
- Push subscriptions are **per-device, per-browser**. A user with a phone and a laptop has two rows and should see both.
- Push endpoints expire. `410 Gone` / `404` from the push service means the subscription is dead — delete the row.

## Files to create / change

### 1. `supabase/migrations/0006_web_push.sql`

- Add `'push'` to the three channel check constraints: `contexts.default_channel`, `notifications.channel`, and any `reminders.channels` validation. Keep `'whatsapp'` allowed so existing rows don't break.
- New table `push_subscriptions`:
  - `id uuid pk default gen_random_uuid()`
  - `user_id uuid not null references auth.users(id) on delete cascade`
  - `endpoint text not null unique`
  - `p256dh text not null`, `auth text not null` (base64url, from the browser subscription)
  - `device_label text` (derived from user agent, e.g. "iPhone · Safari")
  - `created_at`, `updated_at` (with the existing `set_updated_at` trigger), `last_success_at timestamptz`, `failure_count int not null default 0`
  - index on `user_id`
  - RLS enabled; select/insert/update/delete policies all `auth.uid() = user_id`, matching the pattern in `0002_delivery.sql`.
  - Table comment pointing at this file and `lib/integrations/push/`.
- Add `user_settings.push_fallback_email boolean not null default true` — when push delivery fails or no subscription exists, enqueue an email instead.
- **Update the new-user seed trigger** (`handle_new_user_contexts`) so all four contexts seed with `default_channel = 'push'`. Add a one-time backfill for existing rows: `update contexts set default_channel = 'push' where default_channel in ('slack','whatsapp');`
- New RPC `enqueue_push_email_fallback(p_notification_id uuid)` — inserts an email `notifications` row for the same reminder at `now()`, deduped on `(reminder_id, channel, scheduled_for)` the same way `enqueue_due_notifications` does. `security definer`, `revoke from public/anon/authenticated`, `grant execute to service_role`.

### 2. `lib/integrations/push/vapid.ts` — VAPID request signing (WebCrypto only)

Export `buildVapidHeaders({ endpoint, subject, publicKey, privateKey }): Promise<{ Authorization: string }>`.

- `aud` = the scheme + host of the endpoint URL (origin only, no path). `exp` = now + 12h (seconds). `sub` = `mailto:` or `https:` subject.
- Sign the JWT with **ES256**: import the raw base64url P-256 private key as a JWK (`{ kty: "EC", crv: "P-256", d, x, y }`) via `crypto.subtle.importKey("jwk", …, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"])`, then `crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, data)`. WebCrypto returns the raw 64-byte `r||s` signature, which is exactly what JWS ES256 wants — **do not** DER-encode it.
- Header: `Authorization: vapid t=<jwt>, k=<base64url uncompressed public key>`.
- Include small base64url encode/decode helpers here (no padding, `-`/`_` alphabet) and export them for reuse.

### 3. `lib/integrations/push/encrypt.ts` — RFC 8291 `aes128gcm` payload encryption

Export `encryptPayload(payload: string, p256dhB64: string, authB64: string): Promise<Uint8Array>`. Implement exactly:

1. Generate an ephemeral P-256 ECDH keypair (`as_public` = 65-byte uncompressed raw).
2. `shared = ECDH(ephemeral_private, ua_public)` → 32 bytes via `deriveBits`.
3. `prk = HKDF-SHA256(salt = auth_secret, ikm = shared, info = "WebPush: info\0" || ua_public || as_public, len = 32)`.
4. `salt` = 16 random bytes.
5. `cek = HKDF-SHA256(salt, prk, "Content-Encoding: aes128gcm\0", 16)`; `nonce = HKDF-SHA256(salt, prk, "Content-Encoding: nonce\0", 12)`.
6. `plaintext = utf8(payload) || 0x02` (the RFC 8188 padding delimiter for a final record).
7. `ciphertext = AES-128-GCM(cek, nonce, plaintext)`.
8. Body = `salt(16) || recordSize(4, big-endian, 4096) || idLen(1) = 65 || as_public(65) || ciphertext`.

Keep payloads small — some push services cap the record at 4096 bytes. Truncate the title to 100 chars and notes to 200 before encrypting.

### 4. `lib/integrations/push/index.ts` — the adapter

Mirror the shape of `lib/integrations/email/index.ts` so the sweep's `dispatch()` reads uniformly.

```ts
export interface PushSubscriptionRecord { id: string; endpoint: string; p256dh: string; auth: string }
export interface SendPushInput {
  subscription: PushSubscriptionRecord;
  vapid: { subject: string; publicKey: string; privateKey: string };
  reminder: ReminderForDelivery;
  urgency?: "very-low" | "low" | "normal" | "high";
}
export type PushSendResult = SendResult & { gone?: boolean };
export async function sendWebPush(input: SendPushInput): Promise<PushSendResult>;
```

- Payload JSON: `{ reminderId, title, body, contextName, contextSlug, dueAt, url }` where `body` is the notes or the formatted due time, and `url` is `/?reminder=<id>`.
- POST to `subscription.endpoint` with headers `Authorization` (VAPID), `Content-Encoding: aes128gcm`, `Content-Type: application/octet-stream`, `TTL: 86400`, `Urgency: normal`, and the encrypted body.
- `201`/`200` → `{ ok: true, providerMessageId: res.headers.get("location") ?? subscription.id }`.
- `404`/`410` → `{ ok: false, error: "push_subscription_gone", gone: true }` so the caller can delete the row.
- Anything else → `{ ok: false, error: \`push ${status}: ${body.slice(0,300)}\` }`.

### 5. `scripts/generate-vapid.mjs`

Generates a P-256 keypair with WebCrypto and prints the base64url public/private keys plus the exact `.env.local` and `supabase secrets set` lines to copy. Add a `"vapid": "node scripts/generate-vapid.mjs"` npm script. Document the keys in `.env.example`:

```
NEXT_PUBLIC_VAPID_PUBLIC_KEY=   # browser-side, safe to expose
VAPID_PRIVATE_KEY=              # server + edge function only
VAPID_SUBJECT=mailto:rikbanerjee007@gmail.com
```

### 6. `supabase/functions/notification-sweep/index.ts` — wire up the channel

- Widen `NotificationRow["channel"]` to include `"push"`.
- New branch in `dispatch()`:
  - Load all `push_subscriptions` for the user. **No rows** → `{ ok: false, error: "push_no_subscription" }`.
  - Send to every subscription in parallel. Delete any row that comes back `gone`.
  - Success if **at least one** subscription accepted. `providerMessageId` = the first success.
- After a **terminal** push failure (attempts exhausted, or `push_no_subscription`), if `user_settings.push_fallback_email` is true, call `enqueue_push_email_fallback(notification_id)`. Do this exactly once — guard on the dedupe in the RPC, not on edge-function state.
- Read `VAPID_PRIVATE_KEY` / `NEXT_PUBLIC_VAPID_PUBLIC_KEY` / `VAPID_SUBJECT` from `Deno.env`; if unset, return `push_not_configured` (same shape as `resend_not_configured`).
- Don't touch the quiet-hours or retry logic — push inherits both for free.
- Update `CRON_SETUP.md` with the new secrets.

### 7. `app/sw.ts` — push + notificationclick handlers

Add listeners **alongside** `serwist.addEventListeners()` (don't replace it):

- `push`: parse `event.data.json()` defensively (fall back to a generic "Reminder" body if it isn't JSON). `showNotification(title, { body, tag: reminderId, renotify: true, icon: "/icon-192.png", badge: "/icon-192.png", data: { reminderId, url }, actions: [{ action: "done", title: "Done" }, { action: "snooze", title: "Snooze 1h" }], requireInteraction: false })`. `tag: reminderId` is what stops a retried reminder from stacking up three banners. **Note:** iOS ignores `actions` and renders a plain banner — that's expected, don't try to work around it.
- `notificationclick`: `notification.close()`, then
  - `done` / `snooze` → `fetch("/api/push/action", { method: "POST", credentials: "include", body: JSON.stringify({ reminderId, action }) })`
  - default → focus an existing client on the origin if one exists, else `clients.openWindow(url)`.
- `pushsubscriptionchange`: re-subscribe with the same `applicationServerKey` and POST the new subscription to `/api/push/subscribe`. Best-effort — swallow failures.

Wrap each in `event.waitUntil(...)`.

### 8. API routes

- `app/api/push/subscribe/route.ts` — `POST` upserts on `endpoint` (`user_id`, `p256dh`, `auth`, `device_label` from the UA header), `DELETE` removes by endpoint. Auth via `lib/supabase/server.ts` so RLS applies. 401 if no user.
- `app/api/push/test/route.ts` — `POST` sends a "Test reminder from ezyReminder" push to that user's subscriptions right now, bypassing the queue. Returns per-device success/failure so Settings can show which device worked.
- `app/api/push/action/route.ts` — `POST { reminderId, action: "done" | "snooze" }`. Reuses the existing `completeReminder` / `snoozeReminder` logic (extract shared helpers out of `app/actions.ts` rather than duplicating the queries). Same-origin only; RLS scopes the write. Returns 204.

### 9. `lib/push-client.ts` + `components/settings/push-settings.tsx`

Client helper `lib/push-client.ts`:

- `pushSupport()` → `{ supported, needsInstall, permission }`. `needsInstall` is true on iOS Safari when not in standalone display mode.
- `subscribeToPush()` — requests permission (caller guarantees it's inside a gesture), gets the SW registration, `registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(NEXT_PUBLIC_VAPID_PUBLIC_KEY) })`, POSTs to `/api/push/subscribe`.
- `unsubscribeFromPush()` — `subscription.unsubscribe()` + `DELETE`.

Settings section, following existing `settings-view.tsx` card patterns:

- A single primary toggle: **"Push notifications on this device."**
- State-specific copy, all one line, no jargon:
  - not supported → "This browser doesn't support push notifications. You'll still get reminders by email."
  - `needsInstall` → "Add ezyReminder to your Home Screen (Share → Add to Home Screen) to turn on push." Reuse the existing `components/install-nudge.tsx` visual language.
  - `permission === "denied"` → "Notifications are blocked in your browser settings. Email will keep working."
  - enabled → list this device plus any other registered devices with `device_label` and last-success time, each removable.
- **"Send a test"** button, enabled once subscribed — this is the trust-builder, don't skip it.
- A **"Also email me if push doesn't reach you"** switch bound to `user_settings.push_fallback_email`, default on.
- Move Slack into a collapsed "More channels" disclosure. Remove WhatsApp from the picker entirely.

### 10. Onboarding + context defaults

- Add a push-permission step to `components/onboarding/onboarding-view.tsx` — after the contexts step, one screen: why push, the enable button (gesture!), and a prominent **Skip** (email still works). On iOS-not-installed, show the Add-to-Home-Screen instruction instead of a dead button.
- Default-channel pickers (settings + reminder sheet) offer **Push** and **Email** only; Slack appears only if the user has connected it.

### 11. Docs — update, don't leave stale

- `CLAUDE.md`: rewrite the delivery-channels invariant to "Web Push + email are v1; Slack v1.5; WhatsApp not planned (cost)." Note that push requires Home Screen install on iOS.
- `PLAN.md §4.1`: document the push adapter, VAPID env vars, the `push_subscriptions` table, and the email-fallback path.
- `MOBILE.md`: under Stage 1, replace the "bonus layer" framing of Web Push — it's now the primary channel. Add a line that **local scheduled notifications and geofencing remain Stage 2 (Capacitor) only**, since neither is reachable from a PWA.
- `app/manifest.ts`: description is currently "Reminders that reach you — email, Slack, or WhatsApp." Change to "Reminders that actually reach you."

## Verify before you call it done

1. `npm run build` and `npm run lint` clean.
2. `deno check supabase/functions/notification-sweep/index.ts` — the shared `lib/` imports must still resolve with zero Node APIs.
3. Desktop Chrome: enable push in Settings → "Send a test" → banner appears → clicking it focuses the app; "Done" marks the reminder complete without opening a window.
4. Create a reminder due in 2 minutes with channel `push` → the sweep delivers it once, and the `notifications` row lands in `sent`. Re-run the sweep manually → no duplicate banner (this is the idempotency check).
5. Set a context's quiet hours to cover now → a due push is **deferred** (`status` back to `pending`, `scheduled_for` bumped to the window end), not dropped.
6. Delete the subscription row and let a push fire → `push_no_subscription` → an email notification row appears and delivers.
7. iOS: install to Home Screen, enable, send a test. Confirm the pre-install state shows the Add-to-Home-Screen copy rather than a broken toggle.
8. Confirm nothing regressed: email and Slack still deliver on their existing paths.

Work in small commits, one per numbered section where practical.
