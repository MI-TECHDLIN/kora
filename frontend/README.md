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

`VOICEOPS_API_URL` in that file overrides the app's built-in production
backend, so keep it at the Render URL for anything that isn't a local test:
a value left pointing at a LAN address or an old service makes voice fail
without ever reaching Render (Settings > About shows the backend a build
uses).

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

The phrase list is in `assets/wake/wake_phrases.json`. Every other wake tunable
(capture, input gain, decoder defaults, the Normal/High profiles) is in one
file, `lib/core/wake/wake_tuning.dart`.

**Phrases.** From standby the app wakes on `Kora`, `Hey Kora`, `Okay Kora`,
`Hi Kora`, `Hello Kora`, `Good morning/afternoon/evening Kora` and `Wake up
Kora`, plus the `Cora` forms (`Cora`, `Hey Cora`, `Hi Cora`, `Okay Cora`,
`Hello Cora`). The bundled lexicon gives `Cora` exactly the same phones as
`Kora`, so those are one detector; the engine sends sherpa one line per distinct
token sequence, and `keywords.txt` still carries every Cora line as the
generator tokenised it. A bare `hi`, `hey` or `hello` is not a standby wake
phrase, because it fires on background conversation. Settings has **Wake on
greetings** (off by default, with a warning) that adds those three; changing it
reconfigures the engine. Bare `hello` works in the synthetic check, but bare
`hi` and `hey` are unreliable with this model (about 1 hit in 6) and `hey` also
fired on “okay then”, so treat the option as a convenience, not a guarantee.
After activation, the AssemblyAI session keeps the mic visibly hot for the
single configurable `voiceFollowUpWindow` (12 seconds), so greetings and
follow-ups work without the name. When that idle window expires, the app
releases the session mic and returns to keyword-only listening.

**Wake sensitivity (Settings, Normal by default).** A phone on a dashboard hears
the driver far below the level the keyword model expects: in the offline check
the shipped configuration heard 0 of 60 wake samples at -40 dBFS peak. The wake
stream now runs through `WakeInputGain` (`lib/core/wake/wake_input_gain.dart`),
an automatic gain that lifts quiet speech towards -24 dBFS RMS but only on
frames that stand 6 dB above a tracked noise floor, so steady road noise is not
pumped up. It runs inside the wake worker isolate on the wake stream only; the
AssemblyAI stream never sees it. **Normal** allows up to +24 dB (+12 dB at rest).
**High**, for a phone mounted far away, allows up to +36 dB (+24 dB at rest) and
also raises every phrase's sherpa score by 1.0 and lowers its threshold by 0.10;
it wakes more often at a distance and also mis-wakes more.

Wake capture is 16 kHz, mono PCM16 in 100 ms chunks. On Android it uses the
voice-recognition source with no platform gain, echo-cancel, or noise-suppression
effect (`WakeCaptureConfig.androidAudioSource`), then converts little-endian
samples to Float32 by dividing by 32768, applies the input gain, and feeds
sherpa. The audio source is the one thing that cannot be measured offline: other
sources (`camcorder`, `unprocessed`, `voicePerformance`) or Android's own
`AutomaticGainControl` may pick up distant speech better or worse per phone, and
the software gain was chosen so the result does not depend on that.

**Offline check, 2026-09-25** (before = the manifest on `staging` before this
change, where the duplicate `kora` entry made bare Kora effectively score 3.0 /
threshold 0.15; after = the profiles above). Six Edge TTS voices (US, GB, AU, IN)
x ten wake phrases (`Kora`, `Hey/Hi/Okay/Hello Kora`, and the Cora forms) = 60
wake clips; 17 non-wake clips x 6 voices = 102 (Kara, corner, corona, hello
driver, what's up, hi, hey, hello, hey there, hi there, okay, okay then, hey
Carla, Laura, Hey Laura, hello everyone, Hey Sarah how are you). Speech is
peak-scaled to the stated dBFS, a -66 dBFS RMS microphone floor is added,
everything is PCM16-quantized. "Road" is brown-noise road rumble at the stated
speech-to-noise ratio; "room" is a 0.35 s synthetic reverb.

| Speech peak | Staging as shipped | Normal | High |
|---|---|---|---|
| -40 dBFS | 4/60 hits, 1/102 FA | 38/60, 2/102 | 44/60, 6/102 |
| -35 dBFS | 18/60, 3/102 | 41/60, 3/102 | 50/60, 6/102 |
| -30 dBFS | 34/60, 3/102 | 47/60, 6/102 | 52/60, 6/102 |
| -20 dBFS | 50/60, 8/102 | 52/60, 4/102 | 54/60, 7/102 |
| -10 dBFS | 50/60, 9/102 | 50/60, 2/102 | 57/60, 6/102 |
| -35 dBFS + road 5 dB SNR | 11/60, 2/102 | 34/60, 2/102 | 35/60, 4/102 |
| -30 dBFS + road 5 dB SNR | 23/60, 2/102 | 40/60, 2/102 | 41/60, 5/102 |
| -30 dBFS + road 0 dB SNR | 9/60, 1/102 | 23/60, 1/102 | 19/60, 3/102 |
| -35 dBFS + room reverb | 14/60, 0/102 | 25/60, 1/102 | 31/60, 1/102 |

The false accepts are the near-miss names, mostly “hey Carla” and “corner”
(phonetically “Hey Kora” and “Kora”), and once “Kara”; the other clips, and 120 s
each of microphone-floor noise and road noise at -40/-30/-20 dBFS RMS, produced
no accepts in any profile. A fixed gain alone (+10/+20/+30 dB) reached 17/36/38
hits at -40 dBFS with 0/5/4 false accepts, but it over-drives a driver who is
close, which is why the gain tracks the speaker. Findings that did not ship: a per-phrase threshold
raise cut hits about as much as false accepts; a two-stage check (sensitive first
pass, then a stricter re-decode of the last 2 s, peak-normalised) removed only
the false accepts that were already rare, lost 5-10 hits, and cannot separate
“Kara” from “Kora” because both passes use the same model. A re-run with `tool/wake_far_field_eval.py` (different noise draw) moved
individual cells by up to 8 hits in 60, so read the table as ranges, not exact
rates. The numbers come from
synthetic TTS through the same int8 model; they say nothing about Android
microphone processing, real cabin noise, accents or real false accepts per
hour, so **physical-phone testing is still required**, especially High.

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
