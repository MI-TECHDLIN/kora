#!/usr/bin/env python3
"""
Generate co-rider voice preview clips from AssemblyAI Voice Agent API.

Captures the greeting for all 11 voices (or a specified voice) and converts
them to normalized, mono MP3 files under frontend/assets/audio/voice_previews/.

Usage:
    python scripts/generate_voice_previews.py
    python scripts/generate_voice_previews.py --voice anna
    python scripts/generate_voice_previews.py --out-dir /path/to/previews
"""

import argparse
import asyncio
import base64
import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

# Add voiceops-backend to sys.path so app modules import cleanly
BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from dotenv import load_dotenv

# Load .env from voiceops-backend or workspace root
load_dotenv(BACKEND_DIR / ".env")
load_dotenv(BACKEND_DIR.parent / ".env")

import websockets

from app.agents.agent_config import VOICES, DEFAULT_VOICE

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("generate_voice_previews")

URL = os.environ.get("ASSEMBLYAI_VOICE_AGENT_URL", "wss://agents.assemblyai.com/v1/ws")
GREETING = "Hi, I'm Kora, your co-rider. This is how I'll sound on the road."
DEFAULT_OUT_DIR = Path(__file__).resolve().parents[2] / "frontend" / "assets" / "audio" / "voice_previews"
SAMPLE_RATE = 24000  # PCM16 mono, 24kHz, fixed by Voice Agent API


def get_ffmpeg_exe() -> str:
    """Find ffmpeg binary from PATH or fallback to imageio_ffmpeg."""
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        pass
    raise RuntimeError(
        "ffmpeg not found in PATH and imageio_ffmpeg is not installed. "
        "Please install ffmpeg or run 'pip install imageio-ffmpeg'."
    )


async def _read_greeting(ws) -> bytes:
    """Collect PCM16 chunks until reply.done is received."""
    pcm = bytearray()
    async for raw in ws:
        msg = json.loads(raw) if isinstance(raw, str) else json.loads(raw.decode("utf-8"))
        kind = msg.get("type")
        if kind == "reply.audio" and msg.get("data"):
            pcm += base64.b64decode(msg["data"])
        elif kind == "reply.done":
            return bytes(pcm)
        elif kind in ("session.error", "error"):
            raise RuntimeError(f"AssemblyAI Voice Agent session error: {msg}")
    raise RuntimeError("WebSocket closed before reply.done was received.")


async def capture_greeting(voice: str, api_key: str) -> bytes:
    """Connect to AssemblyAI Voice Agent API and capture PCM greeting for voice."""
    headers = {"Authorization": f"Bearer {api_key}"}
    async with websockets.connect(URL, additional_headers=headers, open_timeout=15) as ws:
        session_config = {
            "type": "session.update",
            "session": {
                "system_prompt": "You are Kora, a friendly co-rider. Say only your greeting.",
                "greeting": GREETING,
                "input": {"format": {"encoding": "audio/pcm"}},
                "output": {"format": {"encoding": "audio/pcm"}, "voice": voice},
            },
        }
        await ws.send(json.dumps(session_config))
        pcm = await asyncio.wait_for(_read_greeting(ws), timeout=30)
        try:
            await ws.send(json.dumps({"type": "session.end"}))
        except Exception:
            pass
        return pcm


def convert_pcm_to_mp3(pcm: bytes, dest: Path, ffmpeg_exe: str) -> dict:
    """
    Write PCM to a temporary WAV and convert to normalized, mono MP3 via ffmpeg.
    Returns audio stats (duration_s, size_kb).
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_wav:
        tmp_wav_path = Path(tmp_wav.name)

    try:
        with wave.open(str(tmp_wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)  # 16-bit
            w.setframerate(SAMPLE_RATE)
            w.writeframes(pcm)

        num_frames = len(pcm) // 2
        duration_s = round(num_frames / SAMPLE_RATE, 2)

        # Encode to MP3 with EBU R128 loudness normalization and 96k mono
        cmd = [
            ffmpeg_exe,
            "-y",
            "-i",
            str(tmp_wav_path),
            "-af",
            "loudnorm=I=-16:TP=-1.5:LRA=11",
            "-ac",
            "1",
            "-b:a",
            "96k",
            str(dest),
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"ffmpeg conversion failed: {res.stderr}")

        size_kb = round(dest.stat().st_size / 1024, 1)
        return {"duration_s": duration_s, "size_kb": size_kb}
    finally:
        if tmp_wav_path.exists():
            tmp_wav_path.unlink()


async def generate_previews(voices: list[str], out_dir: Path, api_key: str) -> None:
    ffmpeg_exe = get_ffmpeg_exe()
    logger.info(f"Using ffmpeg executable: {ffmpeg_exe}")
    logger.info(f"Output directory: {out_dir}")
    logger.info(f"Voices to capture ({len(voices)}): {', '.join(voices)}")

    out_dir.mkdir(parents=True, exist_ok=True)
    results = []

    for voice in sorted(voices):
        logger.info(f"Capturing greeting for voice '{voice}'...")
        try:
            pcm = await capture_greeting(voice, api_key)
            dest_file = out_dir / f"{voice}.mp3"
            stats = convert_pcm_to_mp3(pcm, dest_file, ffmpeg_exe)
            logger.info(
                f"Saved {voice}.mp3: duration={stats['duration_s']}s, size={stats['size_kb']} KB"
            )
            results.append({"voice": voice, "status": "ok", **stats})
        except Exception as e:
            logger.error(f"Failed to capture '{voice}': {e}")
            results.append({"voice": voice, "status": f"failed: {e}"})

    logger.info("\n=== Summary ===")
    for r in results:
        if r["status"] == "ok":
            logger.info(f"  [OK] {r['voice']}.mp3 ({r['duration_s']}s, {r['size_kb']} KB)")
        else:
            logger.warning(f"  [FAILED] {r['voice']}: {r['status']}")


def main():
    parser = argparse.ArgumentParser(description="Generate co-rider voice preview clips")
    parser.add_argument(
        "--voice",
        choices=sorted(VOICES),
        help="Generate preview for a single voice (e.g. anna)",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help="Target output directory for MP3 files",
    )
    args = parser.parse_args()

    api_key = os.environ.get("ASSEMBLYAI_API_KEY")
    if not api_key:
        logger.error("ASSEMBLYAI_API_KEY environment variable is missing. Set it in .env or environment.")
        sys.exit(1)

    voices = [args.voice] if args.voice else sorted(VOICES)
    asyncio.run(generate_previews(voices, args.out_dir, api_key))


if __name__ == "__main__":
    main()
