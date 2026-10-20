# ezyReminder

Reminder app (Next.js web + Flutter iOS) for people balancing a corporate job with side gigs. Apple-Notes simple, but reminders are *delivered* to you (iPhone notifications, email as fallback). Owner: Rik (rikbanerjee007@gmail.com).

**Read `PLAN.md` (product, integrations, UX), `DESIGN.md` (design system, screens, interactions — clickable prototype at `design/prototype.html`), and `MOBILE.md` (iOS/Android strategy) before making product or architecture decisions. Don't re-ask Rik for context that's in those files. UI implementation must match DESIGN.md tokens and patterns.**

## Product invariants (do not change without asking)
- Four contexts: **Work / Side Gig / Social / Shopping** — every reminder belongs to exactly one. Contexts drive default channel, color, quiet hours. (Shopping added 2026-07 — a running checklist context, not a single due-date reminder; see PLAN.md §3.1.)
- Delivery channels: **iOS notifications** (hybrid — on-device local notifications scheduled by the Flutter app + APNs push from the server sweep, deduped so a reminder fires once) and **email** (Resend) as the fallback. WhatsApp (Twilio) stays a v1.5 stub. **Slack was removed 2026-10** — don't reintroduce it. See MOBILE.md §3.
- Orders are first-class: a reminder flagged `is_order` gains recipient/ship-by/tracking fields and appears in the **Ship Queue** view.
- Context-specific detail panels (2026-07): Work reminders can carry follow-up fields (manager, department resource, project); Side Gig reminders can carry a small initiative panel (initiative name, client/buyer). Both follow the same toggle-reveal pattern as the Order panel — see PLAN.md §3.1, DESIGN.md §4.2.
- **Two clients, one backend (2026-10):** Next.js web app + Flutter iOS app both talk to Supabase directly under RLS. A reminder created on one is visible/editable on the other; both subscribe to Supabase Realtime. Conflicts: **last edit wins** for now. Multi-step writes live in Postgres RPCs so both clients behave identically. See MOBILE.md §2.
- **UI must match `design/prototype.html` and DESIGN.md exactly** (both clients) — card shadows, borders, context-colored active states, and the sheet slide-up motion are not optional polish, they're the spec. If implementation and prototype disagree, the prototype wins; fix the code, not the doc.
- Shipping is behind a provider interface (`lib/shipping/provider.ts`); manual now, **Shippo** later. Don't hardcode any carrier API.
- Agent-ready: REST API (`/api/v1/*`, scoped API keys) + MCP server so Claude Cowork / OpenClaw-type agents can create/complete reminders. Agent writes tagged `created_by: 'agent:<name>'`.
- Add (revised 2026-10-19, later the same day): the docked bar is a tap-anywhere trigger, never an inline parser. **Today** opens "What would you like to add?" (Work · Side Gig · Home · Social · Shopping), a doorway into the existing organized forms: Side Gig's Task/Order/Follow-up/Expected payment, Home's sections and categories, the Work/Social reminder form, and the Shopping checklist. Each saves through the same atomic RPC as its destination; confirmation offers View. **All** keeps the minimal capture sheet (title, blank context, optional time). Home is a destination, not a context. Tap a saved Side Gig task/order from either list to open the canonical Side Gig editor. See DESIGN.md §5.1. The unused token parser remains available for possible reuse.

## Stack (decided — don't relitigate)
- Next.js 15 App Router + TypeScript + Tailwind + shadcn/ui, deployed on Vercel
- Supabase: Postgres + RLS, magic-link + Google OAuth auth, `pg_cron` → Edge Function minute-sweep for due reminders
- Auth is Supabase-only (magic-link + Google sign-in, plus **Sign in with Apple** — required by App Store guideline 4.8 once the iOS app offers Google). No Firebase/Firestore — one identity system, RLS stays native. See PLAN.md §4.0.
- Notification adapters share one interface: `send(reminder, channel)`; delivery attempts logged in `notifications` table with retries
- Web: Next.js PWA stays (manifest, serwist, share_target) for browser users.
- iOS: **Flutter** app in `mobile/` (decided 2026-10, replaces the earlier Capacitor plan); Android later from the same Flutter project. Apple-only features (Foundation Models, Share Extension, widgets) are thin Swift targets bridged via Pigeon — no full SwiftUI rewrite. See MOBILE.md.

## Conventions
- Schema lives in `supabase/migrations/`; RLS by `user_id` on every table (single-user today, multi-user-safe always)
- Migrations **0001–0018 are applied to hosted Supabase** (0018 Side Gig applied 2026-10-19). They are immutable: never edit or reapply them. Add database changes in the next unused migration number, starting with 0019.
- Integrations under `lib/integrations/<channel>/`, shipping under `lib/shipping/`; Flutter app under `mobile/`
- Notification sweep must be idempotent (`FOR UPDATE SKIP LOCKED`)
- Quiet hours per context are respected by every channel
- Mobile-first UI; dark mode required; context colors: Work=blue, Side Gig=amber, Social=green, Shopping=purple

## Roadmap position
Phases in PLAN.md §6; current status in LAUNCH.md §0. Web app phases 0–4 are shipped. Built locally on `ios-mvp` and backed by hosted migrations, client release pending: **Home** view (PLAN.md §9), **Focus MVP** (PLAN.md §8, contract in `FOCUS_PLAN.md`), and the Flutter iOS app (MOBILE.md §6 build order).

Next for Focus, in order (decided 2026-10-18): ship the current Focus MVP + Home; then Phase 0/1 of `FOCUS_IMPLEMENTATION_PLAN.md` (prototype, one-tap start, remembered duration); then a slim Phase 2 — in-app weekly **Focus times** with derived occurrences. Focus invitations, end alerts and alert protection wait for the Flutter notification phase.

## Agent instruction files
`AGENTS.md` is the canonical instructions file (Codex reads it; most work happens there). `CLAUDE.md` only imports it via `@AGENTS.md` — edit this file, not CLAUDE.md.

## Original brief (Claude Cowork project)
Build a simple reminder app personalized for users with weak memories.
