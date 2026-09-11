# Backend Rules — FastAPI

Scope: everything under `backend/`. Do not touch `frontend/` from a
backend task.

---

## Stack

- **Framework:** Python FastAPI, async throughout
- **DB / auth / storage:** Supabase (PostgreSQL)
- **Hosting:** Railway
- **Push:** Firebase FCM
- **Voice:** AssemblyAI Voice Agent API (real-time),
  AssemblyAI Speech Understanding API (post-shift)
- **Calls:** LiveKit SIP/PSTN
- **SMS:** Vonage
- **Async pipeline:** n8n (post-shift only)

---

## The Parallel Rule

Tool calls execute **in parallel**:

```python
results = await asyncio.gather(
    get_best_route(...),
    call_customer(...),
    get_next_order(...),
)
```

Never rewrite this as sequential awaits. The whole product claim rests
on one voice command firing several tools at once and returning a single
unified spoken response. Sequential execution breaks the latency budget
(target 200–500ms) and the demo.

If a tool can fail independently, use `return_exceptions=True` and handle
partial failure — one failed tool must not sink the whole response.

---

## The n8n Rule

n8n is **HTTP-only and cannot receive WebSockets.**

- It belongs to the post-shift async layer, nothing else
- It is invoked as a fire-and-forget webhook at shift end
- Putting it in the real-time path adds 2,000–3,500ms latency

Never route real-time voice traffic through n8n, under any framing.

---

## Voice Path

```
Flutter
  → FastAPI WebSocket
    → AssemblyAI Voice Agent API   (STT + LLM + tool calling + TTS)
      → Tool Orchestrator          (asyncio.gather)
        → Onfleet / Maps / LiveKit / Vonage / Supabase
      → AssemblyAI TTS
  → Driver
```

The Voice Agent API is a **single WebSocket** carrying STT, LLM, tool
calling, and TTS. Do not decompose it into separate service calls.

---

## The 10 Tools

`get_next_delivery`, `update_delivery_status`, `log_exception`,
`get_best_route`, `start_navigation`, `call_customer`, `notify_customer`,
`get_next_order`, `get_shift_summary`, `alert_dispatcher`

Exact input/output JSON shapes and handler signatures are defined in the
**Agent Tools Reference** doc under `docs/`. That document is the
contract. Do not invent or alter a tool shape — if the reference is
missing something, flag it rather than guessing.

Every handler follows the same signature pattern. Match the existing
handlers rather than introducing a new style.

---

## Proactive Behaviours

These are product features, not nice-to-haves. Preserve them:

- auto-announce the next stop when a delivery completes
- proactive ETA updates
- brief the driver on stops that have prior failure history

---

## Logistics Adapter

```
LogisticsAdapter (abstract base)
├── OnfleetAdapter    — primary, OAuth
└── MockAdapter       — fallback, seeded Lagos data (7+ deliveries)
```

- Never call Onfleet directly from a tool handler — go through the adapter
- If you change the base class, update `MockAdapter` in the same change
- `MockAdapter` must stay functional; it is the demo safety net

---

## Post-Shift Pipeline

```
Shift end → FastAPI fires n8n webhook (fire-and-forget)
  → n8n fetches transcripts from Supabase
    → AssemblyAI Speech Understanding
      → parse → store report → email operator
```

Report includes: failure patterns (topic detection), route issues,
customer sentiment, driver performance summary, recommendations (LeMUR).

LeMUR prompts: `failure_patterns`, `route_issues`, `recommendations`.
Model: `anthropic/claude-3-5-sonnet`.

---

## Security

- Never commit `.env`, API keys, tokens, or Supabase service-role keys
- Service-role keys stay server-side, never returned to the client
- Validate and authorise every request — a driver may only read and
  modify their own deliveries
- Never log full transcripts, phone numbers, or customer addresses at
  INFO level

---

## Error Handling

- External API calls need timeouts — none may block the voice loop
  indefinitely
- Failures return structured errors the agent can speak, not stack traces
- Respect rate limits on Onfleet, Google Directions, LiveKit, Vonage
- On a tool failure, the driver should hear what failed and what to do
  next

---

## Verification

```bash
cd backend
pytest                # if tests exist for the touched area
ruff check .          # or the project's configured linter
```

For a bug fix: reproduce it first, then verify the fix removes it.
Do not suppress an error, disable a check, or delete a failing test to
make a problem disappear.

---

## Scope Discipline

- Branch: `features/backend/<feature-slug>` off `staging`
- Do not reformat files you did not otherwise change
- Do not add a dependency without checking the stack above first
- Do not touch `frontend/`
