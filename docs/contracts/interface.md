# VoiceOps: Frontend ↔ Backend Interface Contract

**Version:** 1.0 (draft), 2026-09-11
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

**Code today:** no WebSocket route exists. `app/api/websocket/` is absent and the include is
commented out in `app/main.py`. The only voice path is the REST prototype
`POST /v1/voice-agent` (§2), and it emits none of the events below. The backend README
documents the path as `/ws/voice/{shift_id}?token={jwt}`. This contract keeps that path but
moves the token into the `Authorization` header so REST and WS share one auth scheme
(`contracts.md` § Auth). Building the relay is an open backend task.

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

**Navigation renders in-app.** `map_route` together with `screen_navigate: map` is the whole
navigation contract. The Flutter map draws the route itself (SDD §4.5), and the app never hands
off to an external maps app. Code today: the prototype's `start_navigation` returns a Google
Maps deep-link URL (`navigation_url`). The frontend must ignore it. Changing the handler to
emit `map_route` is a backend task, scheduled for the Ez + backend-owner review session.

**Privacy.** No server event carries a full customer phone number (`backend.md` § Security).
`call_started` carries the name only.

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

**Written but not mounted.** The modules `app/api/routes/{driver,deliveries,shift}.py` are
imported in `main.py` but never passed to `include_router`, so these paths return 404 today.
The paths are the ones the backend README documents:

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
- **Code today:** the voice path does not check a JWT at all. `voice_agent.py` hardcodes the
  driver context and carries the comment "In production this comes from JWT auth". The unused
  `jwt_secret` / `HS256` settings in `config.py` are not part of this contract, because
  validation goes through Supabase. No refresh endpoint exists yet (open item 4).

---

## Open items for sign-off

1. **Turn signalling on push-to-talk release.** No source defines one. The proposal is a
   `{"event": "ptt_release"}` client message, so the backend can end the turn without waiting for
   voice-activity detection. Adopt or drop it at sign-off.
2. **Parallel tool execution** (`asyncio.gather`) is required by `backend.md` and is not built.
   Today each `tool.call` is dispatched on its own. This doesn't change any shape here, but
   `task_step` streams assume several steps can be `active` at once.
3. The comms-provider events (`call_started` / `call_ended`) are deliberately provider-neutral
   while the comms stack is undecided.
4. **Token refresh.** `otp/verify` returns a `refresh_token`, but there is no backend refresh
   endpoint. Decide whether the app refreshes directly with Supabase (`supabase_flutter` is
   already a dependency) or the backend exposes `POST /v1/auth/refresh`.
