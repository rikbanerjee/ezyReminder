# Native shipping parity

Shipping uses the same Supabase data and operations as the web app. Shipment corrections require migration 0010; carrier credentials are not required. The iOS carrier menu offers UPS, USPS, FedEx, DHL, Postal, DoorDash, Uber, and Other with a custom name. Buying labels through Shippo remains a future feature.

## Behavior

Enable Order in the reminder sheet to enter an order reference, recipient, ship-by date, and carrier. Ship-by is a calendar date independent of the reminder's due time. Tracking remains editable after shipping. Ordinary detail edits preserve the original shipped timestamp and reminder completion status.

Ship Queue lists pending orders by ship-by, with undated orders last and overdue orders highlighted. Mark shipped opens optional carrier/tracking fields; Confirm calls the shared `mark_shipped` RPC, completing the reminder. The success message offers `+3d follow-up`, using the shared `create_follow_up` RPC and its account-timezone behavior. Recent shipments appear in a collapsed seven-day history.

Creation uses `create_reminder` atomically. Existing iOS orders now use `edit_order_reminder` to save the reminder, order details, tracking, and explicit shipment-status changes atomically. Adding Order to an existing non-order reminder still uses `update_reminder` and a separate order detail save, matching the web. A failed detail save can leave the reminder changes saved; the app reports that partial result. Removing Order deletes its order details, as on the web.

Repeated taps are blocked while shipping or creating a follow-up. Before shipping, the repository rereads the order and rejects an already-shipped order. This reduces stale-client repeats; the existing server RPC does not provide an atomic already-shipped guard across simultaneous clients.

## Account smoke test

Use an expendable order in your own account:

1. Create it in the iOS app with all four order fields; confirm it appears on the web.
2. Change its recipient and ship-by on the web; confirm the iOS app refreshes. Keep a locally edited field open and verify the incoming update preserves that draft.
3. In Ship Queue, mark it shipped with a carrier and tracking number. Confirm the web shows the same tracking and completed status.
4. Tap `+3d follow-up` once; confirm one follow-up appears in both clients.
5. Expand shipped history and verify the shipment appears. Clean up the test reminders if desired.

Automated checks and simulator previews use in-memory fixtures and do not mutate a live account. See HUMAN_TODO.md for the latest validation status.

## Local validation — 2026-10-17

- `flutter analyze`: clean.
- `flutter test --reporter expanded`: 30 tests pass. Seven protocol tests use a loopback fake Supabase server, including date-only creation, explicit null ship-by edits, tracking preservation, already-shipped rejection, and partial/zero-row save errors. Widget tests cover order editing after remote completion, sheet shipment, queue confirmation/follow-up, and 1.5× text.
- Both preview and Supabase-configured `flutter build ios --simulator --debug --no-codesign` builds pass.
- On iPhone 17 Pro / iOS 26.5, fixture shipment with tracking, follow-up creation, and tracking in shipped history were verified through the native UI. The light order editor was also inspected. Screenshots: `screenshots/shipping-dark.png`, `screenshots/shipping-history-dark.png`, `screenshots/order-panel-light.png`.
- No hosted migration, deployment, or real-account write was performed. Real-account and physical-device verification remain manual.

## Carrier and tracking inputs — 2026-10-17

Both the reminder sheet and Ship Queue use the same carrier picker and tracking field. Existing custom carrier names remain editable under Other. Tracking is optional and accepts letters as well as numbers. A visible counter shows the input limit: UPS/USPS/FedEx 34 characters, DHL 39, and Postal/DoorDash/Uber/Other 64. These are conservative app input caps, not a claim that every ID of that length is valid. No external tracking lookup is performed.

Keyboard entry or a keyboard paste beyond the cap is rejected as a whole. The explicit Paste button and previously stored values retain the complete ID; an overlong value displays an error and blocks shipment confirmation until corrected. No identifier is silently shortened. Switching carriers rechecks the current value. The repository also validates the effective tracking value before submitting a shipment.

The caps accommodate longer service variants: [UPS tracking support](https://www.ups.com/us/en/support/tracking-support) describes Mail Innovations IDs up to 34 digits; [DHL eCommerce FAQ](https://www.dhl.com/us-en/home/customer-service/ecommerce-tracking-faq.html) describes IDs up to 39 characters; [FedEx Ground Economy documentation](https://developer.fedex.com/api/en-bo/announcements/Apr2022-FGEAnnouncements.html) describes a 34-digit barcode. The generic 64-character cap accommodates custom delivery references.

## Correcting a completed shipment

Open the order with its pencil button in Ship Queue, including the expanded shipped history, or open its reminder in All → Completed. Change the title, notes, context, due date, order reference, recipient, ship-by, carrier, or tracking, then tap Save reminder. Tracking can be cleared as well as replaced.

The Shipped switch changes status only when saved. Turning it off for a shipped order clears `shipped_at`, reopens its reminder (`open`), clears snooze, and returns it to the pending queue. Turning it on completes the reminder and records the shipment time; an existing shipment time is retained. Editing details without touching the switch preserves current server status, including a concurrent shipment update. Unsaved tracking and status drafts survive incoming updates.

Apply `supabase/migrations/0010_edit_order_reminder.sql` before installing this app update against the hosted project. `FLUTTER_IOS_PROMPT.md` reserves hosted migration application for Rik; the coding session prepared and locally tested the migration only. With the CLI linked to the intended project, use `npx supabase db push --linked --dry-run` to review all pending migrations, then `npx supabase db push --linked` to apply that reviewed set. This may also include pending 0008/0009. Do not edit or reapply recorded migrations. Future APNs work must use the next unused number (0011 or later).

A local PGlite harness exercises all migrations and tests ownership, grants, tracking limits, status transitions, timestamp preservation, and transaction rollback on an injected order-write failure. See `scripts/test-edit-order-reminder.mjs` for its isolated dependency setup and run command.

Shipment-correction validation: `flutter analyze` is clean; all 138 Flutter tests pass, including shipped-history editing and reopening/re-shipping, plus the local SQL contract/authorization/rollback harness. Hosted migration and real-account checks remain pending.
