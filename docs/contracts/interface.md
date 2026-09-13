# VoiceOps: Frontend ↔ Backend Interface Contract

**Version:** 1.1 (draft), 2026-09-12. 1.1 records the built WebSocket relay (§1), the
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
| Path | `WS /ws/voice/{shift_id}` |
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

Closing the socket ends the session. The backend then sends `session.end` upstream to AssemblyAI.

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
| `error` | `{"event": "error", "code": "upstream_unavailable", "message": "…"}` | degraded-state banner (`frontend.md` § WebSocket Handling) |
| audio | binary PCM16 / 24 kHz / mono | the co-rider's voice. Push-to-talk shows `speaking` while it plays |

**Field vocabularies**

- `agent_state.state` ∈ `idle | thinking | calling | mapping | task | summarizing | celebrating`.
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
| `reply.audio` | binary audio frame |
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
| shift end (`POST /v1/shift/{id}/end`) | the same summary sequence, carrying the LeMUR `executive_summary`, then `agent_state: idle`. It goes to every socket open on that shift |
| `reply.done` (no tool calls that turn) | `reply_done`, then `agent_state: idle` |
| `reply.done` (tool calls that turn) | nothing. The agent speaks again once it has the results, and that reply ends with `reply_done` |
| `session.error`, upstream drop, `session.ended` | `error` (`upstream_timeout` for AssemblyAI's `agent_timeout`, otherwise `upstream_unavailable`), then close |

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
| GET | `/v1/shift/{shift_id}/report` | none | intelligence report row, or `{"status": "processing", "message"}` |
| GET | `/v1/shift/{shift_id}/stats` | none | `{"total", "delivered", "failed", "success_rate"}` |

A delivery row has these fields (`supabase_schema.sql`): `id, shift_id, recipient_name,
address, phone, status, notes, time_window, latitude, longitude, sequence_order, failure_reason,
created_at, updated_at`. `phone` is server-side only and is stripped before the app sees it.

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
