# Co-Rider Voice Preview Audio Clips

This folder contains pre-rendered audio preview clips for each of the 11 supported co-rider voices.
These clips are played when a driver previews a voice during onboarding or in Settings.

## Format & Requirements
- Format: MP3, mono, 96 kbps
- Loudness: Normalized via EBU R128 (`loudnorm=I=-16:TP=-1.5:LRA=11`)
- Duration: 4-6 seconds each
- Source line: "Hi, I'm Kora, your co-rider. This is how I'll sound on the road."

## Files
- `alba.mp3` (American English)
- `anna.mp3` (British English, default)
- `charles.mp3` (British English)
- `eve.mp3` (American English)
- `george.mp3` (American English)
- `jane.mp3` (American English)
- `jean.mp3` (American English)
- `mary.mp3` (American English)
- `michael.mp3` (American English)
- `paul.mp3` (British English)
- `vera.mp3` (British English)

## Generation
Generated via `voiceops-backend/scripts/generate_voice_previews.py` directly from the AssemblyAI Voice Agent API.
