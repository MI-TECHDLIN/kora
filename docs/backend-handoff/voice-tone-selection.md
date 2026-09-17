# Handoff: co-rider voice selection (backend)

**For:** Maria (backend owner) - **From:** frontend (Ez / Firstmate) - **Date:** 2026-09-16
**Status:** proposal. No backend code changed. Review together before building.

## What the app now does

Settings has a **Co-rider voice** picker, saved locally on the device and set to Anna
until the driver picks another voice. Every voice socket the app opens now carries the choice
as a query parameter:

```
wss://<host>/ws/voice/{shift_id}?voice=michael
Authorization: Bearer <access_token>
```

The path parameter and `Authorization` header are unchanged, so this is purely additive. The
backend ignores `voice` today, so drivers still hear Anna until this lands. Frontend source:
`frontend/lib/providers/co_rider_voice_provider.dart` and `voiceSocketUri` in
`frontend/lib/core/config/backend_config.dart`.

The picker says "Applies to your next conversation". A change never touches an open
socket. It rides on the next connect or reconnect.

## Proposed backend change

1. **Read the parameter** in `voice_socket()` (`voiceops-backend/app/api/websocket/voice.py`),
   e.g. `websocket.query_params.get("voice")`. Validate it and pass it into the session object
   next to `shift_id`.
2. **Thread it through** `_start_upstream()` -> `get_session_config(..., voice=...)` ->
   `get_audio_config(voice)`. Replace the hardcoded `"voice": "anna"` in
   `voiceops-backend/app/agents/agent_config.py` with the validated value.
3. **Validate against an allowlist.** A missing, empty, or unknown value falls back to `anna`
   silently, with no error event. An old app build or a bad value should still get a working
   session.

   ```python
   VOICES = {
       # American English
       "alba", "eve", "george", "jane", "jean", "mary", "michael",
       # British English
       "anna", "charles", "paul", "vera",
   }
   DEFAULT_VOICE = "anna"

   def resolve_voice(value: str | None) -> str:
       v = (value or "").strip().lower()
       return v if v in VOICES else DEFAULT_VOICE
   ```

   AssemblyAI's Voices guide also lists non-English voices. They're out of scope because the
   app and the co-rider prompt are English-only.
4. **Update the contract** in `docs/contracts/interface.md` section 1 in the same change: add the
   optional `voice` query parameter, its allowlist, and the Anna fallback. The WS contract is
   frozen, so this addition needs both owners' sign-off. The frontend half is already built.

## Please verify before shipping

### 1. The voice IDs: the two AssemblyAI docs disagree

The allowlist above comes from AssemblyAI's dedicated **Voices guide** for the Voice Agent
API. The scout also found a second AssemblyAI page, a coding-agent integration doc, that lists
a **different, conflicting catalog** (`ivy`, `james`, `tyler`, ...). Don't trust either doc
blindly. Please **check which voice IDs our AssemblyAI account actually accepts**, for example
by opening a session with each ID and watching for `session.error`.

If the real list differs, the frontend enum (`CoRiderVoice` in
`co_rider_voice_provider.dart`) has to change with it. The query value is the enum's `name`,
and the label is shown as-is. Send the confirmed list back and the frontend will update.

### 2. Stored agent vs inline config: which mode is deployed?

Upstream, `session.agent_id` and inline session configuration are **mutually exclusive**.
`get_session_config()` already branches on this. When `settings.assemblyai_agent_id` is
set, it sends only `{"agent_id": ...}` and never calls `get_audio_config()`, so **the voice
override would be silently ignored**.

Please confirm whether production has `ASSEMBLYAI_AGENT_ID` set.

- **Inline mode (agent_id unset):** the proposal above works as written.
- **Stored agent mode:** needs a different approach. Either keep one stored agent per
  allowed voice and choose the `agent_id` from the voice, or move voice sessions to inline
  mode.

### 3. Session start only

`session.output.voice` is set once, before the session starts, and then locked. Changing it
mid-conversation gets an `immutable_field` error from AssemblyAI by design. So:

- apply the voice only in the first `session.update` sent from `_start_upstream()`
- never send a later `session.update` that includes `output.voice` (for example alongside
  the `reply.create` order-offer nudge)
- a new voice takes effect on the next socket. The app already reconnects with the current
  choice, so no extra event is needed.

## Suggested tests (pytest)

- `resolve_voice`: a valid ID passes through (case-insensitive). `None`, `""`, and `"ivy"`
  (not in the allowlist) fall back to `anna`.
- `get_session_config(..., voice="michael")` inline -> `session.output.voice == "michael"`.
- `get_session_config(..., agent_id="x", voice="michael")` -> only `agent_id`, which documents
  the caveat above.
- WS `/ws/voice/{shift_id}?voice=vera` sends `vera` in the first upstream `session.update`.
