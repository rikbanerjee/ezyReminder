# Build Prompt — UX parity + context detail fields + Shopping context

Paste everything below into your coding agent.

---

You are working in the **ezyReminder** repo. Read `CLAUDE.md`, `PLAN.md`, `DESIGN.md`, and `MOBILE.md` first — they were just updated (2026-07) to reflect this work, so re-read them even if you've read them before in this project. `design/prototype.html` is the visual and interaction reference; open it and compare side-by-side with the running app before touching code.

**Context for why this prompt exists:** the shipped app has drifted from `DESIGN.md`/the prototype in specific, identifiable ways — this isn't "make it feel nicer," it's "match the spec that already exists." Work phase by phase below. After each phase: `npx tsc --noEmit` and `npx eslint .` must be clean, then stop and let me review before starting the next phase.

## Phase A — Visual parity (shadows, borders, colors, motion)

Confirmed gaps between the running app and `design/prototype.html` / `DESIGN.md §2`:

1. **No shadow tokens exist.** `app/globals.css` defines color/radius tokens but zero shadow tokens. `DESIGN.md §2` now specifies `--shadow-card`, `--shadow-sheet`, `--shadow-float` with exact values (light + dark) — add them as CSS custom properties and Tailwind utilities (`shadow-card`, `shadow-sheet`, `shadow-float`) in `@theme inline`.
2. **List cards have borders but no shadow.** `components/home/home-view.tsx` renders section cards as `rounded-xl border border-hairline bg-surface` with no shadow class at all — that's why the app looks flat next to the prototype's `.card{box-shadow:...}`. Add `shadow-card` to every section-card div (the three places in `home-view.tsx`: main sections, Ship soon, Done today).
3. **The detail sheet uses a generic shadow and has no motion.** `components/home/reminder-sheet.tsx` uses Tailwind's default `shadow-xl` and toggles visibility with plain conditional rendering — no slide-up transition, no drag-to-dismiss. Prototype uses a 300ms `cubic-bezier(0.32,0.72,0,1)` slide-up with a fading scrim. Implement this with CSS transitions (translate-y + opacity) — mount the sheet always, toggle an `open` class/state, transition `transform` and the scrim's `opacity`. Swap `shadow-xl` for the new `shadow-sheet` token.
4. **Active context pill is monochrome, should be context-colored.** In `home-view.tsx`'s `FilterPill`, the active state is `bg-foreground text-background` regardless of which context is selected. Prototype: active pill background = the context's own color (`.pill.active[data-ctx="work"]{background:var(--work)}` etc.), with white text. "All" active state can stay neutral (`bg-foreground`).
5. **Quick-add bar isn't docked.** Prototype docks the quick-add bar above a bottom tab bar (`position:absolute; bottom:0`) with a `shadow-float`. The current app renders `<QuickAdd>` inline in the scroll flow inside `home-view.tsx`. Make it `sticky bottom-0` (or `fixed` within the mobile-width container) with safe-area bottom padding (`env(safe-area-inset-bottom)`) and `shadow-float`, so it stays reachable while scrolling — this matters more once Phase B makes it a real text input.
6. **No bottom tab bar.** `app/page.tsx`'s header has Ship Queue and Settings as small icon links; `DESIGN.md §3` specifies a persistent 3-tab bottom bar (Today / Ship Queue / All) with a badge on Ship Queue. Add a `components/tab-bar.tsx` fixed to the bottom (below the quick-add dock) with the three tabs; keep Settings reachable via the header gear icon as today. An "All" tab/screen doesn't exist yet — for now it can route to `/` with no context filter pre-applied and reuse `HomeView`'s list rendering with a search box added on top (small addition, not a new screen architecture).

Do **not** attempt swipe-to-complete/swipe-to-snooze gestures in this phase — that's a larger interaction change; the existing tap-ring + alarm-clock-menu pattern for complete/snooze stays as is for now.

## Phase B — Fix the reminder-creation flow (root cause of the "missed title" bug)

**Root cause of the bug you reported:** `components/home/quick-add.tsx` was rewritten at some point into a button that opens `reminder-sheet.tsx` as a full form — not the inline text input with live parse chips that `DESIGN.md §5.1` and the prototype specify. That's why title feels like a separate mandatory field you can miss: it's now a distinct input in a modal, not the text you just typed. `reminder-sheet.tsx` line ~330 has `disabled={pending || !title.trim()}` with zero visual feedback when disabled — a dead-end button, not validation.

**Fix — restore the inline quick-add as the primary creation path:**
1. Rewrite `components/home/quick-add.tsx` back into a real `<input>` (not a button-that-opens-a-sheet). Reuse the existing `lib/parse/quick-add.ts` (`parseQuickAdd`) which already supports `#context`/`#order`/`@channel` tokens and `chrono-node` dates — confirm it also recognizes `#shopping` after Phase E adds that context.
2. Render live parse chips below the input as the user types (context dot+name, due date, 🚚 Order, channel icons) exactly like the prototype's `.chips` — remove/add chips as parsing changes.
3. On Enter with non-empty text: call `createReminder` (already exists in `app/actions.ts`) directly — no sheet, no modal. Clear the input, keep focus, toast "Added ✓". On Enter with empty/whitespace-only text: do nothing destructive — just a brief shake animation on the input (CSS keyframe, ~150ms) so it's obvious why nothing happened. There's no "missing title" state to hit anymore because the typed text *is* the title.
4. If the reminder was created with `isOrder` true (or, after Phase C/D, a context that has an optional detail panel), toast an offer exactly like the prototype: **"Added ✓ — add order details?"** / **"Add follow-up details?"** / **"Add initiative details?"** with an action button that opens `reminder-sheet.tsx` pre-scrolled to that panel. This is how the sheet still gets used for creation — as an optional next step, never the first step.
5. Keep `reminder-sheet.tsx` fully in place for **editing** an existing reminder (tapping a row) — that flow is correct as is. Just fix its validation UX: if `title` is empty when Save/Add is attempted (only reachable now via editing, since creation no longer goes through the sheet), show a red outline on the title input plus a one-line message ("Title required") instead of silently disabling the button. Apply this same visible-validation pattern anywhere else in the sheet a save could currently fail silently.

**Acceptance for Phase B:** typing `ship mug order fri 5pm #gig #order @email` in the quick-add bar and hitting Enter creates the reminder with zero modal in between — chips appear live, Enter commits, a follow-up toast offers the order panel. Hitting Enter with an empty box does nothing but a visible shake — never a confusingly inert button.

## Phase C — Work context: follow-up details panel

Schema (add as a new migration, e.g. `supabase/migrations/0003_context_panels.sql` — do not edit already-applied migrations):
```sql
create table work_details (
  reminder_id uuid primary key references reminders(id) on delete cascade,
  manager_name text,
  department_resource text,
  project_name text,
  updated_at timestamptz not null default now()
);
alter table work_details enable row level security;
-- policy: user can access their own via the parent reminder's user_id (same join pattern as orders — check lib/orders.ts / the orders RLS policy in 0001_init.sql for the exact pattern used there and mirror it)
```
In `reminder-sheet.tsx`, when the selected reminder's context is Work, show a toggle **"Add follow-up details"** (same visual pattern as the existing `isOrder` toggle — reuse that component structure) revealing: Manager name, Department resource, Project name (3 text inputs, `Field` helper already exists in the file). Add `updateWorkDetails` server action in `app/actions.ts` mirroring `updateOrderDetails`. Fetch and pass work details into `HomeReminder` the same way `order` is currently fetched via `lib/orders.ts` (add an equivalent `lib/work-details.ts` + `fetchWorkDetailsMap`).

This panel and the Order panel are mutually exclusive in the UI (a reminder is either an order or has follow-up details, not both) — the toggle should only appear when `context.slug === 'work'`, same way the Order toggle currently appears unconditionally but should really be scoped too (fix that while you're in here: the Order toggle makes most sense for Side Gig; leave it visible for all contexts since orders can theoretically belong to any context, per existing behavior — don't change that part).

## Phase D — Side Gig context: initiative details panel

Same pattern as Phase C, smaller: `sidegig_details(reminder_id pk fk, initiative_name text, client_name text, updated_at)`. Toggle **"Add initiative details"** shown only when `context.slug === 'sidegig'` and `isOrder` is false (this panel is for non-order side-gig work; order-flagged reminders already get the Order panel — don't show both). 2 fields: Initiative name, Client/buyer.

## Phase E — New Shopping context + checklist items

This is the largest addition — a context that behaves differently from the other three.

1. **Seed the context.** Find the trigger/function in `0001_init.sql` that seeds Work/Side Gig/Social per new user (`CLAUDE.md` mentions this exists) and add Shopping: color `#AF52DE` light / `#BF5AF2` dark (per updated `DESIGN.md §2`), slug `shopping`, sensible default channel (use `email` or make delivery optional — see below).
2. **Schema:** `shopping_items(id uuid pk default gen_random_uuid(), reminder_id uuid fk -> reminders on delete cascade, label text not null, checked boolean not null default false, position int not null, created_at timestamptz default now())`, RLS scoped through the parent reminder.
3. **Server actions:** `addShoppingItem(reminderId, label)`, `toggleShoppingItem(itemId, checked)`, `deleteShoppingItem(itemId)`, `reorderShoppingItems` (optional, skip if it adds too much complexity — position can just be append-order for v1). Each is a single instant write, no batch save.
4. **UI:** when `reminder-sheet.tsx` opens a reminder whose context is Shopping, render the checklist layout from `DESIGN.md §4.2.1` instead of the normal title/date/notes/channels layout: an always-focused "Add item…" input that appends on Enter (optimistic — show the item immediately, reconcile on server response), each item a row with a checkbox (strikethrough label when checked) and a delete affordance (✕ button, or swipe — button is fine for v1). No Save button needed for items themselves; the sheet's existing Close is sufficient.
5. **Today-list row treatment:** in `reminder-row.tsx`, when `reminder.context?.slug === 'shopping'`, replace the due-chip meta line with **"N items left"** (count of unchecked `shopping_items`) — you'll need to include an item count in the `HomeReminder` type/fetch, similar to how `order` is attached today.
6. **Bucketing:** Shopping reminders with no `due_at` should land in the "Someday" bucket (this should already work if `bucketFor(null)` returns `'nodate'` — confirm, don't assume).
7. **Quick-add:** confirm `#shopping` (and reasonable aliases: `shop`, `groceries`) resolves to the Shopping context in `lib/parse/quick-add.ts`'s context-token matching.

**Acceptance for Phase E:** typing `Costco run #shopping` in quick-add creates a Shopping reminder; opening it shows an empty checklist with a focused input; typing "Paper towels" + Enter adds it instantly with no save step; checking it off strikes it through; the Today list shows "1 item left" instead of a date.

## General rules for all phases
- Match `DESIGN.md` tokens exactly — reuse existing CSS variables, don't invent new ad hoc colors/shadows.
- Keep everything typed; extend `lib/supabase/types.ts`'s `Database` type for the three new tables rather than using `any`.
- RLS on every new table, scoped through the parent reminder's `user_id` — mirror the exact pattern already used for `orders` (read that policy before writing new ones).
- Don't touch the Slack/email/WhatsApp delivery pipeline, the notification sweep, or auth in this pass — out of scope.
- If something here conflicts with what you find in the code (e.g., a helper already exists under a different name), use the existing one and tell me in your summary rather than duplicating it.
