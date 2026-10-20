# ezyReminder: Focus review, progress and holistic roadmap

Reviewed 2026-10-18 against `ios-mvp` at `420e251`, the saved Claude session, the source code, and the current product/design/mobile contracts. This is a review and proposed roadmap, not deployment authorization. `AGENTS.md` remains the instructions source; `FOCUS_IMPLEMENTATION_PLAN.md` §13 remains the binding contract for the implementation already built.

## 1. Where the other agent stopped

The saved Claude session contains a completed handoff before its context-limit continuation. The Focus implementation was not abandoned halfway through. Its latest handoff says A → B → C was built and pushed; the checkout contains those commits and matches the local `origin/ios-mvp` tracking ref. This review did not contact GitHub to verify remote state or verify a production deployment.

| Deliverable | Evidence in this checkout | Remaining boundary |
|---|---|---|
| Canonical instructions and scope | `c237cfa`, `cf37fa6`; `AGENTS.md`, plan §13 | Status wording still needs consolidation |
| Preferences + planning backend | `02ccde2`; migrations 0015/0016 | Local only; hosted application requires separate authorization |
| Prototype and design | `e9b1502`; `DESIGN.md` §9 and prototype demo states | Real device usability and authenticated handoff |
| Web client | `133cb05`; `components/focus/`, `lib/focus-plan.ts` | Release and live verification |
| Flutter client | `02e969c`; `mobile/lib/features/focus/` | Signed device build/release and live verification |
| Launch checkpoint | `420e251`; `LAUNCH.md` §0 | Deployment is not equivalent to a code commit |

Built features include one-tap Start N min, remembered duration, saved next steps, explicit session review, continue/replan actions, weekly Focus times, Work on this, deadline warnings, upcoming queues, missed-time recovery and Settings → Focus in both clients. Occurrences are derived; this build does not create a notification scheduling subsystem.

Hosted history ends at **0014**, according to the repository's migration record and the supplied instructions. **0015 and 0016 are written locally, not applied**, and are already occupied numbers. Any additional migration takes the next unused number at implementation time, currently 0017. Never edit 0001–0014. Recheck hosted history before any approved rollout.

Both clients contain compatibility paths for a backend without the new Focus APIs. This is code evidence for staged rollout, not proof of production safety in every mixed-version scenario.

### Verification: distinguish observed from reported

- **Re-run during this review:** `npm run test:focus` passes all 60 tests. `scripts/test-focus-times.mjs` passes against isolated PGlite, covering preferences, dashboard, validation, ownership, idempotent assign/start, moves, triggers, grants, Realtime configuration and account cascades. No hosted data was used.
- **Reported by Claude, not re-run here:** web TypeScript/lint/build, existing Focus/Home SQL suites, Flutter analysis, 239 Flutter tests, simulator debug build and light/dark screenshot comparisons. Its report includes 42 shared scheduling fixtures.
- **Still unverified:** hosted 0015/0016, production web release, signed iPhone release, real authenticated web↔phone transitions, notification permissions and delivery. Embedded SQL success does not prove hosted Realtime or genuine concurrent transaction behavior.
- The compare link in the handoff is a PR creation link, not evidence that a PR already exists. Do not merge or apply migrations as part of this planning review.

## 2. Review of FOCUS_IMPLEMENTATION_PLAN.md

**Assessment:** keep its core model and slim implementation. It is strong on shared state, retry safety, deliberate completion and notification isolation. The main work now is to release and validate that slice, correct a few experience gaps, and connect Focus to the wider commitment workflow without growing a second task manager.

| Priority | Finding | Recommended resolution |
|---|---|---|
| P1 — before advertising the USP | Built is being confused with shipped. Plan §2/§9 still describe future implementation, while §13 and LAUNCH describe local completion. The handoff's phrase “ship” overstates the release state. | Keep a single release checklist with separate code, hosted schema, web deployment, signed phone build and real handoff columns. Add a dated implementation checkpoint to the original plan after review; preserve its contract. |
| P1 — Focus quality | Planned sessions lose the explicit intended outcome. `start_assigned_focus` in 0016 inserts `intended_outcome = null`; both clients omit that input for assigned starts. A title and timer alone underserve the proposed small-step USP. | Add a compatible RPC variant accepting an optional intended outcome; reuse existing limits. Default the setup prompt from the latest next step. Keep one-tap start and never require a new note. Test persistence and cross-client rendering. |
| P1 — user trust | Web archive offers “Undo” by calling save with a fresh ID (`use-focus-controller.ts`). Existing work remains linked to the archived definition. Claude reports the same behavior on Flutter. | Prefer an owner-checked restore operation that restores the same identity. Until then, remove misleading Undo or label the action “Create a copy.” Do not silently reassign existing work. |
| P2 — coherent specification | Broad §6/§7 describe stored occurrences, schedule remapping and future RPCs; §13 intentionally ships derived occurrences and assignment snapshots. Applying the broad section literally would undo the agreed simplification. | Explicitly mark §6/§7 target-state behavior versus §13 current behavior. Preserve existing assignment date/time snapshots on pattern edits; explain that only future choices change. Design the later notification migration from the installed schema. |
| P2 — product positioning | Focus times solve “when,” but the differentiator also needs “what meaningful step” and “where to restart.” §5's smaller-step and recap ideas should not become prerequisites for starting work. | Make the saved next step visible throughout choose → start → review → return. Validate this loop before adding captures, recaps or more planning controls. |
| P2 — whole-app fit | The plan correctly limits Focus to Work/Side Gig, but does not fully connect attention to work commitments, money, shipping and family anchors. | Use the shared Today hierarchy in §4 below. Waiting and payments are later, separate workflow slices; family anchors remain visible without expanding Focus eligibility. |
| Keep | Deadline/work-time/session separation; one unfinished session; manual recovery; no automatic completion; no new Focus tab; no mandatory external calendar. | Retain these constraints. They protect simplicity and both-client consistency. |
| Keep deferred | Invitations, end alerts, alert protection and capture/recap expansion. | Follow the agreed sequence. Native notification foundations and real phone proof come first. Do not infer device-wide Apple Focus control from app-level alert protection. |

These are recommendations, not evidence of a broadly broken implementation. The current slim slice is substantial and is worth testing before another large build.

## 3. The product promise and the core loop

**Proposed promise:** “Remember the commitment. Make progress in the time you have. Pick up where you left off.”

The target user has a day job, a side business and family responsibilities. The distinctive combination is dependable reminders, small useful work sessions and continuity after interruption. A generic countdown, a larger task list or a weekly planning ritual alone does not establish that value.

The primary loop is:

1. Capture a real commitment in the existing full sheet.
2. Choose a useful next step; optionally choose Thursday evening or Saturday morning.
3. Start immediately from known work, with a sensible duration.
4. Pause or finish deliberately; record progress and an optional restart note.
5. Return to that note, or move missed work with one explicit decision.

Focus times remain optional. Someone with ten unexpected free minutes must benefit without configuring a week first. Start-now and planned work use the same session and review model.

### Keep three times distinct

| Time | Owned by | Rule |
|---|---|---|
| Actual deadline / ship-by | Existing reminder or order | Represents the commitment; planning or Focus must not change it |
| Planned work time | Focus assignment | Represents an opportunity; moving/skipping it does not complete or snooze the reminder |
| Next notification eligibility | Existing delivery state, including snooze | Represents when a nudge may send; must not hide or rewrite the deadline |

The actual session records what happened. It is not a new deadline or evidence that an order shipped. Existing six-hour overdue email snoozing stays intact. Focus invitations and end alerts must not enter that ordinary-email auto-snooze path.

## 4. One experience across work, side gig and home

Retain the current prototype's navigation and four context identities. Home groups Social/Personal and Shopping; it is not a fifth context. Focus remains part of Today and task actions. A future Areas navigation experiment needs a separate prototype decision, not a silent change in this build.

### Today hierarchy

- Preserve the current persistent Focus card: unfinished session → explicit highlight → planned suggestion → choose work. An active session stays recoverable under every filter.
- Keep actual deadlines and fixed family commitments in the dated list beneath it. Focus must not hide a school pickup or ship-by obligation. Do not add another competing “top priority” card.
- Keep upcoming Focus times compact and missed recovery to one calm summary. Empty weekly patterns belong in management, not Today.
- Treat Waiting as a later filtered view of existing commitments, with a clear next follow-up. Do not present blocked work as an actionable Focus suggestion.

| Area | Valuable workflow | Relationship to Focus | Scope boundary |
|---|---|---|---|
| Work | Important deliverable → concrete next action → progress/restart | One daily highlight; optional weekly focus opportunity | Start with existing project/contact fields; no mandatory goal hierarchy |
| Side Gig | Client follow-up, payment follow-up, listing work, fulfillment | Focus on the actionable step; resume interrupted work | Payment and shipment are independent facts; never mark payment received because an order shipped |
| Family/Home | Fixed-time family anchor, bill, study follow-up, shopping or maintenance | Keep commitments visible while Work/Gig sessions run | Use existing Home behavior. Social/Shopping Focus eligibility would change the contract and requires a separate decision |

Weekly “big rocks” can initially be expressed through existing project/initiative text and the selected highlight. Validate whether users actually need durable weekly priorities before adding goals, parent tasks, ranking controls or more setup.

## 5. Delivery order from the current checkout

The agreed order remains: release current Focus MVP + Home, then the easier starts, then slim in-app Focus times. All three now exist in source; the next work is staged release evidence, not rebuilding them.

| Step | Concrete work | Completion gate |
|---|---|---|
| R0 — checkpoint and inspect | Review branch/PR scope; reconcile status docs; retain clean reproducible commits. Record mixed-version capabilities and known limitations. | Source, migration and deployment statuses are explicit; no broad “all shipped” claim |
| R1 — release the existing baseline | Release compatible web/iPhone MVP + Home through the approved workflow. Verify actual sign-in and shared state. | Web-created reminder appears on phone; start/pause/review across clients works; Home records and orders still behave correctly |
| R2 — enable preferences and slim planning | Separately approve/review/apply 0015 then 0016, verify grants/RLS/Realtime, release or activate compatible clients. Retain MVP fallback. | Thursday/Saturday assignment, deadline warning, move, missed recovery and preferred duration work with real authenticated clients |
| R3 — strengthen the restart loop | Optional intended outcome for assigned starts; truthful archive recovery; concise next-step treatment and optional first-session guidance. Update prototype before UI changes. | A returning user can find the last restart note and start in one tap; retry/draft recovery works; no extra mandatory planning |
| R4 — finish native reminder delivery | Complete MOBILE.md notification phase and APNs transport proof; implement shared local/server reconciliation, quiet hours, actionable categories and bounded retry. | Real phone online/offline/permission-denied/web-created reminder tests; no uncontrolled minute-by-minute mail |
| R5 — add Focus delivery | Durable occurrence/version identities only when needed; opt-in invitations first, then session-end alerts. | Expired invitations do not burst on return; edits/moves retire old alerts; ordinary reminder snoozing remains isolated |
| R6 — optional protection | Bounded app-level alert holds across all implemented delivery paths, clear deadline exceptions, automatic lease expiry and an in-app release summary. | No indefinite hold after crash/backgrounding; pause/finish/expiry release correctly; no claim to block other apps |
| R7 — pilot-led additions | Waiting/follow-up, minimal side-gig payment status, optional captures or truthful weekly recap, in the order pilot evidence supports. | Each addition improves remembering, restarting or following through without making the core path slower |

No billing, AI decomposition, external calendar, full CRM/accounting, streaks or project hierarchy is required for R0–R6. Share extension, widgets and on-device typing assistance remain on the mobile roadmap; they do not block proving Focus value.

### Later Waiting/payment contracts, before implementation

Keep these small and independent from session outcomes. A Waiting item needs a person, what is expected and a next follow-up time; its action can be “Send follow-up.” Decide whether that follow-up is an explicit child reminder or the existing reminder before selecting schema. Do not reuse snooze as a hidden waiting status.

A side-gig payment record needs payment state and, only if useful, an amount/currency and expected date. Shipping completion must not close an outstanding payment obligation. Home Bill pay already exists and should retain its own completion/repeat semantics. Avoid claiming that it supplies a client invoicing system.

## 6. Engineering and release guardrails

**Backend:** retain installed 0012 signatures and hardened owner-checked RPCs. Keep multi-step assignment/start/finish operations atomic, with stable retry identities. Test real concurrent starts/moves separately from embedded SQL. Add schema incrementally; do not build all future tables now. Recheck migration inventory before assigning numbers or pushing anything.

**Clients:** keep web and Flutter behavior aligned through the shared fixture file, current design tokens and matching state language. Preserve drafts across failures and Realtime refreshes. Keep new Flutter work inside the Focus module; use `main.dart` only for narrow integration changes. Explicitly test unavailable APIs, 0015-only and 0015+0016 backends.

**Scheduling:** preserve account timezone, DST rules, assignment snapshots and explicit manual recovery. Before notifications, define how existing derived assignments migrate to durable occurrences without moving them or duplicating identities. Do not claim stored timezone history exists in the current slim schema.

**Delivery:** keep logical Focus sources separate from ordinary reminder email records. Use source versions, bounded claims, stable provider retry keys and cancellation reconciliation. Share the 64 pending local-notification budget across reminders and Focus. An accepted APNs request does not prove display or reading; an unknown result must not automatically produce another audible/email alert. Treat audible duplication under offline races as a measurable limitation, not an exactly-once guarantee. Do not silently change the live five-minute cron to one minute.

**Deployment:** review and release in small capability steps. Test backward compatibility before schema application. Retain additive schema and disable new features if a rollout fails; do not roll back hosted migrations by editing applied files. Real user notification tests need an explicit test record and expected delivery window.

Future delegated implementation can use backend, web and Flutter owners, with delivery as a separate phase and one integration reviewer. Shared types, fixtures, prototype and the sweep each need a single owner. This review launches no workers and changes no runtime code.

## 7. Acceptance and learning

Run a small pilot with five target users over two weeks after R2/R3. Observe behavior rather than collecting only preference statements.

- Can four of five start useful work within 30 seconds after choosing a task, without configuring Focus times?
- Can four of five assign a task to Saturday and explain that its deadline did not change?
- Do at least three return on another day and use a saved next step to restart?
- Do interruptions lead to deliberate pause/review/recovery rather than silent abandoned sessions?
- Are important family and shipping commitments still noticed? Track missed commitments and notification complaints alongside starts.

These are learning thresholds, not evidence of market fit. Record session starts, saved outcomes, returns and explicit next-step use with minimal metadata; do not copy private notes into analytics. Timer minutes and a “Finished what I planned” outcome are not proof of a completed business result. Historical task-completion metrics require reliable completion events first.

Release scenarios must include cross-account denial, simultaneous starts, stale-client transitions, latest blank next step, deadline edits, order completion without accidental payment completion, archive with planned work, timezone/DST changes, network loss after a save, and web→phone→web recovery. Native delivery adds permission denial, offline acknowledgements, token invalidation, cancellation, quiet hours and stale invitation expiry.

Keep infrastructure cost low through the existing backend, timestamp-based sessions without per-second writes, bounded refetches and queues, and opt-in delivery. Measure email volume and per-active-user costs before setting a paid price. Price and positioning remain hypotheses until users repeatedly get value from the restart loop.

## 8. Immediate next action

Review the completed branch for release, resolve the assigned-intention and misleading archive-Undo decisions, and run the signed-in baseline handoff. Applying 0015/0016, merging to production and distributing a signed build are separate actions requiring the relevant authorization and credentials. No new Focus feature batch should obscure those remaining release checks.
