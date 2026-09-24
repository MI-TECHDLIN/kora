# Kora review verification and fix plan

Verifies `docs/kora-local-llm-review-report.md` (local-LLM review of `origin/staging` at `dedbbf9`, 2026-09-24) against the real code, then splits the fixes between Firstmate's workers and Maria (backend owner).

**How this was verified.** Every finding below was re-read in the actual `origin/staging` code (file and line cited), not taken from the report. Findings that need running tests on the reviewer's machine (test counts, Flutter results) are marked *reviewer-run*: they are consistent with what the workers reported when they built each feature, but were not re-run here. Nothing was changed in the repo.

**Verdict key:** CONFIRMED = the code shows it. PARTIAL = true but the report over- or under-states it. NOT VERIFIED = needs a device, an account, or a test run.

---

## 1. Summary

| Result | Count |
|---|---|
| Bug and risk findings CONFIRMED in code | 12 |
| PARTIAL (true, with a correction) | 1 (greeting replay) |
| Feature verdicts I would change | 1 (greeting: FAIL to PASS with a polish item) |
| NOT VERIFIED here (device, account or test run) | 6 areas |
| Findings that were WRONG | 0 |

The two most serious findings are real and easy to exploit: unauthenticated tool execution and cross-driver access to deliveries. Manual order acceptance is broken by a call to a method that does not exist, introduced by a direct push on 2026-09-23. A live API key is committed and is in git history.

---

## 2. Finding-by-finding verification

### Critical

| # | Report finding | Verdict | Evidence in code |
|---|---|---|---|
| C1 | `/v1/tools/execute-parallel` and `/benchmark` run tools with no authentication and caller-supplied driver and shift context | **CONFIRMED** | `voiceops-backend/app/api/routes/tools.py:33-51`: neither route has `Depends(get_current_driver)`; both pass `request.context` straight to `ToolOrchestrator`. Router is mounted at `/v1/tools` (`app/main.py:83`). |
| C2 | A non-placeholder TomTom API key is committed | **CONFIRMED** | Literal key in **8 tracked files on `staging`**: `voiceops-backend/test_live_data.py:12`, `voiceops-backend/LIVE_TESTING_GUIDE.md:15,218`, `frontend/FRONTEND_SETUP_GUIDE.md:25,256` (the three the report named), plus five the report missed: `voiceops-backend/comprehensive_curl_tests.ps1:5`, `curl_tests.sh:7`, `test_traffic_routing.ps1:11`, `test_traffic_routing.sh:28`, `test_traffic_routing_fixed.ps1:11`. It is also present in git history. The value is deliberately not reproduced here. Found by searching the tree for the key value itself rather than for a pattern. |

### High

| # | Report finding | Verdict | Evidence in code |
|---|---|---|---|
| H1 | Manual order acceptance is broken by a missing `OrderDispatcher.get_order` | **CONFIRMED** | `app/agents/tools/delivery.py:369` calls `dispatcher.get_order(order_id)`. `OrderDispatcher` has `_find`, `accept`, `decline` (`app/dispatch/order_dispatch.py:596,605,681`) and no `get_order`. Introduced in Maria's commit `2d59729` (2026-09-23). Seven tests in the normal suite fail because of it. |
| H2 | Cross-driver access to deliveries and proof of delivery | **CONFIRMED** | `app/api/routes/deliveries.py:58-111`: fetches by delivery id, checks only the state machine, then writes the status and an audit row as the caller. `app/api/routes/pod.py:26-46` (upload) and `:129-147` (read) fetch by delivery id and never check the delivery belongs to the caller's shift. |
| H3 | Any authenticated driver can read the whole fleet | **CONFIRMED, with context** | `app/api/routes/fleet.py:35-45` returns every driver's phone number and live coordinates; `/incidents` and `/analytics` use the same `get_current_driver` gate. Context the report lacks: the app has **no operator or dispatcher role at all** today (`app/dependencies.py` only has `get_current_driver`). A fix needs a role design first, not just a check. |
| H4 | Shift stats and manual LeMUR analysis skip the ownership check | **CONFIRMED** | `app/api/routes/shift.py:221-242` (stats at 222, analyze at 232): `/stats` and `/analyze-lemur` take `shift_id` from the path with no owner check. The queue and report routes do check (`:102-105`, `:189-191`), so the pattern exists to copy. |

### Medium

| # | Report finding | Verdict | Evidence in code |
|---|---|---|---|
| M1 | A stale REST queue response can overwrite a newer WebSocket update | **CONFIRMED** | `frontend/lib/providers/order_queue_provider.dart:85-101` (`refresh`) checks only a reset epoch after its await; `apply()` at `:108-115` replaces the state without bumping any token. This is code the Firstmate frontend worker wrote. |
| M2 | Target acknowledgement can repeat and is not atomic | **CONFIRMED** | `app/services/order_queue_service.py:103-106` (marker built at line 103): marker is `"<date>:<target>"` and the read and write are separate awaits. Reach 3, change to 5, reach 5 on the same day: two announcements. Code the Firstmate backend worker wrote. |
| M3 | Greeting replays on reconnect | **PARTIAL** | `_start_upstream` (`app/api/websocket/voice.py:463-497`) sends the greeting config on every new connection, and a voice change deliberately closes the session so the client reconnects (`:656-675`). So a voice change or dropped connection greets again. Correction: the report says "every upstream start" but the greeting only replays on a *new connection*, not mid-conversation. Real, but a polish item. |

### Low

| # | Report finding | Verdict | Evidence in code |
|---|---|---|---|
| L1 | `pytest.ini` hides 21 test files | **CONFIRMED** | `voiceops-backend/pytest.ini` whitelists 17 files. Includes useful ones (`test_shift_end.py`, `test_driver_ensure_profile.py`, `test_osrm.py`). Some excluded files need `sounddevice` or credentials and must stay opt-in. |
| L2 | Tool reference says 13 tools, registry has 20 | **CONFIRMED** | Registry has 20 tool entries (`app/agents/tool_registry.py`). `docs/VoiceOps_Agent_Tools_Reference.md:139` says "The 13 Tools". `tests/test_tool_registry.py:43` still asserts 14. |
| L3 | Wake model licence is undocumented | **CONFIRMED** | `frontend/README.md` has no licence or attribution line for the bundled model (a case-insensitive search for "licen" finds nothing). Also flagged in the earlier sherpa-onnx scout report. |
| L4 | Two analyzer findings remain | **CONFIRMED** | `frontend/lib/features/map/screens/map_screen.dart:151` (`if` without braces); `frontend/lib/features/voice_onboarding/screens/voice_onboarding_screen.dart:3` (unused `rive` import). |

### Test results and known failures

| Report claim | Verdict |
|---|---|
| Backend 302 passed, 9 failed | *Reviewer-run.* Same 9 the PR workers reported on `staging`. |
| 7 of the 9 are the `get_order` bug, 2 are stale tests | **CONFIRMED** by reading the code for H1 above and the assertions the report names. |
| Frontend 326 passed, analyzer 2 findings | *Reviewer-run.* Matches the frontend worker's 326 and the two known findings. |
| `test_agent_config` stale punctuation (`Hello, Ada!` vs `Hello, Ada.`) | **CONFIRMED**: the calm-opening rewrite in `agent_config.py` changed the greeting text. |
| Parallelism preserved, no n8n in the real-time path | *Reviewer-run / read.* Not re-checked here. |

### Feature verdicts in the report

| Feature | Report | My assessment |
|---|---|---|
| 1 Task-progress reasoning | PASS | Agree (unchanged from earlier audits). |
| 2 Home simplification | PASS | Agree. |
| 3 Greeting and calm replies | FAIL | **Downgrade to PASS with a polish item.** The greeting works. The replay on reconnect is a real but low-severity issue (M3). |
| 4 Sherpa wake word | UNVERIFIED | Agree. Needs a phone. Licence gap is real (L3). |
| 5 MapLibre and motion | UNVERIFIED | Agree. Needs a device. |
| 6 Profile row and error card | PASS | Agree. Note Ez deliberately removed the visible retry card in PR #92, so failures are log-only. |
| 7 Shift end and report | PASS | Agree. |
| 8 Auto-accept and preferences | FAIL | **Agree, but the fault is manual accept (H1), not auto-accept.** Auto-accept has its own tests passing. |
| 9 Sign out | PASS | Agree. |
| 10 Walking and per-mode ETA | PASS | Agree. Walking still follows driving roads (accepted limitation). |
| 11 Queue, progress, target | FAIL | **Agree** (M1, M2). Core behaviour works; the two races are real. |
| 12 Docs and rebrand | FAIL | **Agree** (C2 and L2 are why). The report's "no user-facing VoiceOps string found" was not re-checked here. |

### Not verified here (need a device, an account, or a run)

1. Wake-word accuracy, false accepts per hour, battery, mic handoff (phone).
2. Native MapLibre smoothness and marker alignment (device).
3. Real AssemblyAI greeting and reconnect audio timing (account).
4. Supabase RLS and service-role behaviour (database access), including the older open question about the `drivers` INSERT policy.
5. Real concurrent-driver races on order acceptance (two devices).
6. Twilio call and SMS failure handling (account).

---

## 3. Decisions needed from Ez

1. **The exposed TomTom key.** It must be rotated at TomTom (only the account owner can). Removing it from current files is safe and is included in task F1 below. **Purging it from git history is a separate, destructive step** (rewrites history on a shared repo, breaks everyone's clones) and is not being done without your explicit word. Because the key is already public in history, rotation matters more than the purge.
2. **Fleet endpoints and roles (H3).** There is no operator role in the app. Someone has to decide how dispatchers are identified (a Supabase role claim, a separate table, or a separate token). Until then those three routes stay open to any signed-in driver. Assigned to Maria for the design.
3. **The `/v1/tools/benchmark` endpoint.** It is a demo endpoint. Proposed: remove it or gate it behind a development-only setting. Task F1 will gate it unless you want it kept.

---

## 4. Work split

### A. Firstmate's workers (start now, two at a time)

**Batch 1**

| Task | Scope | Fixes |
|---|---|---|
| **F1 backend security hardening** | Require the signed-in driver on `/v1/tools/*`, derive driver and shift context server-side and ignore caller-supplied identity; gate `/benchmark` to development. Add ownership checks (delivery to shift to driver) on delivery status update, POD upload and POD read, returning 404 on mismatch without breaking the mock and demo flows. Add the ownership check to shift `/stats` and `/analyze-lemur`. Audit the other delivery-id and shift-id routes for the same gap and report. Replace the literal TomTom key in all 8 tracked files with an environment variable read. Add two-driver tests. Do **not** change the fleet routes. | C1, C2 (files only), H2, H4 |
| **F2 queue and target correctness plus polish** | Make the queue provider ignore a stale REST response after a newer `queue_updated`. Make the target acknowledgement once per driver per UTC day regardless of target changes, and race-safe. Greet once per shift instead of on every new connection. Fix the two analyzer findings. Document the wake model licence and attribution (verified from upstream sources, or state clearly that it is unconfirmed). Land this verification file and Maria's handoff file under `docs/`. Tests for each. | M1, M2, M3, L3, L4 |

**Batch 2 (after both finish)**

| Task | Scope | Fixes |
|---|---|---|
| **F3 accept-order repair and test discovery** | If Maria has not already fixed `accept_order`, repair it and restore the seven failing tests; move `pytest.ini` to standard discovery with explicit markers for live, audio and credential tests; fix the stale test expectations. | H1 (fallback), L1 |
| **F4 docs and registry drift** | Regenerate the tool reference from the registry, add a test that fails when the count drifts, update AGENTS.md and the stale tool-count test. | L2 |

### B. Maria (backend owner): handoff file `docs/backend-handoff/review-fixes-for-maria.md`

| # | Item | Why it is hers |
|---|---|---|
| B1 | **Fix `accept_order` (`delivery.py:369`)**: add a lock-safe `get_order` lookup or use `accept()`'s own result. Small, urgent, from her commit `2d59729`. If she does it first, F3 drops it. | Her dispatcher and her regression; direct pushes have collided with workers before. |
| B2 | **Operator and dispatcher role design** and authorization for `/v1/fleet/*` (drivers, incidents, analytics); return only the fields a dispatcher needs. | Needs a product and data-model decision on roles. |
| B3 | **Review Supabase RLS and service-role boundaries** for `deliveries`, `proof_of_delivery`, `driver_preferences`, `drivers` (including the open INSERT-policy question). The workers have no database access. | Needs database access. |
| B4 | **TomTom account**: rotate the key, put the new one in the deployment environment only. | Account owner action (with Ez). |
| B5 | **Performance review** (no measured problems were found; these are unmeasured candidates): the queue snapshot is rebuilt with database reads on every status change; preference reads in the auto-accept path; per-connection greeting and context loading. Measure before changing anything. | Needs production-like data and her deployment metrics. |
| B6 | **Real-service checks**: AssemblyAI reconnect and greeting timing, Twilio failure handling, two-device order race. | Needs live accounts. |
| B7 | **Self-hosted OSRM** with real walking and cycling profiles, so walking mode routes on footpaths (follow-up from PR #93). | Infrastructure. |

### C. Ez

1. Rotate the TomTom key with Maria (B4) and decide on the git-history purge (section 3).
2. Phone tests: wake word, map smoothness, mic handoff.
3. Merge the batch 1 pull requests when they land.

---

## 5. Suggested order

1. Now: F1 and F2 in parallel (disjoint files: routes and tests versus the queue provider, queue service and voice greeting).
2. Maria, in parallel: B1 first (small, unblocks acceptance), then B4 and B2.
3. After batch 1 merges: F3 (only if B1 is not done) and F4.
4. Then the device and account checks (C, B6).
