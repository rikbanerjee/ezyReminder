# Focus sessions — MVP implementation contract

Status: agreed implementation slice, 2026-10-18. Applies to Next.js and Flutter. Visual extension: DESIGN.md §9. Existing contexts, reminder delivery, deadlines and shipping behavior remain authoritative.

## Context & goal

For someone balancing a corporate job and side gigs, remembering a task is only half the job. Focus helps them choose one existing commitment, spend a bounded amount of time on it, and leave a useful next step so restarting feels easy.

First 60 seconds: choose a Work or Side Gig reminder → keep the default 25 minutes → optionally name an outcome → Start focus. No onboarding or new task type.

## Experience contract

| Surface | Primary action | Behavior |
|---|---|---|
| Today | Start focus | One highlighted existing reminder per account-local date, before the dated sections. Empty: “What matters most today?” / “Choose a reminder”. Secondary Change opens a picker. |
| Work/Side Gig reminder | Focus on this | Open the same setup sheet for an existing open/snoozed reminder, including orders. Does not implicitly replace today's highlight. |
| Setup sheet | Start focus | 10 / 25 / 50 / Custom minutes; default 25, whole minutes 1–180. Optional “What would you like to finish?” (500 characters). Show the last session's saved next step. |
| Active session | Pause / Resume | Timestamp-based remaining time; secondary End session. Closing the sheet leaves the session running and a discoverable ongoing-session card. |
| Time elapsed | Review session | “Time is up” / “How did it go?”; timer remains at 00:00 until explicit outcome. Timer expiration is not a result. |
| Outcome sheet | Save session | Choose “Finished what I planned”, “Made progress”, or “Got interrupted”. Optional “Next step for next time” (1,000 characters). Successful save closes the session. |

End session may happen early, from running or paused. Opening/dismissing the outcome form does not silently pause, finish, or discard a session. Include a short reminder: “This saves your session. Your reminder stays as it is.” Completing a reminder or marking an order shipped remains its existing explicit action.

There is at most one unfinished session per user across all devices. If one exists, all start entry points open it. Changing today's highlight does not change an existing session's reminder. At midnight the highlight resets to that date's choice (normally empty); an unfinished session continues. Today is defined by `user_settings.timezone`, with UTC fallback, not whichever device happens to be open.

## Shared database and RPC contract

Add `supabase/migrations/0012_focus_sessions.sql`: 0011 is already occupied by Home maintenance work. Never modify or reapply existing migrations.

`focus_highlights`: `user_id`, `local_date` (composite primary key), nullable `reminder_id` (ON DELETE SET NULL), `reminder_title` and `context_slug` snapshots, `created_at`, `updated_at`.

`focus_sessions`: client-generated UUID `id`, `user_id`, nullable `reminder_id` (ON DELETE SET NULL), `reminder_title` and `context_slug` snapshots, integer `duration_minutes`, nullable `intended_outcome`, `started_at`, nullable `last_resumed_at`, nullable `paused_at`, `elapsed_seconds`, nullable `finished_at`, nullable `outcome` (`finished` / `progress` / `interrupted`), nullable `next_step`, `updated_at`.

| RPC | Parameters | Result |
|---|---|---|
| `get_focus_state` | none | JSON `{server_now, timezone, local_date, highlight, active_session}` |
| `set_focus_highlight` | `p_reminder_id` nullable UUID | local date; null clears today's highlight |
| `start_focus_session` | `p_id`, `p_reminder_id`, `p_duration_minutes`, `p_intended_outcome` nullable | session UUID |
| `pause_focus_session` | `p_id`, `p_expected_updated_at` | session UUID |
| `resume_focus_session` | `p_id`, `p_expected_updated_at` | session UUID |
| `finish_focus_session` | `p_id`, `p_expected_updated_at`, `p_outcome`, `p_next_step` nullable | session UUID |

All timestamps use `timestamptz`, written by the server. All tables have owner-only SELECT RLS; mutation access is exclusively through explicitly granted, hardened SECURITY DEFINER RPCs that check `auth.uid()` and ownership. Revoke anonymous/public execution and direct client writes. Add both tables to Realtime. A partial unique index on `focus_sessions(user_id) WHERE finished_at IS NULL` is the final concurrency guard; serialize starts per user so two devices cannot both start.

Selection/start validates an owned existing reminder in Work/Side Gig with status open/snoozed. An order is eligible under these same rules. Snapshot title/context makes an unfinished or historical session usable if the reminder is later deleted or moved; ending it still works. End/pause/resume validate the owned session rather than requiring the reminder to remain eligible. None of these functions writes `reminders`, `orders`, due dates, snoozes, or notification state.

**Idempotence:** retain the same start UUID across retries after an uncertain response; an already-created owned UUID returns the existing session, never starts again. Row-lock transitions; compare `p_expected_updated_at` with the current session before a state-changing write. Reject stale/conflicting transitions with a refresh error. Repeated finished-session submissions return the existing session without overwriting the first saved outcome. Repeated already-paused/already-running transitions are safe no-ops; stale pause after another device resumes must not pause again. Validate duration, enum and text limits server-side.

**Time math:** `elapsed_seconds` is accumulated active time before the current running segment. While running, add `max(0, server-adjusted-now - last_resumed_at)`; while paused use the stored value. Clamp elapsed to `[0, duration_minutes * 60]`; remaining is the difference. Pause and finish fold the current segment into stored elapsed once; resume changes `last_resumed_at`, retaining elapsed. At zero, derive `awaiting_finish` for display; keep the session unfinished until the user submits an outcome. Do not claim overtime as focused time. `started_at` never changes. Do not persist a decrementing countdown or perform a database write every second.

**Last next step:** SELECT `focus_sessions` for the selected `reminder_id` and authenticated owner, `finished_at IS NOT NULL`, ordered by `finished_at DESC, id DESC`, limit 1. Display that row's nonblank `next_step`. Do not search backwards for an older nonblank note when the latest session deliberately left it empty. Deleted-reminder snapshots are history only; never attach them to a different reminder with the same title.

## Client integration and ownership

- Backend worker: migration 0012, additive database types in `lib/supabase/types.ts`, shared `lib/focus.ts` timer/state types, meaningful backend/time tests.
- Web worker: focus components and data/actions, narrow HomeView/reminder-sheet integration, Realtime tables. Existing home-maintenance edits are concurrent; preserve their routing, tags, and navigation. Do not refactor unrelated view code.
- Flutter worker: new `mobile/lib/features/focus/` models/repository/widgets; targeted `main.dart` integration with `TodayPage`, existing reminder sheet and repository changes stream. Preserve demo mode and all existing untracked mobile work. No broad main.dart refactor.
- Planning: this file and additive DESIGN.md §9. No changes to existing product invariants or original prototype.

Refetch state on initial load, successful mutation, Realtime event, reconnect, and foreground/resume. Calibrate display time with `server_now`; local ticking is only rendering. At a local-date change, fetch a new highlight. Use server state to resolve races. Preserve end-form text after failed requests; never show success until confirmed. A connection loss may continue rendering the known timestamp timer, but mutations show an actionable retry error and must not claim offline saves. Missing migration shows “Focus isn't available yet” without breaking reminders. Clear timers/subscriptions and cached user data on sign-out.

## Verification and release gates

1. Cross-user reads, highlight/start of another user's reminder, direct writes, and foreign session mutations fail. Eligible contexts and duration/text boundaries are enforced.
2. Concurrent starts produce one unfinished session. Retry a lost start response with the same UUID. Repeat finish with a different outcome and verify the first saved value survives. Stale pause/resume cannot reverse a newer device action.
3. Timer fixtures cover running, paused, resumed, zero, past-zero, negative clock skew, reload and foreground recovery. Paused time is excluded. User-timezone midnight and DST date boundaries select the right highlight.
4. Run web TypeScript/lint plus focus tests, Flutter analyze plus focus model/widget tests. Manually verify a web start → phone pause → web resume → phone finish; also delete/complete the reminder externally during a session.
5. Visually compare light/dark mode, narrow screen/keyboard layout, custom-duration validation, sheet curve/shadow, reduced motion, screen-reader labels and 44px touch targets. Verify the ongoing session stays reachable after closing its sheet.
6. Record migration/deployment status separately from local checks. Successful local tests do not mean the hosted Supabase migration is installed.

## Simplification and learning

Now: today's single highlight, start-now timer, explicit outcome, latest next step, two-client sync. Deferred: scheduled sessions, calendar, AI, distraction capture, notification suppression, background timer alerts, streaks, scores, session-history dashboard, new contexts/tabs. The saved sessions already provide a durable basis for later learning; do not add an analytics SDK for this slice.

Pilot hypotheses, not evidence: at least 80% of five first-time testers start a session in under 60 seconds (value/accessibility); at least half of activated users start again on another day within seven days (engagement); at least 60% of ended sessions report finished/progress (self-reported value). Derive starts, active duration and outcomes from session rows; derive daily highlighting from highlight rows. Measure time-to-first-start in the moderated test, since no page-view analytics is being added. Never equate timer expiration with productivity.

**Riskiest Assumption & Cheapest Test:** a saved next step makes it easier to resume real work. Ask five job-plus-side-gig users to use two sessions on one reminder over two days; observe whether they understand the distinction between ending a session and completing the reminder, and whether the saved next step helps them restart without rereading notes.

## Implementation status

The shared backend, web client, and Flutter client are implemented locally. Database tests run against isolated PostgreSQL (PGlite); mobile preview uses an in-memory repository and the same state transitions. Migration 0012 was applied to hosted Supabase on 2026-10-18 with Rik's explicit authorization. RLS, authenticated-only RPC grants, and Realtime publication entries were verified; a real authenticated web/iPhone handoff remains a release check. Scheduled sessions and background focus alerts remain deferred.

Local verification (2026-10-18): 5 TypeScript timer/date tests and the isolated SQL RLS/transition suite pass; TypeScript check and lint on the changed web components pass; an isolated Next production build passes (existing Serwist/WhatsApp warnings); Flutter analysis reports no issues and all 145 current Flutter tests pass. Browser fixture checks cover choose → start → pause → reload → review → saved next step. The browser fixture uses mock data; it does not replace the hosted cross-client release check.

Hosted Focus verification (2026-10-18): the concurrent migration rollout applied 0010 → 0011 → 0012. Independently confirmed 0012 in hosted history; both Focus tables enforce owner-only SELECT RLS and deny direct client writes; all six RPCs allow authenticated users and reject anonymous execution; both tables are published to Realtime; the one-unfinished-session unique index is installed. All local migration versions 0001–0013 match hosted history. No migration was reapplied during verification.

Next iteration: [FOCUS_IMPLEMENTATION_PLAN.md](FOCUS_IMPLEMENTATION_PLAN.md) specifies easier starts, recurring Focus times such as Thursday evenings and Saturday at 9 AM, task assignment and recovery, notifications, optional attention protection, and release gates. It is a plan, not a claim those features are implemented.
