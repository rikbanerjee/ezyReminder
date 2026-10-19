# Side Gig: a place to follow through

Product design proposal · 2026-10-18 · Not a production implementation or migration approval.

Review alongside PLAN.md, DESIGN.md, MOBILE.md, FOCUS_IMPLEMENTATION_PLAN.md §13 and HOLISTIC_FOCUS_PLAN.md. The current app's canonical prototype remains `design/prototype.html`. The proposed experience is `design/sidegig-prototype.html`; it uses the same visual tokens and sheet patterns. Approving this proposal would require promoting its final behavior into DESIGN.md and the canonical prototype before changing web and Flutter.

## 1. Product decision

Replace the **Ship** tab with **Side Gig**: **Today · Side Gig · Home · All**. Side Gig is a view of the existing Side Gig context, not a fifth context, account, workspace, or second task store. Work commitments remain Work. Home continues to group Social/Personal and Shopping.

The user should be able to answer:

1. What needs my attention before something slips?
2. What can I move forward in the time I have?
3. What needs to ship?
4. Who or what am I waiting for?
5. What money do I still need to collect?

The initial audience is an employed seller or freelancer with family commitments and limited time for independent work. This design supports sellers and service providers without making either configure the other workflow. It is a hypothesis to validate, not evidence of demand or willingness to pay.

## 2. Information architecture

Side Gig contains a horizontally scrollable row of section pills:

**Overview · Work · Ship Queue · Follow-ups · Payments**

Overview is the default on first entry. Preserve section and scroll position during a navigation session. Deep links select the relevant section and record. All sections are reachable without setup; empty sections have one useful explanation and one create action, not a checklist of configuration steps.

Ship Queue remains first-class through:

- Its own named section, one tap from Side Gig. Do not reduce it to a flag or a hidden filter.
- A permanent compact Ship Queue entry on Overview, with an actionable count and up to two urgent rows when there are orders.
- An **Add order** action in the queue and the shared create menu.
- Full order detail, manual carrier/tracking, explicit Mark shipped, and shipped history.
- Continued Today → Ship soon and `/ship-queue` links. In implementation, the old route should open Side Gig → Ship Queue, retaining existing shortcuts and incoming links.

There is no separate Clients tab, project hierarchy, accounting dashboard or Focus tab. Client/buyer and initiative are lightweight grouping attributes. Focus is reused, not reimplemented.

## 3. Overview hierarchy

1. **Needs attention** — at most three specific actions. Rank overdue obligations before today's obligations, then near shipping deadlines. Mix task deadlines, shipping, follow-ups and expected payments; each row states its reason. Avoid a revenue leaderboard or a wall of counters. If nothing needs attention, show a quiet single line.
2. **Pick up where you left off** — the user's eligible Side Gig highlight or next planned item, including latest next step and Start N min. A running Work session takes precedence over suggestions and can always be reopened; never offer a second simultaneous session. Starting an order session means working on fulfillment, not shipping it.
3. **Your next focus time** — next populated Side Gig occurrence, its task and planned minutes versus budget. Show a calm capacity message when over budget. Do not equate a free calendar slot with available energy or imply family/calendar integration exists.
4. **Ship Queue** — always discoverable; open count and up to two earliest orders, each with ship-by and recipient. With no orders, a single compact entry says “Orders, when you need them.” Seller users see operational content here; freelancers do not see an empty shipping dashboard.
5. **Follow-ups and payments** — compact actionable entries with counts, not redundant full lists. Payment totals group by currency; never sum unlike currencies or label expected payments as revenue.

The Side Gig bottom-tab badge, if introduced in production, counts distinct commitments requiring attention today, not all open tasks or every occurrence in every section. A payment linked to an order can be a distinct obligation; do not count its same follow-up action again. The prototype leaves the tab badge off to avoid implying the current shipping count has those new semantics.

## 4. Work

Work contains ordinary Side Gig reminders and focusable order work, with **Open / Completed** filters. Show title, client or initiative, actual deadline, latest next step if present, and an explicit planned time. Orders carry a small Order label and link to their shipping detail; completing fulfillment uses Mark shipped.

Actions: open detail, Start N min, Work on this, edit, and explicit completion. Keep creation simple: title + context; date, client and initiative remain optional. A named client is plain text initially, not a new CRM record or required setup.

**Waiting** is an optional condition on work, paired with a linked follow-up obligation. Waiting work stays visible but is excluded from automatic focus suggestions. A “Response received” action can explicitly return linked work to actionable status. Do not overload reminder snooze or change reminder deadlines to model waiting. No automatic blocking inference from notes.

The prototype demonstrates optional next step and estimate capture; their production contract must distinguish a user-edited current next action from the historical next step of a finished Focus session. Clearing the latest next step must not resurrect an older note.

## 5. Ship Queue

Filters: **To ship / Shipped**. Sort pending orders by ship-by, undated last; cancelled/completed non-shipment anomalies need an explicit reconciliation state, never a fake pending shipment. A shipping date is a date in the account timezone. Keep existing independent reminder due time and ship-by rules.

Rows show order reference/title, recipient, ship-by, carrier/tracking if entered, and **Mark shipped**. Missing tracking is informational; manual shipping can proceed without it. Do not show Buy label until an actual shipping provider supports it.

Mark shipped opens the existing sheet pattern with optional carrier and tracking. Confirmation records shipment and completes the shipping reminder using the existing atomic RPC. It does not mark delivery, payment or a follow-up complete. After confirmation offer **Add buyer follow-up**; this is an explicit user-created reminder, not an outbound message or automatic shipment tracking.

Shipped history shows timestamp and tracking. Editing carrier/tracking must not create another shipment. Any reopen/undo behavior must restore the original identity and honor existing order semantics.

Orders retain their existing context rules. For migration compatibility, `/ship-queue` must not silently lose existing orders outside Side Gig: either preserve a clearly labelled legacy all-context view or provide an explicit move choice. Do not silently move records between contexts.

## 6. Follow-ups

Two views: **To follow up / Resolved**. Show the person, what is expected, next follow-up date, related work/order/payment, and last recorded contact where available. A person is useful but optional; “Check supplier confirmation” can stand alone.

Actions:

- **Record follow-up** — user confirms they contacted the person elsewhere, records an optional note and chooses the next check-in. This action sends no message.
- **Response received** — resolves this follow-up; optionally make linked waiting work actionable after confirmation. It does not complete the parent deliverable or record money received.
- **Change date** — moves this follow-up's notification time without changing a linked work deadline.

The list contains both things the user needs to chase and things explicitly awaiting someone else. Neither is represented by hidden snoozing. A later email or messaging integration would need its own consent and delivery contract.

## 7. Payments

Name the section **Payments**, with **Expected / Received** filters. This is a lightweight collection memory, not invoices, bookkeeping, profit reporting or payment processing.

Minimum fields: description and expected date; optional person/business, amount + currency, reference and related commitment. If amount is entered, currency is required. Store money in a precise decimal or minor-unit representation; never floating-point arithmetic. Separate currency totals and omit unknown amounts from sums with a visible note.

Actions: **Record received** with received date and optional reference/note; **Add follow-up** with an explicit next check-in. Receipt of money does not ship an order or complete client work. Shipping does not record payment. A fully prepaid order need not have an expected-payment record.

First implementation should support whole expected payments only. Partial payments, refunds, taxes, expenses, invoice issuance, bank sync and currency conversion are deferred. The prototype demonstrates whole-payment recording in USD, not financial calculations or payment integration.

If a payment has a live follow-up, display that link and avoid creating another accidentally. Recording receipt can offer to resolve its linked collection follow-up; it must not silently resolve unrelated work.

## 8. Create and detail interaction

The docked **Add to Side Gig** bar is a tap-anywhere trigger. It opens a short sheet of **Task / Order / Follow-up / Expected payment**, then the full form in the same sheet. All changes are explicitly saved. Side Gig is visibly selected because the user entered from that destination; the global generic composer keeps its established blank-context behavior.

Task and Order use the same reminder composer with toggle-reveal detail panels. Order selection turns the existing Order toggle on. Optional context fields never become prerequisites to a basic reminder. New follow-up/payment forms use the same typography, tokens and bottom sheet behavior.

Dates use the existing compact calendar with explicit OK. A planned Focus time is distinct from deadline, shipment date, follow-up date and expected-payment date. Sheet errors preserve entered text. Unsaved edits require a discard choice; closing a session sheet leaves its timer running. Completing a Focus session saves its outcome and optional next step; task completion and shipment remain explicit actions.

## 9. Visual and interaction contract

- Match `design/tokens.json`: warm paper, surface cards, 12px card corners, 20px sheet corners, exact shadows, 16px gutters, system typography.
- Side Gig active states use amber borders/tint and text; primary buttons remain inverse text/background. Never use amber-filled marketing tiles or white-on-yellow action labels.
- Context colors remain blue/amber/green/purple. Status is written in text as well as color.
- Controls meet 44px hit targets; section pills scroll on narrow phones. Content remains readable at large text sizes.
- Sheets slide up over a 40% scrim using 300ms cubic-bezier(0.32,0.72,0,1); reduced motion disables animation. Escape/scrim/drag close; preserve drafts on failure and guard unsaved edits. Trap focus and restore it after close.
- One sheet at a time. Focus timers announce state transitions, not ticking seconds.
- Light/dark follow the established tokens. Prototype scenario/theme controls live outside the product phone frame.

## 10. Data and integration boundaries

| Capability | Reuse now | New work before production |
|---|---|---|
| Side Gig view | reminders + contexts + sidegig_details | Aggregation, filters, new navigation/route |
| Ship Queue | orders + mark_shipped + shipping provider seam | Embedding, legacy-route/context compatibility |
| Focus | current Focus provider/repository and atomic RPCs | Side Gig entry points; never a second session engine |
| Follow-ups | existing reminder delivery and create_follow_up where semantics fit | Explicit waiting/relationship/history model and atomic transitions |
| Payments | existing notification infrastructure only | Independent payment obligation and receipt model; exact currency handling |
| Clients/initiatives | optional existing text fields | No separate entity required initially |

Do not add all these records to `sidegig_details` or overload tags with business state. Model follow-up/payment facts independently, link deliberately to reminders, validate owner equality on every relation, and keep all multi-step mutations in owner-checked Postgres RPCs. Every table needs RLS and both clients need the same contract. Account deletion must cover new records. Cross-client idempotency, stale edits and failed saves require explicit handling.

The last inspected checkout has local migrations through 0017 and hosted history documented through 0014. No migration is created by this proposal. Recheck the sequence at implementation time. Existing six-hour email repeats, quiet hours, notification deduplication, reminder recurrence and shipment semantics are not changed by this design. New reminder-backed obligations need agreed notification policies before release; do not double-notify a payment and its linked follow-up for the same action.

## 11. States and acceptance flows

Prototype scenario controls: **Mixed**, **Seller**, **Freelancer**, **New user**, **Busy week**. Reset restores sample records. Data is temporary, local to the open page, and never sent to Supabase, a payment processor or a messaging service. Fixed scenario date: Thursday, October 22, 2026, America/New_York. Prototype Focus is a local demonstration; production uses the existing shared Focus contract.

Validate:

1. Seller opens Side Gig, finds an order due tomorrow, records shipping with optional tracking, finds it in history, and sees its payment still expected.
2. Freelancer sees actionable client work immediately and can ignore shipping without setup.
3. Mixed user records a client follow-up, selects the next date, and sees it leave today's attention list without changing the client deliverable's deadline.
4. User records payment received; shipping and work status remain unchanged. Receipt history reflects the explicit action.
5. Interrupted user starts a work session, pauses, saves a restart note, and finds that exact note on return. No task completes when the timer expires or the session ends.
6. User plans work after its deadline and must explicitly accept the warning or choose an earlier time. Moving work never changes the deadline.
7. New user adds a simple task without configuring client, order, payment, calendar or Focus schedules.
8. Busy-week user understands the budget warning and can choose what to move; no silent rollover or forced plan.
9. Web/phone handoff, RLS, rollback behavior and notification delivery are future implementation acceptance requirements, not demonstrated by this static prototype.

Error and loading states for the real app: retain the last good view on refresh failure, show an actionable inline error for the failed section, never turn a failed query into a false zero balance/empty queue, preserve drafts, disable duplicate submissions while pending, and retry using the same operation ID. Do not show fake business outcomes to demonstrate a failure state.

## 12. Release slices and research

**Slice A:** navigation + Overview + Work + full Ship Queue, reusing existing records and Focus. Preserve all current delivery and order behavior. Evaluate whether users can find orders and useful work without instruction.

**Slice B:** explicit Follow-ups, with waiting/response semantics and delivery contract. Validate repeated use before adding CRM structure.

**Slice C:** expected Payments and received history if collection is a recurring pain in the winning pilot segment. Build receipt semantics before showing money totals.

Do not advertise Follow-ups or Payments as live when only their prototype exists. The full design provides a destination; slices reduce implementation and learning risk.

Test with employed sellers and freelancers who have family responsibilities. Observe: time to find next action, shipping completion without confusion, whether freelancers understand optional shipping, restart-note reuse, whether users can explain shipped versus paid, and whether they return the next week. Ask about actual missed commitments before asking which feature they like. Treat favorable comments as research input, not purchase evidence.

The monetization hypothesis is reduced follow-through effort and fewer consequential misses. Do not charge merely for moving Ship Queue into a new tab. Test actual paid continuation after users experience the connected workflow.
