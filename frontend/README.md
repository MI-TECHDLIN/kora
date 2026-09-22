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

Kora uses Picovoice Porcupine only while the app is in the foreground. Supply
the Picovoice access key at build time; never add it to a committed config file:

```sh
flutter run --dart-define=PORCUPINE_ACCESS_KEY=<access-key>
```

The phrase list and sensitivities are in `assets/wake/wake_phrases.json`.
Train one Porcupine custom keyword per enabled phrase and platform, then place
each `.ppn` under `assets/wake/android/` or `assets/wake/ios/` using the exact
filename from the manifest. Missing files are skipped, and a missing key or a
startup failure leaves the wake-word feature off without affecting the mic
button. Porcupine detects only trained phrases, not arbitrary greetings.

Android and iOS microphone permissions are already declared. Background audio
is intentionally not enabled: listening stops when the app leaves the
foreground and resumes when it returns.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
