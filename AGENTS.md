# VoiceOps — Agent Instructions

This project's full agent context lives in **`CLAUDE.md`** at the repo root.
Read it before making any change.

Layer-specific rules live in `.firstmate/rules/`:

| File | Covers |
|---|---|
| `.firstmate/rules/frontend.md` | Flutter app — structure, state, UI conventions |
| `.firstmate/rules/backend.md` | FastAPI — tool orchestration, adapters, async rules |
| `.firstmate/rules/contracts.md` | Frozen interfaces between frontend and backend |

The contract itself is `docs/contracts/interface.md` (WebSocket, REST,
status enum, JWT) plus `docs/VoiceOps_Agent_Tools_Reference.md` (the 10
tool shapes).

---

## The Short Version

VoiceOps is a voice-first mobile app for last-mile logistics drivers,
built for the AssemblyAI Voice Agent Hackathon (Sep 1–30, 2026).

Monorepo: `frontend/` is Flutter, `backend/` is Python FastAPI. The backend
has not been imported yet. It lives on the orphan branch
`features/backend/assemblyai-voice-agent`.

Three constraints that override anything else you might infer from the code:

1. **n8n never appears in the real-time voice path.** It is async,
   post-shift only. It cannot receive WebSockets.
2. **Tool calls run in parallel** through `asyncio.gather()`. Never
   sequential. This is required but not built yet (open backend task).
3. **Interface contracts are frozen.** Changing a WebSocket message type,
   REST endpoint, delivery status enum, or the JWT auth header requires
   updating both sides in the same change — see `docs/contracts/interface.md`.

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
