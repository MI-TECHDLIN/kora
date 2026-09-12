# Frozen Interface Contracts

These interfaces are **frozen**. They are the boundary that lets frontend
and backend work in parallel without collision.

Changing any of them requires updating **both sides in the same change**.
A one-sided change silently breaks the other layer and will not be caught
by either layer's tests.

---

## What Is Frozen

1. **WebSocket message types** — the real-time voice channel
2. **REST endpoints** — paths, methods, request and response shapes
3. **Delivery status enum** — the shared vocabulary for delivery state
4. **JWT auth header** — the auth scheme on every authenticated call

The authoritative definitions live in **`docs/contracts/interface.md`**
(WebSocket catalogue, REST endpoints, delivery-status enum, JWT header)
and **`docs/VoiceOps_Agent_Tools_Reference.md`** (the 10 tool shapes).
Those two documents are the source of truth, not whatever a given file
happens to contain. The SDD's old event list (§7) is historical.

`interface.md` stays a **draft** until both owners sign it off. Build
against it now anyway, and treat its "open items for sign-off" as
unfrozen.

---

## Rules

**Do not** rename a WebSocket message type, add a required field to an
existing message, change an endpoint path, add or remove a delivery status
value, or alter the auth header format — unless the task explicitly
authorises a contract change and you update both layers together.

**Do** add a new optional field, a new message type, or a new endpoint
when a feature genuinely needs one — additive changes are safe. Note the
addition clearly in your task report so the other layer can pick it up.

---

## If a Contract Change Is Genuinely Required

Stop and escalate rather than proceeding. Report:

1. Which contract needs to change
2. Why the current shape cannot carry the feature
3. What breaks on the other side
4. The proposed new shape

The captain decides. Do not make the change unilaterally, and do not work
around a frozen contract by adding a parallel undocumented channel.

---

## Delivery Status

The status enum (`pending | delivered | failed | rescheduled`, defined in
`docs/contracts/interface.md` §3) is shared vocabulary across Flutter,
FastAPI, Supabase, and the logistics adapters. A value added in one place and not the others
produces silent data corruption rather than a clean failure.

Treat every status value as load-bearing.

---

## Auth

- `Authorization: Bearer <access_token>` on every authenticated request
  (details in `docs/contracts/interface.md` §4)
- The same scheme applies to REST and to the WebSocket handshake
- Never accept an unauthenticated write path "temporarily for testing"

---

## Tool Shapes

The 10 agent tools have exact input and output JSON shapes defined in the
**Agent Tools Reference**. The agent's tool-calling behaviour depends on
these being stable.

An invented or drifted tool shape produces an agent that calls tools
correctly in testing and incorrectly in the demo. Use the reference.
