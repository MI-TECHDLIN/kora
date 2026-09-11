# VoiceOps — Agent Tools Reference

> **Reconstructed edition.** Rebuilt from project context, not the original
> file. If the original surfaces, diff against it and keep the original's
> shapes wherever they differ — the running code and your teammate's work
> follow the original.

This document is the **contract** for the 10 agent tools. The AssemblyAI
Voice Agent calls these tools by name with these exact argument shapes.
A drifted shape produces an agent that works in testing and misfires in
the demo.

Do not invent, rename, or reshape a tool. If a feature needs something
this document does not cover, escalate rather than improvising.

---

## Handler Signature

Every tool handler follows one shape:

```python
async def handler_name(
    args: dict,
    ctx: ToolContext,
) -> ToolResult:
    ...
```

**`ctx: ToolContext`** carries request-scoped state:

| Field | Type | Meaning |
|---|---|---|
| `driver_id` | `str` | authenticated driver, from JWT |
| `shift_id` | `str` | current active shift |
| `adapter` | `LogisticsAdapter` | Onfleet or Mock, resolved per driver |
| `db` | `SupabaseClient` | database handle |
| `session` | `aiohttp.ClientSession` | shared HTTP session |

**`ToolResult`** is what the agent speaks from:

```python
@dataclass
class ToolResult:
    ok: bool
    data: dict | None = None       # on success
    error: str | None = None       # machine code, e.g. "no_active_delivery"
    speech: str | None = None      # natural-language hint for the agent
```

`speech` is a hint, not a script — the Voice Agent LLM composes the final
utterance. Keep it short and factual.

---

## Execution Model

Tools run **in parallel**:

```python
results = await asyncio.gather(
    *[dispatch(call) for call in tool_calls],
    return_exceptions=True,
)
```

`return_exceptions=True` is required. One failing tool must not sink the
whole response — the driver hears what succeeded and what did not.

Every handler needs a timeout. Nothing may block the voice loop
indefinitely.

---

## Error Contract

Return a `ToolResult` with `ok=False`. Never raise into the orchestrator,
and never return a stack trace.

Standard error codes:

| Code | Meaning |
|---|---|
| `no_active_delivery` | driver has no delivery in progress |
| `no_active_shift` | no open shift for this driver |
| `not_found` | referenced entity does not exist |
| `forbidden` | entity does not belong to this driver |
| `upstream_timeout` | external API did not respond in budget |
| `upstream_error` | external API returned a failure |
| `rate_limited` | upstream rate limit hit |
| `invalid_args` | arguments failed validation |

---

## The 10 Tools

### 1. `get_next_delivery`

Fetch the driver's next stop.

**Platform:** Onfleet / MockAdapter

**Arguments:** none

**Success `data`:**
```json
{
  "delivery_id": "dlv_8213",
  "sequence": 3,
  "recipient_name": "Adaeze Okafor",
  "address": "14 Adeola Odeku St, Victoria Island, Lagos",
  "lat": 6.4281,
  "lng": 3.4219,
  "phone": "+2348012345678",
  "notes": "Gate code 4417. Call on arrival.",
  "eta_minutes": 12,
  "has_prior_failure": true,
  "prior_failure_reason": "recipient_unavailable"
}
```

**Errors:** `no_active_shift`, `not_found`, `upstream_timeout`

`has_prior_failure` drives the proactive briefing behaviour — the agent
warns the driver before they arrive. Always populate it.

---

### 2. `update_delivery_status`

Mark the current delivery complete or failed.

**Platform:** Onfleet / MockAdapter

**Arguments:**
```json
{
  "delivery_id": "dlv_8213",
  "status": "delivered",
  "note": "Left with security"
}
```

`status` must be a value from the frozen delivery status enum (see
`.claude/rules/contracts.md`). `note` is optional.

**Success `data`:**
```json
{
  "delivery_id": "dlv_8213",
  "status": "delivered",
  "updated_at": "2026-09-10T14:22:31Z",
  "deliveries_remaining": 4
}
```

**Errors:** `not_found`, `forbidden`, `invalid_args`, `upstream_error`

On success the agent auto-announces the next stop. That chaining lives in
the orchestrator, not in this handler.

---

### 3. `log_exception`

Record a delivery exception without closing the delivery.

**Platform:** Supabase

**Arguments:**
```json
{
  "delivery_id": "dlv_8213",
  "reason": "recipient_unavailable",
  "detail": "Nobody at the gate, waited eight minutes"
}
```

**Success `data`:**
```json
{
  "exception_id": "exc_5521",
  "delivery_id": "dlv_8213",
  "reason": "recipient_unavailable",
  "logged_at": "2026-09-10T14:19:02Z"
}
```

**Errors:** `not_found`, `forbidden`, `invalid_args`

Exceptions feed the post-shift failure-pattern analysis. The free-text
`detail` is what AssemblyAI topic detection reads later — preserve it
verbatim.

---

### 4. `get_best_route`

Compute the optimal route to a destination.

**Platform:** Google Directions API

**Arguments:**
```json
{
  "destination_lat": 6.4281,
  "destination_lng": 3.4219,
  "avoid_tolls": false
}
```

Origin is the driver's current position from `ctx`.

**Success `data`:**
```json
{
  "distance_km": 4.8,
  "duration_minutes": 17,
  "duration_in_traffic_minutes": 24,
  "summary": "Ozumba Mbadiwe Ave",
  "polyline": "yzlkA_ijnBn@...",
  "traffic_note": "Heavy traffic on Ozumba Mbadiwe, +7 min"
}
```

**Errors:** `upstream_timeout`, `upstream_error`, `rate_limited`

`polyline` is consumed by `start_navigation` — return it even when the
agent only speaks the duration.

---

### 5. `start_navigation`

Push a computed route to the Flutter map.

**Platform:** internal (WebSocket push to client)

**Arguments:**
```json
{
  "delivery_id": "dlv_8213",
  "polyline": "yzlkA_ijnBn@...",
  "destination_lat": 6.4281,
  "destination_lng": 3.4219
}
```

**Success `data`:**
```json
{
  "navigation_active": true,
  "delivery_id": "dlv_8213"
}
```

**Errors:** `invalid_args`, `not_found`

This emits a frozen WebSocket message type to the client. Do not change
the message shape without updating the Flutter side in the same change.

---

### 6. `call_customer`

Place an outbound voice call to the recipient.

**Platform:** LiveKit SIP/PSTN

**Arguments:**
```json
{
  "delivery_id": "dlv_8213",
  "reason": "arrival_notice"
}
```

`reason` is one of `arrival_notice`, `unable_to_locate`,
`delivery_attempt`.

**Success `data`:**
```json
{
  "call_id": "call_9c22",
  "status": "ringing",
  "to_masked": "+234801****678"
}
```

**Errors:** `not_found`, `forbidden`, `upstream_error`, `rate_limited`

LiveKit enters the system **only here**. It is a separate lane from
AssemblyAI with no overlap. Never return the full customer phone number
to the client — mask it.

Free Build tier allows 1,000 agent minutes/month. Handle quota
exhaustion as `rate_limited` with a spoken fallback suggesting SMS.

---

### 7. `notify_customer`

Send an SMS to the recipient.

**Platform:** Vonage

**Arguments:**
```json
{
  "delivery_id": "dlv_8213",
  "template": "arriving_soon",
  "eta_minutes": 8
}
```

`template` is one of `arriving_soon`, `attempted_delivery`,
`delivered`, `delayed`.

**Success `data`:**
```json
{
  "message_id": "msg_3f81",
  "status": "submitted",
  "to_masked": "+234801****678"
}
```

**Errors:** `not_found`, `forbidden`, `upstream_error`, `rate_limited`

Templates are server-side. Never let the agent compose raw SMS body text
— that is an injection surface and a compliance risk.

---

### 8. `get_next_order`

Fetch upcoming orders beyond the immediate next stop.

**Platform:** Onfleet / MockAdapter

**Arguments:**
```json
{
  "limit": 3
}
```

`limit` defaults to 3, max 10.

**Success `data`:**
```json
{
  "orders": [
    {
      "delivery_id": "dlv_8214",
      "sequence": 4,
      "recipient_name": "Chinedu Eze",
      "area": "Lekki Phase 1",
      "eta_minutes": 31
    }
  ],
  "total_remaining": 4
}
```

**Errors:** `no_active_shift`, `upstream_timeout`

Return `area` rather than a full address — the agent is giving a spoken
preview, not navigation.

---

### 9. `get_shift_summary`

Summarise the current shift so far.

**Platform:** Supabase

**Arguments:** none

**Success `data`:**
```json
{
  "shift_id": "shf_1180",
  "started_at": "2026-09-10T08:02:00Z",
  "elapsed_minutes": 382,
  "completed": 7,
  "failed": 1,
  "remaining": 4,
  "distance_km": 41.6
}
```

**Errors:** `no_active_shift`

---

### 10. `alert_dispatcher`

Escalate to the operator.

**Platform:** Supabase + n8n webhook

**Arguments:**
```json
{
  "severity": "high",
  "reason": "vehicle_breakdown",
  "detail": "Bike chain snapped on Ozumba Mbadiwe, cannot continue"
}
```

`severity` is one of `low`, `medium`, `high`.

**Success `data`:**
```json
{
  "alert_id": "alt_7702",
  "severity": "high",
  "dispatched_at": "2026-09-10T14:31:09Z",
  "channels": ["dashboard", "email"]
}
```

**Errors:** `no_active_shift`, `invalid_args`

The n8n webhook here is **fire-and-forget**. Do not await its response —
that would put n8n in the real-time path and blow the latency budget.

---

## Parallel Call Example

The product claim in one exchange:

> Driver: *"Call the customer, check the best route, and get my next order."*

```python
results = await asyncio.gather(
    call_customer({"delivery_id": "dlv_8213", "reason": "arrival_notice"}, ctx),
    get_best_route({"destination_lat": 6.4281, "destination_lng": 3.4219}, ctx),
    get_next_order({"limit": 1}, ctx),
    return_exceptions=True,
)
```

Three tools fire simultaneously. The Voice Agent composes one unified
spoken response from all three results. Target end-to-end: 200–500ms.

Sequential execution breaks this. It is the single most important
constraint in the backend.

---

## Proactive Behaviours

Three behaviours are orchestrator-level, not tools. Preserve them:

| Behaviour | Trigger |
|---|---|
| Announce next stop | `update_delivery_status` returns success |
| Proactive ETA update | route recalculation shows material delay |
| Prior-failure briefing | `get_next_delivery` returns `has_prior_failure: true` |

---

## Adapter Rule

`get_next_delivery`, `update_delivery_status`, and `get_next_order` all go
through `ctx.adapter`, never directly to Onfleet.

```
LogisticsAdapter (abstract)
├── OnfleetAdapter    primary, OAuth
└── MockAdapter       fallback, seeded Lagos data (7+ deliveries)
```

`MockAdapter` is the demo safety net. Any change to the base class
updates `MockAdapter` in the same commit.

---

## Security

- Never return a full customer phone number or full address to the client
  beyond the active delivery
- Every tool authorises against `ctx.driver_id` — a driver touches only
  their own deliveries
- Never log transcripts, phone numbers, or addresses at INFO level
- Service-role keys stay server-side
