# Handoff: generating the co-rider voice preview clips (backend)

**For:** Maria (backend owner) - **From:** Ez / Firstmate - **Date:** 2026-09-19
**Status:** proposal. No backend code changed. Review together before building.

## What is missing and why it matters

The onboarding voice step and the Settings voice picker have a "hear this voice" button. It plays
a bundled clip per voice from `frontend/assets/audio/voice_previews/<voice>.mp3` - no microphone,
no live session, no shift. The code is merged on `staging`, but **that folder holds only its
README: no clip has ever been committed, on any branch.** With no clips the app disables the
button, so previews look broken. We need 11 short audio files, and you are the person with the
AssemblyAI key and the working knowledge of the Voice Agent API, so this asks you to produce them.

## The deliverable

Eleven files, named exactly (lowercase, the `CoRiderVoice` enum names, the same IDs as
`VOICES` in `voiceops-backend/app/agents/agent_config.py`):

- American English: `alba.mp3`, `eve.mp3`, `george.mp3`, `jane.mp3`, `jean.mp3`, `mary.mp3`, `michael.mp3`
- British English: `anna.mp3`, `charles.mp3`, `paul.mp3`, `vera.mp3`

Requirements (from `frontend/assets/audio/voice_previews/README.md`):

- MP3, mono, 3-6 seconds.
- The **same short line in every voice**, so a driver comparing voices hears only the voice
  change. Suggested line: "Hi, I'm Kora, your co-rider. This is how I'll sound on the road."
- Similar loudness across all eleven, so switching voices does not jump in volume.
- Small: roughly 30-60 KB each at 96 kbps mono is plenty.

Please send the finished files to Ez rather than committing them yourself: they are frontend
assets, so Ez commits them on a `features/frontend/` branch (branching strategy in `AGENTS.md`).

## Recommended approach: capture the real voices from the Voice Agent API

Record each voice's greeting straight from AssemblyAI, so the previews are the voices drivers
will actually hear. It is a one-off run of about 11 short sessions (a few cents), re-run only if
the greeting line or the voice list changes.

What the relay already does, and this script should mirror (all in `voiceops-backend/app/api/websocket/voice.py`
unless noted):

- Connect to `wss://agents.assemblyai.com/v1/ws` (`settings.assemblyai_voice_agent_url`) with the
  header `Authorization: Bearer <ASSEMBLYAI_API_KEY>` (`_open_upstream`).
- Send one `session.update` whose `session` carries `system_prompt`, `greeting`,
  `input`/`output` `format.encoding = "audio/pcm"` and `output.voice` (`get_session_config` and
  `get_audio_config` in `agent_config.py`).
- Wait for `session.ready` or `session.updated`. The greeting is spoken next: the relay itself
  treats "the greeting is next" at that point.
- The greeting arrives as `reply.audio` messages whose base64 `data` is **PCM16, mono, 24 kHz**
  (`docs/contracts/interface.md` section 1, `TARGET_SAMPLE_RATE`), followed by `reply.done`.
- End the session with `{"type": "session.end"}`.

The script needs no microphone audio, no tools, no shift and no Supabase. Run the voices
one after another, not in parallel, so it never depends on the open question below about
concurrent sessions.

### Sketch (not run against the live API - verify on one voice first)

```python
# voiceops-backend/scripts/generate_voice_previews.py
import asyncio, base64, json, os, subprocess, wave
from pathlib import Path
import websockets
from app.agents.agent_config import VOICES  # allowlist: single source of truth

URL = "wss://agents.assemblyai.com/v1/ws"
GREETING = "Hi, I'm Kora, your co-rider. This is how I'll sound on the road."
OUT = Path(__file__).resolve().parents[2] / "frontend/assets/audio/voice_previews"
RATE = 24000  # PCM16 mono, fixed by the Voice Agent API

async def _read_greeting(ws) -> bytes:
    pcm = bytearray()
    async for raw in ws:
        msg = json.loads(raw)
        kind = msg.get("type")
        if kind == "reply.audio" and msg.get("data"):
            pcm += base64.b64decode(msg["data"])
        elif kind == "reply.done":
            return bytes(pcm)
        elif kind in ("session.error", "error"):
            raise RuntimeError(msg)
    raise RuntimeError("socket closed before reply.done")

async def capture(voice: str) -> bytes:
    headers = {"Authorization": f"Bearer {os.environ['ASSEMBLYAI_API_KEY']}"}
    async with websockets.connect(URL, additional_headers=headers, open_timeout=10) as ws:
        await ws.send(json.dumps({"type": "session.update", "session": {
            "system_prompt": "You are Kora, a friendly co-rider. Say only your greeting.",
            "greeting": GREETING,
            "input": {"format": {"encoding": "audio/pcm"}},
            "output": {"format": {"encoding": "audio/pcm"}, "voice": voice},
        }}))
        pcm = await asyncio.wait_for(_read_greeting(ws), timeout=30)
        await ws.send(json.dumps({"type": "session.end"}))
        return pcm

def to_mp3(pcm: bytes, dest: Path) -> None:
    wav = dest.with_suffix(".wav")
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(pcm)
    subprocess.run(["ffmpeg", "-y", "-i", str(wav),
                    "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
                    "-ac", "1", "-b:a", "96k", str(dest)], check=True)
    wav.unlink()

async def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for voice in sorted(VOICES):
        print(f"capturing {voice} ...")
        to_mp3(await capture(voice), OUT / f"{voice}.mp3")

asyncio.run(main())
```

Notes on the sketch:

- Run it from `voiceops-backend/` so `app.agents.agent_config` imports, with `ASSEMBLYAI_API_KEY` in
  the environment. `websockets` is already in `requirements.txt`; `ffmpeg` is the one external
  tool. Never commit the key.
- The inline `session.update` deliberately does **not** pass `agent_id`. See the first item below.
- `loudnorm` in a single pass is coarse on a 4-second clip. It is fine as a starting point;
  check by ear and with `ffmpeg -i <clip>.mp3 -af ebur128 -f null -` (aim for the eleven
  integrated levels to sit within about 1-2 LU of each other), and trim leading or trailing
  silence if a clip has any.

## Please verify before running

1. **Stored agent vs inline config.** Same question as in `voice-tone-selection.md`: if
   production has `ASSEMBLYAI_AGENT_ID` set, `get_session_config` sends only `{"agent_id": ...}`
   and the voice override is ignored. The script above uses inline config, so its clips would
   then be voices the live app cannot actually produce. Please confirm production runs inline
   mode. If it does not, tell Ez: the previews would mislead drivers, and voice selection itself
   would not be working either.
2. **The greeting fires from an inline `greeting`.** The relay's behaviour implies it does, but
   this sketch has not been run. Run one voice first (for example `anna`), listen to it, and check
   the transcript text (`transcript.agent`) matches `GREETING` before running all eleven.
3. **Concurrent Voice Agent sessions on one account** are undocumented. The script runs
   sequentially, so it does not depend on the answer.
4. **Length.** If the suggested line runs over 6 seconds in some voices, shorten the line and
   re-run all eleven, so every voice still says the identical words.

## Acceptance checklist

- [ ] Eleven files, names exactly as above, all `.mp3`, mono.
- [ ] Each 3-6 seconds, and each says the same line.
- [ ] Loudness within about 1-2 LU across the set; no clipping and no long silences.
- [ ] Each voice sounds like the voice the live app uses for that ID (compare one against a real
      session).
- [ ] No API key or secret anywhere in the repo, the script or the files' metadata.
- [ ] Files handed to Ez to commit under `frontend/assets/audio/voice_previews/`.

## Alternatives, if you would rather not script it

- Record each voice by hand from a live session of the app or the AssemblyAI playground, then
  process the recordings with the same `ffmpeg` step. It works, but it is 11 manual runs, and it
  cannot be repeated exactly if the line changes.
- A runtime preview endpoint (returning a voice's greeting on request, with no shift and no
  live session) would keep previews always in sync, but it needs backend work and costs a little
  AssemblyAI usage per tap. Ez chose bundled clips for now, so this is a possible later
  replacement and out of scope here.
