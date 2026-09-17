# VoiceOps: Frontend ↔ Backend Interface Contract

**Version:** 1.5 (draft), 2026-09-16. 1.5 adds co-rider voice selection via optional `voice` query parameter on `WS /ws/voice/{shift_id}` with allowlist validation and `anna` fallback (§1).
**Version:** 1.4 (draft), 2026-09-14. 1.4 adds traffic-aware routing and proactive reroute suggestions: new `PROACTIVE_ALERT` event with `route_suggestion` field for ROUTE_DEVIATION alerts, and traffic-aware ETA integration in order offers.
**Version:** 1.3 (draft), 2026-09-13. 1.3 lets the offer card answer an order offer over the
voice WebSocket (§1). See "Changes in 1.3". 1.2 added new-order dispatch: the `order_offer` and
`order_offer_closed` events and unprompted agent replies (§1), the Order Intake API (§2), the
server-side order states `offered` and `unassigned` (§3), and the `accept_order` /
`decline_order` tools. See "Changes in 1.2". 1.1 recorded the built WebSocket relay (§1), the
`start_navigation` result change, the `show_screen` tool, and the nullable fields listed under
"Changes in 1.1".
**Status:** DRAFT. It is frozen once Ez (frontend) and the backend owner both sign it off in the
PR that lands it. Until then, treat every cross-layer field as unfrozen.
**Authored from:** the running backend on `features/backend/assemblyai-voice-agent`
(`app/main.py`, `app/api/routes/*`, `app/dependencies.py`, `app/agents/*`,
`supabase_schema.sql`, backend `README.md`), `SDD v2.0 §7`, and the event needs in `PRD v4.0`
§4 and §6-7.
**Rules for changing it:** `.firstmate/rules/contracts.md`. Tool argument and result shapes live
in `docs/VoiceOps_Agent_Tools_Reference.md`. That doc is part of this contract.

This file covers four things: (1) the WebSocket message catalogue, (2) the REST endpoints,
(3) the delivery-status enum, and (4) the JWT auth header. Each section keeps the **contract**
(what both sides build against) separate from **code today** (what the prototype actually does).

---

## 1. WebSocket: the real-time voice channel

| | |
|---|---|
| Path | `WS /ws/voice/{shift_id}[?voice=<voice_id>]` |
| Query params | optional `voice`: co-rider voice choice (allowlist: `alba`, `eve`, `george`, `jane`, `jean`, `mary`, `michael`, `anna`, `charles`, `paul`, `vera`). Case-insensitive. Defaults to `anna` if missing, empty, or unrecognised. |
| Auth | `Authorization: Bearer <access_token>` on the upgrade request (see §4) |
| Text frames | JSON objects, each with an `"event"` key (the SDD §7 convention) |
| Binary frames | audio only: PCM16 little-endian, mono, **24 kHz** |
| Ownership | one socket per app session, owned by a single Riverpod provider (`frontend.md`) |

**Code today:** built. The route is `app/api/websocket/voice.py`, mounted in `app/main.py`,
with event builders in `app/api/websocket/events.py` and tests in
`voiceops-backend/tests/test_voice_ws.py`. The token goes in the `Authorization` header, not
the `?token=` query the backend README used to describe, so REST and WS share one auth scheme
(`contracts.md` § Auth). The socket must be for a shift that belongs to the authenticated
driver. Any other shift gets `auth_failed`. The REST prototype `POST /v1/voice-agent` (§2)
still exists as a test harness and emits none of these events.

### Client → server

| Frame | Shape | Notes |
|---|---|---|
| audio | binary PCM16 / 24 kHz / mono, ~50 ms per frame (2400 bytes) | Sent only while push-to-talk is `recording`. 24 kHz is the Voice Agent API's fixed format (`voice_agent.py` `TARGET_SAMPLE_RATE`), so the backend forwards it without resampling |
| `end_call` | `{"event": "end_call", "call_id": "…"}` | Driver taps "end call" on the call overlay (TechFeasibility §6) |
| `accept_order` | `{"event": "accept_order", "order_id": "…"}` | Driver accepts the visible offer card. The backend calls the existing `accept_order` tool handler directly; no LLM round-trip |
| `decline_order` | `{"event": "decline_order", "order_id": "…"}` | Driver declines the visible offer card. The backend calls the existing `decline_order` tool handler directly; no LLM round-trip |
| `change_voice` | `{"event": "change_voice", "voice": "michael"}` | Driver changes co-rider voice in settings. The backend reconnects the session with the new voice. Voice must be in the allowlist (see WebSocket path parameters). Invalid voices fall back to the current voice. |

Closing the socket ends the session. The backend then sends `session.end` upstream to AssemblyAI.
For either order response, `order_id` is required and must name the offer currently visible on
that socket (otherwise `error` `invalid_message`). Success produces the same `order_offer_closed`
event as a spoken answer. A failure that leaves the offer open produces an `error` event, so the
driver can try again. If the offer closed meanwhile (for example `withdrawn`), its
`order_offer_closed` already says why and no `error` follows.

### Server → client

| Event | Shape | Drives |
|---|---|---|
| `agent_state` | `{"event": "agent_state", "state": "thinking"}` | co-rider mood (`agentStateProvider.setFromKey`) |
| `screen_navigate` | `{"event": "screen_navigate", "screen": "map"}` | tab switch (`navigationProvider.navigateForAgent`) |
| `task_step` | `{"event": "task_step", "step": "Checking delivery route", "status": "active"}` | task progress card |
| `map_route` | see below | map pins, polyline, ETA card |
| `call_started` | `{"event": "call_started", "call_id": "…", "delivery_id": "…", "customer_name": "Amara J.", "sequence": 4}` | call overlay opens |
| `call_ended` | `{"event": "call_ended", "call_id": "…"}` | call overlay closes |
| `summary_chunk` | `{"event": "summary_chunk", "text": "Today you completed…", "final": false}` | Summary screen typewriter; `final: true` on the last chunk |
| `transcript` | `{"event": "transcript", "role": "driver", "text": "What's my next stop?"}` | home-screen transcript display; `role` ∈ `driver` \| `agent` |
| `reply_done` | `{"event": "reply_done"}` | the agent's spoken reply is finished; push-to-talk goes `speaking → idle` |
| `order_offer` | see below | new-order card with a countdown; the co-rider reads it out unprompted |
| `order_offer_closed` | `{"event": "order_offer_closed", "order_id": "…", "outcome": "accepted"}` | the card closes |
| `error` | `{"event": "error", "code": "upstream_unavailable", "message": "…"}` | degraded-state banner (`frontend.md` § WebSocket Handling) |
| `voice_change_accepted` | `{"event": "voice_change_accepted", "voice": "michael", "message": "Voice will change to michael. Reconnecting..."}` | Voice change accepted, client should reconnect with new voice parameter |
| `voice_unchanged` | `{"event": "voice_unchanged", "voice": "anna", "message": "Voice is already set to anna"}` | Voice already set to requested value, no reconnection needed |
| audio | binary PCM16 / 24 kHz / mono | the co-rider's voice. Push-to-talk shows `speaking` while it plays |

**Field vocabularies**

- `agent_state.state` ∈ `idle | thinking | calling | mapping | task | summarizing | celebrating | speaking`.
  These are exactly the `AgentState.riveKey` values in `frontend/lib/mascot/mascot_state.dart`,
  and the same strings feed the Rive state machine later.
- `screen_navigate.screen` ∈ `voice | map | summary | settings` (`MainTab` names in
  `frontend/lib/app/router.dart`). The call overlay is not a screen. It opens on `call_started`.
- `task_step.status` ∈ `pending | active | done` (`TaskStepStatus` in
  `task_progress_provider.dart`). This replaces SDD §7's `"complete"`. `step` is the display
  label and identifies the step within the current task. The client shows "All complete" once
  every known step is `done`.
- `error.code` ∈ `auth_failed | session_expired | upstream_unavailable | upstream_timeout |
  invalid_message | internal`. `message` is short, human-readable, and safe to display.
- `order_offer_closed.outcome` ∈ `accepted | declined | expired | withdrawn` (`OFFER_OUTCOMES`
  in `events.py`). `withdrawn` means the order is gone before this driver could take it: the
  database says it was already assigned.

**`map_route`.** Field names follow the code's `get_next_delivery` and `get_best_route`
outputs:

```json
{
  "event": "map_route",
  "delivery_id": "…",
  "stops": [
    {"delivery_id": "…", "sequence": 4, "recipient_name": "Amara Johnson",
     "address": "14 Broad Street, Lagos Island", "latitude": 6.4541, "longitude": 3.3947}
  ],
  "polyline": "<Google encoded overview polyline>",
  "summary": "Victoria Bridge",
  "distance_km": 3.2,
  "duration_mins": 11,
  "duration_text": "11 mins"
}
```

`stops` holds the one stop being routed to. When Directions returns no route, `map_route`
still arrives with the stop: `polyline` is `""` and `summary`, `distance_km`,
`duration_mins`, and `duration_text` are `null`. The client drops the pin and skips the line.
Without a Google key, the backend's mock route is a straight line from the driver to the stop.
It is a real encoded polyline.

**`order_offer`.** A logistics platform's new order, offered to this driver
(`app/dispatch/order_dispatch.py`). Only a driver with an open voice socket is ever offered
an order. It goes to the nearest one (straight-line distance from their latest GPS ping, or
the demo area centre before the app posts one), one offer per driver at a time. Nothing
reaches a driver without a session: no push, no wake-up. An order with nobody online waits
`unassigned` and is offered when a driver connects. If the socket of a driver holding an offer
closes, the offer moves to the next online driver at once.

```json
{
  "event": "order_offer",
  "order_id": "…",
  "area": "Lavaca St, Austin",
  "latitude": 30.271,
  "longitude": -97.746,
  "distance_km": 0.51,
  "time_window": "3:00 PM – 5:00 PM",
  "package_count": 2,
  "expires_in_s": 75
}
```

Until the driver accepts, the app gets the street and city only (`area`, no house number or
unit), and the drop-off rounded to 3 decimals (about 100 m). It never gets the recipient's name
or phone. `distance_km` is a straight line from the driver. `time_window` and `package_count`
may be `null`. `expires_in_s` counts down from when the event was sent. The offer ends with
`order_offer_closed`. On `accepted` the order is a `pending` stop on this shift, so
`GET /v1/deliveries` returns it with the full address. The driver answers by voice or with the
card's Accept / Decline buttons (the `accept_order` / `decline_order` client events above).

**Traffic-aware enhancement (v1.4):** The order offer now includes traffic-aware ETA information:
```json
{
  "event": "order_offer",
  "order_id": "…",
  "area": "Lavaca St, Austin",
  "latitude": 30.271,
  "longitude": -97.746,
  "distance_km": 0.51,
  "eta_minutes": 12,
  "traffic_delay_minutes": 4,
  "time_window": "3:00 PM – 5:00 PM",
  "package_count": 2,
  "expires_in_s": 75
}
```
`eta_minutes` is the traffic-aware ETA in minutes, and `traffic_delay_minutes` shows how much
longer than free-flow the current traffic conditions add. These fields are computed using the
TomTom Routing API with traffic data and are only present for the winning candidate (not during
candidate ranking to minimize API calls).

**`PROACTIVE_ALERT`.** Proactive alert from the risk engine for time window risks, excessive idle,
or route deviations. The alert is pushed via the driver WebSocket and includes optional route
suggestion data for ROUTE_DEVIATION alerts.

```json
{
  "event": "PROACTIVE_ALERT",
  "severity": "HIGH",
  "risk_type": "ROUTE_DEVIATION",
  "message": "Traffic ahead adds about 8 minutes on your current route. Want me to reroute?",
  "delivery_id": "…",
  "route_suggestion": {
    "eta_minutes": 12,
    "current_eta_minutes": 20,
    "geometry": "route_geometry_string"
  }
}
```

For plain TIME_WINDOW_RISK or EXCESSIVE_IDLE alerts, `route_suggestion` is absent/`null`. Only
ROUTE_DEVIATION alerts include route suggestion data. The frontend can use the `geometry` to draw
the alternate route on the map and display the time savings comparison.

**Unprompted replies.** When an offer arrives, the relay asks AssemblyAI to speak now
(`reply.create`, below). The app then gets agent audio, a `transcript` (`agent`), and
`reply_done` without the driver pressing push-to-talk. Push-to-talk goes `idle → speaking →
idle` for these. The relay waits for a quiet moment first: no reply playing or due, the
driver not talking, and no tool results outstanding.

**Navigation renders in-app.** `map_route` together with `screen_navigate: map` is the whole
navigation contract. The Flutter map draws the route itself (SDD §4.5), and the app never hands
off to an external maps app. `start_navigation` returns route data, not a deep link (Tools
Reference §5).

**Privacy.** No server event carries a full customer phone number (`backend.md` § Security).
`call_started` carries the name only.

### What emits each event

The relay maps AssemblyAI's upstream events and the agent's tool calls onto the catalogue
above. Tool calls in one turn run concurrently from the moment each `tool.call` arrives. The
relay gathers them on the turn's `reply.done`, because AssemblyAI takes `tool.result` only
after that.

| Source | Events sent to the app, in order |
|---|---|
| `reply.audio` (first frame of a burst) | `agent_state: speaking`, then binary audio frame |
| `reply.audio` (subsequent frames) | binary audio frame |
| `transcript.user` | `transcript` (`driver`), then `agent_state: thinking` |
| `transcript.agent` | `transcript` (`agent`) |
| any `tool.call` | `agent_state` (mood below), `task_step` `active` … `task_step` `done` |
| `get_next_delivery` (has a next stop) | `screen_navigate: map`, `map_route` (route from the driver to that stop) |
| `get_best_route` | `screen_navigate: map`, `map_route` (the fastest of `all_routes`) |
| `start_navigation` | `screen_navigate: map`, `map_route` (from the result's `route`) |
| `call_customer` (success) | `call_started`, then `call_ended` on the driver's `end_call` or when the provider reports the call finished |
| `update_delivery_status` → `delivered` | `agent_state: celebrating` |
| `get_shift_summary` | `agent_state: summarizing`, `screen_navigate: summary`, `summary_chunk`s of the tool's `message` |
| `show_screen` | `screen_navigate` with the requested screen |
| order dispatcher offers this driver an order | `order_offer`. At the next quiet moment the relay sends AssemblyAI `reply.create`, and that reply arrives like any other: audio, `transcript` (`agent`), `reply_done`. An offer is spoken again on a new socket, because a new socket is a new conversation |
| `accept_order` (success) | `order_offer_closed` (`accepted`) |
| `decline_order` (success) | `order_offer_closed` (`declined`) |
| app sends `accept_order` / `decline_order` | FastAPI invokes that existing tool handler directly, emitting its normal `task_step`s and `order_offer_closed`; the tap never passes through AssemblyAI. If the offer had already been spoken, the relay then sends `reply.create` so the co-rider confirms the answer in one sentence and doesn't ask again |
| offer window runs out | `order_offer_closed` (`expired`). If the offer had already been spoken, the co-rider says briefly that it timed out. An offer that expires before it was spoken is dropped silently |
| shift end (`POST /v1/shift/{id}/end`) | the same summary sequence, carrying the LeMUR `executive_summary`, then `agent_state: idle`. It goes to every socket open on that shift |
| `reply.done` (no tool calls that turn) | `reply_done`, then `agent_state: idle` |
| `reply.done` (tool calls that turn) | nothing. The agent speaks again once it has the results, and that reply ends with `reply_done` |
| app sends `change_voice` | `voice_change_accepted` (if voice changed) or `voice_unchanged` (if same voice), then socket closes to force reconnection with new voice parameter |
| `session.error`, upstream drop, `session.ended` | `error` (`upstream_timeout` for AssemblyAI's `agent_timeout`, otherwise `upstream_unavailable`), then close |

**`reply.create`** is the Voice Agent API's documented client message for an agent reply with
no user audio: `{"type": "reply.create", "instructions": "<one-shot instructions>"}`. The
instructions don't change the system prompt. The resulting reply is a normal LLM turn, so it
can lead to tool calls. AssemblyAI's docs don't say what happens if it arrives mid-reply, so
the relay never sends it then.

Tool moods: `mapping` for `get_next_delivery`, `get_best_route`, and `start_navigation`.
`calling` for `call_customer`. `summarizing` for `get_shift_summary`. `task` for the rest.
Each `task_step.step` is a fixed label per tool, for example "Checking delivery route" for
`get_best_route` (`TOOL_STEPS` in `events.py`). A failed tool still ends `done`, because the
enum has no failed state. The spoken reply says what failed.

`summary_chunk`s split the text at sentence boundaries. Concatenating every chunk's `text` in
order restores it exactly, whitespace included.

`call_started.sequence` is `null` when the backend doesn't know the stop number for that
delivery. `end_call` for a `call_id` the backend doesn't know still gets a `call_ended` back,
so a stale overlay can close.

**Close codes.** `1008` after `auth_failed` or `session_expired`. `1011` after an upstream or
`internal` error. `1000` when the client closes. An unknown or malformed client frame gets
`error` / `invalid_message` and the socket stays open.

### Driver position and vehicle

Neither needs a new server event. A voice request for either comes through the `show_screen`
tool (Tools Reference §11), which emits the existing `screen_navigate`.

- **Live position** comes from the phone's GPS. The map shows it client-side (`geolocator`,
  planned in `AGENTS.md`). When there is no active route, the map screen follows the driver.
  When a `map_route` arrives, the camera fits the stop and the driver together. If the app
  posts `POST /v1/deliveries/location` pings, the relay uses the latest ping as the route origin
  for the routing tools. Otherwise the origin falls back to a mock position.
- **Vehicle details** are `vehicle_type` and `name` on the driver row, returned by
  `GET /v1/driver/profile` (§2). The relay puts the driver's name and vehicle into the agent's
  system prompt, so the co-rider can answer "what am I riding?" out loud. "Show my vehicle"
  sends `screen_navigate: settings`, and the settings screen renders the profile's vehicle.
- **"Zoom to my location" / "where am I"** sends `screen_navigate: map` with no `map_route`
  after it. The map screen then centres on the driver's live position.

---

## 2. REST endpoints

Base URL: the Railway deployment. JSON in and out. Every endpoint except `/`, `/health`, and
`/v1/auth/*` requires the §4 header.

**Mounted in `app/main.py` today**

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/` | none | `{"message": "VoiceOps API", "version": "1.0.0", "status": "running"}` |
| GET | `/health` | none | `{"status": "ok"}` |
| POST | `/v1/auth/otp/send` | `{"phone": "+234…"}` | `{"message": "OTP sent successfully"}` · 400 on failure |
| POST | `/v1/auth/otp/verify` | `{"phone": "+234…", "token": "123456"}` | `{"access_token", "refresh_token", "user"}` · 401 on failure |
| POST | `/v1/voice-agent` | `{"audio": "<base64 PCM16>", "sample_rate": 24000, "session_id": null}` | `{"audio", "user_transcript", "agent_transcript", "audio_size", "session_id"}` |

`/v1/voice-agent` is a **prototype test harness**, not part of the app contract. It is
unauthenticated, single-shot, and runs with a hardcoded driver context. The app uses the §1
WebSocket.

**Order Intake API.** Server to server: a logistics platform pushes new orders here. The
MockAdapter's order feed builds the same payload internally.

| Method | Path | Request | Response |
|---|---|---|---|
| POST | `/v1/logistics/orders` | `OrderCreatedEvent` (below), header `X-VoiceOps-Signature` | 202 `{"order_id", "external_id", "status", "duplicate"}` · 401 bad or missing signature · 422 invalid payload · 503 intake not configured, or the order could not be stored |

```json
{
  "event": "order.created",
  "source": "mock-logistics",
  "external_id": "MLX-20260913-7F3K2Q",
  "created_at": "2026-09-13T14:02:11-05:00",
  "order": {
    "recipient": {"name": "Priya Patel", "phone": "+15125550142"},
    "dropoff": {"address": "812 Lavaca St, Apt 3B, Austin, TX 78701",
                "latitude": 30.2713, "longitude": -97.7455},
    "notes": "Leave with the front desk.",
    "time_window": {"start": "2026-09-13T15:00:00-05:00", "end": "2026-09-13T17:00:00-05:00"},
    "package_count": 2
  }
}
```

`recipient.phone`, `notes`, `time_window`, `package_count`, and `created_at` are optional.
The time window is stored as display text in the sender's UTC offset ("3:00 PM – 5:00 PM").
This endpoint takes no driver JWT. The platform signs the raw body with the shared secret
`LOGISTICS_WEBHOOK_SECRET` and sends `X-VoiceOps-Signature: sha256=<hex HMAC-SHA256>`. With
no secret configured the endpoint returns 503, so it is never an open write path. Intake is
idempotent on `(source, external_id)`: a repeat returns the first `order_id` with
`duplicate: true`. `status` is the order's state from §3 (`offered` or `unassigned`).

**Also mounted.** `app/main.py` includes the `driver`, `deliveries`, and `shift` routers too.
Until 2026-09-12 they failed with a 500 after auth, because `get_current_driver` returned a
Supabase `User` object that the routes indexed as a dict. It now returns a dict. These paths
match the backend README:

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/v1/driver/profile` | none | driver row (`id, phone, name, vehicle_type, …`) |
| PUT | `/v1/driver/profile` | `{"name"?, "vehicle_type"?}` | updated driver row |
| POST | `/v1/driver/connect` | `{"platform", "connect_code"?, "credentials"?}` | `{"message", "connection"}`. A 6-digit `connect_code` resolves the platform via `operator_codes` |
| GET | `/v1/deliveries?shift_id=…` | none | `{"deliveries": [delivery row, …]}` ordered by `sequence_order` |
| PUT | `/v1/deliveries/{delivery_id}/status` | `{"status", "notes"?, "failure_reason"?}` | updated delivery row. `status` per §3 |
| POST | `/v1/deliveries/{delivery_id}/notify` | `{"message_type", "custom_message"?}` | `{"message", "delivery_id", "message_type"}` (stub) |
| POST | `/v1/deliveries/location?shift_id=…` | `{"latitude", "longitude"}` | stored ping row |
| POST | `/v1/shift/start` | none | `{"shift_id", "status": "active", "message"}` |
| POST | `/v1/shift/{shift_id}/end` | none | `{"shift_id", "status": "completed", "message"}` |
| GET | `/v1/shift/{shift_id}/report` | none | intelligence report row (with optional `"status": "ready"`, `shift_started_at`, `shift_ended_at`), or `{"status": "processing", "message"}` |
| GET | `/v1/shift/{shift_id}/stats` | none | `{"total", "delivered", "failed", "success_rate"}` |

A delivery row has these fields (`supabase_schema.sql`): `id, shift_id, recipient_name,
address, phone, status, notes, time_window, latitude, longitude, sequence_order, failure_reason,
source, external_id, created_at, updated_at`. `phone` is server-side only and is stripped
before the app sees it. `source` and `external_id` name the logistics platform and its order
id, and are `null` for deliveries that didn't come through order intake.

Errors use FastAPI's default `{"detail": "…"}` with 400, 401, 404, or 500.

---

## 3. Delivery-status enum

```
pending | delivered | failed | rescheduled
```

| Value | Meaning | Set by |
|---|---|---|
| `pending` | not yet attempted. This is the DB default, and "next delivery" selects the lowest `sequence_order` among these | backend on import or seed |
| `delivered` | handed over | driver, via the `update_delivery_status` tool or `PUT …/status` |
| `failed` | attempt failed. `failure_reason` holds the reason | driver, same two paths |
| `rescheduled` | moved to a later attempt | driver, same two paths |

Sources: `schemas.py` `DeliveryStatusUpdate` ("pending, delivered, failed, rescheduled"),
`queries.py` (`.eq("status", "pending")`), and the `update_delivery_status` tool enum
(`delivered | failed | rescheduled`; a driver never sets `pending`). Every layer uses these four
values: Flutter, FastAPI, Supabase, and the logistics adapters. **Code today:** the
`deliveries.status` column is a plain `VARCHAR` with no `CHECK` constraint. Adding one is an open
backend task.

**Server-side order states: `offered | unassigned`.** Added in 1.2. A platform's new order is a
`deliveries` row with `shift_id` NULL until a driver accepts it.

| Value | Meaning | Set by |
|---|---|---|
| `offered` | waiting on one driver's answer (`order_offer`) | order dispatcher |
| `unassigned` | no driver has it: nobody online was free, or every online driver declined or let it lapse. Offered again when a driver connects or frees up | order dispatcher |

Acceptance sets `shift_id` and flips the row to `pending`. From then on it is an ordinary
delivery. The app never sees these two values. They exist only on rows with no shift, and
`GET /v1/deliveries`, the stats, and the RLS policy all scope deliveries to a shift. The
driver-facing enum above is unchanged. A logistics adapter must treat both as "not yet a
driver's delivery".

Separate vocabularies, not frozen here and defined in the Tools Reference: `log_exception.reason`
and `resolution`, and `notify_customer.message_type`. Shift status is `active | completed`.

---

## 4. JWT auth header

```
Authorization: Bearer <access_token>
```

- `<access_token>` is the Supabase session access token returned by `POST /v1/auth/otp/verify`
  (phone OTP). The same header goes on every authenticated REST call **and** on the WebSocket
  upgrade request.
- Server side, `app/dependencies.py` `get_current_driver` validates the token with Supabase
  (`supabase.auth.get_user`). The authenticated user id is the `driver_id` that every tool and
  query authorises against.
- Failures return 401 with one of these `detail` values: `"Authorization header missing"`,
  `"Invalid authorization header format"`, or `"Invalid or expired token"`. Over the WebSocket, a
  rejected token closes the socket after an `error` event with code `auth_failed`, or
  `session_expired` if the token expires mid-session.
- **Code today:** `authenticate_bearer` in `app/dependencies.py` validates for both REST and
  the WebSocket. The WS relay builds the tool context from the authenticated driver. Only the
  REST test harness `voice_agent.py` still hardcodes a driver context. The relay reads the
  token's `exp` claim, after Supabase has validated the token, to time `session_expired`. The
  unused `jwt_secret` / `HS256` settings in `config.py` are not part of this contract, because
  validation goes through Supabase. No refresh endpoint exists yet (open item 4).

---

## Changes in 1.1

These change shapes that 1.0 already described. The frontend must handle them.

| Change | Old | New |
|---|---|---|
| `map_route` when Directions returns no route | unspecified | `polyline: ""`, and `summary` / `distance_km` / `duration_mins` / `duration_text` are `null` |
| `call_started.sequence` | always a number | `null` when the stop number is unknown |
| `start_navigation` result (Tools Reference §5) | `action`, `navigation_url` deep link | `delivery_id`, `address`, `latitude`, `longitude`, `route` (the `map_route` route fields, or `null`) |

Additive in 1.1: the `show_screen` tool (Tools Reference §11), which emits the existing
`screen_navigate`.

Everything else in 1.1 documents behaviour that 1.0 had left open: when `reply_done` fires,
close codes, and the source of each event.

---

## Changes in 1.2

All additive. Nothing that 1.1 defined changes shape.

| Addition | Where |
|---|---|
| `order_offer` and `order_offer_closed` server events | §1 |
| Unprompted agent replies (audio, `transcript`, `reply_done` with no push-to-talk) | §1 |
| `POST /v1/logistics/orders` (Order Intake API) | §2 |
| `deliveries.source`, `deliveries.external_id` | §2, `supabase_schema.sql` |
| Server-side order states `offered`, `unassigned` | §3 |
| `accept_order`, `decline_order` tools; `get_next_order` reads the live order queue | Tools Reference §8, §12, §13 |

**Frontend:** the global offer card is driven by `order_offer` / `order_offer_closed`; it stays
visible across all four main tabs. Unprompted replies use the same audio playback path as any
other co-rider reply.

---

## Changes in 1.3

Additive: the `accept_order` and `decline_order` client WebSocket events in §1 let the visible
offer card invoke the same handlers as a voice answer without going through the LLM. When the
co-rider had already spoken the offer, it confirms a tapped answer in one sentence. No existing
client or server event changed shape.

---

## Changes in 1.4

Additive: traffic-aware routing and proactive reroute suggestions.

|| Addition | Where |
|---|---|
| `PROACTIVE_ALERT` server event with optional `route_suggestion` field | §1 |
| `eta_minutes` and `traffic_delay_minutes` fields in `order_offer` event | §1 |
| `accept_reroute` tool for accepting traffic-based reroute suggestions | Tools Reference §5.5 |
| Traffic-aware ETA integration in risk detection and order dispatch | Backend services |

**Frontend:** The order offer card should display traffic-aware ETA and delay information when available. The `PROACTIVE_ALERT` event should be handled to display traffic alerts, and when `route_suggestion` is present, the alternate route should be drawn on the map with time savings comparison. The new `accept_reroute` tool allows drivers to accept suggested reroutes via voice.

---

## Changes in 1.5

Additive: co-rider voice selection and report timings.

| Addition | Where |
|---|---|
| Optional `voice` query parameter on `WS /ws/voice/{shift_id}` with allowlist validation and `anna` fallback | §1 |
| Shift report response optional fields (`status: "ready"`, `shift_started_at`, `shift_ended_at`) | §2 |

**Frontend:** Settings co-rider voice picker passes `?voice=<voice_id>` on the voice WebSocket URI. Unrecognized or missing voices fall back to Anna on the server.

---

## Open items for sign-off

1. **Turn signalling on push-to-talk release.** No source defines one. The proposal is a
   `{"event": "ptt_release"}` client message, so the backend can end the turn without waiting for
   voice-activity detection. Adopt or drop it at sign-off.
2. **Parallel tool execution** is built in the WS relay. Each `tool.call` starts as it
   arrives, and the turn's calls are gathered with `asyncio.gather` on `reply.done`. Several
   `task_step`s can therefore be `active` at once. Nothing is left to decide here unless the
   owners want to reword `backend.md`.
3. The comms-provider events (`call_started` / `call_ended`) are deliberately provider-neutral
   while the comms stack is undecided.
4. **Token refresh.** `otp/verify` returns a `refresh_token`, but there is no backend refresh
   endpoint. Decide whether the app refreshes directly with Supabase (`supabase_flutter` is
   already a dependency) or the backend exposes `POST /v1/auth/refresh`.
