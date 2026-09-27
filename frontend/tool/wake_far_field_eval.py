#!/usr/bin/env python3
"""Offline far-field check for the wake word: hits and false accepts by level.

Synthesises the corpus with Edge TTS (needs network), scales it to quiet
levels, adds a microphone floor, optional road noise and reverb, then runs the
bundled sherpa model with the Normal and High profiles. Its constants mirror
`lib/core/wake/wake_tuning.dart` and `wake_input_gain.dart`; keep them in sync
when either changes. Synthetic voices cannot validate a real phone, cabin or
accent, so this does not replace testing on a device.

  python3 -m pip install sherpa-onnx==1.13.8 edge-tts soundfile numpy scipy
  python3 tool/wake_far_field_eval.py --corpus /tmp/wake-corpus
"""

from __future__ import annotations

import argparse
import asyncio
import math
from pathlib import Path

import numpy as np
import sherpa_onnx
import soundfile as sf
from scipy.signal import lfilter, resample_poly

FRONTEND = Path(__file__).resolve().parents[1]
WAKE_DIR = FRONTEND / "assets" / "wake"
MODEL = WAKE_DIR / "model"
SR = 16000
VOICES = ["en-US-AriaNeural", "en-US-GuyNeural", "en-GB-RyanNeural",
          "en-AU-NatashaNeural", "en-IN-NeerjaNeural", "en-US-JennyNeural"]
WAKE = ["Kora", "Hey Kora", "Okay Kora", "Hi Kora", "Hello Kora",
        "Cora", "Hey Cora", "Hi Cora", "Okay Cora", "Hello Cora"]
NON_WAKE = ["Kara", "corner", "corona", "hello driver", "what's up", "hi", "hey",
            "hello", "hey there", "hi there", "okay", "okay then", "hey Carla",
            "Laura", "Hey Laura", "hello everyone", "Hey Sarah, how are you"]

# Mirrors WakeTuning.normal / WakeTuning.high.
PROFILES = {
    "Normal": dict(gain=dict(max_db=24, idle_db=12), score_delta=0.0, thr_delta=0.0),
    "High": dict(gain=dict(max_db=36, idle_db=24), score_delta=1.0, thr_delta=-0.10),
}
TARGET_DB, MIN_ACTIVE_DB, ACTIVE_RATIO_DB = -24.0, -60.0, 6.0
FLOOR_RISE_DB_S, ENV_HALF_LIFE_S, ATTACK, RELEASE_S = 1.0, 0.5, 0.5, 0.4


def lin(db): return 10 ** (db / 20)


def agc(x, max_db, idle_db):
    """Same algorithm as WakeInputGain, 10 ms frames."""
    frame = 160
    target, max_g, idle = lin(TARGET_DB), lin(max_db), lin(idle_db)
    rise = lin(FLOOR_RISE_DB_S / 100)
    decay = 0.5 ** (1 / (100 * ENV_HALF_LIFE_S))
    rel = 1 - math.exp(-1 / (100 * RELEASE_S))
    gain, floor, env = idle, 1e-3, 0.0
    out = np.empty(len(x) // frame * frame)
    for i in range(0, len(out), frame):
        f = x[i:i + frame]
        rms = math.sqrt(float(np.dot(f, f)) / frame)
        floor = max(rms, 1e-6) if rms < floor else floor * rise
        if rms > max(floor * lin(ACTIVE_RATIO_DB), lin(MIN_ACTIVE_DB)):
            env = max(rms, env * decay)
            tgt = min(max(target / env, 1.0), max_g)
        else:
            env *= decay
            tgt = idle if env < lin(MIN_ACTIVE_DB) else gain
        nxt = gain + (tgt - gain) * (ATTACK if tgt < gain else rel)
        out[i:i + frame] = np.clip(f * np.linspace(gain, nxt, frame, endpoint=False), -1, 1)
        gain = nxt
    return out


async def synth(corpus: Path):
    import edge_tts
    corpus.mkdir(parents=True, exist_ok=True)
    for voice in VOICES:
        for text in WAKE + NON_WAKE:
            path = corpus / f"{voice}__{text.replace(' ', '_')}.mp3"
            if not path.exists():
                await edge_tts.Communicate(text, voice).save(str(path))


def load(path):
    data, rate = sf.read(path)
    return resample_poly(data, SR, rate) if rate != SR else data


def noise(n, rms, brown=False):
    w = np.random.default_rng(1).standard_normal(n)
    w = lfilter([1, -1], [1, -0.995], lfilter([1], [1, -0.985], w)) if brown else lfilter([1], [1, -0.7], w)
    return w * rms / np.sqrt(np.mean(w ** 2))


def case(clip, peak_db, snr_db=None, reverb=False):
    x = clip
    if reverb:
        t = np.arange(int(0.35 * SR)) / SR
        ir = np.random.default_rng(2).standard_normal(len(t)) * 10 ** (-3 * t / 0.35)
        ir[0] = 1
        x = np.convolve(np.concatenate([x, np.zeros(int(0.4 * SR))]), ir / np.linalg.norm(ir))[: len(x) + int(0.4 * SR)]
    x = x * lin(peak_db) / np.abs(x).max()
    speech_rms = np.sqrt(np.mean(x[np.abs(x) > 0.1 * np.abs(x).max()] ** 2))
    x = np.concatenate([np.zeros(int(0.4 * SR)), x, np.zeros(int(0.6 * SR))])
    if snr_db is not None:
        x = x + noise(len(x), speech_rms * lin(-snr_db), brown=True)
    x = x + noise(len(x), lin(-66))
    return np.clip(np.round(x * 32768), -32768, 32767) / 32768


def keyword_buffer(profile):
    tokens = {}
    for line in (WAKE_DIR / "keywords.txt").read_text().splitlines():
        parts = line.split()
        tokens[parts[-1][1:]] = " ".join(parts[:-1])
    import json
    lines, seen = [], set()
    for p in json.loads((WAKE_DIR / "wake_phrases.json").read_text())["phrases"]:
        if p["enabled"] is not True or p.get("requires") or tokens[p["id"]] in seen:
            continue
        seen.add(tokens[p["id"]])
        score = min(max(p.get("score", 2.0) + profile["score_delta"], 0.1), 4.0)
        thr = min(max(p.get("threshold", 0.25) + profile["thr_delta"], 0.05), 0.95)
        lines.append(f"{tokens[p['id']]} :{score:.2f} #{thr:.2f} @{p['id']}")
    return "\n".join(lines) + "\n"


def spotter(buffer):
    keywords = Path("/tmp/wake_eval_keywords.txt")
    keywords.write_text(buffer)
    return sherpa_onnx.KeywordSpotter(
        tokens=str(MODEL / "tokens.txt"),
        encoder=str(MODEL / "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx"),
        decoder=str(MODEL / "decoder-epoch-13-avg-2-chunk-16-left-64.onnx"),
        joiner=str(MODEL / "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx"),
        keywords_file=str(keywords), num_threads=1, max_active_paths=4,
        num_trailing_blanks=1, keywords_score=1.0, keywords_threshold=0.25)


def hit(sp, samples, profile):
    stream = sp.create_stream()
    for i in range(0, len(samples), 1600):
        chunk = samples[i:i + 1600]
        if profile:
            chunk = agc(chunk, **profile["gain"])
        stream.accept_waveform(SR, chunk.astype(np.float32))
        while sp.is_ready(stream):
            sp.decode_stream(stream)
            if sp.get_result(stream):
                return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(synth(args.corpus))
    clips = {p.stem: load(p) for p in sorted(args.corpus.glob("*.mp3"))}
    def group(texts): return [c for n, c in clips.items() if n.split("__")[1] in {t.replace(" ", "_") for t in texts}]
    wake, other = group(WAKE), group(NON_WAKE)
    conditions = [(-40, None, False), (-35, None, False), (-30, None, False), (-10, None, False),
                  (-35, 5, False), (-30, 5, False), (-35, None, True)]
    print("condition (peak dBFS, road SNR, reverb) | " + " | ".join(f"{n}: hits/FA" for n in PROFILES))
    for peak, snr, rev in conditions:
        row = []
        for profile in PROFILES.values():
            sp = spotter(keyword_buffer(profile))
            hits = sum(hit(sp, case(c, peak, snr, rev), profile) for c in wake)
            fas = sum(hit(sp, case(c, peak, snr, rev), profile) for c in other)
            row.append(f"{hits}/{len(wake)} {fas}/{len(other)}")
        print(f"{peak} dBFS, road {snr}, reverb {rev} | " + " | ".join(row))


if __name__ == "__main__":
    main()
