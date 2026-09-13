# VoiceOps: Agent Tools Reference

> **v2.4, 2026-09-13.** v2.4 records that the app's offer card can invoke `accept_order` (§12)
> and `decline_order` (§13) directly through additive client WebSocket events. The tool argument
> and result shapes are unchanged.
> **v2.3, 2026-09-13.** v2.3 adds new-order dispatch: `get_next_order` now reads the live
> order queue (§8), and two tools answer an offer, `accept_order` (§12) and `decline_order`
> (§13). The agent also announces offers unprompted (see Proactive Behaviours).
> **v2.2, 2026-09-13.** v2.0 was generated from code on 2026-09-11. Every argument shape, enum,
> and result field below was read from `app/agents/tool_registry.py` and
> `app/agents/tools/{delivery,navigation,communication}.py`. v2.1 adds the WebSocket relay's
> wiring and context, the in-app `start_navigation` result (§5), and position-aware routing
> (§4), and adds an 11th tool, `show_screen` (§11). v2.2 moves routing (§4, §5) from Google Directions
> to OSRM and leaves every shape unchanged. This edition supersedes the earlier "reconstructed edition". The code's own header cites
> "Agent Tools Reference v1.0", and that original was never recovered.

This document is the **contract** for the 13 agent tools, together with
`docs/contracts/interface.md`. The AssemblyAI Voice Agent calls these tools by name with these
exact argument shapes. A drifted shape gives you an agent that works in testing and misfires in
the demo.

Do not invent, rename, or reshape a tool. If a feature needs something this document doesn't
cover, escalate rather than improvising (`.firstmate/rules/contracts.md`).

Each section is split in two:
- **Contract.** The shape both sides build against. For arguments and result fields this is
  exactly what the code does.
- **Code today / gap.** Where the prototype has not reached the contract yet. These are open
  backend tasks, not permission to drift.

---

## How Tools Are Wired

1. At session start the backend sends AssemblyAI a `session.update` whose `tools` array is
   `get_tools()`. Each entry is `{"type": "function", "name", "description", "parameters": <JSON Schema>}`.
2. AssemblyAI emits `{"type": "tool.call", "name", "call_id", "arguments": {…}}`.
3. The backend runs `execute_tool(name, arguments, context)` as soon as the call arrives. On
   that turn's `reply.done` it replies with
   `{"type": "tool.result", "call_id", "result": "<JSON string>", "is_error": bool}`.
   AssemblyAI accepts results only after `reply.done`. `is_error` is true whenever the result
   dict contains an `error` key, even an empty one.
4. The Voice Agent LLM speaks from the result. Meanwhile the WebSocket relay mirrors the call to
   the app as UI events (`docs/contracts/interface.md` §1, "What emits each event").

---

## Handler Signature

**Code (current contract):**

```python
async def handler(parameters: dict, context: dict) -> dict:
    ...
```

`context` is a plain dict built once per voice session by the WebSocket relay
(`app/api/websocket/voice.py`). The REST harness `app/api/routes/voice_agent.py` still builds a
hardcoded one.

| Key | Meaning |
|---|---|
| `driver_id` | authenticated driver, the Supabase user id from the bearer token |
| `driver_name` | spoken name (read by `alert_dispatcher`). From the `drivers` row, else the auth metadata |
| `vehicle_type` | `drivers.vehicle_type`, or `null` |
| `shift_id` | the socket's shift, checked to belong to `driver_id` |
| `session_id` | the `voice_sessions` row id, or `null` if it could not be created |
| `current_delivery` | `{id, recipient_name, address, customer_phone, notes, time_window, latitude, longitude, sequence}`. The delivery the driver is on. It starts as the shift's next pending delivery from Supabase, and a successful `get_next_delivery` replaces it |
| `deliveries` | `{delivery_id: stop}` for every delivery this session has seen, in the `map_route` stop shape. The navigation tools read destinations from it |
| `latitude`, `longitude` | the driver's last known position: the latest `location_pings` row for the shift, refreshed before each routing tool. Absent until the app posts a ping |
| `location` | optional driver location string (read by `alert_dispatcher`). The relay doesn't set it |

**Target:** a typed `ToolContext` (`driver_id` from the JWT, `shift_id`, `adapter:
LogisticsAdapter`, `db`, `session: aiohttp.ClientSession`), with handlers typed
`(args: dict, ctx: ToolContext) -> ToolResult`. When this lands, the argument and field names
below must not change.

---

## Result Envelope

**On the wire today** every handler returns a flat dict:

```json
{"success": true,  "...tool fields...": "...", "message": "Speakable one-liner."}
{"success": false, "error": "free-text reason"}
```

**Target envelope.** It sits on top of the same fields and renames or drops none of them:

```python
@dataclass
class ToolResult:
    ok: bool                  # == success
    data: dict | None = None  # == every tool field except success / error / message
    error: str | None = None  # machine code from the table below (today: free text)
    speech: str | None = None # == the tool's `message` field: a hint, not a script
```

`speech` is a hint, not a script. The Voice Agent LLM composes the final utterance. Keep it
short and factual.

### Error codes (target)

Handlers never raise into the orchestrator and never return a stack trace. `execute_tool`
already catches exceptions and returns `{"success": false, "error": str(e)}`. The target
replaces the free text with one of these codes:

| Code | Meaning |
|---|---|
| `no_active_delivery` | driver has no delivery in progress |
| `no_active_shift` | no open shift for this driver |
| `not_found` | referenced entity does not exist (includes unknown tool name) |
| `forbidden` | entity does not belong to this driver |
| `upstream_timeout` | external API did not respond in budget |
| `upstream_error` | external API returned a failure |
| `rate_limited` | upstream rate limit hit |
| `invalid_args` | arguments failed validation |

---

## Execution Model

**Required (`.firstmate/rules/backend.md`):** tools run **in parallel** with
`asyncio.gather(*[dispatch(c) for c in tool_calls], return_exceptions=True)`. One failing tool
must not sink the whole response. Every handler needs a timeout.

**Code today, built in the WebSocket relay.** Each `tool.call` starts as an asyncio task as
soon as it arrives. On `reply.done` the relay runs `asyncio.gather(..., return_exceptions=True)`
over that turn's tasks and sends every `tool.result`. Each call has a 10 s budget
(`TOOL_TIMEOUT` in `voice.py`). A call that runs over it returns
`{"success": false, "error": "<tool> took too long to respond."}`. The REST harness
`voice_agent.py` still sends each result as its tool finishes, before `reply.done`, which
AssemblyAI's protocol does not allow.

---

## The 13 Tools

### 1. `get_next_delivery`

The next delivery in the current shift. *Triggers: "next stop", "where to?", "next delivery".*
**Platform:** Onfleet / MockAdapter (via Supabase)

**Arguments:** none (`{}`)

**Result fields:**
```json
{
  "success": true,
  "has_next": true,
  "delivery_id": "uuid",
  "recipient_name": "Amara Johnson",
  "address": "14 Broad Street, Lagos Island",
  "latitude": 6.4541,
  "longitude": 3.3947,
  "notes": "Ring bell twice. 3rd floor.",
  "time_window": "2:00 PM – 4:00 PM",
  "sequence": 4
}
```

**Gap:** returns mock data (`TODO: Query Supabase`). The prior-failure briefing behaviour needs
a `has_prior_failure` field. That would be an additive change and is not in the code yet.

---

### 2. `update_delivery_status`

Mark the current delivery delivered, failed, or rescheduled. *Triggers: "mark as delivered",
"done", "package delivered", "failed", "nobody home".*
**Platform:** Onfleet / MockAdapter (status synced to Supabase and the platform)

**Arguments:**
```json
{
  "status": "delivered",
  "failure_reason": "",
  "notes": "Customer signed on delivery"
}
```

| Arg | Type | Required | Values |
|---|---|---|---|
| `status` | string | yes | `delivered` \| `failed` \| `rescheduled` |
| `failure_reason` | string | no | free text, used when `status` is `failed` |
| `notes` | string | no | free text |

There is no `delivery_id` argument. The handler acts on `context.current_delivery.id`. It falls
back to an undeclared `parameters.delivery_id`, which the agent is never told about. The status
values are three of the four in the frozen enum (`docs/contracts/interface.md` §3). A driver
never sets `pending`.

**Result fields:**
```json
{
  "success": true,
  "delivery_id": "uuid",
  "status": "delivered",
  "message": "Delivery marked as delivered and synced to platform."
}
```

When this succeeds, the orchestrator announces the next stop. That chaining is not in this
handler.

---

### 3. `log_exception`

Log a delivery exception with a reason and a resolution. *Triggers: "failed delivery",
"wrong address", "gate locked", "package damaged".*
**Platform:** Supabase + Onfleet / MockAdapter

**Arguments:**
```json
{
  "reason": "access_denied",
  "resolution": "reschedule",
  "notes": "Gate code not working, no response from customer"
}
```

| Arg | Type | Required | Values |
|---|---|---|---|
| `reason` | string | yes | `customer_unavailable` \| `wrong_address` \| `access_denied` \| `damaged` \| `other` |
| `resolution` | string | yes | `reschedule` \| `leave_with_neighbor` \| `return_to_depot` \| `await_customer` |
| `notes` | string | no | free text. Post-shift topic detection reads it, so preserve it verbatim |

Like `update_delivery_status`, this acts on `context.current_delivery.id`.

**Result fields:**
```json
{
  "success": true,
  "delivery_id": "uuid",
  "reason": "access_denied",
  "resolution": "reschedule",
  "message": "Exception logged. Resolution: reschedule."
}
```

**Gap:** nothing is persisted yet (`TODO: Log to Supabase`). The system prompt's tool list
leaves this tool out, although `get_tools()` registers it.

---

### 4. `get_best_route`

Best route with traffic. *Triggers: "best route", "any traffic", "check my route", "faster way".*
**Platform:** OSRM (`alternatives=true`, `geometries=polyline`), no live traffic

**Arguments:**
```json
{ "delivery_id": "uuid" }
```

| Arg | Type | Required |
|---|---|---|
| `delivery_id` | string | yes |

The origin is the driver's current position. Destination coordinates come from the delivery.

**Result fields:**
```json
{
  "success": true,
  "best_route": {
    "summary": "Victoria Bridge",
    "distance_km": 3.2,
    "duration_mins": 11,
    "duration_text": "11 mins"
  },
  "time_saved_mins": 7,
  "has_faster_route": true,
  "all_routes": [
    {"summary": "Victoria Bridge", "distance": 3200, "duration": 660, "polyline": "<encoded>"}
  ],
  "destination_address": "22 Victoria Island Drive"
}
```

`all_routes[].distance` is in metres and `duration` is in seconds (from OSRM, rounded to whole
numbers). `summary` is OSRM's leg summary, up to two main road names such as
`"Victoria Bridge, Ahmadu Bello Way"`, or `"Route"` when OSRM gives none. When OSRM returns
nothing, the tool still succeeds:
`{"success": true, "has_faster_route": false, "best_route": {"summary": "Current route", "duration_mins": 14}, "time_saved_mins": 0, "destination_address": "…"}`.
The `polyline` of the fastest entry in `all_routes` feeds the `map_route` event (`interface.md` §1).

The origin is `context.latitude` / `longitude` (the latest GPS ping). The destination is the
delivery's coordinates from `context.deliveries` or `context.current_delivery`. **Gap:** either
one falls back to mock coordinates when the session doesn't know it: origin `6.44, 3.39`,
destination `22 Victoria Island Drive`. Routes come from OSRM (`app/integrations/osrm.py`) with
an 8 s client timeout and no API key: the public demo server `router.project-osrm.org` unless
`OSRM_BASE_URL` points at a self-hosted `osrm-routed`. OSRM has no live traffic, so durations
are typical driving times and the first route is already the fastest (`has_faster_route` is
false). No route, an OSRM error, or an unreachable server all mean no routes.

---

### 5. `start_navigation`

Start navigation to the delivery. *Triggers: "navigate", "take me there", "get directions".*
**Platform:** internal. Navigation renders **in-app** on the Flutter map.

**Arguments:**
```json
{ "delivery_id": "uuid" }
```

| Arg | Type | Required |
|---|---|---|
| `delivery_id` | string | yes |

**Result fields:**
```json
{
  "success": true,
  "delivery_id": "uuid",
  "address": "22 Victoria Island Drive",
  "latitude": 6.4286,
  "longitude": 3.4108,
  "route": {
    "polyline": "<Google encoded overview polyline>",
    "summary": "Victoria Bridge",
    "distance_km": 3.2,
    "duration_mins": 11,
    "duration_text": "11 mins"
  },
  "message": "Route to 22 Victoria Island Drive is on your map: 11 mins via Victoria Bridge."
}
```

`route` is the fastest OSRM route from the driver's position, in exactly the `map_route`
route fields. `distance_km` is rounded to one decimal place and `duration_mins` is whole
minutes. `route` is `null` when OSRM returns nothing, and then the message is
"<address> is on your map." The origin and destination come from the same place as in
`get_best_route` (§4).

**Contract:** navigation happens inside the app. For this tool the relay pushes
`screen_navigate` (`map`) and a `map_route` event built from `route` (`interface.md` §1), and
the Flutter map draws the route. There is no deep link. Before 2026-09-12 the handler returned
`action: "open_navigation"` and a Google Maps `navigation_url`. Both are gone, because leaving
the app breaks "drivers never touch their phone" (PRD §1).

---

### 6. `call_customer`

Call the customer. *Triggers: "call the customer", "ring the customer", "call them".*
**Platform:** comms provider **pending decision**. Earlier docs say LiveKit SIP/PSTN, and the
prototype calls Twilio. The shapes below don't depend on the provider.

**Arguments:**
```json
{
  "delivery_id": "uuid",
  "message": "Your delivery driver is on the way and will arrive in 5 minutes."
}
```

| Arg | Type | Required | Notes |
|---|---|---|---|
| `delivery_id` | string | yes | |
| `message` | string | no | spoken to the customer when the call connects. The default is a generic "your delivery driver is calling" line |

**Result fields:**
```json
{
  "success": true,
  "call_sid": "CA123…",
  "customer_name": "Amara Johnson",
  "customer_phone": "+2348012345678",
  "message": "Calling Amara Johnson now."
}
```

`call_sid` is the provider's call id, and it becomes `call_id` in the `call_started` event.
The relay sends `call_ended` when the driver sends `end_call`, which also hangs up a real call,
or when polling the provider shows the call has finished. A mock call (`mock-call-…`) ends only
on `end_call` or when the socket closes.
Failure example: `{"success": false, "error": "No customer phone number on file."}`. Without
provider credentials or a from-number, the handler returns a mock success with
`"call_sid": "mock-call-<delivery_id>"`.

**Gap:** `customer_phone` is returned unmasked. The result goes to the LLM, not to the app, but
the Security rules below still say mask it. The phone and name are mock data.

---

### 7. `notify_customer`

SMS the customer. *Triggers: "message the customer", "tell customer I'm close", "send ETA",
"I'm 5 minutes away".*
**Platform:** comms provider **pending decision**, same situation as `call_customer`.

**Arguments:**
```json
{
  "delivery_id": "uuid",
  "message_type": "nearby",
  "custom_message": ""
}
```

| Arg | Type | Required | Values |
|---|---|---|---|
| `delivery_id` | string | yes | |
| `message_type` | string | yes | `on_my_way` \| `nearby` \| `running_late` \| `missed` \| `custom` |
| `custom_message` | string | no | body text, used only when `message_type` is `custom` |

The server-side templates are `on_my_way` ("…your driver is on the way."), `nearby` ("…your
driver is nearby — please be ready to receive your delivery."), `running_late` ("…running
slightly late but will be there soon."), and `missed` ("…attempted delivery but missed you.
Please call to reschedule."). An unknown type falls back to `nearby`.

**Result fields:**
```json
{
  "success": true,
  "status": "delivered",
  "message_sid": "SM…",
  "customer_name": "Amara Johnson",
  "message_sent": "Hi Amara, your driver is nearby — please be ready to receive your delivery.",
  "message": "SMS sent to Amara Johnson."
}
```

`message_sid` is absent in mock mode.

**Open point:** `custom` lets the agent compose raw SMS text. The reconstructed edition banned
that as an injection and compliance risk. Whether to keep `custom` is for the backend review
session. Until then it is part of the contract because the code ships it.

---

### 8. `get_next_order`

The next new order waiting for a driver: the one offered to this driver, else the nearest
unassigned one. *Triggers: "next order in queue", "what's coming after this", "next job",
"any new orders".*
**Platform:** order dispatcher (`app/dispatch/order_dispatch.py`), fed by the logistics adapter

**Arguments:** none (`{}`)

**Result fields:**
```json
{
  "success": true,
  "has_next": true,
  "order_id": "uuid",
  "external_id": "MLX-20260913-7F3K2Q",
  "status": "offered",
  "offered_to_you": true,
  "recipient_name": "Priya Patel",
  "address": "812 Lavaca St, Apt 3B, Austin, TX 78701",
  "notes": "Leave with the front desk.",
  "time_window": "3:00 PM – 5:00 PM",
  "distance_km": 0.51,
  "expires_in_s": 52,
  "sequence_order": null,
  "message": "Order offered to you: 812 Lavaca St, Apt 3B, Austin, TX 78701, 0.5 km away. Accept or decline it."
}
```

The 2.1 fields stay. `sequence_order` is always `null`, because an order has no place on a run
until a driver accepts it. `status` is `offered` or `unassigned` (`interface.md` §3).
`expires_in_s` is `null` unless the order is offered to this driver. `distance_km` is
straight-line from the driver's last ping, or from the demo area centre when there is none.
With nothing waiting the result is
`{"success": true, "has_next": false, "message": "No new orders are waiting right now."}`.

Changed 2026-09-13. Before this, the tool returned one hardcoded order.

---

### 9. `get_shift_summary`

Shift statistics and progress. *Triggers: "how am I doing", "how many left", "my progress",
"shift summary".*
**Platform:** Supabase (aggregated shift stats)

**Arguments:** none (`{}`)

**Result fields:**
```json
{
  "success": true,
  "total": 22,
  "delivered": 14,
  "failed": 2,
  "remaining": 6,
  "success_rate_percent": 87.5,
  "avg_time_per_stop_mins": 6.3,
  "message": "14 of 22 complete. 6 remaining. 2 failed."
}
```

**Gap:** mock data (`TODO: Query Supabase`). This is the in-shift summary. The post-shift LeMUR
report is a separate pipeline.

---

### 10. `alert_dispatcher`

Escalate to the dispatcher. *Triggers: "alert the dispatcher", "contact dispatch", "I need help".*
**Platform:** Supabase + n8n webhook (fire-and-forget)

**Arguments:**
```json
{
  "delivery_id": "uuid",
  "message": "Customer is being aggressive. Need support at 14 Broad Street.",
  "priority": "urgent"
}
```

| Arg | Type | Required | Values |
|---|---|---|---|
| `delivery_id` | string | no | |
| `message` | string | yes | free text |
| `priority` | string | yes | `normal` \| `urgent` |

**Result fields:**
```json
{
  "success": true,
  "priority": "urgent",
  "message": "Dispatcher has been alerted."
}
```

**Side effect:** fires the n8n dispatcher-alert webhook in the background
(`trigger_dispatcher_alert_background`). The handler never awaits it, which keeps n8n out of the
real-time path. The mapping is `urgent` → `severity: "critical"`, `alert_type: "safety_incident"`,
and `normal` → `severity: "normal"`, `alert_type: "driver_alert"`. The payload also carries
`driver_id`, `driver_name`, `location` (from `context.location` or the current delivery's
address), `shift_id`, `timestamp`, and `dispatcher_email`. The workflow is `n8n/workflows/dispatcher_alerts.json`,
and alerts land in the `dispatcher_alerts` table.

---

### 11. `show_screen`

Open one of the app's screens when no other tool would. *Triggers: "open the map", "where am
I", "zoom to my location" (`map`), "show my vehicle", "my profile" (`settings`), "show my
summary" (`summary`), "go home" (`voice`).*
**Platform:** internal. The relay emits `screen_navigate` with this screen.

Added 2026-09-12. The routing tools already open the map, and `call_customer` opens the call
overlay. Without this tool, nothing could take the driver to `settings` (where the app shows
the driver's vehicle from `GET /v1/driver/profile`) or open the map on their live position when
there is no route. It adds no WebSocket event. It reuses `screen_navigate` and its frozen
`screen` enum.

**Arguments:**
```json
{ "screen": "settings" }
```

| Arg | Type | Required | Values |
|---|---|---|---|
| `screen` | string | yes | `voice` \| `map` \| `summary` \| `settings`. Exactly `screen_navigate.screen` in `interface.md` §1 |

**Result fields:**
```json
{
  "success": true,
  "screen": "settings",
  "message": "Opening your profile and settings."
}
```

Any other `screen` returns `{"success": false, "error": "Unknown screen 'x'. Use one of: voice, map, summary, settings."}`,
and no event is sent.

---

### 12. `accept_order`

Take the new order offered to the driver. It becomes the last `pending` stop on their shift.
*Triggers: "yes, I'll take it", "accept", "add it to my run".*
**Platform:** order dispatcher. The logistics adapter is told who has the order.

Added 2026-09-13. Call it only after the driver says yes.

The Flutter offer card can also invoke this handler directly with
`{"event": "accept_order", "order_id": "…"}` on the voice WebSocket. That tap path skips
AssemblyAI and emits the same `order_offer_closed` (`accepted`) event as the voice path.

**Arguments:**
```json
{ "order_id": "uuid" }
```

| Arg | Type | Required | Values |
|---|---|---|---|
| `order_id` | string | no | the `order_offer` / `get_next_order` id. Omit it to accept the order currently offered to the driver. An id the dispatcher doesn't know also falls back to that order, because the offer's id reaches the agent only through one-shot `reply.create` instructions and may be garbled |

A driver can accept the order offered to them, or an `unassigned` order named by its id. An
order offered to another driver is refused.

**Result fields:**
```json
{
  "success": true,
  "order_id": "uuid",
  "delivery_id": "uuid",
  "external_id": "MLX-20260913-7F3K2Q",
  "recipient_name": "Priya Patel",
  "address": "812 Lavaca St, Apt 3B, Austin, TX 78701",
  "latitude": 30.2713,
  "longitude": -97.7455,
  "notes": "Leave with the front desk.",
  "time_window": "3:00 PM – 5:00 PM",
  "sequence": 8,
  "status": "pending",
  "message": "Order accepted. Priya Patel at 812 Lavaca St, Apt 3B, Austin, TX 78701 is now stop 8 on your run. Delivery window 3:00 PM – 5:00 PM."
}
```

`delivery_id` equals `order_id`: the order is now a delivery. The relay adds it to
`context["deliveries"]`, so `start_navigation` can route to it, and it becomes
`current_delivery` if the driver had none. It emits `order_offer_closed` (`accepted`).
Failures: `"No order is waiting for you right now."`, `"That order is offered to another
driver right now."`, `"Someone else already took that order."`, and `"Couldn't reach the order
system. Try accepting again."` (the offer stays open).

---

### 13. `decline_order`

Pass on the new order offered to the driver. It goes to the next-nearest free driver with an
open voice session. *Triggers: "no", "pass", "decline it", "I can't take it".*
**Platform:** order dispatcher (nearest online driver by straight-line distance)

Added 2026-09-13. Call it only after the driver says no.

The Flutter offer card can also invoke this handler directly with
`{"event": "decline_order", "order_id": "…"}` on the voice WebSocket. That tap path skips
AssemblyAI and emits the same `order_offer_closed` (`declined`) event as the voice path.

**Arguments:**
```json
{ "order_id": "uuid", "reason": "Too far from my route" }
```

| Arg | Type | Required | Values |
|---|---|---|---|
| `order_id` | string | no | as for `accept_order`. Omit it to decline the order currently offered to the driver |
| `reason` | string | no | free text. It is logged and not stored |

**Result fields:**
```json
{
  "success": true,
  "order_id": "uuid",
  "status": "offered",
  "passed_to": {"driver_name": "Maria", "distance_km": 5.07},
  "message": "Declined. Passed it to Maria, 5.1 km from the drop-off."
}
```

`passed_to.driver_name` is a first name, or `null` when the driver has no name on file. When no
other online driver is free, `passed_to` is `null`, `status` is `unassigned`, and the message says
the order waits in the unassigned queue. A driver who declines is never offered that order
again. The relay emits `order_offer_closed` (`declined`). With no offer for this driver the
result is `{"success": false, "error": "No order is offered to you right now."}`.

---

## Parallel Call Example

> Driver: *"Call the customer, check the best route, and get my next order."*

```python
results = await asyncio.gather(
    call_customer({"delivery_id": d}, context),
    get_best_route({"delivery_id": d}, context),
    get_next_order({}, context),
    return_exceptions=True,
)
```

Three tools fire at once, and the Voice Agent composes one spoken response from all three
results. The end-to-end target is 200–500 ms. The WS relay does this with one task per
`tool.call`, gathered on `reply.done` (see Execution Model).

---

## Proactive Behaviours (orchestrator-level, not tools; mostly not built)

| Behaviour | Trigger |
|---|---|
| Announce next stop | `update_delivery_status` returns `success: true`. **Code today:** a system-prompt instruction asks the agent to call `get_next_delivery` after a delivery, so the next stop is spoken and drawn on the map. There is no orchestrator-side chaining |
| Proactive ETA update | `get_best_route` shows `has_faster_route` or a material delay |
| Prior-failure briefing | `get_next_delivery` flags a prior failure (field still to be added) |
| Announce a new order offer | The order dispatcher offers this driver an order. **Built:** the relay sends `order_offer` to the app, then AssemblyAI `reply.create` with one-shot instructions at the next quiet moment. The agent reads the offer out and asks; the driver's answer leads to `accept_order` / `decline_order`. If the driver answers on the card instead, a second `reply.create` has the agent confirm the tapped answer in one sentence, only when the offer was already spoken. See `interface.md` §1 |

`reply.create` is the Voice Agent API's documented way to have the agent speak with no user
audio. It is an ordinary LLM turn, not canned TTS, which is why the agent can go straight on to
call a tool from the driver's answer.

---

## Adapter Rule

`get_next_delivery`, `update_delivery_status`, and `get_next_order` go through the logistics
adapter, never directly to Onfleet.

```
LogisticsAdapter (abstract)            app/integrations/logistics/base.py
├── OnfleetAdapter    primary, OAuth   not built
└── MockAdapter       demo feed        app/integrations/logistics/mock_adapter.py
```

`MockAdapter` is the demo safety net. Any change to the base class updates `MockAdapter` in the
same commit. **Code today:** the adapter covers new orders: an order feed in, and write-backs
out (`order_assigned`, `order_unassigned`). `MockAdapter` generates an order every random 3-7
minutes (`ORDER_FEED_*` settings) in downtown Austin, the demo area, as an Order Intake API
payload (`interface.md` §2). `get_next_order`, `accept_order`, and `decline_order` read and
change that queue through the order dispatcher. `get_next_delivery` and
`update_delivery_status` still return inline mock data.

---

## Security

- Never send a full customer phone number or full address to the client beyond the active delivery
- Every tool authorises against the JWT-derived `driver_id`, so a driver touches only their own
  deliveries. Today's hardcoded context doesn't enforce this yet
- Never log transcripts, phone numbers, or addresses at INFO level
- Service-role keys stay server-side
