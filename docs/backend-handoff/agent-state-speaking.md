# Proposal: add `speaking` to the `agent_state` vocabulary

**For:** Medge (backend / agentic workflows)
**From:** frontend, 2026-09-16
**Status:** proposal — no backend code was written for this.

## What the frontend does today

The co-rider orb's `speaking` mood is now wired up on the client
(`fm/vops-orb-speaking-wire`). Because the backend has no `speaking`
state, the app **infers** it: `VoiceSession._setPtt` mirrors push-to-talk's
`speaking` — which turns on in `_onAudio` when reply audio chunks start
arriving and off on `reply_done` — onto `agentStateProvider`
(`AgentStateNotifier.setSpeaking`).

The precedence rule the client uses: while reply audio is playing,
`speaking` overlays whatever mood the backend last sent; when playback
ends the mood falls back to that backend mood (or `idle`). A mood that
arrives mid-reply (say `mapping`) is remembered and shown once the reply
finishes.

## The ask

1. Add `speaking` to the `agent_state` vocabulary in
   `docs/contracts/interface.md` (§ *Field vocabularies*, the
   `agent_state.state ∈ …` line). The key already exists on the client as
   `AgentState.speaking` / `riveKey: 'speaking'` in
   `frontend/lib/mascot/mascot_state.dart`, so nothing new is invented.
2. Emit `{"event": "agent_state", "state": "speaking"}` when the relay
   starts streaming reply audio — on the first `reply.audio` frame of a
   burst, in the § *What emits each event* table. It is the mirror image
   of `reply_done`'s existing "the agent's spoken reply is finished"
   framing, and the `agent_state: idle` the relay already sends after
   `reply_done` closes it, so no new closing event is needed.

   Note a tool turn has two audio bursts ("Let me check…", then the answer
   after the tools) and only one `reply_done`. The second burst should
   send `speaking` again after the tool's mood (`mapping`, `calling`, …),
   so the last state before `reply_done` is `speaking`.

## Why it is worth doing

Inferring `speaking` from audio chunks works, but the ordering against
other `agent_state` transitions is guessed client-side. The backend knows
when a reply starts and how it interleaves with tool moods, so an explicit
event makes that ordering server-authoritative rather than a heuristic the
two sides have to agree on independently. It also removes a second,
undocumented source of mood from the client, leaving `agent_state` as the
single channel the contract already says it is.

## Compatibility

The change is additive and safe to ship on its own. `setFromKey` already
resolves `'speaking'`, and the client's overlay is idempotent: a backend
`speaking` arriving during playback shows the same mood the client is
already showing. Once the backend emits it, the client-side inference can
be dropped in a follow-up (delete `AgentStateNotifier.setSpeaking` and let
`_setPtt` go back to a plain `_ptt.set`) — but it does not have to be, and
nothing breaks if both are live.

## Out of scope here

The Rive asset (`frontend/assets/rive/corider.riv`) has no `speaking`
trigger authored yet — that is the captain's to do in Rive Desktop. Until
it exists, the mood resolves to the Flutter placeholder orb's `speaking`
look and the missing trigger is a silent no-op on device.
