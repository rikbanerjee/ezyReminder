# Focus times and continued progress — implementation plan

Prepared 2026-10-18. Status: proposed next implementation, with the product direction requested by Rik. This document plans the work; it does not mark features shipped or authorize deployment. The implemented first version and its immutable database contract remain in [FOCUS_PLAN.md](FOCUS_PLAN.md).

## 1. Product promise and scope

**Make progress in the time you have.** Help someone balancing employment and side gigs choose a useful step, work on it in an available moment, and remember where to restart. The positioning to validate is: **ezyReminder helps you make time for what matters and pick up exactly where you left off.**

The main planning interaction is assigning work to familiar **Focus times**, such as **Thursday at 7 PM** or **Saturday at 9 AM**. These are reusable weekly opportunities with a small task queue and a time budget. People do not have to arrange a calendar, connect external accounts, or drag appointments around.

Existing contexts, shipping, Home, and reminders continue serving their existing purposes. Focus initially applies to open/snoozed Work and Side Gig reminders, including orders. Home remains a view and Shopping remains a checklist; no new context or top-level navigation tab is introduced.

This plan includes simpler starts and endings, persistent next steps, Focus times, assignment and recovery, start/end notifications, an optional distraction capture, optional protection from ezyReminder alerts, onboarding, and a modest weekly recap. Calendar sync, automatic prioritization, AI decomposition, streaks/XP, device-wide app blocking, social accountability, and a project-management hierarchy remain outside this implementation.

## 2. Verified starting point

- Next.js web and Flutter already have a daily highlight, start-now sessions, timestamp timers, pause/resume, explicit outcomes, and a saved next step.
- One unfinished session per user is enforced in Postgres. Sessions do not complete reminders or shipments.
- Migrations 0001–0017 are hosted and immutable (0015–0017, the §13 Focus build, applied 2026-10-18; see `supabase/MIGRATION_STATUS.md`). Allocate new numbers from the next unused number **at implementation time**, currently 0018. Never assume consecutive numbers are reserved by this plan.
- The last Focus verification had a passing production web build, TypeScript/scoped lint, 5 timer tests, isolated SQL tests, clean Flutter analysis, and 145 passing Flutter tests. These are a historical baseline, not proof that future revisions pass.
- Release of the current clients and a real signed-in web/iPhone Focus handoff remain checks to complete.
- Hosted notification cron was verified on a five-minute schedule. Native local/APNs delivery is still gated by the hosted APNs transport proof and the mobile notification phase. Schema readiness does not mean push delivery exists.
- Successful ordinary reminder emails currently trigger six-hour snoozing (0013). Focus invitations and end alerts must never invoke that behavior or modify the task's real deadline.

## 3. Product model: three separate things

| Concept | Example | Meaning |
|---|---|---|
| Reminder and deadline | Publish mug listing, due Friday | The commitment and its actual deadline |
| Focus time and occurrence | Saturdays 9 AM; this Saturday at 9 AM | A recurring opportunity and one specific occurrence |
| Assignment and actual session | Select photos for 15 minutes; worked 12 minutes | Planned work and what the person actually did |

**Recurring availability does not make the task recurring.** Assigning a task to Saturday creates one assignment for the selected Saturday. The next Saturday is another opportunity; it does not generate a duplicate reminder, start a timer, or silently carry the task forward.

“Thursday or Saturday” presents alternatives. Tapping Saturday assigns the task only to that occurrence. People can create a Focus time with multiple weekday chips at one clock time, or separate Focus times when Thursday and Saturday have different hours.

Use these labels consistently:

- **Due:** actual deadline, optional for normal Work/Side Gig reminders.
- **Work on this:** chosen Focus time/date, optional.
- **Next step:** the small action to start with.
- **Start 15 min / Resume / Review session:** the current direct action.

## 4. End-to-end experience

### 4.1 First use and setup

On Today, retain one compact focus card above the dated sections. With no selection: “What would you like to move forward?” Offer **Choose a reminder** and a secondary **Set my focus times**. Onboarding can guide one task, but never creates fake account data.

Focus times are managed in a bottom sheet reachable from this card and Settings → Focus. Example configuration:

- Name: Shop time (optional).
- Days: selectable Thursday and Saturday chips.
- Time: 9 AM; creating separate patterns supports a different Thursday time.
- “I usually have”: 15 / 30 / 60 / Custom minutes; 30 by default, range 1–180.
- Context: Work or Side Gig; restrict the picker and set the default for this queue.
- “Remind me when it starts”: off until explicitly enabled and a working channel is confirmed.
- Account timezone shown beneath the time, with a link to existing Settings.

Use the existing compact time controls and explicit OK action. The first build supports weekly patterns and assigning a one-time occurrence through “Pick another day”; an ad hoc choice need not create a new recurring pattern. No external calendar is required.

### 4.2 Assign work with familiar choices

An existing eligible reminder offers **Work on this**. Show the next occurrences as plain choices: **Thursday · 7 PM**, **Saturday · 9 AM**, **Pick another day**, **Keep unscheduled**. The date appears in secondary text so “Saturday” is unambiguous.

Selecting an occurrence shows its small ordered queue, remaining planned minutes, and a duration selector. Prefer the reminder's saved next step over asking the person to write another intention. All fields beyond task/context are optional where existing reminder rules allow them. One outstanding planned/in-progress assignment per reminder prevents accidental booking into both choices; moving it explains the existing assignment and uses one atomic move.

If the chosen Focus time is after the real deadline or ship-by date, show a visible warning with **Choose an earlier time** and an explicit **Plan it anyway** action. Never move the deadline. Orders retain their shipping fields and Mark shipped behavior.

The create/edit reminder sheet can expose **Work on this** as a compact optional row. Saving a new reminder and its assignment is one RPC, preserving the full-sheet quick-add flow and its validation.

### 4.3 Today and the upcoming list

Today prioritizes one clear action:

1. Unfinished session → Resume/Open session/Review, even when a filter changes.
2. Otherwise, explicitly chosen daily highlight → its saved next step and Start N min.
3. Otherwise, first assigned task in the current or next Focus time → a suggestion, not an automatically changed highlight.
4. Otherwise, choose a reminder or set a Focus time.

Starting a suggestion does not silently pin it as today's highlight. Keep the existing highlight record authoritative and provide an explicit “Make today's focus” action.

Below the main card, a compact **Your focus times** section shows the next three populated occurrences, for example:

| Focus time | Planned work | Action |
|---|---|---|
| Thursday · 7 PM | Choose photos · 15 min | View |
| Saturday · 9 AM | Write description · 20 min | View |

Show **3 tasks · 35 min planned** when applicable, with the first task visible. “View all” opens a sheet with day headings and ordered tasks. Empty recurring times live in the management sheet; do not fill Today with empty cards. An empty occurrence sends no invitation.

### 4.4 Starting and working

For an already chosen task, the primary **Start N min** button starts immediately with its known duration and next step. A small adjacent duration control opens customization. The first selection can show one lightweight setup sheet; repeated starts must not require choosing the same task twice.

Persist the user's preferred duration across clients. Default to 25 minutes for an unplanned start. For an assignment, use its planned duration. Changing the preference does not change existing assignments or a running session. Offer a short start for someone with less time; custom durations remain available.

The session view emphasizes the task and next step, with a quieter countdown. Keep the list of overdue work behind the sheet. Pause/Resume and End session remain obvious. Closing the sheet keeps the session recoverable. Zero time means ready for review, never automatic task completion.

Late starts and work beyond the suggested budget are allowed deliberately. A Focus time is a helpful opportunity, not a hard appointment lock. Show “15 minutes left in this focus time” and offer a shorter session or “I have more time.” Never auto-start the next task.

### 4.5 Ending and returning

Retain the existing three explicit outcomes: Finished what I planned / Made progress / Got interrupted. Give the next-step prompt prominence: **“Where will you start next time?”** Keep it optional and preserve drafts on failure.

After saving a session, offer a concise optional follow-up: **Continue for 10 min**, **Choose another focus time**, **I'm done for now**. An unfinished task moves only when the user chooses. The assignment just worked becomes reviewed; another planned session gets a new assignment and session identity.

A separate explicit Complete reminder action may follow a “finished” outcome, but must never be triggered by it. Orders continue to require their existing Mark shipped action. The latest saved next step, including an intentionally blank latest note, determines the next display; do not resurrect an older note.

### 4.6 Missed time and recovery

After the opportunity's time budget has passed with unstarted work, show one calm recovery card: **“Didn't get to this?” → Start now / Next Saturday / Choose another time / Leave unscheduled**. Do not turn an unstarted Focus time into an overdue task or a failed session.

No automatic backlog grows inside later occurrences. Older missed assignments remain accessible in the planning sheet; show a summary rather than a stack of red cards. Starting another session, completing the reminder, deleting it, disabling a Focus time, and changing context all have explicit recovery behavior (section 6).

## 5. Additional value, after the core planning flow

### Smaller next steps

Offer **Make this smaller** in setup with a short optional prompt: “What could you finish in 10–15 minutes?” Let the person write one concrete action, such as “Choose three product photos.” The first implementation uses editable examples and the existing intention field, not generated subtasks or an AI service.

### Save a thought

Inside an active session, **Save a thought** captures one short note without leaving the session. It is a capture, not a reminder. Afterward, the person can keep it as a note, discard it, or open the existing full composer to turn it into a reminder with an explicit context. Conversion is atomic and idempotent; no duplicate task if a request is retried. This interaction must remain optional and must not block ending a session.

### Weekly progress

Show a small in-app recap by context: sessions with a saved outcome, resumptions, and the next useful step. Use truthful language such as “3 sessions marked Made progress.” An elapsed timer is not evidence of productive work.

Do not infer “published two listings” from task titles, changed `updated_at`, or the Finished-session choice. Initially use the user's saved result and actual session outcomes. Counting completed reminders over time requires reliable completion events; add that separately before displaying historical completion counts. Grouping by initiative can follow once stable initiative identity is available; the existing free-text initiative name is not a durable project ID. No streaks, leaderboards, or obligatory weekly emails.

## 6. Detailed scheduling rules

| Situation | Required behavior |
|---|---|
| A Focus time repeats weekly | Generate new occurrences, not duplicate tasks. Only populated occurrences can notify. |
| Same reminder selected in two places | Present its current outstanding assignment and offer Move. DB prevents two active assignments for one reminder. |
| Multiple tasks in an occurrence | Keep explicit queue order; sum planned minutes. Work starts one task at a time. |
| Planned minutes exceed the budget | Show “35 min planned for 30 min available”; let the person shorten/move work or explicitly accept the larger plan. No automatic reprioritization. |
| Another session is unfinished | Open it; never start a second timer. For an upcoming invitation, show “Resume your current session” in-app and suppress a competing invitation. |
| Reminder completed/cancelled/deleted | Cancel pending assignments and unsent invitations. Keep session snapshots/history. A running session stays reviewable. |
| Reminder moved outside Work/Side Gig | Cancel future assignments and explain on refresh; keep active/history snapshots. |
| Reminder deadline changes | Keep the chosen work time and recalculate the warning. Do not silently move either value. |
| Focus time edited | Increment its schedule version; regenerate untouched future occurrences. Preview affected assignments before atomic remapping. Do not move today's already-started work or history. |
| Focus time disabled/deleted | Cancel future invitations; preserve unfinished reminders. Offer Move work / Leave unscheduled. Keep referenced occurrence history. |
| Assignment skipped | Suppress its old invitation; do not complete/snooze the reminder or create next week's assignment. |
| Person chooses Next Saturday | Resolve the next date strictly after the skipped occurrence; show its full date before committing. |
| User changes account timezone | Preview the affected future times. Recompute future UTC timestamps in the new zone and invalidate old schedules. Running sessions retain their UTC timing. |
| Spring DST gap | Shift the nonexistent wall time forward by the gap; show the resolved time. Shared fixtures define the exact result. |
| Autumn repeated hour | Use the first occurrence of the wall time once. One local-date occurrence key prevents duplicate invitations. |
| Quiet hours overlap a Focus time | Show the conflict at setup. Defer to the next allowed time only if it is still inside the opportunity; otherwise suppress the invitation and leave work recoverable in-app. |
| Device is offline | Existing known timer can render; do not claim a new shared session or assignment was saved. Keep draft and retry using the same operation ID. |
| App returns after a long absence | Reconcile current server state, expire stale invitations, show one recovery summary; do not send a burst of past reminders. |

All schedule interpretation uses `user_settings.timezone`, not the device's default timezone. Keep weekly local wall times and store resolved UTC timestamps on each occurrence. A historical occurrence records its timezone snapshot. A normal deadline notification retains its own existing quiet-hours rules.

## 7. Data and API design

> **Scope decision (2026-10-18, Rik): build in the order A → B → C.** A = docs/commit checkpoint, B = ship the current Focus MVP + Home, then Phase 0/1 (`focus_preferences` only), C = a slim Phase 2: in-app Focus times with **derived** occurrences. Phase 2 adds only `focus_times`, `focus_assignments` (carrying `focus_time_id` + `local_date` instead of an occurrence FK) and `focus_sessions.assignment_id`. `focus_occurrences`, `focus_notifications`, `focus_protection` and `focus_captures` below are **deferred** until the Flutter notification phase (MOBILE.md §6) ships; materialize occurrences then, when invitations need a durable row to key on.

This is the full target contract to implement in new migrations. Preserve old Focus RPC names/argument shapes for installed clients; use new named RPCs for expanded mutations to avoid PostgREST overload ambiguity.

| Record | Proposed core fields and constraints |
|---|---|
| `focus_preferences` | `user_id` PK, preferred minutes, onboarding state, weekly recap preference, optional protection defaults, timestamps. Owner RLS. |
| `focus_times` | UUID, `user_id`, label, context ID, weekday set, local start time, budget minutes, reminder enabled, enabled, schedule version, timestamps. Validate weekly days, supported context, and 1–180 minutes. |
| `focus_occurrences` | UUID, `user_id`, nullable parent time, local date/time, timezone snapshot, resolved `starts_at`/`ends_at`, schedule version, state. Unique `(focus_time_id, local_date, schedule_version)` for recurring rows; client operation ID for one-off rows. |
| `focus_assignments` | UUID, `user_id`, nullable reminder FK plus title/context snapshots, occurrence FK, planned minutes, optional intended next step, position, state, optional moved-from assignment, timestamps. Unique outstanding assignment per owned reminder where state is planned/in_progress. |
| Existing `focus_sessions` | Add nullable `assignment_id`; retain existing timestamps, duration, outcome, and next-step fields. At most one session references an assignment; ordinary unplanned sessions remain valid. |
| `focus_notifications` | UUID, owner, occurrence/session source, kind (`invitation`, `session_end`, later `release_summary`), channel, scheduled time, source version, delivery identity, status, claim lease, attempts, payload snapshot, delivery-started/sent/superseded times, provider ID/error. Unique source/kind/version/channel identity. |
| `focus_captures` | UUID, owner, session FK, text, state, nullable converted reminder ID, client operation ID, timestamps. Max text length and one conversion per capture. |
| `focus_protection` | Optional bounded lease tied to the unfinished session, held context IDs, deadline-exception setting, target end/revision, timestamps. Protection cannot outlive its explicit time bound. |

State transitions are explicit:

| Record | States and transitions |
|---|---|
| Focus time | enabled ↔ disabled; deletion archives the definition while referenced history survives. |
| Occurrence | scheduled → elapsed or cancelled. Whether the start time is in the future/current is derived from UTC timestamps; elapsed means the opportunity passed, not that the person failed. |
| Assignment | planned → in_progress → reviewed; planned → skipped/moved/cancelled. Moving atomically marks the source moved and creates one linked planned destination. A running assignment is reviewed before replanning. |
| Session | Existing running/paused/awaiting-finish/finished contract. Only an explicit saved outcome finishes it. |
| Focus notification | pending → sending (with lease) → sent, pending/retrying after a known retryable failure, or failed/superseded. Unknown provider acceptance preserves the original key and reconciliation state. |
| Capture | saved → converted or discarded. Conversion replays return the same reminder ID. |

A client submitting a transition after the reminder was completed, moved outside supported contexts, or its occurrence was cancelled receives current state and an explanation; it must not fabricate success. An atomic schedule edit validates the preview version, while ordinary field edits keep the established last-edit-wins behavior. Start/finish/move idempotency tokens are retained until the client resolves an uncertain response.

Occurrences are generated idempotently for the next eight weeks, with on-demand creation for a later selected date. Do not precreate unlimited history. Create a notification only for a populated, eligible occurrence. Queue position changes and assignment moves are atomic. RPCs verify ownership of every related row; FKs alone do not prove that two rows belong to the same person.

Proposed client RPCs:

- `get_focus_dashboard_v2`: server time/timezone, active session, highlight, latest next step, next populated occurrences, recovery count, preferences. Bounded result avoids per-card query chains.
- `save_focus_preferences`, `save_focus_time_v2`, `disable_focus_time_v2`: validate owner, preview/version of affected future assignments, regenerate and retire schedules atomically. Regular preference edits use last-edit-wins; an atomic schedule remap validates the preview version.
- `assign_focus_work_v2`, `move_focus_work_v2`, `reorder_focus_work_v2`, `skip_focus_work_v2`: stable client operation IDs for retry safety and scoped locks for conflicting moves.
- `create_reminder_with_focus_v2`: uses the shared reminder creation behavior and assignment in one transaction; leaves existing create RPC valid.
- `start_assigned_focus_v2`: verify eligibility, consume/mark assignment in progress, snapshot intention, and create session in one transaction under the existing per-user start lock. Existing start-now RPC remains supported.
- `finish_focus_with_plan_v2`: save explicit outcome and latest next step, mark its assignment reviewed, release protection, supersede the end alert, and optionally create the user's selected next assignment atomically. Old `finish_focus_session` is extended through a shared internal transition/trigger to maintain the same assignment cleanup for older clients.
- `save_focus_capture`, `convert_focus_capture_v2`: owner checks and idempotent creation/conversion through the existing full composer.
- `get_focus_weekly_review_v2`: aggregate only recorded facts, respect account-local week boundaries, return bounded context summaries.

Security: owner-only RLS on every new table, hardened RPC search paths, anonymous execution denied, private/service-only queue claim and schedule-generation operations, explicit grants. Subscribe user-facing planning tables to Realtime. Do not expose provider payloads/secrets through client reads. Delete-account cascades cover all new user data. Preserve existing agent attribution conventions when agent endpoints are added; no new MCP dependency is required for this release.

## 8. Notifications and protecting attention

### 8.1 Keep Focus delivery independent

Use a dedicated `focus_notifications` queue. Do not create synthetic ordinary reminders, reuse `reminders.due_at`/`snoozed_until` as focus planning fields, or write Focus sends to the ordinary notification rows that trigger six-hour auto-snoozing. Existing reminder emails and shipping alerts retain their semantics.

Reuse email/APNs transports and quiet-hours logic with explicit Focus message templates and `/focus/<occurrence-or-session-id>` deep links. Preserve the existing reminder adapter API through wrappers; do not invent reminder IDs to satisfy an email payload type. The deep link opens the matching sheet on web or the installed Flutter app and recovers gracefully if its source was moved or cancelled.

Extend the existing authenticated sweep with an independently bounded Focus queue pass; avoid starving due reminders and avoid creating a competing scheduler. Claim work with `FOR UPDATE SKIP LOCKED`, reclaim crashed claims by lease, check the current source and version immediately before provider I/O, freeze payload and provider idempotency key across retries, and log unknown delivery outcomes honestly. Never retry an old invitation after its opportunity expires. A send already accepted by a provider cannot be retracted by a later pause or edit.

### 8.2 Start invitations

One logical invitation per populated occurrence, mentioning its first eligible task and optional count. Example: “Your Saturday shop time is ready. Pick up here: write the listing description.” Opening offers Start N min / Later / Skip; an invitation never starts the timer automatically. Revalidate ownership, assignment, and session state after opening.

No repeat-every-six-hours behavior for these invitations. Later changes only this invitation, with a user-selected time inside the same opportunity or an explicit move to another one. Skip cancels the invitation and offers recovery in-app. A whole occurrence gets one notification, not one for every queued task.

The current five-minute cron cannot promise an exact 9 AM server alert. For scheduled Focus release, propose moving the shared scheduler to a one-minute cadence after load checks and explicit rollout authorization; publish an approximately one-minute server target, not an exact-delivery guarantee. Local iPhone scheduling supplies the on-device path once native delivery is verified.

### 8.3 Local iPhone, APNs, and email

Complete the established hosted APNs transport gate and native notification phase before advertising phone delivery. Focus occurrence/session versions join the hybrid scheduling and cancellation design: acknowledgements identify the source version and device; edits, moves, pause/resume, completion, and logout invalidate/reconcile local schedules. Respect the pending local-notification budget across reminders and Focus together.

Define logical invitation identity separately from device/channel delivery attempts. Pick a registered primary phone for focus invitations; all clients still see the occurrence in-app. Suppress APNs when that phone has a valid local schedule acknowledgement. Stable platform identifiers replace stale source-version notifications where supported. Test offline/stale-ack races and report residual duplicate-alert limitations; platform replacement alone is not proof of exactly one audible alert.

Email is the fallback when no usable phone path exists or a known send failure occurs. APNs acceptance does not prove presentation/read; lack of a tap is not a reason to send another email. Unknown provider outcome requires conservative reconciliation, not a second logical invitation.

Session-end alerts have a separate identity. Pause cancels them, resume reschedules for the remaining active time, and finish retires them. They never complete the reminder or save an outcome. If permissions are declined, keep in-app recovery fully usable and explain the available email/in-app behavior. Email-only end alerts are opt-in and do not promise second-level timing.

### 8.4 Optional protection from ezyReminder alerts

After delivery works, add **Hold other ezyReminder reminders during this session**, off by default and explicitly scoped. The person chooses held contexts and whether imminent deadline/shipping alerts may pass. This controls ezyReminder delivery, not other apps, calls, or the operating system's Focus mode.

Use a server-recorded protection lease, not an indefinitely active session flag. It is valid only while the session is running and before its projected end; pause, expiry, or finish releases it. Closing an app does not hold alerts forever, and leaving an expired session unreviewed does not extend protection. An extension requires an explicit server update. Apply the same lease rules to local scheduling, server APNs, and email.

**First protection release:** provide an in-app release summary and resume individual delivery through the ordinary queue with rate limits. A delivered summary email/push is a later enhancement; it stays disabled until its receipt/audit contract is implemented.

Hold by deferring delivery, never by editing a task deadline or snooze. On release, offer one in-app summary; if the person opts into a delivered summary, link it to canonical notification records so the same occurrences are not sent again individually. Ordinary reminder emails that were not sent do not count as sent for 0013. A delivered summary must use an explicit receipt path for the included occurrences before applying any reminder-repeat behavior. Ship this part only when individual and summarized delivery have an unambiguous audit/retry contract. Otherwise release via the existing ordinary queue with rate limits and no duplicate summary send.

## 9. Implementation sequence and acceptance gates

| Phase | Work | Dependencies and completion evidence |
|---|---|---|
| 0 — Baseline and visual contract | Verify current client release status and signed-in handoff. Extend the clickable prototype for new Today, Focus time setup, assignment, missed-time recovery, and recap; update DESIGN.md only for approved new patterns. | Prototype reviewed in light/dark, narrow widths, large text, keyboard, reduced motion. Existing UI remains usable. |
| 1 — Easier starts and returns | Prominent saved next step; choose-and-start flow; one-tap repeat start; persisted duration preference; optional smaller-step prompt; simpler outcome and separate completion controls. | Existing timer/ownership/retry tests pass. A new user starts in under 30 seconds in a moderated test; an established user starts from the card with one tap. |
| 2 — Focus times and task planning | New planning tables/RPCs, weekly patterns, one-time occurrences, populated upcoming list, per-time queue, capacity hints, atomic moves, deadline warnings, missed-time recovery. | Same fixtures and behavior in Next and Flutter; no ordinary deadline, snooze, completion, or shipping side effects. Schedule editing/timezone/DST/retries verified. Can release as explicit in-app planning without claiming notifications. |
| 3 — Delivery foundation and invitations | Finish native gate; implement typed Focus queue, deep links, local/APNs/email routing, dedupe/cancellation, one-minute scheduler proposal and load checks, explicit opt-in permissions. | Real phone permissions/offline tests, server failure/retry tests, no six-hour auto-snooze leakage, invitation invalidation on edits. Scheduled-focus delivery is a release gate, not implied by Phase 2. |
| 4 — Session end and quiet focus | Versioned end alerts; optional bounded alert protection with compatible local/server behavior; honest recovery and release handling. | Pause/resume across clients cancels/replaces alerts; protection expires without a foreground app; no lost/duplicate ordinary reminders or hidden urgent deadlines. |
| 5 — Captures, recap, onboarding | Save a thought and deliberate conversion; modest weekly outcome review; first-task/first-time onboarding; clear product promise in product surfaces. | No new required fields in capture or session ending, no fabricated productivity claims, first-use and repeat-use pilot completed. |
| 6 — Release and learning | Compatibility/dry-run review, migrations in order, worker/client rollout, pilot, monitoring, refine. | Focus times and invitations work on signed-in web and phone; shipping/Home/ordinary delivery regression checks pass; metrics use recorded behavior. |

Implement each phase across both clients before advertising it as supported. New planning migrations can deploy before their UI behind additive capability flags. Notification behavior changes require compatible worker/native clients and controlled activation; avoid releasing only half of a cross-channel suppression feature.

Do not commit migration sequence numbers in advance. Use separate additive batches for preferences, planning, notification queue, protection, and capture/recap as those phases become ready. Review all earlier pending migrations before any hosted push (0001–0014 are already hosted). No `db push` of unrelated pending files just to release Focus.

## 10. Code ownership and integration plan

For a future build using Rik's requested Astra/Sol split, Astra can audit the final product contract and edge cases; Sol workers implement bounded areas. Account/model availability must be checked before dispatch. This planning task does not start those workers.

| Owner | Scope |
|---|---|
| Backend | New migrations, typed RPC contracts, shared schedule fixtures, RLS/transition/generator tests. Additive edits in `lib/supabase/types.ts`; preserve all applied SQL. |
| Web | `components/focus/`, `lib/focus-client.ts`, narrow Today/reminder-sheet/Settings integration, deep-link route. Refactor the current large provider into dashboard state, planning sheet, session sheet, and review only when needed for this feature. |
| Flutter | `mobile/lib/features/focus/`, focused tests, narrow `main.dart` and Settings integration. Keep reminder interfaces and independent Home work intact. |
| Delivery | `supabase/functions/notification-sweep/`, `lib/integrations/<channel>/`, native schedule reconciliation and shared delivery contract. Backend and Flutter agree the source-version protocol before this work starts. |
| Integration/review | Prototype parity, compatibility tests, full regression checks, rollout records and pilot observations. One owner coordinates shared files such as types, Settings, and the sweep. |

At most three implementation workers plus the coordinator run together. Planning/review uses a slot before dispatch or after a worker finishes. Every worker receives explicit file ownership and instructions to preserve concurrent work; no simultaneous ownership of `main.dart`, SQL types, or the sweep. The current dirty checkout must be inventoried before implementation; no broad reset, overwrite, or unrelated refactor.

## 11. Verification matrix

- **Behavior:** Thursday versus Saturday is a single choice; weekly opportunity creates no task copies; Start now remains available without setup; no double selection; duration preference survives reopen; next step survives cross-client refresh; empty latest note stays empty.
- **Security:** cross-user times/occurrences/assignments/session/capture access denied; relationships validate common owner; anonymous mutations denied; service-only generator/claim APIs are not client callable; delete account removes new data.
- **Concurrency:** simultaneous starts preserve one unfinished session; competing moves leave one outstanding assignment; reorder cannot duplicate positions; completion while starting has an explicit outcome; stale schedule-preview apply fails safely; stable operation IDs survive lost responses.
- **Time:** Thursday/Saturday weekly math across month/year boundaries; account midnight; DST gap/fold; timezone changes; editing a pattern with future assignments; skipped date; budget crossing midnight; starting early/late; quiet hours ending inside/outside the opportunity. One TypeScript/Dart/Postgres fixture set defines outcomes.
- **Delivery:** five-minute baseline versus one-minute target; populated-only invitation; empty queue; skip/move/disable/completion retire old sends; retries retain exact payload/key; expired invitation never sends; stale device ack; offline phone; push declined; no phone; known failure versus unknown outcome; no duplicate provider retry across idempotency expiry.
- **Ordinary reminder isolation:** focus invitation/email never changes reminder status, due date, snooze, or six-hour repeat schedule. All original duplicate suppression, quiet-hours, provider retry, shipment-edit and Home recurrence tests still pass.
- **Protection/end alerts:** pause/review/expiry release protection; no indefinite hold; projected end changes invalidate old end alerts; no double release; manual deadline exception honored; old mobile offline schedule limitations are documented rather than hidden.
- **Interface:** 44px controls; light/dark; existing shadows/motion; reduced motion; narrow display with keyboard; large text; accessible radio/selection semantics; focus trapped/restored in sheets; announce state changes, not every timer tick; no unexplained disabled Save action; no draft loss on failed save or Realtime refresh.
- **Real acceptance flow:** web assigns task to Saturday 9 AM → phone sees task and next step → invitation opens exact task → phone starts → web pauses/resumes → phone saves progress → task is explicitly moved to Thursday → old Saturday invitation stays retired → ordinary deadline is unchanged.

## 12. Rollout, success measures, and decisions

Roll out behind per-capability flags: easier start, planning, invitations, end alerts, protection, captures/recap. Flags must also gate server scheduling; hiding a client button does not stop queued messages. Kill switches prevent new Focus sends without disabling ordinary reminder delivery. Retain additive data and historical sessions when rolling back a UI or worker; do not reverse an applied migration to turn a feature off.

Before activation: snapshot/dry run on the linked project; ensure compatible clients; validate notification routing and feature flags; pause/resume the existing scheduler only when a reviewed migration requires it; restore its recorded prior state. After activation: verify migration history, RLS/RPC/publication entries, queue lag/failures, and one explicitly authorized real-account smoke test. Never mark a provider request accepted as a delivered/read notification.

Measure real transitions: focus time saved, work assigned/moved/skipped, invitation queued/provider accepted/opened, session actually started, outcome explicitly saved, and next-step reuse. Derive facts from session/assignment/queue rows and deliberate UI events; store operational metadata without duplicating private task/note contents into analytics. A timer reaching zero is not an outcome.

Pilot hypotheses: five target users; at least four can assign a task to Saturday 9 AM without explanation, start a first session within 30 seconds of choosing work, and explain deadline versus work time. At least three return on another day to continue and say the saved next step helped them restart. Review skipped invitations and notification complaints alongside starts; no incentives for maximizing timer minutes. These are learning thresholds, not statistical proof of product-market fit.

Decisions made for the first planned release: weekly local Focus times; Thursday/Saturday as alternatives or an explicitly selected weekly pattern; one outstanding assignment per reminder; manual recovery instead of automatic rollover; no notification for empty times; no calendar required; one-tap start from known work; Work/Side Gig eligibility; notifications opt-in; optional protection only after all delivery paths agree.

Decisions to validate in the prototype/pilot: preferred name “Focus times”; whether people understand a 30-minute budget; whether a lightweight weekly recap helps; whether two or three upcoming occurrences is the right amount of Today content. These do not block the initial specification or require Rik to supply information already present in the repo.

## 13. Build contract — Phase 1 + slim Phase 2 (2026-10-18)

This section is the binding contract for the first build. It narrows sections 4–7; anything not listed here is deferred. Old 0012 RPCs stay unchanged for installed clients.

### 13.1 Migration 0015 — `focus_preferences` (Phase 1)

- `focus_preferences(user_id uuid pk → auth.users on delete cascade, preferred_minutes int not null default 25 check 1–180, updated_at timestamptz)`. Owner-only SELECT RLS; writes only through RPCs; added to Realtime.
- `save_focus_preferences(p_preferred_minutes int) → int`: upsert for `auth.uid()`; 22023 outside 1–180.
- `get_focus_dashboard_v2() → jsonb`: everything `get_focus_state` returns, plus `preferred_minutes` (default 25 with no row), `highlight_next_step` and `session_next_step` (the latest finished session's `next_step` for that reminder, null when the latest one is blank — never an older note).

### 13.2 Migration 0016 — Focus times (slim Phase 2)

- `focus_times`: `id uuid pk` (client-generated), `user_id`, `label text null ≤40`, `context_slug in ('work','sidegig')`, `weekdays smallint[]` (ISO 1=Mon…7=Sun, non-empty, distinct, 1–7), `start_time time`, `budget_minutes int 1–180 default 30`, `enabled bool default true`, `archived_at timestamptz null`, `created_at`, `updated_at`.
- `focus_assignments`: `id uuid pk` (client operation ID → idempotent), `user_id`, `reminder_id → reminders on delete set null`, `reminder_title`/`context_slug` snapshots, `focus_time_id → focus_times null` (null = one-off "Pick another day"), `local_date date`, `start_time time`, `planned_minutes int 1–180`, `position int`, `state in ('planned','in_progress','reviewed','skipped','moved','cancelled')`, `moved_to uuid null`, `created_at`, `updated_at`. Partial unique index on `reminder_id where state in ('planned','in_progress')`. **Occurrences are not stored**: an occurrence is `(focus_time_id, local_date)`; its UTC start is derived from the account timezone.
- `focus_sessions.assignment_id uuid null → focus_assignments on delete set null`, unique where not null.
- RPCs (all `security definer`, `auth.uid()` owner checks on every related row, anon revoked, authenticated granted):
  - `save_focus_time(p_id, p_label, p_context_slug, p_weekdays, p_start_time, p_budget_minutes, p_enabled) → uuid`: upsert. Edits apply to future choices; already-planned assignments keep their own date/time snapshot.
  - `archive_focus_time(p_id) → uuid`: sets `archived_at`, `enabled=false`. Planned work stays visible and recoverable.
  - `assign_focus_work(p_id, p_reminder_id, p_focus_time_id, p_local_date, p_start_time, p_planned_minutes) → uuid`: idempotent on `p_id`. Reminder must be open/snoozed Work/Side Gig; a focus time must belong to the user, not be archived and match the reminder's context; `p_local_date` must not be before today in the account timezone. An existing `planned` assignment for the reminder is atomically marked `moved` (`moved_to = p_id`); an `in_progress` one raises "Finish the current session first". Position = last in that occurrence.
  - `skip_focus_work(p_id) → uuid`: planned → skipped. Used for both "Skip" and "Leave unscheduled". No reminder side effects.
  - `start_assigned_focus(p_session_id, p_assignment_id, p_duration_minutes) → uuid`: under the same per-user advisory lock as `start_focus_session`; assignment must be planned and its reminder eligible; creates the session with `assignment_id` and marks the assignment `in_progress`. Idempotent on `p_session_id`.
  - Trigger: when a session with `assignment_id` gets `finished_at`, its assignment becomes `reviewed` (covers the old `finish_focus_session`).
  - Trigger: a reminder leaving open/snoozed, moving outside Work/Side Gig or being deleted cancels its `planned` assignments (in-progress ones stay until the session is reviewed).
  - `get_focus_dashboard_v2` is replaced (`create or replace`) to add `focus_times` (non-archived, by start time) and `assignments` (planned/in_progress, by date, time, position) with reminder `due_at` and order `ship_by` for deadline warnings.
- Realtime: `focus_times`, `focus_assignments`.

### 13.2a Migration 0017 — planned intents and restore (2026-10-18)

- `start_assigned_focus(p_session_id, p_assignment_id, p_duration_minutes default null, p_intended_outcome text default null) → uuid` replaces the three-argument version (drop + create; three-argument calls still resolve). The outcome is trimmed, blank → null, max 500 (22023), and kept on retry with the same session id.
- `restore_focus_time(p_id, p_enabled bool default true) → uuid`: owner only (P0002 otherwise); clears `archived_at` and sets `enabled` to the value the client saw before archiving. Same id, so planned work linked to it stays linked. A live time is a no-op.
- `get_focus_dashboard_v2` adds `focus_api: 17`. Clients send `p_intended_outcome` and offer archive Undo only when `focus_api ≥ 17`.

### 13.3 Shared occurrence rules

`nextFocusOccurrences(time, now, timeZone, count)` lives in `lib/focus.ts` and in Dart `focus_models.dart`, both tested against `design/focus-time-fixtures.json`: weekly dates on or after today's account-local date whose start is not yet past its budget; spring DST gap shifts forward by the gap; autumn repeated hour uses the first instance. An occurrence is **missed** when `start + max(budget, Σ planned)` is past and it still has planned work. "Next {weekday}" resolves strictly after the missed date.

### 13.4 Client behaviour (web + Flutter, identical)

- **Today card priority:** unfinished session → highlight → first planned task of the current/next occurrence (labelled "Up next · Saturday 9 AM") → empty state with **Choose a reminder** and **Set my focus times**.
- **One-tap start:** the card's primary button is **Start N min** (N = assignment planned minutes, else the saved preference). A small adjacent "N min" chip opens the setup sheet. Setup shows "Next step from last time" and the prompt "What could you finish in 10–15 minutes?". Starting from setup with a different duration saves it as the preference.
- **Review:** outcomes "Finished what I planned / Made progress / Got interrupted"; prominent "Where will you start next time?". After saving, offer **Continue for 10 min**, **Choose another focus time** (when it has Focus times), **I'm done for now**, and, after "Finished", a separate **Mark reminder done**. Never auto-complete.
- **Your focus times** (below the card): next 3 populated occurrences: "Thursday · 7 PM", first task + "3 tasks · 35 min planned", capacity hint when over budget. Tapping one opens the occurrence sheet: ordered tasks, Start per task, Skip.
- **Missed recovery card:** "Didn't get to this?" → Start now / Next {weekday} / Choose another time / Leave unscheduled. One card, oldest missed first, with a "+N more" count.
- **Work on this** (eligible reminder's sheet, next to Focus on this): next 4 occurrences of enabled times in the reminder's context ("Thursday · 7 PM", date as secondary text), **Pick another day** (date + time with OK), planned minutes chips 10/15/25/custom. Shows the current plan and says choosing another moves it. If the occurrence starts after `due_at`/`ship_by`, show a warning with **Choose an earlier time** and **Plan it anyway**.
- **Focus times sheet** (from the card and Settings → Focus): list + edit form: name (optional), weekday chips, time, "I usually have" 15/30/60/custom, Work/Side Gig, account timezone note. Archive to delete; the toast's **Undo** calls `restore_focus_time` (0017) so the same time, and its planned work, comes back. Without 0017 no Undo is offered.
- **Planned setup** (0017): starting planned work from the setup sheet shows the same optional "What could you finish in 10–15 minutes?" field and saves it as the session's intended outcome. One-tap starts never ask. Without 0017 the field is hidden for planned work.
- Deferred from this build: create-sheet "Work on this", notifications/invitations, protection, captures, weekly recap, schedule-edit remapping.
