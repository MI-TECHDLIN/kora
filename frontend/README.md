# voiceops

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

## Supabase Configuration

Use the public Supabase URL and anon/publishable key through a local JSON
file. Never put a service-role key in Flutter or commit it to the repository.

```powershell
Copy-Item config/supabase.prod.json.example config/supabase.prod.json
# Edit config/supabase.prod.json with the current anon key.
flutter run --dart-define-from-file=config/supabase.prod.json
```

For a physical Android phone on the same Wi-Fi network, set
`VOICEOPS_API_URL` to the computer's LAN address and start FastAPI with:

```powershell
cd ..\voiceops-backend
py -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The local production file is ignored by Git. Rotate any exposed service-role
key and keep it on the backend only.

## Wake-word configuration

Kora uses sherpa-onnx keyword spotting on-device while the app is in the
foreground. The bundled model is
`sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20`, using its chunk-16 int8
encoder and joiner, fp32 decoder (the release has no int8 decoder), and English
phone tokens. No service account or access key is required.

The phrase list and sensitivities are in `assets/wake/wake_phrases.json`.
Bare `Kora` is the primary phrase, with conservative explicit score/threshold
overrides; `Hey Kora` and `Okay Kora` remain the safer alternatives. Bare
greetings such as “hi”, “hello”, “hey”, and “what's up” are deliberately not
always-on wake phrases. After activation, the AssemblyAI session keeps the mic
visibly hot for the single configurable `voiceFollowUpWindow` (12 seconds), so
greetings and follow-ups work naturally without repeating `Kora`. When that
idle window expires, the app releases the session mic and returns to
keyword-only listening. The once-per-shift agent greeting is unchanged.

Wake capture is 16 kHz, mono PCM16 in 100 ms chunks. On Android it uses the
voice-recognition source without an additional gain, echo-cancel, or
noise-suppression effect, then converts little-endian samples to Float32 by
dividing by 32768 before sherpa. This matches sherpa's reference input shape;
its feature extractor already normalizes sample levels.

The 2026-09-25 offline check used four Edge TTS voices, PCM16-quantized at
-30/-20/-10 dBFS. Across 36 wake samples (`Kora`, `Hey Kora`, `Okay Kora`),
hits moved from 23/36 to 32/36. Across 72 non-wake samples, accepts moved from
0/72 to 8/72; all eight were “Cora”, which has the same phone tokens as
`Kora`. “Kara”, “corner”, “corona”, “hello driver”, and “what's up” stayed at
0/60. At 0 dB synthetic road-noise SNR, wake hits moved from 4/12 to 6/12;
nine noise-only clips produced no accepts before or after. This synthetic check
cannot validate Android microphone processing, real vehicle noise, accents, or
real false accepts; physical-phone testing is still required.

To add or change a phrase:

1. Edit `assets/wake/wake_phrases.json`, using a unique snake-case `id`.
2. Install the generator dependencies with
   `python3 -m pip install sherpa-onnx==1.13.8 pypinyin`.
3. From `frontend/`, run `python3 tool/generate_wake_keywords.py`. The script
   downloads the matching phone lexicon when `SHERPA_KWS_MODEL_DIR` is not set,
   calls sherpa's `text2token --tokens-type phone+ppinyin`, and rewrites
   `assets/wake/keywords.txt`.
4. Commit both the JSON and generated text file. An out-of-vocabulary word is a
   generation error; do not hand-write guessed phone tokens.

Android and iOS microphone permissions are already declared. Background audio
is intentionally not enabled: listening stops when the app leaves the
foreground and resumes when it returns. The iOS target is already 13.0, which
matches the sherpa pod minimum, and no background-audio capability is needed.

Before merging a phrase or sensitivity change, test a release build on a
physical Android phone and iPhone. Try several real voices and accents in a
quiet room and a moving/noisy vehicle; confirm a wake hit enters the same voice
flow as the mic button and that wake capture releases the mic cleanly on both
platforms. Then leave the foreground app listening to ambient conversation,
TV, podcasts, and driving audio for several hours, record false accepts per
hour (including “Cora”, “Kara”, “corner”, and “corona”), and compare one-hour
battery drain and temperature with wake word disabled. Also check wake-to-voice
latency and that the beginning of the command is not clipped after handoff.

## Third-party notices

### sherpa-onnx wake-word model

The files in `assets/wake/model/` are from
[`sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20`](https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models),
published by the k2-fsa sherpa-onnx project for Chinese and English keyword
spotting. The model-specific licence for these weights and `tokens.txt`, and
the model's training-data provenance, are not stated in the upstream model
documentation or release. Their licence is therefore **unconfirmed; ask the
maintainers before commercial distribution**. Do not assume the repository's
licence covers these model artifacts.

The sherpa-onnx software itself is licensed under
[Apache License 2.0](https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE).

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
