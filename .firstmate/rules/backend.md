# Backend Rules — FastAPI

Scope: everything under `backend/`. Do not touch `frontend/` from a
backend task. `backend/` is not in `main` yet. The prototype lives on the
orphan branch `features/backend/assemblyai-voice-agent`.

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

**Status: not built yet.** The prototype's `execute_tool()` dispatches one
tool per `tool.call` event, and there is no orchestrator. The backend
README's "asyncio.gather() for sub-500ms multi-tool dispatch" claim is
inaccurate. See Open Backend Tasks.

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

## The 13 Tools

`get_next_delivery`, `update_delivery_status`, `log_exception`,
`get_best_route`, `start_navigation`, `call_customer`, `notify_customer`,
`get_next_order`, `accept_order`, `decline_order`, `get_shift_summary`,
`alert_dispatcher`, `show_screen`

Exact input/output JSON shapes and handler signatures are defined in
`docs/VoiceOps_Agent_Tools_Reference.md` (v2.4, generated from the
running code). The Flutter-facing WebSocket, REST, status-enum, and auth
contract is `docs/contracts/interface.md`. Those documents are the
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
- announce a new order offer unprompted (built: the relay sends AssemblyAI
  `reply.create` at a quiet moment, `app/api/websocket/voice.py`)

---

## Logistics Adapter

```
LogisticsAdapter (abstract base)   app/integrations/logistics/
├── OnfleetAdapter    — primary, OAuth (not built)
└── MockAdapter       — demo order feed, downtown Austin
```

- Never call Onfleet directly from a tool handler — go through the adapter
- New orders enter through the adapter's feed or `POST /v1/logistics/orders`,
  and `app/dispatch/order_dispatch.py` offers each to the nearest driver
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
Model: `anthropic/claude-sonnet-5` (current Claude Sonnet, in LeMUR's
`anthropic/<model>` form). Check it against AssemblyAI's supported-model
list when the pipeline is built. No post-shift code exists yet.

Speech Understanding scope: transcription, topic detection (failure
patterns), sentiment (customer mood), and LeMUR (the prompts above plus
the shift summary). Diarization and entity extraction are not needed
because driver and agent turns are stored separately (`voice_sessions`).

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
- Respect rate limits on Onfleet, OSRM (the public demo server is shared), LiveKit, Vonage
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

## Open Backend Tasks

These are gaps between the contract docs and the prototype. They are
tracked here so nobody mistakes the docs for a description of built code.
Where a string or comment needs changing, it waits for the joint Ez +
backend-owner review session.

- **`OnfleetAdapter`**. Not built. `LogisticsAdapter` and `MockAdapter` cover
  new orders only; `get_next_delivery` and `update_delivery_status` still
  return inline mocks
- **REST harness** `POST /v1/voice-agent` still hardcodes its tool context and
  sends each `tool.result` before `reply.done`. The WS relay is the real path
- **System prompt and greeting** say "voice assistant" / "VoiceOps
  assistant". The locked term is **co-rider** (`agent_config.py`)

## Scope Discipline

- Branch: `features/backend/<feature-slug>` off `staging`. PR back into
  `staging`
- Do not reformat files you did not otherwise change
- Do not add a dependency without checking the stack above first
- Do not touch `frontend/`
