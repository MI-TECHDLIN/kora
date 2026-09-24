# Handoff: review fixes for the backend owner

**For:** Maria, backend owner, and Ez, frontend owner - **From:** review verification - **Date:** 2026-09-24
**Status:** proposal and work list. No backend code is changed by this document.

A local-LLM review of `staging` (`docs/kora-local-llm-review-report.md`) was checked against the real code (`docs/kora-review-verification.md` has the finding-by-finding evidence). Most findings are backend. Two fix tasks (security hardening on the routes, and queue and target correctness) are being done by the Firstmate workers in separate pull requests. This file lists what is left for Maria, in priority order, and what to avoid doing twice.

## Being done by Firstmate workers (please do not duplicate)

| Task | Files it touches |
|---|---|
| F1 security hardening | `app/api/routes/tools.py`, `deliveries.py`, `pod.py`, the stats and analyze routes in `shift.py`, and the tracked docs and test file that contain the TomTom key |
| F2 queue and target correctness | `app/services/order_queue_service.py` (target acknowledgement), the greeting-once-per-shift change in `app/api/websocket/voice.py` and `agent_config.py`, plus frontend files |

If you are editing any of those files, push early and tell Ez so the pull requests can be rebased.

## Maria's items

### 1. Fix `accept_order` (small, urgent)

`app/agents/tools/delivery.py:369` calls `dispatcher.get_order(order_id)`, but `OrderDispatcher` has no `get_order` (`app/dispatch/order_dispatch.py` has `_find`, `accept`, `decline`). This came in with `2d59729` on 2026-09-23. Effect: a manual accept by voice or by tapping the offer card returns an internal error and the offer stays open.

- Either add a lock-safe lookup method on `OrderDispatcher`, or drop the pre-lookup and use the result `accept()` already returns.
- Seven tests in `tests/test_order_dispatch.py` fail today because of this (`test_get_next_order_reads_the_live_queue`, `test_accept_tool_failure_logs_order_shift_and_reason`, `test_driver_accepts_the_offer_by_tap`, `test_driver_accepts_second_offer_by_tap_after_finishing_first`, `test_tap_on_an_offer_not_yet_spoken_says_nothing`, `test_tap_on_an_order_taken_elsewhere_closes_it_without_an_error`, `test_failed_tap_reports_an_error_and_keeps_the_offer_open`). They should all pass after the fix.
- One more failure in the same file, `test_auto_accept_takes_the_order_and_announces_it_unprompted`, is a stale wording check: the announcement no longer contains the full street number. Update the test or the message, whichever matches the intended announcement.
- If this is not done by the time the security PR merges, a Firstmate worker will pick it up. Reply in the pull request or tell Ez.

### 2. Operator and dispatcher roles for the fleet routes

`GET /v1/fleet/drivers` (`app/api/routes/fleet.py:35`) returns every driver's phone number and live coordinates to any signed-in driver. `/v1/fleet/incidents`, `/v1/fleet/analytics` and `/v1/fleet/overview` use the same driver-only gate. There is no operator role anywhere (`app/dependencies.py` has only `get_current_driver`), so this needs a decision first:

- How are dispatchers identified: a Supabase role claim in the JWT, an `operators` table, or a separate token?
- Add a `get_current_operator` dependency and use it on the fleet routes.
- Return only the fields a dispatcher console needs. Phone numbers and exact coordinates should not go to other drivers.
- Add tests: a driver token gets 403, an operator token gets 200.
- The security PR (F1) also found routes with the same problem that need the same role decision: `GET /v1/drivers/{driver_id}/location` and `/history` expose another driver's position to any signed-in driver.

### 2b. Other unauthenticated or loosely authenticated routes found by F1

- The legacy `POST /v1/voice-agent` accepts authorization inside the JSON body and falls back to demo context on purpose. Decide whether it should still exist.
- `POST /v1/driver/onboard` can use caller-supplied identity and contact fields without required authentication.

### 3. Supabase security review (needs database access)

The workers have no database access, so these could not be checked:

- Row-level security and service-role use on `deliveries`, `proof_of_delivery`, `driver_preferences`, `drivers`, `shifts`.
- The older open question: does the deployed `drivers` table have the INSERT policy, or does `supabase_schema.sql` disagree with the live project?
- Whether the storage bucket for proof-of-delivery photos and signatures is private and scoped per driver.

Ownership checks in the route code (F1) are the first line of defence; row-level security is the second, and it is the one that catches a future route that forgets the check.

### 4. Rotate the TomTom key

A live TomTom key was committed in 8 tracked files (`voiceops-backend/test_live_data.py`, `LIVE_TESTING_GUIDE.md`, `frontend/FRONTEND_SETUP_GUIDE.md`, and five curl and traffic test scripts under `voiceops-backend/`) and is in git history. F1 replaces it in the current files with an environment-variable read. Rotation has to be done in the TomTom account:

- Revoke the old key, create a new one, set it only in the deployment environment.
- Purging git history is a separate, destructive step that rewrites shared history. It is not being done without an explicit decision from Ez. Because the key is already public in history, rotation is what actually removes the risk.
- Consider adding a secret scanner (for example gitleaks) to the repository so this is caught before it is committed.

### 5. Performance review (nothing measured yet)

The review found no measured performance problems. These are candidates worth measuring with production-like data before changing anything:

- The queue snapshot (`app/services/order_queue_service.py`) is rebuilt with database reads on every delivery status change, including proof of delivery, geofence arrival and auto-accept.
- Preference reads on each auto-accept check (`_maybe_auto_accept`) and the preference service being created per call.
- Per-connection work when a voice session starts: driver context, greeting and config.

### 6. Checks that need real accounts

- AssemblyAI: greeting and reconnect timing, concurrent tool calls, real voice behaviour after a voice change.
- Twilio: call and SMS failure handling.
- Two devices racing for one order, to confirm a single driver wins and the other gets the calm "taken elsewhere" message.

### 7. Self-hosted OSRM (follow-up from walking mode)

The public OSRM demo only serves the driving profile, so walking and cycling ETAs are derived from driving distance and a fixed speed. A self-hosted `osrm-routed` with foot and bicycle profiles, set through `OSRM_BASE_URL`, would give real routes. `app/services/vehicle_modes.py` holds the speed block that would then become a fallback.

## Suggested order

1. Item 1 first (small, unblocks manual acceptance).
2. Item 4 (rotation) in parallel, since it is an account action.
3. Item 2 (role design), then item 3 (security review).
4. Items 5, 6 and 7 when there is production data or infrastructure to test against.
