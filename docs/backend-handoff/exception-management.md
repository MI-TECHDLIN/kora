# Design handoff — Automated Exception Management (proactive dwell check-in)

**For:** Maria (FastAPI + agentic workflows) · **Originally written:** 2026-09-16, added to this repo 2026-09-17
**Status:** design doc; the core is implemented since, see the status update below.
**Companion doc:** `traffic-parking-intelligence.md` — **read that one first.** This feature needs
the same links closed, and the two should ship as one branch.

> **Status update (2026-09-21, checked against the code on `staging`):** the must-have scope in §8 has
> landed. `risk_engine._check_idle_time` is now gated on the 100m stop geofence (or an `arrived`
> delivery), asks a second-person question, adds `prior_failures` context, and reaches the driver
> through `present_proactive_alert()` (`app/api/websocket/voice.py`), the shared bridge described in
> `traffic-parking-intelligence.md`. Still open: `handle_access_denied`, the `check_driver_status`
> tool, handling notes in the next-stop announcement, and a dwell threshold expressed in seconds
> (the check still counts 5 pings). Twilio is what `exception_workflow` calls today.

---

## TL;DR

The detection is built. The resolution machinery is built. What's missing is the **conversation in
the middle**: the co-rider noticing and asking *"are you stuck?"*.

`_check_idle_time` already flags a stationary driver. `exception_workflow` already does call → SMS
→ attempt++ → dispatcher escalation. Between them sits one prompt and one geofence condition.

This is the review's highest-value idea per unit of work — but only *after*
`traffic-parking-intelligence.md`'s Links B and C exist, because it rides on both.

---

## 1. The behaviour we want

Driver pulls up at a stop. Five minutes pass, no movement, no delivery marked. Unprompted:

> **Co-rider:** *"You've been at this stop a while — are you stuck at a gate, or having trouble
> finding the door?"*
> **Driver:** *"Gate's locked, nobody's answering."*
> **Co-rider:** *"Want me to call the customer, or flag it to dispatch?"*
> **Driver:** *"Call them."*

The second and third turns need **no new code** — `log_exception`, `call_customer` and
`alert_dispatcher` are registered tools and the LLM will reach for them once the conversation is
open. The work is getting the *first* turn to happen.

---

## 2. What already exists (don't rebuild)

| Piece | Where | State |
|---|---|---|
| Dwell detection | `risk_engine._check_idle_time` (`:86`) | built — fires on 5+ consecutive pings at speed ≤1.0, current speed ≤2.0 |
| Arrival geofence | `location_service.py:114` | built — `DRIVER_ARRIVED` within 100m of dropoff. **Not currently consulted by the idle check** |
| Autonomous resolution | `services/exception_workflow.py` | built — `handle_customer_unavailable`: call → SMS → `increment_delivery_attempts` → `delivery_events` row → dispatcher escalation (urgent at attempt ≥2) |
| Reachable from voice | `tools/delivery.py:220` | built — `log_exception(reason="customer_unavailable")` already triggers the workflow |
| Exception vocabulary | `tool_registry.py` | built — reasons: `customer_unavailable, wrong_address, access_denied, damaged, other`; resolutions: `reschedule, leave_with_neighbor, return_to_depot, await_customer` |
| Dispatcher escalation | `alert_dispatcher` tool + `n8n/workflows/dispatcher_alerts.json` | built |
| Cooldown | `proactive_alert_service.should_alert` | built — 15 min per `{driver_id}:{risk_type}` |
| GPS ping loop (frontend) | see `traffic-parking-intelligence.md` | **built** — this feature's prerequisite Link A is done |

---

## 3. What is genuinely missing

### 3a. The idle check can't tell a stop from a red light

`_check_idle_time` fires on *any* sustained stillness. A traffic jam, a level crossing, a long
light — all look identical to it. Shipping as-is means the co-rider interrupts a driver sitting in
traffic to ask if they're stuck at a gate, which is worse than silence.

**Fix:** gate `EXCESSIVE_IDLE` on proximity to the current stop — the 100m `DRIVER_ARRIVED`
geofence in `location_service.py:114` already computes exactly this. Only ask "are you stuck at a
gate?" when the driver is actually *at* the gate.

Treat this as **required, not polish.** It is the difference between a proactive agent and a
nagging one, and a judge will notice a false positive instantly.

### 3b. The message is written for a dispatcher, not a driver

Current `recommended_action` (`risk_engine.py:105`):

> *"Driver has been stationary for over 5 minutes. Check if there are vehicle issues or parking
> delays."*

That is third-person status prose for an ops console. It needs to become a second-person question
that invites an answer — the whole point is to open a conversation, not deliver a notification.

Note also that **"over 5 minutes" is a guess about ping cadence.** The check counts 5–6 pings, so
the real duration is `cadence × 5`. At the 10–15s cadence the frontend already uses, that's 50–75
seconds, not 5 minutes. Pick a dwell threshold in *seconds* and derive the ping count from it,
rather than hardcoding a count and describing it in minutes.

### 3c. It can't be spoken yet

Same Link B/C problem as the traffic feature — `emit_voice_alert` sends JSON to
`/ws/driver/{driver_id}`, which the app never opens, and never reaches AssemblyAI. See
`traffic-parking-intelligence.md` §3. **Solve it once; both features use it.**

### 3d. The workflow only handles one exception type

`exception_workflow` implements `handle_customer_unavailable` only. `access_denied` — the locked
gate, Ez's own example — falls through to the generic `log_exception` path: it records the
event but runs no resolution. Worth a sibling `handle_access_denied` (call customer for a gate
code, escalate to dispatch), reusing the same step/guidance shape.

---

## 4. Proposed new tool — `check_driver_status`

The proactive path needs no new tool if the announcement simply opens the conversation and lets the
LLM pick from the existing tools. Add this **only** if you want the dwell state queryable.

Written in the style of `docs/VoiceOps_Agent_Tools_Reference.md`:

### `check_driver_status`

**Description.** Report how long the driver has been stationary and whether they are at a delivery
stop, so the agent can ask a grounded question instead of a generic one.

**Trigger phrases:** internal — fired by the proactive announcement path, not by driver speech.

**Arguments**

| Name | Type | Required | Notes |
|---|---|---|---|
| `driver_id` | string | no | Defaults to the session's driver |

**Returns**

```json
{
  "success": true,
  "is_stationary": true,
  "stationary_seconds": 312,
  "at_stop": true,
  "delivery_id": "…",
  "recipient_name": "Amara Johnson",
  "address": "14 Broad Street",
  "prior_failures": 1,
  "message": "Stationary 5 minutes at stop 4 (14 Broad Street). One prior failed attempt."
}
```

**Notes.** `prior_failures` comes from `attempt_count` on `deliveries` — it lets the co-rider say
*"this one failed last time too"*, which is one of the proactive behaviours AGENTS.md already
promises and nothing currently delivers.

---

## 5. Risks to decide on

**Twilio.** `exception_workflow.handle_customer_unavailable` calls `make_call` / `send_sms` from
`integrations/twilio_client.py`. **Twilio is banned in Ez's country**, and he and Maria are
sourcing a compliant alternative — this is parked, not decided. The interim ruling is *keep
Twilio, don't rip it out, don't touch the docs that mention it*. Flagging so it doesn't become the
thing that blocks the submission video — if the demo is recorded from a compliant environment this
is fine, otherwise the call step needs a stub path.

**False positives.** §3a. The geofence gate is the mitigation.

**Interrupting at a bad moment.** `_announce` already waits for a quiet moment
(`voice.py:279-289`) — reuse it, don't invent a second path.

**Nagging.** The 15-min cooldown is in-memory and resets on redeploy. Probably fine for a
hackathon; worth knowing.

---

## 6. Bonus — the salvageable kernel of "Smart Load Sequencing"

The review recommended **skipping** load sequencing entirely — there's no cargo data model
anywhere in the system (the only cargo attribute at all is an integer `package_count`), and it
inverts the hands-free problem statement: van loading happens parked at the depot with hands free,
the one moment a screen is *better* than voice, not worse. It also structurally fights the
order-dispatch design, which grows a driver's run mid-shift by appending accepted orders, so a
load plan computed up front would be invalidated immediately. Ez confirmed skipping it. But one
piece of it is worth having and belongs on *this* feature's plumbing:

**Handling notes in the next-stop announcement.** When the co-rider announces the next stop, have
it mention handling notes — *"this one's marked fragile"* — from the existing free-text `notes`
column on `deliveries`, or from the `access_notes` column proposed in
`traffic-parking-intelligence.md` §6.

Prompt-template change on an announcement path that already exists. No new data model, no new
tool, no packing heuristic. It delivers the part of Ez's third idea a driver would
actually notice, for about a day of work.

---

## 7. Open questions for you

1. **Dwell threshold in seconds** — 3 min? 5? And derive the ping count from it rather than the
   other way round (§3b).
2. **Geofence-gate `EXCESSIVE_IDLE`, or keep firing anywhere?** Strong recommendation: gate it.
   If you keep it ungated, the message has to be generic enough to make sense in traffic.
3. **Does `handle_access_denied` get built now,** or does `access_denied` stay on the generic
   `log_exception` path for the hackathon?
4. **Open the conversation, or push a notification?** i.e. does the agent ask a question and wait,
   or state a fact? Ez's framing is clearly a *question* — confirm the agent stays in the
   turn and waits for an answer.
5. **`check_driver_status` (§4) — needed, or is the announcement's instruction text enough
   context?**
6. **What happens on no answer?** Driver ignores the check-in. Escalate to dispatch, retry once,
   or drop it silently?

---

## 8. Suggested scope for Sep 30

**In:** geofence-gate `EXCESSIVE_IDLE` · rewrite the message as a driver-facing question · route it
through the shared risk → `_announce` bridge (see `traffic-parking-intelligence.md`) · dwell
threshold in seconds.

**Nice to have:** `handle_access_denied` · `prior_failures` in the check-in · handling notes in the
next-stop announcement (§6).

**Out:** new exception categories beyond the existing enum · persistent cooldown · replacing
Twilio.
