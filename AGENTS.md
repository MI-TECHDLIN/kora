# VoiceOps — Agent Context

Read this fully before touching any code. Rule files in `.firstmate/rules/`
carry the detail for each layer. Claude Code loads this file through
`CLAUDE.md`, and Codex and other harnesses read it directly. There is one
file, so the two can't drift apart.

**Which doc wins.** This file, `.firstmate/rules/*`, `docs/product/VoiceOps_PRD_v4.0.md`,
`docs/contracts/interface.md`, and `docs/VoiceOps_Agent_Tools_Reference.md` are current. The
SDD, TechFeasibility, and Synopsis (all v2) are historical and marked superseded. Where they
disagree with the current docs, the current docs win.

---

## What This Is

Voice-first mobile app for last-mile logistics drivers.
A hands-free operations layer: the driver speaks, an autonomous agent acts
across multiple systems in parallel, and the driver hears one unified result.

- **Tagline:** "Talk to your operations. Let your operations talk back."
- **Built for:** AssemblyAI Voice Agent Hackathon, lablab.ai (Sep 1–30, 2026)
- **Problem solved:** the interface gap — drivers cannot safely use
  screen-based apps while riding or driving.

Two distinct value layers:
1. **Real-time voice agent** — during the shift.
2. **Post-shift intelligence** — for operators, after the shift.

---

## Repo Structure (Monorepo)

```
voiceops/
├── frontend/          Flutter app
├── backend/           Python FastAPI + asyncio (not imported yet, see below)
├── docs/              PRD, SDD, TechFeasibility, Synopsis, Agent Tools Reference,
│                      contracts/interface.md, inspiration/
├── AGENTS.md          this file (agent context, all harnesses)
├── CLAUDE.md          @AGENTS.md import pointer for Claude Code
└── .firstmate/rules/  layer-specific rules (frontend, backend, contracts)
```

Frontend and backend live in ONE repo. Do not split them. The backend
prototype currently lives only on `features/backend/assemblyai-voice-agent`,
an orphan branch with no shared history. Bringing it under `backend/` is
the backend owner's call.

---

## Architecture — Non-Negotiable Constraints

**Real-time voice path:**

```
Flutter
  → FastAPI WebSocket
    → AssemblyAI Voice Agent API   (STT + LLM + tool calling + TTS)
      → FastAPI Tool Orchestrator  (asyncio.gather — parallel)
        → Logistics / Maps / LiveKit / Vonage
      → AssemblyAI TTS
  → Driver
```

Three rules that must never be broken:

1. **n8n is ONLY in the post-shift async layer. Never in the real-time path.**
   n8n is HTTP-only and cannot receive WebSockets. Putting it in the
   real-time path adds 2,000–3,500ms latency versus 200–500ms with
   FastAPI asyncio.

2. **Tool calls execute in parallel via `asyncio.gather()`.**
   One voice command can trigger several tools at once. Never rewrite
   parallel execution as sequential awaits. **Not built yet.** The
   prototype dispatches one tool per call. The orchestrator is an open
   backend task.

3. **AssemblyAI Voice Agent API is a single WebSocket** carrying STT, LLM,
   tool calling, and TTS together. Do not split these into separate services.

---

## AssemblyAI Dual Integration

This dual use is the core technical differentiator for the hackathon.
Both layers must remain in the codebase.

| Layer | API | Role |
|---|---|---|
| 1 — real-time | Voice Agent API | STT + LLM + tool calling + TTS over one WebSocket, ~$4.50/hr flat |
| 2 — post-shift | Speech Understanding API | transcription, topic detection (failure patterns), sentiment (customer mood), LeMUR (report prompts + shift summary). Not built yet. Diarization and entity extraction are not needed because driver and agent turns are stored separately |

---

## The 13 Agent Tools

| Tool | What it does | Platform |
|---|---|---|
| `get_next_delivery` | Fetch the next stop | Onfleet / MockAdapter |
| `update_delivery_status` | Mark delivery complete or failed | Onfleet / MockAdapter |
| `log_exception` | Record a delivery exception | Supabase |
| `get_best_route` | Compute optimal route (also routes `start_navigation`) | OSRM, public demo or `OSRM_BASE_URL` |
| `start_navigation` | Push route to the Flutter map (in-app, never a deep link) | internal |
| `call_customer` | Outbound voice call | LiveKit SIP/PSTN |
| `notify_customer` | Outbound SMS | Vonage |
| `get_next_order` | The new order offered to the driver, else the nearest unassigned one | order dispatcher / MockAdapter |
| `accept_order` | Take the offered order as the last stop on the shift | order dispatcher / MockAdapter |
| `decline_order` | Pass the offered order to the next-nearest driver | order dispatcher |
| `get_shift_summary` | Summarise current shift stats | Supabase |
| `alert_dispatcher` | Push alert to operator | Supabase + n8n |
| `show_screen` | Open an app screen by voice (map, settings/vehicle, summary, voice) | internal |

Exact input/output JSON shapes and handler signatures live in
`docs/VoiceOps_Agent_Tools_Reference.md` (v2.4, generated from the running
code). The WebSocket, REST, status-enum, and auth contract is
`docs/contracts/interface.md`. Those two docs are the contract. Do not
invent tool shapes.

**Proactive agent behaviours** that must be preserved:
- auto-announces the next stop after a delivery completes
- proactive ETA updates
- briefs the driver on stops that have prior failures
- announces a new order offer unprompted. Built: the relay sends AssemblyAI
  `reply.create` at a quiet moment (`interface.md` §1)

---

## Tech Stack

**Frontend:** Flutter. Canonical dependencies (`frontend/pubspec.yaml`):
`flutter_riverpod` (state), `go_router` (routing), `flutter_map` with
OpenFreeMap vector tiles via `vector_map_tiles` (map; no API key, no billing),
`web_socket_channel`, `tabler_icons_plus`, `google_fonts` (Plus Jakarta
Sans), `rive` (co-rider swap-in), `supabase_flutter`, `just_audio` (audio
out), `record` (audio in), and `geolocator` (live position).
`google_maps_flutter` was dropped for billing and must not come back.

**Backend:** Python FastAPI + asyncio, Supabase (PostgreSQL + auth +
storage), Railway hosting, Firebase FCM.

**Comms:** LiveKit SIP/PSTN for outbound calls (free Build tier,
1,000 agent mins/mo). Vonage for global SMS.

**External APIs:** AssemblyAI (Voice Agent + Speech Understanding),
OSRM (routing, no key; `OSRM_BASE_URL` for self-hosting), OpenFreeMap (app
map tiles), Onfleet, n8n.

Dropped and must not be reintroduced: **Twilio** (too expensive),
**Africa's Talking** (VoiceOps is global, not Africa-specific).

---

## Logistics Layer

- **Primary:** Onfleet API (OAuth, free dev account). Not built yet
- **Fallback:** `MockAdapter`, a random new-order feed in downtown Austin (the demo area)
- Both sit behind an abstract `LogisticsAdapter` base class (`voiceops-backend/app/integrations/logistics/`)

Never bypass the adapter abstraction. If you change the base class,
update `MockAdapter` in the same change.

New orders arrive through the adapter's feed or `POST /v1/logistics/orders`.
`voiceops-backend/app/dispatch/order_dispatch.py` offers each one to the nearest driver
with an open voice session, then the next on decline or timeout. A driver with no
session is never offered or notified. The order waits unassigned until one connects.

A 6-digit connect code links a driver to their logistics company platform.

---

## Post-Shift Intelligence (n8n)

```
Shift end
  → FastAPI fires n8n webhook (fire-and-forget)
    → n8n fetches transcripts from Supabase
      → AssemblyAI Speech Understanding
        → parse results → store report → email operator
```

Report contents: failure patterns (topic detection), route issues,
customer sentiment, driver performance summary, AI recommendations (LeMUR).

LeMUR prompts: `failure_patterns`, `route_issues`, `recommendations`.
Model: `anthropic/claude-sonnet-5` (current Claude Sonnet, in LeMUR's
`anthropic/<model>` form). Check it against AssemblyAI's supported-model
list when the pipeline is built. No post-shift code exists yet.

n8n also handles: operator email/Slack notifications, daily fleet
summaries, driver welcome SMS.

---

## Design System

- **Dark-mode-first** for the main app. Tokens live in
  `frontend/lib/core/theme/tokens.dart` (summarised in SDD §8). Lime
  `#C8F250` is reserved for the mic-hot state
- Mascot is called the **"co-rider"** — never "co-pilot" or "assistant"
- Two orb materials: **holographic bubble** orb for onboarding,
  **chrome/mercury** orb for the main app
- The mascot is an orb placeholder (`MascotDisplay`) for now. A Rive `.riv`
  swap-in comes later per SDD §6.1 and touches only that widget
- Typography: **Plus Jakarta Sans** (substitute for Circular Std /
  Sofia Pro until a licence is secured)
- Icons: **Tabler Icons** via `tabler_icons_plus` — no emoji icons

Push-to-talk button: large circular, minimum 80×80px.
States: `idle → recording → processing → speaking`.

Home screen layout: map (top 45%), next stop card, transcript display,
push-to-talk button, bottom nav.

Onboarding is 3 screens, shown before the auth gate: a splash with giant
editorial type and inline holographic pills ("Meet your co-rider for every
delivery route", white "Get started" CTA), then hook and power. Next on
Power hands off to the auth welcome screen's "Get started" and sign-up. The
fourth, trust, screen was retired on 2026-09-12 (captain's call).

---

## Branching Strategy

```
main → dev → staging → features/frontend/*
                     → features/backend/*
                     → features/ai/*
```

- `staging` is the live integration branch. It was brought level with
  `main` on 2026-09-11
- Cut every feature branch from `staging`, named
  `features/<layer>/<feature-slug>`, one per feature
- Feature PRs target `staging`. Promote upward by PR: `staging → dev`,
  then `dev → main`. No direct pushes to `main` or `dev`
- Frontend work goes under `features/frontend/`
- Backend work goes under `features/backend/`
- Agent-layer work goes under `features/ai/` and follows `backend.md`

Interface contracts are **frozen**: WebSocket message types, REST
endpoints, delivery status enum, JWT auth header. They are defined in
`docs/contracts/interface.md`. The rules are in
`.firstmate/rules/contracts.md`.

---

## Before You Start

- Confirm which layer your task belongs to: frontend, backend, or ai
  (agent-layer work follows `backend.md`)
- Branch from `staging`, the live integration branch, named
  `features/<layer>/<feature-slug>`. PR back into `staging`, then promote
  `staging → dev → main` by PR
- Read the rule file for your layer
- Keep changes scoped — do not refactor code outside your task

## Before You Finish

- Run the relevant checks (`flutter analyze` / `pytest`) — see your layer's rule file
- Verify no `.env`, key, or token was committed
- Confirm the diff touches only files your task required

---

## What NOT to Do

- Do not put n8n anywhere in the real-time WebSocket path
- Do not convert parallel tool calls into sequential awaits
- Do not reintroduce Twilio or Africa's Talking
- Do not change the WebSocket message contract without updating both
  frontend and backend in the same change
- Do not modify `LogisticsAdapter` without updating `MockAdapter`
- Do not invent tool input/output shapes — use the Agent Tools Reference
- Do not open an external maps app or deep link for navigation. Routes
  render in-app on the Flutter map
- Do not commit API keys, tokens, or `.env` files
- Do not refactor code unrelated to your assigned task

---

## Team

- **Ez** — Flutter frontend, assists on the agentic layer
- **Teammate** — FastAPI backend and agentic workflows (primary backend owner)

Working remotely. Keep changes scoped to one layer so parallel work
does not collide.

---

## Firstmate Crew Notes

- Crewmates implementing tool handlers use
  `docs/VoiceOps_Agent_Tools_Reference.md`. If it is ever missing, stop
  and flag it. Do not reconstruct it from memory.
- To route crewmates to Codex instead of Claude Code, run
  `echo "codex" > /workspaces/firstmate/config/crew-harness`. Leave the
  file out to keep crewmates on Claude Code.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
