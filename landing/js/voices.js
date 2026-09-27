/*
 * Kora's co-rider voices, mirrored from the app.
 *
 * Names, grouping and order copy `CoRiderVoice`
 * (frontend/lib/providers/co_rider_voice_provider.dart). The set is the
 * intersection of that enum and the backend allowlist (`VOICES` in
 * voiceops-backend/app/agents/agent_config.py) with the bundled preview
 * clips (frontend/assets/audio/voice_previews/, copied to
 * assets/audio/voices/ here) - all three agree on these 11 today.
 *
 * Character silhouette, accent colour and feature per voice are copied
 * from the CAST table in frontend/tool/rive/build_voice_characters.js (the
 * generator for the app's `voice_characters.riv`, used only in its
 * post-sign-up voice step - see docs/kora-voice-characters-rive-spec.md).
 * `voice_characters.js` renders the same silhouette formula in SVG so the
 * web picker shows the same eleven characters, not a different mascot set.
 */

const bump = (th, at, w) => {
  const d = ((th - at + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
  return Math.exp(-(d * d) / (w * w));
};

/*
 * breath/blink (seconds): idle timing per character, so eleven characters
 * don't breathe or blink in lockstep - copied from the same CAST entries.
 */
export const VOICES = [
  {
    id: "alba", label: "Alba", group: "american", color: "#C4B5FD", face: -22, feature: "crest",
    body: { R: 138, sx: 0.82, sy: 1.08 }, breath: 2.4, blink: 4.6,
  },
  {
    id: "eve", label: "Eve", group: "american", color: "#F9A8D4", face: -10, feature: "sprig",
    body: { R: 140, tilt: 8 }, breath: 2.6, blink: 5.3,
  },
  {
    id: "george", label: "George", group: "american", color: "#7DD3FC", face: 8, feature: "brim",
    body: { R: 138, sx: 1.06, sy: 0.9, n: 3.2 }, breath: 2.8, blink: 4.2,
  },
  {
    id: "jane", label: "Jane", group: "american", color: "#A7F3D0", face: 0, feature: "antenna",
    body: { R: 132, warp: (th) => [0, -34 * bump(th, 0, 0.5)] }, breath: 2.2, blink: 5.6,
  },
  {
    id: "jean", label: "Jean", group: "american", color: "#FDBA74", face: -6, feature: "halo",
    body: { R: 134, sy: 1.08, warp: (th, x, y) => [x * 0.1 * (y / 140), 0] }, breath: 2.5, blink: 4.9,
  },
  {
    id: "mary", label: "Mary", group: "american", color: "#FCA5A5", face: 14, feature: "cheeks",
    body: { R: 140, sx: 1.05, sy: 0.96, warp: (th, x, y) => [x * 0.16 * (y / 140), -12 * bump(th, 0, 0.6)] },
    breath: 2.3, blink: 4.4,
  },
  {
    id: "michael", label: "Michael", group: "american", color: "#93C5FD", face: 0, feature: "glasses",
    body: { R: 138, sx: 1.08, sy: 0.9, warp: (th, x, y) => [x * 0.14 * (-y / 140), 0] }, breath: 2.7, blink: 5.1,
  },
  {
    id: "anna", label: "Anna", group: "british", color: "#D8B4FE", face: -6, feature: "ribbon",
    body: { R: 140, sx: 0.8, sy: 1.02, warp: (th, x, y) => [x * 0.08 * (y / 140), -22 * bump(th, 0, 0.7)] },
    breath: 2.4, blink: 4.8,
  },
  {
    id: "charles", label: "Charles", group: "british", color: "#FDE68A", face: -14, feature: "bowtie",
    body: { R: 138, sx: 0.98, sy: 0.92, n: 4.2 }, breath: 2.6, blink: 5.5,
  },
  {
    id: "paul", label: "Paul", group: "british", color: "#5EEAD4", face: 6, feature: "tuft",
    body: { R: 136, warp: (th) => [12 * Math.cos(th - 1.0), 8 * Math.cos(th + 0.2)] }, breath: 2.0, blink: 4.0,
  },
  {
    id: "vera", label: "Vera", group: "british", color: "#F0ABFC", face: 0, feature: "streak",
    body: { R: 146, sx: 0.9, sy: 1.02, n: 1.45 }, breath: 2.4, blink: 5.9,
  },
];

export const GROUP_LABELS = {
  american: "American English",
  british: "British English",
};

/** Matches CoRiderVoice.fallback / the backend's DEFAULT_VOICE. */
export const DEFAULT_VOICE = "anna";

export const voiceAssetFor = (id) => `assets/audio/voices/${id}.mp3`;

export const voiceById = (id) => VOICES.find((v) => v.id === id);
