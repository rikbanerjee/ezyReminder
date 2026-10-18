# Phase 1 review — shared backend groundwork

Implemented on `ios-mvp`, 2026-10-14. Rik requested a local checkpoint commit after the database deployment handoff. The remaining hosted smoke tests and release steps are not complete.

## Hosted deployment handoff

- Rik reports migration history is synchronized through 0007. Migration 0005 already existed; 0006 and 0007 were rehearsed inside a transaction and rolled back without errors, then applied. Rik also checked live main against the new access rules.
- This session independently checked the connected Supabase OpenAPI schema and confirmed all five new RPCs are visible. This resolves the earlier missing-function setup issue; it does not replace the signed-in web smoke test.
- Migration 0007 is now immutable, SHA-256 `55dae2dbbf14d29005e48d4ef4079bf3882b83392db9ded34bd0faeece752c8c`. Future schema fixes require a new migration, starting at 0008.
- The `delete-account` Edge Function was deployed 2026-10-15 with JWT verification on; unauthenticated and malformed-token calls return 401. No account has been deleted through it yet. The order/shipping/follow-up, Shopping, and two-tab smoke tests remain open.
- Rik reports production main still exposes Slack. A stale client can write unsupported reminder channels and break the global enqueue batch. Deploy the updated web client promptly. The separate, unapplied `0008_guard_notification_channels.sql` repairs invalid channel arrays and adds a constraint rejecting future unsupported/null channel values. A legacy Slack save fails individually, protecting other users' queued notifications. Phase 1 checkpoint: `224d3ee`.

## Built

- Baseline parity and data-access inventories in `PARITY.md` and `DATA_ACCESS.md`.
- Migration `0007_ios_foundation.sql`: five transactional, authenticated, security-invoker RPCs; context/parent ownership checks; device tokens and local schedule acknowledgements; APNs channel constraints; Realtime publication for six tables; full replica identities; commented rollback guidance.
- Web actions call the same RPCs that Flutter will use. Added `update_reminder` beyond the original list because editing also changes the order row and must be atomic.
- Hardened notification parent ownership too: a user's notification must reference that user's reminder, preventing the privileged sweep from fetching a different user's reminder for delivery.
- Realtime refresh on data changes, reconnection, focus, visibility, and network resume. An open web sheet keeps its selected snapshot during refresh so unsaved fields survive. The Flutter dirty-field merge layer is Phase 3 work.
- Reminder links `/r/<uuid>` check auth and RLS ownership and open the existing sheet, including older completed reminders. Targets survive sign-in and onboarding. Closing a linked sheet clears its query parameter; a later visit can reopen it.
- Public AASA file, JSON response header, middleware exclusion, mobile ESLint/TypeScript/Vercel ignores.
- Authenticated account deletion function and typed `DELETE` control in web Settings.
- Shared JSON design tokens, CSS/Dart generator, date/quiet-hours fixtures and tests. Existing CSS values are preserved.

## Validation

- `npx tsc --noEmit`: passed.
- `npm run lint`: passed; one preexisting unused `_input` warning in the WhatsApp stub.
- `npm run build`: passed in the main checkout. Temporary worktree builds were blocked by Turbopack's external `node_modules` symlink rule; the sandboxed build was blocked by its worker-port restriction. The main checkout build passed with the local-worker sandbox exception.
- `npm run test:shared`: passed in America/New_York, America/Los_Angeles, Europe/London, and Asia/Tokyo. All five date/quiet-hours helpers use portable JSON expectations.
- `npm run test:edge`: eight tests passed against the actual Edge handler with mocked Auth/admin clients; no network calls or real deletion.
- `npm run test:auth`: passed internal return-target and open-redirect rejection cases.
- `npm run test:ios-foundation`: nineteen checks passed in in-memory PGlite 0.5.10 against migrations 0001–0008. Includes RLS isolation/hostile references, invoker/role privileges, order edits, shipping, checklist positions, injected-failure transaction rollback, device acknowledgement ownership, notification ownership, auth-user cascade deletion, invalid channel repair/rejection, and idempotent enqueue across users.
- `npm run tokens`: repeat generation is byte-identical; existing CSS declarations compare equal after whitespace normalization.
- Local built AASA endpoint: HTTP 200, `Content-Type: application/json`, no cookie and no redirect. Production verification remains on Rik's checklist.
- `git diff --check`: passed.

## Reproduce the optional database check

The PostgreSQL test runtime is a temporary development dependency outside the app dependency tree:

```sh
sql_runtime="$(mktemp -d)"
npm install --prefix "$sql_runtime" --no-package-lock --ignore-scripts @electric-sql/pglite@0.5.10
EZY_SQL_RUNTIME="$sql_runtime" npm run test:ios-foundation
```

The harness stubs Supabase Auth's user table, `auth.uid()`, roles and standard grants; it skips only migration 0001's pgcrypto extension statement because UUID generation is built into the runtime. It runs migration 0007's publication changes, but cannot verify concurrent database connections or hosted Realtime transport. Those remain manual smoke tests. No production dependency was added.

## Decisions and limitations

- Bundle ID `com.ezyreminder.app`, `<TEAM_ID>`, and an unresolved production domain are the approved placeholders. Current `NEXT_PUBLIC_APP_URL` is localhost.
- Existing explicit order ship-by dates survive ordinary reminder due-date edits. A newly enabled order uses the due timestamp's UTC date as before.
- A +3d follow-up preserves the current wall-clock time three calendar days ahead in `user_settings.timezone`, with UTC fallback.
- Quiet-hours target instants use the target day's DST offset. During a repeated hour choose the earliest matching endpoint still in the future; a nonexistent endpoint shifts forward by the DST gap while preserving its minutes.
- The prototype was inspected at phone width. Its older inline quick-add and missing Shopping context are superseded by the explicit July revisions in the current specs. Other native visual requirements remain unverified until the Flutter spike.
- The generated Dart tokens are ready; no Flutter project, iOS binary, simulator screenshots, APNs dispatcher, or Foundation Models bridge is claimed in Phase 1.
- Existing Social context seeding still uses the WhatsApp stub from migration 0006. The mobile delivery defaults need reconciliation before notification release; WhatsApp remains hidden in the native UI.
- Apple token revocation on account deletion must be addressed when Apple sign-in is introduced, before App Store release.

## Required next gate

Follow `mobile/HUMAN_TODO.md`: migration 0007 is applied and `delete-account` is deployed; deploy/smoke-test the updated web client, and approve starting Phase 2. Rik authorized checkpointing Phase 1 locally before those remaining checks. The Flutter spike still waits for the gate.
