# Voice preview clips

One short clip per co-rider voice, played by the "hear this voice" button in
the post-sign-up voice step and in Settings. Loaded by
`lib/providers/voice_preview_provider.dart`. The clips are supplied by the
captain; until one exists, that voice's preview button is disabled ("Preview
coming soon") and nothing else breaks.

**Format:** MP3, named `<voice>.mp3` (the `CoRiderVoice` enum `name`).

Expected files (11):

- `alba.mp3`, `eve.mp3`, `george.mp3`, `jane.mp3`, `jean.mp3`, `mary.mp3`,
  `michael.mp3` (American English)
- `anna.mp3`, `charles.mp3`, `paul.mp3`, `vera.mp3` (British English)

**Guidance:**

- 3-6 seconds.
- A short greeting in that voice (for example the co-rider's opening line).
- Similar loudness across all eleven clips, so switching voices doesn't jump
  in volume.

This folder is declared in `pubspec.yaml` (`assets/audio/voice_previews/`);
Flutter needs the directory to exist at build time, which this README keeps
true while the clips are missing. This file is bundled too and is never played.
