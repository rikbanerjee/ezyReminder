# ezyReminder — Design Spec (native-feel webapp)

Companion to PLAN.md §5. This is the buildable spec: tokens, components, and screen-by-screen behavior. A clickable prototype lives at `design/prototype.html` — open it in a browser (narrow window or phone) to feel the interactions.

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
- Right meta: 🚚 if order, channel glyphs (✉ ✳ ⧉ = email/Slack/WhatsApp) at 40% opacity.

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
DELIVER VIA   ✉ Email [on]  ✳ Slack [off]  ⧉ WhatsApp [on]
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
Grouped iOS-style table: **Contexts** (rename, color, default channel, quiet hours per context), **Channels** (connect email/Slack/WhatsApp, test-send button, monthly WhatsApp count), **API & Agents** (API keys list, create key with scopes, MCP setup snippet, per-agent activity log), **Appearance** (system/light/dark), **Account** (email, sign out).

## 5. Key flows

### 5.1 Quick add — revised 2026-07 (supersedes the original inline-parse spec)
The docked quick-add bar is a **trigger, not a text field** — tapping anywhere on it (not just a "+" glyph) opens the full create sheet (§4.2, `reminder={null}` mode), per direct product feedback after the inline shorthand-parsing version shipped and proved less intuitive in practice than just filling in the same structured form used for editing. There is one creation path now: the full sheet, with the context select, `DateTimePicker` (below), and the same Order/Work/Side Gig panels as editing.

`lib/parse/quick-add.ts`'s `chrono-node`/`#context`/`@channel` token parser is no longer wired into the UI but is left in place — it's cheap to resurrect later (e.g. inside the sheet's title field, or a search box) if shorthand entry turns out to be worth reintroducing.

**Date/time — compact calendar, not the native picker.** The due-date control is a custom `DateTimePicker` (small popover: month grid with small cells, a time input, and an explicit **OK** button to confirm), not `<input type="datetime-local">` — the native OS picker was too large and had no explicit confirm step. "No date" clears it.

**Context select starts blank ("Choose template").** Creating fresh never silently defaults to an arbitrarily-sorted first context — the select's first option is a disabled "Choose template" placeholder, and attempting to save without picking one shows inline validation (same red-outline-plus-message pattern as a missing title), not a silently-disabled button.

**Validation, everywhere a Save/Add can be disabled:** a disabled button with no explanation is a dead end, not validation. If a required field is missing, the field itself shows the problem (red outline + a one-line message under it, e.g. "Title required") the moment the user tries to submit — never just a button that quietly won't click.

### 5.2 Delivery transparency
- Row meta shows channel glyphs; after a send, glyph gets a subtle ✓ underdot; on failure an amber ⚠ badge appears on the row → tap opens the notification log for that reminder (attempt times, error, **Retry now**).
- iOS push (installed PWA) mirrors deliveries as local notifications when available — bonus, never the only channel.

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
