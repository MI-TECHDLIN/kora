# Design handoff — Predictive Traffic Intelligence (spoken proactive reroute)

**For:** Maria (FastAPI + agentic workflows) · **Originally written:** 2026-09-16, added to this repo 2026-09-17
**Status:** design doc; mostly implemented since, see the status update below.
**Companion doc:** `exception-management.md` — **read both before starting.** They share the same
plumbing and should land as one branch.

> **Status update (2026-09-21, checked against the code on `staging`):** the core of this proposal has
> since landed. `present_proactive_alert()` in `app/api/websocket/voice.py` now delivers the risk
> engine's alert on the voice socket and queues a spoken `reply.create` through `_announce`
> (Links B and C closed); the event uses the contract's `"event": "PROACTIVE_ALERT"` key
> (`events.proactive_alert()`), a `TOMTOM_API_KEY` startup warning exists (`app/main.py`), and
> `pytest.ini` collects `test_reroute_risk.py`. Still open: the `get_traffic_ahead` tool, `access_notes`,
> and any parking work. As of 2026-09-24, the unused unauthenticated `/ws/driver/{driver_id}` endpoint
> and its duplicate alert push were removed; proactive alerts use only the authenticated voice socket.
> Read the sections below as the original design rationale, not a to-do list.

> **Status update (2026-09-17):** Link A's frontend half (see §3 below) has since been built —
> the app now posts `POST /v1/locations/ping` every 10-15s while a voice session is connected, and
> parses `PROACTIVE_ALERT` events on the **voice socket** (not the driver socket originally
> described below). Links B and C — the backend actually emitting that event on the voice socket
> and routing the risk engine's output through it to AssemblyAI — are still the real gap. Treat the
> frontend-specific parts of §3/§5 as already handled; the backend work described below is still
> open.

---

## TL;DR

You already built this. `risk_engine.py` detects the traffic slowdown, composes the sentence, and
picks the alternate route. What is missing is that **its output never reaches AssemblyAI**, so the
co-rider never says it out loud.

This doc is about closing the remaining links, not building a feature.

**Parking is explicitly out of scope** — reasoning in §6.

---

## 1. The behaviour we want

Driver is en route. Traffic builds ahead. Without being asked, the co-rider speaks:

> *"Traffic ahead adds about 8 minutes on your current route. An alternate route saves 5 minutes.
> Want me to reroute?"*

Driver says "yeah, do it." The agent calls `accept_reroute`, the new line draws on the in-app map.

That sentence is not aspirational — it is `app/services/risk_engine.py:213-215` today.

---

## 2. What already exists (don't rebuild any of this)

| Piece | Where | Notes |
|---|---|---|
| Traffic-aware routing | `app/integrations/traffic_routing.py` | TomTom Routing API, `traffic=true`, returns `traffic_delay_minutes`, `free_flow_eta_minutes`, `geometry`. Needs `TOMTOM_API_KEY` |
| Slowdown detection | `risk_engine._check_reroute_available` (`:180`) | Fires only when time window risk is ≥MEDIUM **and** an alternate saves ≥3 min |
| The spoken sentence | `risk_engine.py:213` | already written |
| Alert de-duplication | `proactive_alert_service.should_alert` | 15-min cooldown keyed `{driver_id}:{risk_type}` |
| Accept path | `accept_reroute` tool | registered in `tool_registry.py`, documented Tools Reference §5.5 |
| Contract entry | `docs/contracts/interface.md:171-192` | `PROACTIVE_ALERT` with `route_suggestion` |
| GPS ping loop (frontend) | `frontend/lib/providers/location_ping_provider.dart` | **built** — posts every 10-15s while a voice session is connected |
| `PROACTIVE_ALERT` parsing (frontend) | `frontend/lib/core/realtime/voice_events.dart`, `frontend/lib/overlays/proactive_alert_card.dart` | **built** — parses the event on the voice socket, draws route suggestions, shows a dismissible card |
| Tests | `tests/test_reroute_risk.py` | ⚠️ not collected — see §5 |

---

## 3. The links to close

### Link A — GPS pings (frontend: done; backend: verify)

`risk_engine.evaluate()` is called from exactly one place: `app/api/routes/locations.py:92`,
inside `POST /v1/locations/ping`. **The frontend now calls this** every 10-15s while a voice
session is connected.

**Sharp edge — this will bite you.** `driver_ws.py:78` also accepts `location_ping` frames, but it
only calls `location_service.process_location_update`. It does **not** call `risk_engine.evaluate`.
The frontend uses the REST route (as recommended below), so this shouldn't currently be hit, but
if anything ever moves ingestion onto the driver socket instead, the risk engine will silently stop
running. **Keep REST `POST /v1/locations/ping` as the one path that runs the risk engine.**

### Link B — the alert needs to reach the app on the voice socket

`alert_service.emit_voice_alert` currently pushes via `driver_ws.ws_manager` →
`/ws/driver/{driver_id}`, which the app does not open. The frontend now parses `PROACTIVE_ALERT`
on the **voice socket** (`/ws/voice/{shift_id}`) instead — the backend needs to emit it there,
not (or not only) on the driver socket.

### Link C — `emit_voice_alert` produces no voice

Despite the name it writes a `dispatcher_alerts` row and sends JSON. It never touches AssemblyAI.

The mechanism that *does* make the co-rider speak unprompted already exists and works:
`VoiceSession._announce(key, instructions)` → `reply.create` sent upstream at a quiet moment
(`app/api/websocket/voice.py:279-289`). "Quiet" = no reply playing or due, driver not talking, no
tool results outstanding. It is what announces order offers today.

**The work is to let the risk engine reach `_announce`.** `voice.py` already exposes a
module-level `present_offer(shift_id, offer)` that reaches into live sessions by shift — the same
shape works here. Something like a `present_alert(driver_id, risk)` that finds the driver's live
voice session and queues an announcement, and also emits `PROACTIVE_ALERT` on that same voice
socket connection so the frontend's already-built handler can draw the route suggestion.

**Open design choice for you (§7 Q1):** does the risk alert go out as `reply.create` instructions
(LLM phrases it, natural, variable) or as fixed TTS text (deterministic, demo-safe)? The existing
offer path uses instructions. Consistency argues for instructions; demo nerves argue for fixed.

---

## 4. Proposed new tool — `get_traffic_ahead`

Optional, and **only if you want the driver to be able to ask**. The proactive path above needs no
new tool: it reuses `accept_reroute`. Add this only if "how's traffic?" should work on demand.

Written in the style of `docs/VoiceOps_Agent_Tools_Reference.md`:

### `get_traffic_ahead`

**Description.** Check live traffic conditions on the driver's current route and report any delay,
with an alternate route if one saves meaningful time.

**Trigger phrases:** "how's traffic", "is there traffic ahead", "am I going to get stuck",
"what's the hold-up".

**Arguments**

| Name | Type | Required | Notes |
|---|---|---|---|
| `delivery_id` | string | no | Defaults to the driver's current pending delivery |

**Returns**

```json
{
  "success": true,
  "has_delay": true,
  "traffic_delay_minutes": 8.0,
  "current_eta_minutes": 20,
  "alternate_eta_minutes": 12,
  "time_savings_minutes": 8,
  "geometry": "<encoded polyline>",
  "message": "Traffic ahead adds about 8 minutes. An alternate route saves 8 minutes."
}
```

**Notes.** Thin wrapper over `traffic_routing_client.get_traffic_aware_eta` + the driver's current
position. When `time_savings_minutes < 3`, return `has_delay: false` and no geometry, so the agent
says "you're clear" rather than offering a pointless reroute. If the driver says yes, the agent
follows with the existing `accept_reroute`.

---

## 5. Data, config, and contract fixes

**Config.** `TOMTOM_API_KEY` (`config.py:59`, `tomtom_api_key`). Without it
`get_traffic_aware_eta` returns `None` and the whole reroute path silently no-ops — worth an
explicit startup warning, because the failure is invisible.

**TomTom is now in AGENTS.md's "External APIs" list** (added alongside this doc's port into the
main repo) but still missing from the PRD and Synopsis. Worth adding there too, noting where it
sits relative to OSRM (OSRM for plain routing, TomTom for traffic-aware ETA).

**Contract bug — fix before/alongside wiring Link B.**
`interface.md:177` specifies `{"event": "PROACTIVE_ALERT", ...}`.
`proactive_alert_service.py:73` emits `{"type": "PROACTIVE_ALERT", ...}`.
Every other server→client frame on the voice socket uses `"event"`, and the frontend's already-built
handler expects `"event"`. Pick `"event"`, change the code, and confirm with Ez — the frontend side
is already built expecting it.

**Also decide:** now that proactive alerts are moving onto the voice socket (Link B), does
`PROACTIVE_ALERT` still need to exist on the driver socket at all? Two channels carrying the same
event is how this got disconnected in the first place.

**Tests don't run.** `pytest.ini` restricts collection:

```ini
python_files = test_tools_unit.py test_twilio.py test_milestones_unit.py
```

`tests/test_reroute_risk.py` — the tests for exactly this feature — **is never collected.** Same
for `test_order_dispatch.py`, `test_voice_ws.py`, `test_parallel_tools.py`. Worth widening to
`test_*.py` and fixing whatever falls out; otherwise this ships unverified.

---

## 6. Parking — deferred, and why

The review recommends **not** building the parking half for the hackathon:

- **No data source.** Nothing in the repo models parking. Real kerbside/parking-availability data
  (INRIX, ParkWhiz, SpotHero, TomTom Parking Availability) is paid, permissioned, and thin for the
  demo area. Van-appropriate kerbside availability is not a solved dataset anywhere.
- **Faking it is worse than omitting it.** A hardcoded "try the side street" is precisely what
  invites the judge's follow-up question.

**The honest substitute, if Ez wants the flavour:** a per-stop `access_notes` text column
on `deliveries`, authored by dispatcher or driver, spoken during the existing next-stop
announcement — *"heads up, this one's a locked gate, the bay is round the back."* Real data, no
invented API, ~1 day. It also directly feeds `exception-management.md`'s gate check-in, which is
why the two docs are a bundle.

---

## 7. Open questions for you

1. **`reply.create` instructions vs fixed TTS text** for proactive risk alerts (§3, Link C).
   Consistency with the offer path says instructions; demo determinism says fixed.
2. **One ingestion path or two?** Keep REST `/v1/locations/ping` as the only risk-engine entry
   (recommended, and what the frontend already assumes), or also run the engine in `driver_ws`?
3. **Ping cadence.** The frontend already pings every 10-15s. `_check_idle_time` needs 5–6
   consecutive pings, so cadence directly sets how long "stationary too long" actually means. At
   15s that's ~75s, not the "over 5 minutes" the message claims — the message and the cadence must
   agree.
4. **Where does the alert go when the driver has no open voice session?** Currently it still writes
   `dispatcher_alerts`. Keep that as the fallback, or suppress?
5. **Do we need `get_traffic_ahead` at all** (§4), or is proactive-only enough for the demo?
6. **Cooldown tuning.** 15 min per risk type is in-memory only, so it resets on redeploy. Fine for
   the hackathon? (Flagging, not asking you to fix it.)

---

## 8. Suggested scope for Sep 30

**In:** risk → `_announce` bridge · `PROACTIVE_ALERT` moved onto the voice socket · `event`/`type`
contract fix · TomTom key + startup warning · widen `pytest.ini`.

**Out:** parking availability · `get_traffic_ahead` unless cheap · persistent cooldown storage ·
any new external data provider.
