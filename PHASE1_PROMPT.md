# Build Prompt — easyReminder Phase 1 (Today screen)

Paste everything below into your coding agent.

---

You are working in the **easyReminder** repo — a Next.js 15 (App Router) + TypeScript + Tailwind v4 + shadcn/ui reminder app on Supabase, deployed to Vercel. Read `CLAUDE.md`, `PLAN.md`, `DESIGN.md`, and `MOBILE.md` before making product or architecture decisions and do not re-ask for context that's in them.

**Current state:** Phase 0 (scaffold) is complete — Supabase magic-link + Google auth, the full schema in `supabase/migrations/0001_init.sql` (contexts, reminders, orders, notifications, api_keys, all with RLS by `user_id`, plus a trigger that seeds Work/Side Gig/Social contexts per user), design tokens in `app/globals.css`, and shadcn components in `components/ui/`. The home page `app/page.tsx` is a temporary placeholder that just lists the user's contexts.

**Your task:** Build **Phase 1 — the Core loop / Today screen** per `PLAN.md §5.2` and `DESIGN.md §4.1`. Replace the placeholder home with the real reminder list: a smart quick-add box, context filter pills, and Overdue / Today / Upcoming / Someday / Done-today sections with complete, reopen, snooze, and delete. No delivery/cron yet (that's Phase 2) — persist `channels` but don't send anything.

## Hard requirements & invariants (do not violate)

- Every reminder belongs to exactly one context (Work=blue, Side Gig=amber, Social=green). Context drives the default channel shown.
- Capture a reminder in under 5s via **one** smart-parse quick-add box. No mandatory fields beyond the text. Use `chrono-node` (already a dependency) for dates and `#context` / `#order` / `@channel` tokens.
- Match `DESIGN.md` tokens and patterns exactly. Use the CSS variables already defined in `app/globals.css`: `surface`, `text-2`, `hairline`, `work`/`sidegig`/`social`, `danger`, `primary`, `muted`, `foreground`, `background`. Mobile-first, single column, dark mode must work (it's driven by the existing `ThemeProvider`).
- RLS stays intact: all data access goes through `lib/supabase/server.ts` (server components / actions) — never bypass it. Reads are naturally user-scoped by RLS; every write sets `user_id`.
- **Timezone:** the server runs UTC. Do all date bucketing and relative-time formatting **on the client** in the browser's local timezone. Fetch raw timestamps server-side, group client-side.
- Keep it typed. `lib/supabase/types.ts` has hand-written `Database` types — reuse `Channel`, `ReminderStatus`, etc. Don't loosen to `any`.
- Available deps already installed: `chrono-node`, `sonner` (Toaster is already mounted in `app/layout.tsx`), `lucide-react`, `radix-ui`, `next-themes`. Don't add new dependencies.

## Files to create / change

### 1. `lib/parse/quick-add.ts` — smart-parse (pure, client-safe)
Export `parseQuickAdd(raw: string, contexts: {slug,name}[]): ParsedQuickAdd` returning `{ title, dueAt: Date|null, contextSlug: string|null, isOrder: boolean, channels: Channel[], hasDate: boolean }`.
- Strip `@email|@slack|@whatsapp` (plus aliases `mail`, `wa`, `text`) → `channels`.
- Strip `#order`/`#ship` → `isOrder=true`; other `#token` → match against context slugs, context names (spaces removed), and aliases (`work`/`job`; `side`/`sidegig`/`gig`/`etsy`; `social`/`life`/`personal`) → `contextSlug`. Unknown `#tags` stay in the title.
- `chrono.parse(text, new Date(), { forwardDate: true })`; take the first result for `dueAt` and remove its matched text from the title. Collapse extra whitespace.

### 2. `lib/dates.ts` — client-side date helpers
- `bucketFor(due: Date|null, now?): 'overdue'|'today'|'upcoming'|'nodate'` — overdue = past; today = before local midnight tomorrow; else upcoming; null = nodate.
- `relativeDue(due, now?)`: compact chip — `in 12m`, `in 3h`, `Tomorrow 9 AM`, `Tue 6:00 PM`, `2h overdue`. Same-day uses relative, otherwise absolute; caller applies danger styling.
- `snoozeTarget('1h'|'tonight'|'tomorrow'|'nextweek', now?): Date` — 1h = +1 hour; tonight = 7pm (next day if past); tomorrow/nextweek = 9am.

### 3. `app/actions.ts` — server actions (`"use server"`)
Keep existing `signOut`. Add, each returning `{ok:true} | {ok:false,error}` and calling `revalidatePath("/")` on success, guarded by a `requireUser()` helper that redirects to `/login` if no user:
- `createReminder(input: {title, dueAt: string|null, contextSlug: string|null, isOrder: boolean, channels: Channel[]})` — trim/validate title; resolve context by slug else fall back to `sidegig` else first context; insert with `created_by: 'ui'`.
- `completeReminder(id)` → status `done`, clear `snoozed_until`.
- `reopenReminder(id)` → status `open`, clear `snoozed_until`.
- `snoozeReminder(id, until: string)` → status `snoozed`, set `snoozed_until`.
- `deleteReminder(id)` → delete row.

### 4. `components/home/` — client components
- `types.ts`: `HomeContext`, `HomeReminder` (with resolved `context: HomeContext|null`), and `effectiveDue(r)` = `new Date(snoozed_until ?? due_at)` or null. A snoozed reminder surfaces at its snooze target.
- `quick-add.tsx`: input that runs `parseQuickAdd` live and renders parsed **chips** (context dot+name, due, Order 🚚, channel icons) below before saving so nothing feels magical. Submit calls `createReminder` inside `useTransition`, clears + refocuses on success, toasts on error. Placeholder should demo the syntax, e.g. `Add a reminder — try "ship mug order tue 6pm #sidegig @whatsapp"`.
- `reminder-row.tsx`: 52px-ish row — context-colored **completion ring** (tap to complete → filled with check, `navigator.vibrate(10)` where supported; done rows are strikethrough and tap to reopen), title (17/600, truncated), second line (`relativeDue` in `danger` when overdue · context name), right meta (🚚 if order, channel glyphs at 40% opacity — explicit channels else the context default). A snooze button reveals a small menu: 1 hour / Tonight / Tomorrow / Next week + Delete. Use lucide icons (`Check`, `Truck`, `AlarmClock`, `Trash2`, `Mail`, `MessageSquare`, `MessageCircle`).
- `home-view.tsx`: receives `contexts`, `reminders` (open+snoozed), `doneToday`. Holds the active-context filter (All + one pill per context, colored dots; pill style = filled `foreground/background` when active) and a collapsed "Done today" toggle. Buckets `reminders` via `bucketFor(effectiveDue(r))`, sorts each dated bucket ascending, renders sections **Overdue** (danger header) / **Today** / **Upcoming** / **Someday**, each a rounded `surface` card of rows with `divide-hairline`. Friendly one-line empty state when nothing matches.

### 5. `app/page.tsx` — server component
Keep the header (title + Sign out form). Fetch contexts (`id, slug, name, color, default_channel`) and build an id→context map. Fetch active reminders (`status in ('open','snoozed')`, order by `due_at`) and done reminders (`status='done'`, `updated_at >= now-48h`, desc). Map rows to `HomeReminder` (resolve context, default `channels` to `[]`). Render `<HomeView …/>`. Container: `max-w-md`, mobile-first padding.

## Acceptance criteria
- Logging in shows the Today screen (not the contexts placeholder).
- Typing `ship mug order tue 6pm #sidegig @whatsapp` shows chips for Side Gig, the parsed date, Order, and WhatsApp; saving creates a reminder that lands in the right section under the right context with a 🚚.
- Complete/reopen, snooze (all four presets), delete, and context filtering all work and reflect immediately (server action + `revalidatePath`).
- Overdue items show red relative time; "Done today" is collapsed by default.
- Dark mode renders correctly; layout is clean on a phone-width viewport.

## Verify before finishing
Run `npx tsc --noEmit` and `npx eslint .` — both must be clean (no `any`, no unused vars). Do a quick runtime check of `parseQuickAdd` against a handful of inputs (with/without dates, each token type) to confirm chrono extraction and title stripping. Note: `next build` may need network to fetch the SWC binary — if it can't, rely on tsc + eslint + `npm run dev`.

## Notes
- The `reminders` table already exists in `supabase/migrations/0001_init.sql`; if it isn't applied to the live project yet, apply the migration (`supabase db push` or the SQL editor) before testing writes.
- Do NOT build delivery, the cron sweep, the Ship Queue, the detail bottom-sheet, or the REST/MCP API — those are later phases. Keep this to the Today list loop.
