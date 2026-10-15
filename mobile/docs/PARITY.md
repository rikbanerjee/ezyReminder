# Native iOS parity inventory

Source priority: `design/prototype.html` wins over current web behavior; `DESIGN.md` is the normative expanded interaction spec, including 2026 revisions. Items marked **WEB GAP** are explicit native follow-ups where current React components omit required behavior. `design/prototype.html` itself is an older interactive mock and visibly diverges from the revised spec; follow-up details are called out below.

Legend: `[ ]` implement/verify in Flutter. References use source file:line or prototype selector/function.

## App shell and navigation

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | Safe-area-aware installed app frame; system font; light/dark surfaces and context colors | DESIGN.md:5-11, 13-48; prototype `#frame`, `.dark` | |
| [ ] | Bottom dock remains anchored while main content scrolls; quick-add above tab bar | DESIGN.md:50-67; `components/home/home-view.tsx:104-112,238-244`; prototype `.dock` | |
| [ ] | Today, Ship Queue, All tabs with active state and Ship count badge | `components/bottom-dock.tsx`; prototype `#tabbar .tab`, `#shipCnt` | Inspect source for final details. |
| [ ] | Gear opens Settings; context pills hidden on Ship Queue and Settings | prototype `#gearBtn`, `#pills`; React route navigation in `app/settings/page.tsx` | Prototype interaction reference. |
| [ ] | Active context pill uses context color; All uses foreground; pills scroll horizontally | `components/home/home-view.tsx:113-128,249-276`; prototype `.pill`, `#pills` | |
| [ ] | Dark mode follows system and supports manual System/Light/Dark setting | DESIGN.md:36; prototype `matchMedia`, `#darkToggle` | **WEB GAP:** settings component has no appearance control. |
| [ ] | Reduced Motion disables transitions/animations | prototype `@media (prefers-reduced-motion: reduce)` | Native equivalent must honor accessibility preference. |
| [ ] | Dynamic Type through 1.5×, VoiceOver labels, minimum 44pt controls | FLUTTER_IOS_PROMPT.md §2 UI parity | Native accessibility acceptance criteria. |

## Today / home

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | Sections ordered Overdue, Today, Ship soon, Upcoming, Someday, Done today; only nonempty sections shown | `components/home/home-view.tsx:29-34,142-184,186-208`; DESIGN.md:71-80; prototype `renderToday()` | WEB GAP: Someday/Nodate section omitted from the prescribed ordering logic? Home view includes nodate; prototype missing Someday and Ship soon. |
| [ ] | Overdue header/count danger color; dated rows sort by effective due time | `components/home/home-view.tsx:76-94,147-159,280-299`; prototype `section()` | |
| [ ] | Ship soon appears only for unshipped orders with ship-by within 3 days; link opens Ship Queue | `components/home/home-view.tsx:68-74,161-179`; DESIGN.md:73; prototype fixture rows only | |
| [ ] | Context filtering includes All and every context; filters both open and done-today rows | `components/home/home-view.tsx:62-66,96-100,113-128`; prototype `#pills` | |
| [ ] | Empty state “Nothing here yet. Add your first reminder above.” | `components/home/home-view.tsx:142-145`; prototype `.empty` says “Nothing here. Add one below 👇” | **WEB DIVERGENCE:** web empty copy differs from prototype. Prototype wins for exact copy, but DESIGN.md can supersede where expanded spec says otherwise. |
| [ ] | Done today collapsed by default; tap header expands list and chevron rotates | `components/home/home-view.tsx:186-208`; prototype `renderToday()` currently static header | **WEB GAP:** prototype's Done section is not interactive/list-backed. |
| [ ] | Search appears in All only; filters title as user types | `components/home/home-view.tsx:130-140`; prototype `renderAll()` | |
| [ ] | Reminder row anatomy: context ring, one-line title, due/context second line, order and channel glyphs | `components/home/reminder-row.tsx:84-165`; DESIGN.md:80-90; prototype `rowHTML()` | **WEB GAP:** verify exact title typography/opacity against DESIGN. |
| [ ] | Shopping row shows remaining item count instead of due chip | `components/home/reminder-row.tsx:45-47,122-133`; DESIGN.md §4.2.1 | |
| [ ] | Due text relative; overdue due text danger; explicit context name | `components/home/reminder-row.tsx:122-133`; prototype `.due` | |
| [ ] | Failed delivery marker and retry action; success/error feedback | `components/home/reminder-row.tsx:134-150`; prototype `rowHTML()` warning sample | **WEB DIVERGENCE:** prototype only labels retry and has no functional retry flow. iOS should expose error and retry only if an iOS-safe endpoint exists. |
| [ ] | Tap row opens reminder detail sheet | `components/home/home-view.tsx:155-157,201-204`; `components/home/reminder-row.tsx:105-112`; prototype `bindRows()` | |
| [ ] | Tap completion ring completes/reopens; context-colored fill; pop animation and haptic | `components/home/reminder-row.tsx:64-71,91-103`; DESIGN.md:92-93; prototype `completeRow()` | **WEB GAP:** React uses a basic color transition and vibrate; prototype pop/collapse/undo are richer. |
| [ ] | Swipe right reveals green Done then completes; swipe left reveals snooze presets; row tap opens sheet | DESIGN.md:92-97; prototype `.swipe-under`, `bindRows()` | **WEB GAP:** React row has action menu; gesture behavior should match prototype/DESIGN. Include Pick… from DESIGN; prototype only 1h/Tonight/Tomorrow. |
| [ ] | Long press context menu: Edit, Duplicate, Move context, Delete | DESIGN.md:96 | **WEB GAP:** absent from React and prototype implementation. |
| [ ] | Desktop keyboard fallbacks e/s/n/1/2/3 (not required on phone) | DESIGN.md:97; prototype keydown only supports n | |
| [ ] | Completing animates check and row collapse; shows “Completed ✓” with Undo | prototype `completeRow()` | **WEB GAP:** current `ReminderRow` has no optimistic success/undo toast. DESIGN.md:193 requires optimistic mutation + 5s undo. |
| [ ] | Snooze 1h / Tonight / Tomorrow / Next week (and Pick… per DESIGN); confirmation toast | `components/home/reminder-row.tsx:31-36,73-77`; prototype `.snz` | **WEB DIVERGENCE:** web includes Next week; prototype lacks it; DESIGN specifies Pick… instead. Use DESIGN expanded spec. |
| [ ] | Mutation failure toast for complete, reopen, snooze, delivery retry | `components/home/reminder-row.tsx:57-62,79-82` | |

## Quick add and reminder sheet

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | Docked bar is tap-anywhere trigger, not inline parser/text input; opens same create sheet | `components/home/quick-add.tsx:6-11,34-47`; DESIGN.md §5.1; FLUTTER_IOS_PROMPT.md §2 | **PROTOTYPE DIVERGENCE:** prototype still contains inline quick-parse input/chips/Return flow (`#qaInput`, `parseQA`, keydown); revised DESIGN and web implementation supersede it. |
| [ ] | Share target prefill opens create sheet with title filled | `components/home/quick-add.tsx:23-32`; `components/home/home-view.tsx:222-235`; DESIGN.md:193-195 | |
| [ ] | Sheet initially slides up from bottom with 300ms Apple curve and 40% scrim; safe-area bottom padding | `components/home/reminder-sheet.tsx:74-90,315-345`; DESIGN.md:44-48; prototype `.scrim`, `.sheet` | |
| [ ] | Half-height initial sheet, drag up full height; drag down >120px or scrim tap dismisses | DESIGN.md:99; prototype `.sheet` pointer handlers | **WEB GAP:** web sheet uses max-height 85vh and has no drag gesture/half-height stop. |
| [ ] | Reduced motion sheet transitions disabled | prototype reduced-motion CSS | |
| [ ] | Title inline editing; notes; close button; Save/Done and Delete | `components/home/reminder-sheet.tsx:349-368,411-421,560+`; DESIGN.md:99-120 | |
| [ ] | Context selector; create form starts blank “Choose template”; title/context inline validation appears after submit attempt | `components/home/reminder-sheet.tsx:93-103,143-153,369-392`; DESIGN.md §5.1 | Prototype does not represent create form validation. |
| [ ] | Date/time control opens compact month calendar + time field; previous/next month, select date, No date, explicit OK | `components/home/date-time-picker.tsx:83-103,105-195`; DESIGN.md §5.1 | |
| [ ] | Date picker outside tap closes; OK disabled without selected day; selected day/today styling | `components/home/date-time-picker.tsx:105-115,145-190` | |
| [ ] | Recurrence chip opens in-sheet picker; repeats default off | DESIGN.md:101-120; prototype `#shDue` and Repeat chip | **WEB GAP:** recurrence absent in current web sheet. |
| [ ] | Channel choices default from context; per-reminder overrides; quiet-hours summary and override | DESIGN.md:104-108; `components/home/reminder-sheet.tsx:139-141,423+`; prototype `.chanrow`, `.quiet` | **WEB GAP:** current component `CHANNELS` only includes Email (see lines 27-32), no iPhone or quiet hours/override. WhatsApp remains hidden per brief. |
| [ ] | Hide WhatsApp in iOS; no Slack/Firebase/Web Push options | FLUTTER_IOS_PROMPT.md §2; `components/home/reminder-sheet.tsx:27-32` | Required invariant. |
| [ ] | Order toggle reveals Order ref, recipient, ship-by, carrier/tracking, Mark shipped; panel expands/collapses | `components/home/reminder-sheet.tsx:103-110,425+`; DESIGN.md:110-122; prototype `#orderSwitch`, `#orderPanel` | Prototype includes basic order panel; UI implementation must use prototype interactions, expanded fields follow DESIGN. |
| [ ] | Mark shipped exposes inline tracking input and paste affordance; success completes order and offers +3d follow-up | `components/home/reminder-sheet.tsx:264-286`; DESIGN.md:120-122; prototype `#shipFromSheet` | **WEB GAP:** sheet code captures tracking but prototype's sheet only toast; make native flow match DESIGN. |
| [ ] | Work toggle-reveal: Manager, Department resource, Project fields | `components/home/reminder-sheet.tsx:112-116,236-247`; DESIGN.md:124-127 | |
| [ ] | Side Gig non-order toggle-reveal: Initiative and Client/buyer fields; hidden for order reminders | `components/home/reminder-sheet.tsx:118-121,248-257`; DESIGN.md:124-127 | |
| [ ] | Shopping context replaces standard details with list name + checklist; no required due date; optional delivery hidden under More options | `components/home/reminder-sheet.tsx:394-421`; DESIGN.md §4.2.1 | **WEB GAP:** current web still renders context/date controls before checklist, no More options channel control. |
| [ ] | Save success toast “Added ✓” / “Saved”; backend and partial detail save errors surfaced | `components/home/reminder-sheet.tsx:155-260` | |
| [ ] | Delete reminder; complete/reopen from sheet; close after successful action | `components/home/reminder-sheet.tsx:289-307,560+` | |
| [ ] | Sheet close slide-out 300ms after close/save | `components/home/reminder-sheet.tsx:88-91,321-345` | |
| [ ] | Post-create Order toast action opens created reminder at Order panel | `components/home/home-view.tsx:57-60,222-235`; `components/home/reminder-sheet.tsx:65-66,132-137` | Verify mobile route/state handoff. |

## Shopping checklist

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | Create shopping list first; explanatory empty panel until it has an id | `components/home/reminder-sheet.tsx:394-409` | |
| [ ] | Add item input, Enter or + button adds; blank labels ignored; input clears and remains focused | `components/home/shopping-checklist.tsx:20-35,68-95`; DESIGN.md §4.2.1 | Prototype has no Shopping context/list yet. |
| [ ] | Items render unchecked/checked; checked text struck through | `components/home/shopping-checklist.tsx:97-113`; DESIGN.md §4.2.1 | |
| [ ] | Check/uncheck and delete are immediate optimistic writes; rollback and error toast on failure | `components/home/shopping-checklist.tsx:38-56` | |
| [ ] | Remove item button; empty list state has add field and no save step | same source; DESIGN.md §4.2.1 | |
| [ ] | Shopping row shows N items left and defaults to Someday if no due date | `components/home/reminder-row.tsx:122-133`; DESIGN.md §4.2.1 | |

## Ship Queue

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | Pending orders sorted by ship-by ascending; null dates last; count in heading | `components/ship-queue/ship-queue-view.tsx:9-25`; DESIGN.md §4.3 | |
| [ ] | Empty state “Nothing to ship. Flag a reminder with #order.” | `components/ship-queue/ship-queue-view.tsx:27-29` | **WEB DIVERGENCE:** prototype always shows sample rows and has no empty state. |
| [ ] | Row shows context color, order ref/title, recipient, carrier/tracking, ship-by; overdue danger styling | `components/ship-queue/ship-queue-row.tsx:17-19,42-59`; DESIGN.md §4.3 | |
| [ ] | Mark shipped expands inline carrier and tracking inputs with Confirm; no sheet needed | `components/ship-queue/ship-queue-row.tsx:61-78`; DESIGN.md:159 | |
| [ ] | Confirm shipped handles error toast; success toast offers +3d follow-up; follow-up success/error toast | `components/ship-queue/ship-queue-row.tsx:20-39` | |
| [ ] | Shipped this week collapsed by default; tap expands shipped rows | `components/ship-queue/ship-queue-view.tsx:37-54`; prototype `renderShip()` static shipped heading | **WEB GAP:** prototype lacks collapse interaction/data. |
| [ ] | Shipped rows show shipped date and no Mark shipped button | `components/ship-queue/ship-queue-row.tsx:56-62` | |
| [ ] | Optional Buy label entry point is future Shippo only; do not hardcode carrier API | DESIGN.md:159-160; prototype `.btn.outline` | Omit or present disabled/coming-later; Shippo is out of scope. |

## Settings

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | Contexts grouped settings: rename, color, default channel, per-context quiet hours | DESIGN.md §4.5; prototype `renderSettings()` | **WEB GAP:** React settings only shows timezone + quiet hours. |
| [ ] | Channels group: iPhone notification status per device, email, test-send; WhatsApp later | DESIGN.md §4.5; prototype `renderSettings()` | Hide WhatsApp for iOS per build prompt. |
| [ ] | API & Agents group: API keys/scopes, MCP setup snippet, per-agent activity | DESIGN.md §4.5; prototype `renderSettings()` | UI/API is broader than current implementation; may be roadmap parity. |
| [ ] | Appearance supports System/Light/Dark | DESIGN.md:36, §4.5; prototype `#darkToggle` | **WEB GAP:** absent in React Settings. |
| [ ] | Account email and sign out | DESIGN.md §4.5 | **WEB GAP:** absent from `SettingsView`. |
| [ ] | Timezone input saves; blank timezone rejected; saved/error toast; helper shows IANA example | `components/settings/settings-view.tsx:41-70` | Prototype has no timezone editor. |
| [ ] | Per-context quiet-hours start/end time inputs; save only when dirty; success/error toast | `components/settings/settings-view.tsx:73-120` | Prototype only displays context summary, not edit flow. |

## Onboarding

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | New user sees onboarding gate; seeded example per context; email delivery status and signed-in email | `components/onboarding/onboarding-view.tsx:10-43`; `app/onboarding/page.tsx` | Prototype has no onboarding screen; build prompt specifies current web gate. |
| [ ] | Continue disabled while saving; completes onboarding and routes to Today | `components/onboarding/onboarding-view.tsx:14-19,45-47` | |
| [ ] | Dark mode/system styling and accessible status labels | DESIGN.md §2, §6 | |

## Login / authentication

| Check | State / interaction | Source | Parity note |
|---|---|---|---|
| [ ] | Login page supports email magic link and Google sign-in; email required/typed; sending/sent state | `app/(auth)/login/page.tsx:12-15,34-53,56-129` | Prototype has no login. Native additionally requires Apple and reviewer email/password per MOBILE.md. |
| [ ] | Magic-link success shows “Check <email> for a sign-in link”; action to use another email | `app/(auth)/login/page.tsx:64-77` | |
| [ ] | Auth errors surface toast; Google pending label and retry on failure | `app/(auth)/login/page.tsx:17-32,79-89` | |
| [ ] | Google native GIS button behavior/error path (experimental web-only path) | `components/auth/google-native-button.tsx:47-114` | Native follows MOBILE.md `google_sign_in` + Supabase ID token, not GIS. |
| [ ] | Sign in with Apple, email/password reviewer route, magic link PKCE deep link, persistent session | FLUTTER_IOS_PROMPT.md §3; MOBILE.md §2, §6 | Native requirements; not present in web. |
| [ ] | Onboarding gate based on `user_settings.onboarded_at` mirrors web | FLUTTER_IOS_PROMPT.md §1, §3 | |

## Required scope constraints

| Check | Source | Requirement |
|---|---|---|
| [ ] | FLUTTER_IOS_PROMPT.md §2-3; MOBILE.md §3 | Supabase only; APNs + local notifications + email fallback. No Firebase, Slack, Web Push. |
| [ ] | FLUTTER_IOS_PROMPT.md §2 | WhatsApp hidden in native UI. |
| [ ] | AGENTS.md invariants; MOBILE.md §2 | Four contexts include Shopping; reminder context color/quiet hours/channel defaults. |
| [ ] | FLUTTER_IOS_PROMPT.md §2 | UI matches prototype; where prototype and DESIGN revised spec conflict, use current explicit July DESIGN rules for quick-add and Shopping, document old prototype divergence. |
