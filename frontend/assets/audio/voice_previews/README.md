# Voice preview clips

One short clip per co-rider voice, played by the "hear this voice" button in
the post-sign-up voice step and in Settings. Loaded by
`lib/providers/voice_preview_provider.dart`. The clips are generated via
`voiceops-backend/scripts/generate_voice_previews.py` directly from the
AssemblyAI Voice Agent API.

**Format:** MP3, named `<voice>.mp3` (the `CoRiderVoice` enum `name`).

Expected files (11):

- `alba.mp3`, `eve.mp3`, `george.mp3`, `jane.mp3`, `jean.mp3`, `mary.mp3`,
  `michael.mp3` (American English)
- `anna.mp3`, `charles.mp3`, `paul.mp3`, `vera.mp3` (British English)

**Guidance & Specifications:**

- 3-6 seconds each.
- Spoken line: "Hi, I'm Kora, your co-rider. This is how I'll sound on the road."
- Normalized via EBU R128 (`loudnorm=I=-16:TP=-1.5:LRA=11`) at 96 kbps mono.
- Similar loudness across all eleven clips, so switching voices doesn't jump
  in volume.

This folder is declared in `pubspec.yaml` (`assets/audio/voice_previews/`);
Flutter needs the directory to exist at build time.
