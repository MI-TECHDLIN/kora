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

The local production file is ignored by Git. Rotate any exposed service-role
key and keep it on the backend only.
For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
