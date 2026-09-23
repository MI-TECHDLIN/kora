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
`Hey Kora` and `Okay Kora` are the primary phrases. Bare `Kora` is disabled by
default because the synthetic spike missed the isolated word and falsely fired
on “Cora” and “corner”. The Settings toggle, foreground lifecycle, and mic
button fallback are unchanged.

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

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
