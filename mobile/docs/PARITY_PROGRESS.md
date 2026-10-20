# Web-to-iOS priority build

Rik authorized this sequence on 2026-10-17. Each stage is implemented and checked before the next feature stage begins. Existing auth and shipping behavior must remain intact. All automated and simulator mutations use fixtures or a loopback fake backend.

| Stage | Scope | Status |
|---|---|---|
| 1 | Shopping lists: immediate item add/check/delete and remaining counts | Implemented; analysis clean, 77 tests pass; iOS simulator build passes |
| 2 | All/search, completed reminders/reopen, reminder deletion | Implemented; analysis clean, 88 tests pass; iOS simulator build passes |
| 3 | Work follow-up and Side Gig initiative panels | Implemented; analysis clean, 102 tests pass; iOS simulator build passes |
| 4 | Settings: timezone, quiet hours, account deletion | Implemented; analysis clean, 120 tests pass; preview and configured iOS simulator builds pass |
| 5 | Native local/APNs notifications, actions, quiet hours, deduplication | Blocked at required hosted HTTP/2 gate; probe ready, 9 offline tests pass |

No hosted migrations, deployments, secrets, pushes, or App Store uploads are authorized by this implementation sequence. Necessary source and setup instructions will be prepared locally. Apple credentials and real-device delivery checks remain human setup steps.

Shared date/quiet-hours helpers now pass the canonical fixtures, including DST gaps/repeated hours and cleared quiet-hours endpoints. The pinned IANA database library is [timezone 0.11.2](https://pub.dev/packages/timezone/versions/0.11.2).

Stage 1 native fixture review verified add/check/delete, title persistence, and new-list creation opening the checklist. Light/dark captures: `screenshots/shopping-list-light.png` and `screenshots/shopping-list-dark.png`.

Stage 2 intentionally makes older completed reminders available in All, as required by DESIGN.md §4.4; the web currently limits completed fetches to the last 48 hours. Today uses `updated_at` as the available recency proxy, not a fabricated completion timestamp. Permanent deletion asks for confirmation and has no misleading Undo.

Stage 2 native fixture review verified All title search, complete/reopen, and delete confirmation cancellation. Capture: `screenshots/all-dark.png`. A fresh source review requested additional guards for stale refresh errors, Today pending completion, and accessible overflow deletion; these are included in the next validation run.

Stage 3 includes snapshot-based saves, a retained reminder ID after a panel-save failure, a blocked retry if creation returned no ID, and dirty toggle/field merging. Additional Stage 2 review fixes are integrated.

Stage 3 native fixture review verified Work Manager changes and Side Gig initiative/client changes persisted after save/reopen. Light/dark captures: `screenshots/context-work-panel-{light,dark}.png` and `screenshots/context-sidegig-panel-{light,dark}.png`.

Stage 4 adds Settings gear entry points on Today and All, shared state across routes, IANA timezone validation, context quiet hours with clearing, sign-out, and typed-confirmation account deletion through the existing edge function. Settings source and UI/protocol tests were independently reviewed; the save response cannot discard a newer timezone draft.

Settings native visual review was attempted after the successful preview build but the Mac was locked. No Settings screenshots or live-account verification are claimed. The simulator service remains reachable by authorized CLI; the visual QA limitation is the locked host.

## Notification gate

FLUTTER_IOS_PROMPT.md §2 requires: “In Phase 5, first prove that `fetch` from a Supabase Edge Function negotiates HTTP/2 with `api.sandbox.push.apple.com`.” Hosted deployment is separately reserved for Rik. We prepared an admin-only, credential-free transport diagnostic at [apns-transport-probe](../../supabase/functions/apns-transport-probe/README.md); its 9 offline tests pass, but it has not been deployed or invoked against the hosted runtime. Follow that README and share its non-sensitive JSON result before APNs implementation continues. The probe needs no APNs key and cannot send to a real device.

No notification adapter, local scheduler, permission flow, channel/default switch, migration, or production sweep change was made in this priority build. Existing email delivery behavior is preserved. Google/Apple auth source, applied migrations, and the pending notification occurrence fix were checked unchanged.

The final configured debug simulator build passes using the existing ignored environment, so Xcode is prepared for the connected app rather than preview fixtures. Settings native visual inspection and real-account cross-client smoke tests remain open.

## Carrier and date/time refinement — 2026-10-17

The reminder sheet and Ship Queue now share preset/custom carrier controls and bounded tracking input (see SHIPPING.md). A repository guard blocks overlong shipment IDs before RPC submission. Reminder and snooze date/time dialogs retain the compact calendar and explicit OK, with a time-only wheel, AM/PM or device 24-hour display, and Morning/Noon/Evening presets. Cancel preserves the previous value.

`flutter analyze` is clean; the full Flutter suite passes 133 tests. This includes carrier/custom-name refresh behavior, tracking input and repository limits, time wheel changes, exact minutes, midnight/noon, cancellation, and 1.5× dark layout. No live-account or physical-device write was performed for this refinement.

The configured unsigned iPhone Release build passes (`flutter build ios --release --no-codesign --dart-define-from-file=env/dev.json`). The current Xcode Run scheme selects Release for phone launches, so the simulator build could not select a destination; its scheme/signing settings were preserved. Phone installation still requires normal development signing.

## Shipment correction editing — 2026-10-17

Existing order reminders now save through the atomic `edit_order_reminder` RPC. Shipped orders retain editable carrier/tracking and a Shipped toggle, so Save reminder can correct details, reopen a shipment, or mark it complete. Untouched shipment state preserves the server's current completion/timestamp; explicit reopening clears shipped state and reminder snooze. Existing custom carrier and tracking-length controls remain in use.

`flutter analyze` is clean and all 138 Flutter tests pass. New tests exercise the atomic RPC payload, nullable status intent, shipped detail edits, reopening/return to queue, and shipping again. The portable PGlite regression harness passes ownership, grants, validation, state/timestamp preservation, and transactional rollback checks after applying migrations locally.

Migration `0010_edit_order_reminder.sql` is prepared but NOT applied to hosted Supabase, per FLUTTER_IOS_PROMPT.md's human-only migration rule. Apply it before using this editor against a live account; the app reports the missing migration rather than attempting separate partial writes. Real-account cross-client checks are in HUMAN_TODO.md.

The final configured unsigned iPhone Release build passes. Reinstall with normal development signing after applying 0010. No hosted deployment or live-account mutation was performed.

## Xcode simulator framework resolution — 2026-10-18

The reported missing Flutter module errors were found in Xcode activity logs for `Release-iphonesimulator`. Flutter does not support Release on simulators. Runner now uses Debug for Run (with LLDB); RunnerDevice retains the previous Release Run configuration without the debugger for physical-phone home-screen launches. Both retain Flutter’s framework preparation pre-action and the existing signing/auth configuration.

Verification passed: a fresh direct Xcode Debug simulator build; the normal configured `flutter build ios --simulator --debug --no-codesign`; a configured unsigned Flutter iPhone Release build; and a direct Xcode RunnerDevice Release build. No plugin cache or package sources were edited. Phone installation/signing was not tested in this session. See README.md for scheme selection and clean/rebuild steps.

## Focus one-tap start and Focus times — 2026-10-18

Implements FOCUS_IMPLEMENTATION_PLAN.md §13 (Phase 1 + slim Phase 2) to match `design/prototype.html`: Today's focus card priority (session, highlight, Up next, empty) with one-tap **Start N min** and a length chip, Setup with next step and saved usual length, session/review/after-save flow (Continue 10 min, Choose another focus time, separate Mark reminder done / Mark shipped), missed-recovery card, **Your focus times** with the occurrence sheet, **Work on this** (reminder sheet and review) with deadline warning, and the Focus times list/editor (Today **Manage**, Settings → Focus).

- Schedule rules are ported to `lib/features/focus/focus_schedule.dart` and pass all 42 cases of `design/focus-time-fixtures.json`; math uses the account timezone from the dashboard, never the device zone.
- Compatibility: if `get_focus_dashboard_v2` is missing (PGRST202/42883) the app falls back to `get_focus_state` (25 min default) and hides Focus times, Work on this and saved-length UI with no error. Planning tables use a separate Realtime channel so missing tables cannot affect the core subscription.
- Writes use client UUIDs kept across retries of the same intent. Drafts live in each sheet mode's own State, so Realtime refreshes never discard them.
- `flutter analyze` clean; 239 tests pass (149 before, +90 incl. fixtures, grouping, card priority, missed actions, move/deadline warning, fallback, one-tap start, review follow-ups, 1.5× text and dark mode). `flutter build ios --simulator --debug --no-codesign` passes. No hosted migration or live-account write was made.
- Preview tour: `flutter run -t tool/focus_preview.dart --dart-define=EZY_PREVIEW=true --dart-define=FOCUS_TOUR=true` (in-memory data only).
