# ezyReminder — Design Spec (web + Flutter iOS)

Companion to PLAN.md §5. This is the buildable spec: tokens, components, and screen-by-screen behavior. **It applies to both clients**: the Next.js web app and the Flutter iOS app (MOBILE.md §2) render from the same tokens. The Flutter mappings are `BoxShadow` for the shadows, `Cubic(0.32, 0.72, 0, 1)` for the sheet curve, `DraggableScrollableSheet` for the sheet, and `HapticFeedback` in place of `navigator.vibrate`. A clickable prototype lives at `design/prototype.html` — open it in a browser (narrow window or phone) to feel the interactions.

## 1. Design goals

1. **Feels installed, not visited.** No browser-y chrome, no page reloads, thumb-first layout, spring animations, safe-area aware.
2. **One-hand operation.** Everything important lives in the bottom 60% of the screen: quick-add bar docked above the keyboard, bottom sheets instead of new pages, tab bar navigation.
3. **Zero-training UI.** If you've used Apple Notes/Reminders, you already know this app.

## 2. Design tokens

### Color
| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#F7F6F3` (warm paper) | `#111113` | App background |
| `surface` | `#FFFFFF` | `#1C1C1F` | Cards, sheets, tab bar |
| `text` | `#1A1A1A` | `#F2F2F2` | Primary text |
| `text-2` | `#8A8A8E` | `#98989E` | Secondary (due chips, meta) |
| `hairline` | `#E5E4E0` | `#2C2C2E` | 0.5px separators |
| `work` | `#3478F6` | `#4C8DFF` | Work context |
| `sidegig` | `#F5A623` | `#FFB340` | Side Gig context |
| `social` | `#34C759` | `#40D66B` | Social context |
| `shopping` | `#AF52DE` | `#BF5AF2` | Shopping context |
| `danger` | `#FF3B30` | `#FF453A` | Overdue, delete |

### Shadows (explicit — do not substitute Tailwind's default `shadow-sm`/`shadow-lg`)
| Token | Value | Use |
|---|---|---|
| `--shadow-card` | `0 1px 3px rgba(0,0,0,.05)` (dark: `0 1px 3px rgba(0,0,0,.4)`) | Section list cards, quick-add bar, pills |
| `--shadow-sheet` | `0 -8px 40px rgba(0,0,0,.18)` (dark: `0 -8px 40px rgba(0,0,0,.5)`) | Bottom sheet |
| `--shadow-float` | `0 4px 20px rgba(0,0,0,.12)` (dark: `0 4px 20px rgba(0,0,0,.45)`) | Docked quick-add, floating menus |

These must exist as real CSS custom properties (`app/globals.css`) and Tailwind utilities (`shadow-card`, `shadow-sheet`, `shadow-float`), not approximated with generic `shadow-sm`/`shadow-xl` — the flat, border-only look in earlier builds came from cards using `border` with no shadow at all.

Dark mode follows the system (`prefers-color-scheme`) with a manual override in Settings. Context color is used *sparingly*: a 6px dot on rows, tinted pill when a context filter is active, tinted section accent in detail sheet. Never full-colored cards — that's what makes it feel like a toy.

### Type & spacing
- System stack: `-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, Segoe UI, Roboto, sans-serif` — free native feel on every OS.
- Scale: 28/700 (screen title), 17/600 (row title), 15/400 (notes preview), 13/500 (due chips, section headers — uppercase, letter-spaced, `text-2`).
- Spacing grid: 4px. Screen gutter 16px. Row height ≥ 52px; all touch targets ≥ 44×44px.
- Radii: rows-in-card 12px, sheets 20px (top corners), pills/chips 999px.

### Motion (the native tell)
- Sheets: slide up 300ms `cubic-bezier(0.32, 0.72, 0, 1)` (Apple's sheet curve), dimmed scrim 40%.
- Row complete: checkbox fills with a 200ms pop (scale 1 → 1.15 → 1), row fades + collapses 250ms, then count badges update.
- Context switch: list cross-fades 150ms; active pill slides with a spring.
- Everything under 300ms; `prefers-reduced-motion` disables all of it.

## 3. App shell

```
┌─────────────────────────────┐
│ Today                    ⚙︎ │  ← large title, collapses to 17pt on scroll
│ [All] [Work] [Gig] [Social] │  ← context pills, horizontally scrollable
│ ─────────────────────────── │
│                             │
│        (screen content)     │
│                             │
│ ─────────────────────────── │
│  ⊕ Remind me to…            │  ← quick-add bar, docked bottom
│ ▣ Today   🚚 Ship   ☰ All   │  ← tab bar (3 tabs), safe-area padded
└─────────────────────────────┘
```

- **Tab bar:** Today (default), Ship Queue (badge = orders due ≤ 3 days), All/Browse. Settings is the gear in the header — not worth a tab.
- **Quick-add bar** is persistent on Today and All tabs; on tap it expands upward into the composer (see §5.1). This is the app's center of gravity.

## 4. Screens

### 4.1 Today (home)
Sections in order, each a rounded `surface` card of rows:

1. **Overdue** — red section header with count; due chips in `danger`.
2. **Today** — sorted by due time; all-day items last.
3. **Ship soon** — appears only if orders have `ship_by` ≤ 3 days; rows show 🚚 + countdown; header links to Ship Queue tab.
4. **Upcoming** — next 7 days, grouped by day label (Tomorrow, Wed…).
5. **Done today** — collapsed by default, count in header, tap to expand.

**Row anatomy** (52px, single line + optional second line):
```
(○)  Ship mug order to Portland          🚚  ✉ ⧉
 │   in 2h · Side Gig                             
 └ 22px tap-to-complete ring, context-colored
```
- Left: completion ring (context color outline → filled on complete).
- Title 17/600, one line, ellipsized.
- Second line 13px `text-2`: relative due ("in 2h", "Tue 6pm", red "2h overdue") · context name.
- Right meta: 🚚 if order, channel glyphs (📱 ✉ ⧉ = iPhone notification/email/WhatsApp) at 40% opacity.

**Row gestures:**
- Tap row → detail sheet (§4.2).
- Tap ring → complete (pop animation, haptic via `navigator.vibrate(10)` where supported).
- Swipe right → complete (green reveal).
- Swipe left → snooze menu reveal: **1h · Tonight · Tomorrow · Pick…**
- Long-press → context menu: Edit, Duplicate, Move context, Delete.
- Desktop fallbacks: hover reveals the same actions as inline icon buttons; keys `e` complete, `s` snooze, `n` new, `1/2/3` context filters.

### 4.2 Reminder detail — bottom sheet (never a new page)
Half-height sheet, drag handle, drag up for full height, drag down or scrim-tap to dismiss.

```
━━━ (handle)
Title (inline-editable, 20/600)
[● Side Gig ▾]  [Tue 6:00 PM ▾]  [Repeat: off ▾]
Notes… (grows)
DELIVER VIA   📱 iPhone [on]  ✉ Email [on]  ⧉ WhatsApp [off]
              Quiet hours: 9pm–8am (from context) · Override ↗
🚚 THIS IS AN ORDER  [toggle]
   ┌ order panel (slides open when on) ─────────┐
   │ Order ref  [Etsy #1042        ]            │
   │ Recipient  [Sarah M.          ]            │
   │ Ship by    [Fri Jul 24  ▾]                 │
   │ Carrier    [USPS ▾]   Tracking [–]         │
   │ [ Mark shipped ]                           │
   └────────────────────────────────────────────┘
(Delete)                              (Done)
```

- Every field is a tappable chip that opens a mini-picker in-sheet — no navigation stack.
- Channel toggles default from the context; changing them here affects only this reminder.
- **Mark shipped** asks for tracking inline (one field + paste button), stamps `shipped_at`, completes the reminder, and toasts "Shipped ✓ — remind me to follow up?" with a one-tap **+3d follow-up** action.

**Other context panels (same toggle-reveal pattern as Order, 2026-07):**
- **Work → "Add follow-up details"** reveals: Manager name · Department resource · Project name (3 fields, `work_details`, PLAN.md §3.1).
- **Side Gig → "Add initiative details"** reveals: Initiative name · Client/buyer (2 fields, `sidegig_details`) — deliberately lighter than Work's panel. Doesn't apply to order-flagged reminders (they use the Order panel instead).
- **Shopping** reminders skip the standard sheet layout entirely — see §4.2.1.

### 4.2.1 Shopping list (checklist, not a due-date reminder)
Opening a Shopping-context reminder shows a checklist, not the title/date/notes layout:
```
━━━ (handle)
Costco run                              (title = list name, inline-editable)
[+ Add item…]                           ← always-focused input, Enter adds
☐ Paper towels                      ⌫
☐ Coffee beans                      ⌫
☑ Dish soap  (struck through)       ⌫
```
- Every add/check/delete is its own instant write (optimistic UI, no Save button) — this list is meant to be edited standing in a store with one thumb.
- No mandatory due date; delivery channels are hidden by default (rarely relevant) but reachable via "More options" if the user wants a nag reminder to go shopping at all.
- Today-list row for a Shopping reminder shows **"N items left"** instead of a due chip; it lives in the Someday bucket unless the user sets an explicit due date.

### 4.3 Ship Queue tab
The side-gig money view. Sorted by `ship_by` ascending.

```
SHIP QUEUE (4)                    [+ New order]
┌──────────────────────────────────────────────┐
│ ⚠ Etsy #1042 · Sarah M.       SHIP BY FRI    │
│   USPS · no label yet     [Mark shipped]     │
├──────────────────────────────────────────────┤
│ Shopify #88 · Ben K.          ship by Jul 28 │
│   ...                                        │
└──────────────────────────────────────────────┘
SHIPPED THIS WEEK (2)  — collapsed
```

- Rows overdue-to-ship get the `danger` treatment.
- **Mark shipped** works inline (tracking # field expands in the row) — no sheet needed for the happy path.
- When Shippo lands, `[Mark shipped]` gains a sibling `[Buy label]`; the row layout already reserves the space. Tracking numbers become tappable → carrier page.

### 4.4 All / Browse tab
Search field (filters as you type) + the full list grouped by context, including items with no due date ("Someday" group per context). Same row component everywhere.

### 4.5 Settings (gear)
Grouped iOS-style table: **Contexts** (rename, color, default channel, quiet hours per context), **Channels** (iPhone notifications status per device, email, WhatsApp later; test-send button), **API & Agents** (API keys list, create key with scopes, MCP setup snippet, per-agent activity log), **Focus** (Focus times, §9), **Appearance** (system/light/dark), **Account** (email, sign out).

## 5. Key flows

### 5.1 Quick add — revised 2026-07 (supersedes the original inline-parse spec)
The docked quick-add bar is a **trigger, not a text field** — tapping anywhere on it (not just a "+" glyph) opens the full create sheet (§4.2, `reminder={null}` mode), per direct product feedback after the inline shorthand-parsing version shipped and proved less intuitive in practice than just filling in the same structured form used for editing. There is one creation path now: the full sheet, with the context select, `DateTimePicker` (below), and the same Order/Work/Side Gig panels as editing.

`lib/parse/quick-add.ts`'s `chrono-node`/`#context`/`@channel` token parser is no longer wired into the UI but is left in place — it's cheap to resurrect later (e.g. inside the sheet's title field, or a search box) if shorthand entry turns out to be worth reintroducing.

**Date/time — compact calendar, not the native picker.** The due-date control is a custom `DateTimePicker` (small popover: month grid with small cells, a time input, and an explicit **OK** button to confirm), not `<input type="datetime-local">` — the native OS picker was too large and had no explicit confirm step. "No date" clears it.

**Context select starts blank ("Choose template").** Creating fresh never silently defaults to an arbitrarily-sorted first context — the select's first option is a disabled "Choose template" placeholder, and attempting to save without picking one shows inline validation (same red-outline-plus-message pattern as a missing title), not a silently-disabled button.

**Validation, everywhere a Save/Add can be disabled:** a disabled button with no explanation is a dead end, not validation. If a required field is missing, the field itself shows the problem (red outline + a one-line message under it, e.g. "Title required") the moment the user tries to submit — never just a button that quietly won't click.

### 5.2 Delivery transparency
- Row meta shows channel glyphs; after a send, glyph gets a subtle ✓ underdot; on failure an amber ⚠ badge appears on the row → tap opens the notification log for that reminder (attempt times, error, **Retry now**).
- iPhone notifications come from the Flutter app (local + APNs, MOBILE.md §3); email is the fallback so a reminder is never iPhone-only.

### 5.3 Agent activity
Reminders created by agents show a tiny ✦ before the context name ("✦ via claude-cowork" in the detail sheet). Settings → API & Agents lists recent agent actions. No approval friction by default; a per-key "require confirmation for deletes" toggle exists.

## 6. Native-feel checklist (PWA specifics)

- `display: standalone`, `viewport-fit=cover`, safe-area insets on header/tab bar/quick-add.
- No rubber-band white flash: `bg` on `html`, `overscroll-behavior-y: none`.
- Tap highlight off; `touch-action: manipulation` (kills 300ms delay + double-tap zoom).
- Skeleton rows on first load (< 400ms goal); optimistic UI on every mutation (complete/snooze apply instantly, sync in background, undo toast 5s).
- Sheet drag uses `touch` events with momentum; scroll-locks the page behind.
- Share sheet target: shared text/URL prefills the composer.
- Home-screen shortcut actions: "New reminder", "Ship Queue".

## 7. Component inventory (maps to shadcn/ui)

| Component | Base | Notes |
|---|---|---|
| ReminderRow | custom | ring, swipe, meta glyphs |
| BottomSheet | `drawer` (vaul) | Apple sheet curve, drag states |
| ContextPills | `tabs` restyled | scrollable, spring indicator |
| QuickAdd | custom input | chrono-node + token parser, chip renderer |
| ShipQueueRow | custom | inline tracking field expand |
| SettingsTable | `card` + rows | iOS grouped-table look |
| Toast/Undo | `sonner` | bottom, above tab bar |
| MiniPickers | `popover`/`calendar` | date, context, repeat, carrier |

## 8. Open design questions (fine to defer)

1. Recurrence UI depth — v1 ships presets (daily / weekdays / weekly / monthly); custom rrule editor later.
2. Whether "Done today" should auto-clear at midnight or persist a 7-day history view (leaning: history lives in All tab).
3. Snooze "Tonight" definition (leaning: 6pm same day, configurable later).

## 9. Focus sessions — one-tap start, focus times (2026-10)

Focus supports existing **Work / Side Gig** reminders, including orders. It adds no context or navigation tab. Behavior and RPC contract live in `FOCUS_IMPLEMENTATION_PLAN.md` §13; **the prototype (`design/prototype.html`, Today tab, "Prototype only · Focus demo states" switcher) is the visual spec for every state below** and uses sample data only.

**Shared sheet rules.** All Focus sheets reuse the established 20px top corners, drag handle (drag down or scrim-tap or Esc to dismiss), `shadow-sheet`, 40% scrim and 300ms `cubic-bezier(0.32, 0.72, 0, 1)` slide-up. One sheet at a time; modes swap inside the open sheet (a ‹ Back in the header only where there is a parent list). Work/Side Gig colors appear only as dots, selected chips/rows (1.5px context border + 8–10% tint) and the left accent of the session focus block — never filled buttons. **Primary buttons use the existing inverse `text`-on-`bg` fill** (as Done/Save elsewhere); secondary = hairline outline; tertiary = ghost `text-2`. Touch targets ≥ 44px, fields stay above the keyboard, dark mode uses the existing tokens, reduced motion disables transitions. Timers have an accessible name and are not live regions; announce state changes (started, paused, resumed, time is up, saved), not every second. Validation follows §5.1: a visible inline message under the field on submit, never a silently disabled button.

**Today's focus card** sits after the context pills and above the dated sections, under a 13px uppercase `text-2` heading "Today's focus". Card = `surface`, 12px radius, 1px hairline border, `shadow-card`, 14px padding; context dot + name 13/600 `text-2`, title 17/600, metadata 13px `text-2`. It is not filtered by the context pills. Priority: running/paused/time-up session → chosen highlight → first planned task of the current/next occurrence → empty. Primary action is always one tap:
- **Empty:** "What would you like to move forward?" · "Choose one Work or Side Gig reminder." · **Choose a reminder** (primary) + ghost **Set my focus times**.
- **Highlight:** dot + context, ghost **Change** top-right; title; "Due Fri, Oct 23 · 4 PM" (orders: "Ship by …" — the deadline is never changed by Focus); optional inset (`bg`, 10px radius) "Next step from last time" + saved text (omitted when blank); row of primary **Start 25 min** (N = saved preference) and an adjacent small outline duration chip "25 min" that opens Setup.
- **Up next:** first line "● Up next · Saturday 9 AM" (never silently pinned), title, "Side Gig · 20 min planned · Sat, Oct 24", same inset, **Start 20 min** (the assignment's minutes) + "20 min" chip, and a ghost **Make today's focus** below (the only way to pin it).
- **Running / paused / time up:** "Work · In focus | Paused | Time is up", title, tabular 26/600 countdown (paused dims it), outline **Open session**; at zero the card says "How did it go?" and the button becomes primary **Review session**. Never auto-completes anything.

**Missed recovery card** (directly below the card, only when planned work's occurrence has passed unstarted; oldest first). Same surface as the card, calm — no red, no stack: "Didn't get to this?" with "+N more" on the right, the task, "Saturday · 9 AM · Sat, Oct 17 · 20 min planned", then a 2-column grid: primary **Start now** · **Next Saturday** (next weekday strictly after the missed date) · **Choose another time** (opens Work on this) · ghost **Leave unscheduled**. Acting reveals the next missed item.

**Your focus times** (below the cards, `section-h` with ghost **Manage ›**): one `card` of up to 3 rows for the next populated occurrences — no empty occurrences. Row: context dot, "Thursday · 7 PM" 16/600, first task + minutes ("Choose photos for mug listing · 15 min"), when several "3 tasks · 35 min planned", when over budget a quieter 12px line "35 min planned for 30 min available" (informational, no warning color); right side "Oct 29 ›". No focus times and a non-empty card → a single row **Set my focus times ›**; times but nothing planned → **Nothing planned yet · Manage ›**. Tapping a row opens the **occurrence sheet**: title "Thursday · 7 PM", "Side Gig · Thu, Oct 29 · Shop time", the same planned/over-budget lines, then an ordered list (numbered; task, "15 min · due…", "Next: …") each with primary **Start 15 min** and ghost **Skip**. Start is disabled with an explanatory note while a session is running. Footer: "Skip leaves the reminder as it is. Nothing starts on its own."

**Setup sheet** (title "Focus on this"; from the duration chip or the reminder sheet's **Focus on this**, which never replaces today's highlight): context dot + name, title, due line, "Next step from last time" inset, "How long?" chips **10 min · 25 min · 50 min · Custom** (current length selected), Custom reveals "Minutes (1–180)" with "Choose a whole number from 1 to 180 minutes."; a quiet note "Starting with 15 min saves it as your usual length." when it differs from the preference; label "What could you finish in 10–15 minutes? (optional)"; primary **Start now**. No due-date picker.

**Session sheet**: header "In focus | Paused | Time is up"; context; the task at 22/700; a focus block (3px context accent on the left, `bg`) labelled "Your focus" (intended outcome) or "Next step"; a quiet 56/300 `text-2` countdown (tabular), line "One thing at a time." / "Paused" / "Time is up. Ready to review?"; primary **❚❚ Pause** / **▶ Resume** beside outline **End session**; at zero a single primary **Review session**. Closing the sheet keeps the session alive.

**Review sheet** ("How did it go?"): context · minutes worked, task; three mutually exclusive rows **Finished what I planned / Made progress / Got interrupted** (none preselected; "Choose how the session went." on submit); a prominent 17/600 label **"Where will you start next time?"** over a 3-row textarea, helper "Optional. It appears on your card when you come back."; helper "This saves your session. Your reminder stays as it is."; primary **Save session**; ghost **Back to session** until time is up. On failure a bordered block with a `danger` left accent: "Couldn't save your session" / "Your answers are still here." + **Retry**; values are preserved. **After saving** the sheet becomes "Session saved" (green ✓, task, outcome · minutes, "Next time" inset) with stacked **Continue for 10 min** (primary), **Choose another focus time** (only when Focus times exist), **I'm done for now**; after "Finished" a separated block "Your reminder is still open. Finishing it is a separate step." with **Mark reminder done** (orders: **Mark shipped**, which opens the existing reminder sheet). The latest saved note — including a blank one — is what the card shows next.

**Work on this** (reminder sheet → FOCUS row with **Focus on this** and **Work on this** side by side, and a one-line state: "Planned: Thursday · 7 PM · 15 min" / "Not planned yet"; Work and Side Gig only): context, title, due line; if already planned an inset "Currently planned — Thursday · 7 PM · 15 min. Choosing another time moves it."; "When" as a radio list of the next 4 occurrences of enabled Focus times in that context — primary line "Tuesday · 12:30 PM", secondary "Tue, Oct 27 · Lunch focus" — then **Pick another day** (opens the compact picker below the row: month grid, Time input, explicit **OK**; past days disabled) and **Keep unscheduled**. Choosing an occurrence reveals "Planned minutes" chips **10 min · 15 min · 25 min · Custom** (15 default) and the occurrence summary ("Also planned here: …", "2 tasks · 30 min planned", over-budget line). If the occurrence starts after the due/ship-by time a bordered `danger`-accent block appears: "This is after the due time" / "Due Tue, Oct 27 · 10 AM. Your deadline stays the same." with outline **Choose an earlier time** and primary **Plan it anyway** (these replace **Save plan** while the warning is showing). Otherwise primary **Save plan**; with nothing chosen: "Choose when you'd like to work on this." With no Focus time in that context: "You haven't set up a Work focus time yet. Set my focus times".

**Focus times sheet** (card's Manage / Set my focus times, and Settings → **Focus** → "Focus times · 3 set up ›"): list rows (context dot, name or day summary, "Thursday · 7 PM · 30 min") with a footer "Times use your account timezone, America/New_York. Change in Settings" and primary **Add a focus time**. The edit form (‹ Back) has: Name (optional, 40 max, "e.g. Shop time"); Days as 7 chips Mon–Sun; Time as a compact chip ("⏰ 7 PM") that reveals a time input + **OK**; the account-timezone line; "I usually have" **15 · 30 · 60 · Custom** min (1–180; default 30); "For" Work | Side Gig segmented (blank on a new one — "Choose Work or Side Gig."; "Choose at least one day." likewise); helper "Changes apply to future choices. Work you've already planned keeps its time."; primary **Save focus time**; ghost danger **Archive** (planned work stays visible and recoverable; toast with Undo). "Remind me when it starts" is deferred with notifications.

### 4.7 Home tab (revised 2026-10)

The app tab bar reads **Today · Ship · Home · All**. Home uses existing backgrounds, surface cards, hairlines, shadows, 16px gutters, dark tokens, and bottom dock. Inside Home, a scrollable row of section pills reads **Home care · Groceries · Bill pay · Study & kids**. Open Home care by default; deep links select the task's section. These are optional sections, not new reminder contexts. Only the selected section's forms/history are shown.

Home care cards: **Car service & maintenance**, **HVAC & air filters**, **Dryer maintenance**, **Smart-home batteries**, **Other home care**. The old Filter changes card is consolidated into HVAC; existing filter reminders and history stay visible there. Other sections are peers: Groceries uses existing instant checklists, Bill pay uses bill reminders and Payment history, Study & kids uses education reminders and Study & follow-up history.

All task sheets reuse 20px top corners, drag handle, 40% scrim, `shadow-sheet`, 300ms Apple slide-up curve, compact date/time picker with OK, reduced motion, and 44px touch targets. Field labels, placeholders, validation, repeat presets, completion controls and records come from `design/home-templates.json` for both clients and the prototype. No generic “Car or appliance” field remains.

- Car: Service or task · Car name · Car make · Car model · Next service due · Repeat after service · Service instructions.
- HVAC: HVAC task · System or room · Air-filter size · Next service or filter change · Repeat after HVAC care · HVAC instructions.
- Dryer: Dryer task · Dryer location · Next dryer maintenance · Repeat after dryer care · Dryer care instructions.
- Batteries: Battery task · Device & location · Battery or charger type · Next charge or battery change · Repeat after charging or replacing · Battery instructions.
- Other care: Home-care task · Area or item · Next due · Repeat after completing · Task instructions.
- Bills: Bill name · Biller or provider · Amount due · Currency · Payment due · Billing schedule · Payment notes. **Mark bill paid** opens Paid on and Payment confirmation notes, then **Save payment record**.
- Study: Study task or follow-up · Student or family member · Subject or course · Teacher or school contact · Session or follow-up due · Study or follow-up schedule · Study or follow-up plan. **Record study or follow-up** opens Completed on and Progress & next steps.

Extra metadata is optional. An amount requires a valid decimal and three-letter currency. Missing task/date errors identify the current task's field. Saving errors preserve drafts. Completion explains whether the task closes or advances, and whether its schedule follows the due date (bills/study) or completion (care). Records retain the original make/model, bill amount/currency, or study details after later edits. Deleting a reminder confirms that saved records remain. Each section has its own history and empty copy; Home care also filters by category.
