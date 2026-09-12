# VoiceOps: Agent Tools Reference

> **v2.0, generated from code 2026-09-11.** Every argument shape, enum, and result field below
> was read from `app/agents/tool_registry.py` and `app/agents/tools/{delivery,navigation,communication}.py`
> on `features/backend/assemblyai-voice-agent`. That code is the only thing that has actually run
> against AssemblyAI. This edition supersedes the earlier "reconstructed edition". The code's own
> header cites "Agent Tools Reference v1.0", and that original was never recovered.

This document is the **contract** for the 10 agent tools, together with
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
3. The backend runs `execute_tool(name, arguments, context)`, then replies with
   `{"type": "tool.result", "call_id", "result": "<JSON string>", "is_error": bool}`.
   `is_error` is true whenever the result dict contains `error`.
4. The Voice Agent LLM speaks from the result.

---

## Handler Signature

**Code (current contract):**

```python
async def handler(parameters: dict, context: dict) -> dict:
    ...
```

`context` is a plain dict built per session in `app/api/routes/voice_agent.py`:

| Key | Meaning |
|---|---|
| `driver_id` | authenticated driver. **Code today:** the session id, not a JWT subject |
| `driver_name` | spoken name (read by `alert_dispatcher`) |
| `shift_id` | current shift. **Code today:** the session id |
| `session_id` | voice session id |
| `current_delivery` | `{id, recipient_name, address, customer_phone, notes, time_window}`. The delivery the driver is on. **Code today:** hardcoded demo row |
| `location` | optional driver location string (read by `alert_dispatcher`) |

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

**Code today, not built:** each `tool.call` event is dispatched on its own, as it arrives, through
`execute_tool`. There is no orchestrator that gathers several calls. The `_drain_until_reply_done`
docstring's "executes tools in parallel" is aspirational, and so is the backend README's
"asyncio.gather() for sub-500ms" claim (see the open-backend-tasks note in
`.firstmate/rules/backend.md`). Only the Directions call (10 s) and the n8n webhook (5 s) have
timeouts.

---

## The 10 Tools

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
**Platform:** Google Directions API (`departure_time=now`, `alternatives=true`, `traffic_model=best_guess`)

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

`all_routes[].distance` is in metres and `duration` is in seconds (raw from Directions). When
Directions returns nothing, the tool still succeeds:
`{"success": true, "has_faster_route": false, "best_route": {"summary": "Current route", "duration_mins": 14}, "time_saved_mins": 0, "destination_address": "…"}`.
The `polyline` of the chosen route feeds the `map_route` event (`interface.md` §1).

**Gap:** origin and destination are mock coordinates. The Directions call is real when
`GOOGLE_MAPS_API_KEY` is set, and it has a 10 s timeout.

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

**Result fields (code today):**
```json
{
  "success": true,
  "action": "open_navigation",
  "navigation_url": "https://www.google.com/maps/dir/?api=1&destination=6.4286,3.4108&travelmode=driving",
  "address": "22 Victoria Island Drive",
  "message": "Navigation opening to 22 Victoria Island Drive."
}
```

**Contract:** navigation happens inside the app. The backend pushes `screen_navigate` (`map`)
and a `map_route` event (`interface.md` §1), and the Flutter map draws the route. The
`action` / `navigation_url` deep link is a prototype leftover. The frontend must not launch
it, because leaving the app breaks "drivers never touch their phone" (PRD §1). Switching the
handler over is a backend task for the Ez + backend-owner review session.

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

The next order in the queue beyond the current run. *Triggers: "next order in queue",
"what's coming after this", "next job".*
**Platform:** Onfleet / MockAdapter (unassigned task queue)

**Arguments:** none (`{}`)

**Result fields:**
```json
{
  "success": true,
  "has_next": true,
  "external_id": "onfleet_task_xyz",
  "recipient_name": "Emeka Okonkwo",
  "address": "3 Marina Road, Lagos",
  "notes": "Corporate delivery. Security clearance required.",
  "sequence_order": 5
}
```

**Gap:** mock data (`TODO: Query Onfleet`).

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

## Parallel Call Example (target)

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
results. The end-to-end target is 200–500 ms. **Not built yet** (see Execution Model).

---

## Proactive Behaviours (orchestrator-level, not tools; not built yet)

| Behaviour | Trigger |
|---|---|
| Announce next stop | `update_delivery_status` returns `success: true` |
| Proactive ETA update | `get_best_route` shows `has_faster_route` or a material delay |
| Prior-failure briefing | `get_next_delivery` flags a prior failure (field still to be added) |

---

## Adapter Rule

`get_next_delivery`, `update_delivery_status`, and `get_next_order` go through the logistics
adapter, never directly to Onfleet.

```
LogisticsAdapter (abstract)
├── OnfleetAdapter    primary, OAuth
└── MockAdapter       fallback, seeded Lagos data (7+ deliveries)
```

`MockAdapter` is the demo safety net. Any change to the base class updates `MockAdapter` in the
same commit. **Code today:** there is no adapter class yet. The handlers return inline mock
data.

---

## Security

- Never send a full customer phone number or full address to the client beyond the active delivery
- Every tool authorises against the JWT-derived `driver_id`, so a driver touches only their own
  deliveries. Today's hardcoded context doesn't enforce this yet
- Never log transcripts, phone numbers, or addresses at INFO level
- Service-role keys stay server-side
