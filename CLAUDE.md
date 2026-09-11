# VoiceOps — Agent Context

Read this fully before touching any code. Rule files in `.claude/rules/`
carry the detail for each layer.

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
├── backend/           Python FastAPI + asyncio
├── docs/              PRD, SDD, Technical Feasibility, Presenter Guide
├── CLAUDE.md          this file
├── AGENTS.md          pointer for Codex/other harnesses
└── .claude/rules/     layer-specific rules
```

Frontend and backend live in ONE repo. Do not split them.

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
   parallel execution as sequential awaits.

3. **AssemblyAI Voice Agent API is a single WebSocket** carrying STT, LLM,
   tool calling, and TTS together. Do not split these into separate services.

---

## AssemblyAI Dual Integration

This dual use is the core technical differentiator for the hackathon.
Both layers must remain in the codebase.

| Layer | API | Role |
|---|---|---|
| 1 — real-time | Voice Agent API | STT + LLM + tool calling + TTS over one WebSocket, ~$4.50/hr flat |
| 2 — post-shift | Speech Understanding API | transcription, sentiment, topic detection, summarisation, speaker diarization, entity extraction, LeMUR |

---

## The 10 Agent Tools

| Tool | What it does | Platform |
|---|---|---|
| `get_next_delivery` | Fetch the next stop | Onfleet / MockAdapter |
| `update_delivery_status` | Mark delivery complete or failed | Onfleet / MockAdapter |
| `log_exception` | Record a delivery exception | Supabase |
| `get_best_route` | Compute optimal route | Google Directions |
| `start_navigation` | Push route to the Flutter map | internal |
| `call_customer` | Outbound voice call | LiveKit SIP/PSTN |
| `notify_customer` | Outbound SMS | Vonage |
| `get_next_order` | Fetch upcoming orders | Onfleet / MockAdapter |
| `get_shift_summary` | Summarise current shift stats | Supabase |
| `alert_dispatcher` | Push alert to operator | Supabase + n8n |

Exact input/output JSON shapes and handler signatures live in the
**Agent Tools Reference** doc under `docs/`. That doc is the contract —
do not invent tool shapes.

**Proactive agent behaviours** that must be preserved:
- auto-announces the next stop after a delivery completes
- proactive ETA updates
- briefs the driver on stops that have prior failures

---

## Tech Stack

**Frontend:** Flutter — Riverpod (state), go_router (routing),
`google_maps_flutter`, `just_audio`, `record`, `web_socket_channel`,
`geolocator`, `tabler_icons_plus`.

**Backend:** Python FastAPI + asyncio, Supabase (PostgreSQL + auth +
storage), Railway hosting, Firebase FCM.

**Comms:** LiveKit SIP/PSTN for outbound calls (free Build tier,
1,000 agent mins/mo). Vonage for global SMS.

**External APIs:** AssemblyAI (Voice Agent + Speech Understanding),
Google Maps + Directions, Onfleet, n8n.

Dropped and must not be reintroduced: **Twilio** (too expensive),
**Africa's Talking** (VoiceOps is global, not Africa-specific).

---

## Logistics Layer

- **Primary:** Onfleet API (OAuth, free dev account)
- **Fallback:** `MockAdapter` with seeded Lagos delivery data (7+ realistic deliveries)
- Both sit behind an abstract `LogisticsAdapter` base class

Never bypass the adapter abstraction. If you change the base class,
update `MockAdapter` in the same change.

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
Model: `anthropic/claude-3-5-sonnet`.

n8n also handles: operator email/Slack notifications, daily fleet
summaries, driver welcome SMS.

---

## Design System

- **Dark-mode-first** for the main app
- Mascot is called the **"co-rider"** — never "co-pilot" or "assistant"
- Two orb materials: **holographic bubble** orb for onboarding,
  **chrome/mercury** orb for the main app
- Typography: **Plus Jakarta Sans** (substitute for Circular Std /
  Sofia Pro until a licence is secured)
- Icons: **Tabler Icons** via `tabler_icons_plus` — no emoji icons

Push-to-talk button: large circular, minimum 80×80px.
States: `idle → recording → processing → speaking`.

Home screen layout: map (top 45%), next stop card, transcript display,
push-to-talk button, bottom nav.

Onboarding is 4 screens: a splash with giant editorial type and inline
holographic pills ("Meet your co-rider for every delivery route", white
"Get started" CTA), then hook, power, and trust screens.

---

## Branching Strategy

```
main → dev → staging → features/frontend/*
                     → features/backend/*
                     → features/ai/*
```

- One feature branch per feature, named by layer and feature slug
- PRs target `staging` first, then `staging → dev → main`
- Frontend work goes under `features/frontend/`
- Backend work goes under `features/backend/`

Interface contracts are **frozen**: WebSocket message types, REST
endpoints, delivery status enum, JWT auth header. See
`.claude/rules/contracts.md`.

---

## What NOT to Do

- Do not put n8n anywhere in the real-time WebSocket path
- Do not convert parallel tool calls into sequential awaits
- Do not reintroduce Twilio or Africa's Talking
- Do not change the WebSocket message contract without updating both
  frontend and backend in the same change
- Do not modify `LogisticsAdapter` without updating `MockAdapter`
- Do not invent tool input/output shapes — use the Agent Tools Reference
- Do not commit API keys, tokens, or `.env` files
- Do not refactor code unrelated to your assigned task

---

## Team

- **Ez** — Flutter frontend, assists on the agentic layer
- **Teammate** — FastAPI backend and agentic workflows (primary backend owner)

Working remotely. Keep changes scoped to one layer so parallel work
does not collide.
