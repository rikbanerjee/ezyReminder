# easyReminder

Reminder webapp for people balancing a corporate job with side gigs. Apple-Notes simple, but reminders are *delivered* to you (email / Slack DM / WhatsApp). Owner: Rik (rikbanerjee007@gmail.com).

**Read `PLAN.md` (product, integrations, UX), `DESIGN.md` (design system, screens, interactions — clickable prototype at `design/prototype.html`), and `MOBILE.md` (iOS/Android strategy) before making product or architecture decisions. Don't re-ask Rik for context that's in those files. UI implementation must match DESIGN.md tokens and patterns.**

## Product invariants (do not change without asking)
- Four contexts: **Work / Side Gig / Social / Shopping** — every reminder belongs to exactly one. Contexts drive default channel, color, quiet hours. (Shopping added 2026-07 — a running checklist context, not a single due-date reminder; see PLAN.md §3.1.)
- Delivery channels: email (Resend), Slack DM, WhatsApp (Twilio). Email + Slack are v1; WhatsApp v1.5.
- Orders are first-class: a reminder flagged `is_order` gains recipient/ship-by/tracking fields and appears in the **Ship Queue** view.
- Context-specific detail panels (2026-07): Work reminders can carry follow-up fields (manager, department resource, project); Side Gig reminders can carry a small initiative panel (initiative name, client/buyer). Both follow the same toggle-reveal pattern as the Order panel — see PLAN.md §3.1, DESIGN.md §4.2.
- **UI must match `design/prototype.html` and DESIGN.md exactly** — card shadows, borders, context-colored active states, and the sheet slide-up motion are not optional polish, they're the spec. If implementation and prototype disagree, the prototype wins; fix the code, not the doc.
- Shipping is behind a provider interface (`lib/shipping/provider.ts`); manual now, **Shippo** later. Don't hardcode any carrier API.
- Agent-ready: REST API (`/api/v1/*`, scoped API keys) + MCP server so Claude Cowork / OpenClaw-type agents can create/complete reminders. Agent writes tagged `created_by: 'agent:<name>'`.
- UX bar: capture a reminder in <5s via one smart-parse quick-add box (`chrono-node` for dates; `#context`, `#order`, `@channel` tokens). No mandatory fields beyond the text.

## Stack (decided — don't relitigate)
- Next.js 15 App Router + TypeScript + Tailwind + shadcn/ui, deployed on Vercel
- Supabase: Postgres + RLS, magic-link + Google OAuth auth, `pg_cron` → Edge Function minute-sweep for due reminders
- Auth is Supabase-only (magic-link + Google sign-in). No Firebase/Firestore — one identity system, RLS stays native. See PLAN.md §4.0.
- Notification adapters share one interface: `send(reminder, channel)`; delivery attempts logged in `notifications` table with retries
- PWA first (manifest, serwist service worker, share_target); **Capacitor** wrapper later if App Store/native push needed. Never a Swift/Kotlin rewrite. See MOBILE.md.

## Conventions
- Schema lives in `supabase/migrations/`; RLS by `user_id` on every table (single-user today, multi-user-safe always)
- Integrations under `lib/integrations/<channel>/`, shipping under `lib/shipping/`
- Notification sweep must be idempotent (`FOR UPDATE SKIP LOCKED`)
- Quiet hours per context are respected by every channel
- Mobile-first UI; dark mode required; context colors: Work=blue, Side Gig=amber, Social=green, Shopping=purple

## Roadmap position
Phases in PLAN.md §6. Nothing is built yet — start at Phase 0 (scaffold) when Rik says go.
