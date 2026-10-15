# Flutter data access inventory (Phase 0B)

Scope: current Next.js/Supabase data paths inspected on 2026-10-14. All direct client calls below should use the authenticated Supabase session and anon key; RLS is the authorization boundary. `user_id` must be set to `auth.uid()` for direct inserts/upserts where required. Keep client writes tagged `created_by: 'ui'`.

This is the pre-implementation inventory. Phase 1 implements all five RPCs listed below in `0007_ios_foundation.sql`, including `update_reminder`, and strengthens parent/context ownership checks. `retryNotification` remains a web server action until a mobile-safe endpoint is built in a later phase.

## Read paths — direct CRUD under RLS

| Data | Access and purpose | Ownership / notes |
|---|---|---|
| `contexts` | Select all own contexts, ordered by name; home data, create default selection and settings (`lib/home-data.ts`, `app/actions.ts:50-62`, `app/settings/page.tsx:9-18`) | `contexts.user_id`; RLS select own. Context IDs supplied to writes still need explicit ownership validation because the reminder FK can reference another user's context. |
| `reminders` | Select active (`open`,`snoozed`) sorted by due date, plus done rows updated in last 48h (`lib/home-data.ts`); reminder and context joined into Ship Queue (`app/ship-queue/page.tsx:13-23`); retry fetches reminder fields and context name (`app/actions.ts:369-382`) | `reminders.user_id`; RLS select own. All RLS-visible reads are safe as direct reads. |
| `orders` | Home order map (`lib/orders.ts`), pending + shipped-this-week Ship Queue with joined reminder/context (`app/ship-queue/page.tsx:13-23`) | `orders.user_id`; RLS select own. |
| `work_details`, `sidegig_details` | Maps keyed by `reminder_id` (`lib/work-details.ts`, `lib/sidegig-details.ts`) | Both tables have `user_id`, RLS select own. |
| `shopping_items` | All own items, ordered by `position`, grouped by reminder (`lib/shopping-items.ts`) | `shopping_items.user_id`; RLS select own. |
| `notifications` | Failed notification rows for home indicator, newest first (`lib/home-data.ts`); a selected row is loaded for retry (`app/actions.ts:362-367`) | `notifications.user_id`; RLS select own. Data needed for user display is safe to read directly. |
| `user_settings` | `timezone` in Settings; `onboarded_at` in Today and Onboarding gates (`app/settings/page.tsx`, `app/page.tsx:28-29`, `app/onboarding/page.tsx:18-20`) | Primary key `user_id`; RLS select own. |

## Writes — direct CRUD under RLS

These are single-row mutations with no cross-row invariant and can be implemented as direct Supabase table calls. Check affected-row/error results where the UI needs to distinguish missing/unauthorized rows from success.

| Operation | Tables / fields | Existing source and caveats |
|---|---|---|
| Complete, reopen, snooze | Update `reminders.status`, `snoozed_until` | `app/actions.ts:99-129`. Single-row direct update. |
| Delete reminder | Delete `reminders` by id | `app/actions.ts:132-137`; FK cascades dependent detail/order/item/notification rows. |
| Save order details | Upsert `orders` with `reminder_id`, `user_id`, order ref, recipient, ship-by, carrier | `app/actions.ts:194-215`. Direct upsert is suitable for an existing order panel row, provided parent relationship is valid. |
| Save Work details | Upsert `work_details` with `user_id`, reminder id and panel fields | `app/actions.ts:218-238`. |
| Save Side Gig details | Upsert `sidegig_details` with `user_id`, reminder id and panel fields | `app/actions.ts:240-257`. |
| Toggle/delete checklist item | Update `shopping_items.checked`; delete by id | `app/actions.ts:342-355`. |
| Update quiet hours | Update `contexts.quiet_hours` by context id | `app/actions.ts:415-424`; RLS owns row. |
| Update timezone / finish onboarding | Upsert `user_settings` with current `user_id` and timezone or onboarded timestamp | `app/actions.ts:407-433`. Single user-settings row. |

## Writes — needs Postgres RPC

The RPCs must be `security invoker`, execute transactionally, and retain RLS. Each RPC accepting a `context_id` must verify the context belongs to `auth.uid()`; FK validation alone does not enforce ownership. Return created/affected IDs. `last edit wins` means no version precondition; realtime merges must preserve currently dirty form fields.

| RPC | Existing behavior / reason | Required invariant and gap to close |
|---|---|---|
| `create_reminder` | `createReminder` inserts reminder then optional order (`app/actions.ts:42-97`). | Atomic reminder + order creation. Validate context belongs to caller; current action only uses RLS on reminder row and an FK, so a caller could set another user's context id. Use `created_by='ui'`; optional order defaults ship-by from due date. |
| `update_reminder` (required addition) | `updateReminder` updates reminder, then selects/inserts/deletes order based on `isOrder` (`app/actions.ts:140-192`). | This is multi-step and **must move to an RPC** too. Today the reminder update can persist while order insert fails; deleting order errors are ignored. Validate target reminder and new context belong to caller. Keep `is_order` and `orders` row consistent atomically. Preserve existing order fields when remaining an order; create a default order row when toggled on and delete it when toggled off. Current action also does not update `orders.ship_by` when an existing order remains checked and due date changes—decide whether this should track due date or leave explicit ship-by unchanged. UI sheet saves reminder/order detail separately, so avoid unintentionally overwriting order fields. |
| `mark_shipped` | Updates order shipped/tracking/carrier then reminder to done (`app/actions.ts:260-283`). | Atomic order + reminder change; validate both belong to caller / order maps to caller's reminder. Current two calls can leave shipped order with open reminder or vice versa. |
| `create_follow_up` | Reads source reminder title/context, inserts “Follow up: …” due in three days (`app/actions.ts:285-310`). | Put source read and insert in one transaction; validate source ownership/context ownership. Return new reminder id. Current code ignores query error distinction and is a read-then-write action. |
| `add_shopping_item` | Counts items for reminder then inserts at `position=count` (`app/actions.ts:312-340`). | Atomic allocation and insert; concurrent clients can choose the same position, and count errors are ignored. Validate reminder is caller-owned and is in Shopping context. Return item id. |

For actions exposed via server actions, preserve their signatures and revalidation behavior while routing these mutations to RPCs. Flutter should call the same RPCs directly.

## Writes — needs edge function / secret-bearing server path

| Operation | Reason / current behavior |
|---|---|
| Retry notification delivery | `retryNotification` reads notification/reminder, calls Resend with `RESEND_API_KEY` + `RESEND_FROM_EMAIL`, then updates delivery status (`app/actions.ts:358-405`). Secret must not ship in Flutter. Implement an authenticated Edge Function (or equivalent server-only endpoint) that validates the caller and notification ownership, sends email, and records result. Current path supports only email; WhatsApp returns unavailable. Avoid exposing arbitrary notification IDs across users. |
| Delete account (planned) | `MOBILE.md §7` requires in-app account deletion backed by an edge function because deleting the Supabase Auth user requires privileged server credentials. Not present in current app/actions. |

The scheduled notification sweep is already an Edge Function and remains server-only; Flutter should not enqueue/dispatch delivery notifications itself. It is not a client CRUD surface.

## Auth and Realtime

- Auth operations are Supabase Auth, not table CRUD: magic-link OTP (`app/(auth)/login/page.tsx`), Google OAuth / native Google ID token (`components/auth/google-native-button.tsx`), callback code exchange (`app/auth/callback/route.ts`), current user lookup and sign-out. Flutter follows `MOBILE.md`: Supabase session, magic link, Google `signInWithIdToken`, Sign in with Apple, and password demo account path.
- Pages currently perform server-side reads through `@supabase/ssr`; components invoke server actions rather than directly reading/writing Supabase (`rg` found no component `.from()` calls). For Flutter, repositories can query the same tables directly under RLS.
- `MOBILE.md §2` requires Realtime on reminders/orders/shopping_items and last-edit-wins. Foundation plan adds contexts/work_details/sidegig_details too. Track dirty fields in an open sheet and merge incoming events only into non-dirty fields, so a remote event never overwrites text/date/context currently being edited. Re-fetch on focus. Realtime publication is currently not enabled per the prompt's verified current state.

## Schema ownership and RLS notes

| Table | User ownership | Current RLS / relevant shape |
|---|---|---|
| `contexts` | `user_id` | Owner CRUD policies; user-scoped unique `(user_id, slug)`. |
| `reminders` | `user_id` | Owner CRUD policies; `context_id` FK references contexts but does not guarantee same `user_id`. |
| `orders` | `user_id` | Owner CRUD policies; one row per reminder. |
| `notifications` | `user_id` | Owner CRUD policies; delivery status/provider fields are server-controlled by convention, although policy currently permits owner updates. |
| `work_details`, `sidegig_details` | `user_id` | Owner CRUD policies; one row per reminder. |
| `shopping_items` | `user_id` | Owner CRUD policies; reminder FK. Current policies check only item's `user_id`, not parent reminder ownership/context. |
| `user_settings` | `user_id` primary key | Own select/insert/update; no delete policy. |
| `api_keys` | `user_id` | Own select/delete; hashes written only server-side by convention. No current Flutter screen access. |

## Core change requests / open risks

- Add `update_reminder` RPC to the planned RPC set; `updateReminder` is a multi-step order/reminder invariant and is omitted from the current `MOBILE.md §6 Phase 1A` list.
- Current child-table RLS trusts caller-supplied `user_id` without verifying that the referenced parent reminder belongs to that user. At minimum RPCs must validate this for their writes; consider tightening direct child table policies for `orders`, detail tables, and shopping items to parent ownership. Shopping RPC should also enforce Shopping context.
- Direct table update policies currently allow owners to update `notifications`; Flutter should treat notification delivery rows as read-only and use the retry edge function.
- `updateReminder` ignores errors from deleting order rows and doesn't reconcile ship-by on existing order when due date changes. The RPC contract needs an explicit preservation rule for order fields and ship-by.
- No global direct CRUD is needed for any other multi-step read in the UI; all current component mutations route through `app/actions.ts`.
