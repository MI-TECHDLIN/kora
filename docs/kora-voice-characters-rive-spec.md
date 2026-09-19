# Kora voice characters - Rive build spec (v1)

For use with the Rive Editor's official MCP integration (Claude Code, Cursor, or Codex running
locally alongside your open Rive Editor). Paste this whole file as your starting prompt once
the Rive Editor is open with an empty file.

These are the **eleven co-rider voice characters** shown only in the post-sign-up voice
selection step of onboarding. Settings never loads them. They are a sibling of the co-rider
orb (`docs/voiceops-corider-orb-rive-spec-v2.md`), not a replacement: the orb stays the
co-rider everywhere else in the app.

## Read this first - what is fixed and what is your call

**Fixed (the Flutter code depends on these exactly - do not rename anything below):**

- **One file**, saved as `frontend/assets/rive/voice_characters.riv`.
- **Eleven artboards**, named exactly (lowercase, no spaces):
  `alba`, `eve`, `george`, `jane`, `jean`, `mary`, `michael`, `anna`, `charles`, `paul`, `vera`.
  The app looks each one up by the voice's ID, so a misspelled artboard name silently falls
  back to the grey placeholder.
- **One state machine per artboard**, named exactly `Voice`, with exactly **two Boolean
  inputs**, named exactly `selected` and `speaking` (case-sensitive). Booleans, not triggers:
  both states are held for as long as they are true.
- Each artboard is **500 x 500 px with a transparent background**. Transparent fill is
  load-bearing: the character renders over the onboarding backdrop, and a solid artboard color
  shows as a hard square around it.
- The character's visual center is the artboard's geometric center (250, 250). Flutter scales
  the artboard with `BoxFit.contain`.

**Your call (creative direction below is a starting point - override freely):**
silhouettes, faces, accessories, accent colors, and exact motion. The tables below are
proposals, not requirements. Edit the personality column after listening to each voice's
preview in the app - the seeds there come from the names only, not from how the voices
actually sound.

## Design language

- **Dark-mode-first.** Preview every character against `#0F0E1A`.
- **Same family as the orb.** Soft, glowing, rounded, friendly. Not photorealistic, not a
  human portrait, not 3D. Think small companion creatures built from the orb's own visual
  vocabulary (soft glowing body, a few drifting motes), each with a distinct silhouette so the
  eleven are tellable apart at a glance - **by shape and features first, color second**, so
  they still read for color-blind drivers.
- **No national symbols, flags, or caricature.** The voices are American or British English,
  but that must not show up as a costume. Accent does not affect the design at all.
- **Consistent construction.** One shared rig (see "Build order") so all eleven feel like one
  cast: same eye style, same mouth/voice indicator, same idle timing family, different bodies.
- **Hard rule: never use lime `#C8F250` anywhere, in any character, in any state.** That color
  is reserved exclusively for the push-to-talk "mic is live" indicator. Also stay clear of
  any yellow-green that reads as lime.
- **Glass and glow are restrained.** Kora targets a smooth 60fps on mid-range Android and the
  picker can show all eleven at once.

## The cast

Accent colors are starting points chosen to be distinct from each other on `#0F0E1A`, using
the app's existing hue family. The personality column is a seed derived from the name alone -
rewrite it after you listen to the real voices.

| Artboard  | Accent (start) | Personality seed (edit after listening) | Silhouette idea                       | Distinguishing feature idea          |
|-----------|----------------|------------------------------------------|----------------------------------------|---------------------------------------|
| `alba`    | `#C4B5FD`      | bright, fresh, morning-like              | tall soft oval                         | small rising-sun crest                |
| `eve`     | `#F9A8D4`      | curious, gentle                          | round with a slight lean               | tiny leaf sprig                       |
| `george`  | `#7DD3FC`      | steady, dependable                       | wide rounded square                    | flat cap-like brim                    |
| `jane`    | `#A7F3D0`      | friendly, practical                      | round with a soft point at the top     | single antenna with a dot             |
| `jean`    | `#FDBA74`      | calm, composed                           | egg shape                              | small ring halo                       |
| `mary`    | `#FCA5A5`      | warm, caring                             | plump teardrop                         | soft cheek glow                       |
| `michael` | `#93C5FD`      | confident, upbeat                        | broad-shouldered blob                  | pair of round glasses                 |
| `anna`    | `#D8B4FE`      | graceful, clear                          | slim teardrop                          | trailing ribbon mote                  |
| `charles` | `#FDE68A`      | polished, courteous                      | rounded rectangle                      | small bow-tie shape                   |
| `paul`    | `#5EEAD4`      | easygoing, casual                        | lopsided friendly circle               | small tuft on top                     |
| `vera`    | `#F0ABFC`      | crisp, precise                           | faceted rounded diamond                | single sharp highlight streak         |

`anna` is the app's default voice. It should read as the most "neutral home" character of
the set - the one a driver sees selected when they arrive.

## Build order (do it in this order)

1. **Build `alba` first, completely,** as the master rig: body, eyes, mouth/voice indicator,
   two or three drifting motes, the `Voice` state machine with both Boolean inputs, and all
   three animation layers below. Preview it at every size in "Sizes" and fix problems now,
   while there is only one artboard to fix.
2. **Duplicate the artboard ten times** and rename each to the exact names above. Change the
   body silhouette, the distinguishing feature, and the accent color per the cast table.
   Keep the rig, eye style, timing family, and state machine wiring identical so nothing
   drifts between characters.
3. **Vary the idle timing slightly per character** (see "Idle") so eleven characters in the
   picker do not breathe in lockstep.
4. **Check every artboard** against the QA checklist at the end.
5. **Save as `frontend/assets/rive/voice_characters.riv`** and report back (see "Deliverable").

## State machine wiring (per artboard)

State machine name: `Voice`. Inputs: `selected` (Boolean), `speaking` (Boolean).

Use **three animation layers** so the states stack instead of fighting:

- **Layer 1 - Base (always on):** `idle` loop. Never leaves this layer.
- **Layer 2 - Selection:** default state `unselected` (no change to the base). When
  `selected` becomes true, transition to `presenting`; when it becomes false, transition
  back. ~400ms, cubic ease-in-out (matches `Curves.easeInOutCubic` in Flutter).
- **Layer 3 - Voice:** default state `quiet` (no change). When `speaking` becomes true,
  transition to `talking`, a **looping** state that holds for as long as `speaking` stays
  true. When it becomes false, transition back to `quiet` (~300ms).

`selected` and `speaking` are independent: a character can be selected and quiet, selected and
talking, or (briefly, mid-switch) talking while not selected. All four combinations must look
right.

## Animation specs

**Idle (Layer 1, loop):**
- Subtle breathing scale **0.98 -> 1.02 -> 0.98 over ~2.4s**, cubic ease-in-out, looping.
  Per character, vary the period by up to +/-0.4s.
- A blink every ~4-6 seconds, desynced per character.
- Motes keep drifting on their own always-on loop (see "Motes").
- No color change during idle.

**Presenting (Layer 2, on `selected` = true):**
- Gentle lift to ~1.08 scale, a soft accent-colored glow ring fades in around the body, eyes
  brighten slightly. One clean settle, no bounce overshoot beyond ~4%.
- Holds while `selected` stays true. Reverses on false.

**Talking (Layer 3, on `speaking` = true, looping):**
- A rhythmic swell of the body or mouth like a voice's cadence - similar in spirit to the
  orb's `speaking` mood. Eyes stay attentive.
- Loops seamlessly until `speaking` goes false. No exit-time return; the `speaking` = false
  transition handles it.

**Motes:** 2-3 small drifting circles per character (radius 3-6px at 500x500), on a dedicated
always-on loop with deliberately desynced periods (e.g. 8s, 11s, 14s), unaffected by state.

## Performance budget (load-bearing - eleven of these can be on screen at once)

- **Vertex budget:** total path vertices per artboard <= 80.
- **No stacked blur/glow layers.** Get richness from shape and color, not filter effects. One
  soft glow ring on `presenting` is the only glow allowed.
- **Motes:** 2-3, never more.
- Keep the idle and quiet states as cheap as possible - most of the eleven sit idle all the
  time and only one at a time is ever `talking`.

## Sizes it has to read at

| Context                                   | Approx. size | Notes                                        |
|--------------------------------------------|--------------|-----------------------------------------------|
| Character in the picker grid               | ~88dp        | Smallest - silhouette legibility tested here  |
| Selected character (hero on the screen)    | ~160dp       | Full detail visible                           |

Preview inside Rive at the matching px (88 and 160) against `#0F0E1A`, not at editor zoom.
Simplify any feature (glasses, bow-tie, sprig) that turns to noise at 88.

## QA checklist (run per artboard before you save)

- [ ] Artboard name matches the table exactly (lowercase).
- [ ] 500 x 500, transparent background, visual center at (250, 250).
- [ ] State machine is named `Voice` with exactly `selected` and `speaking` as Booleans.
- [ ] Toggling `selected` on/off animates cleanly both ways.
- [ ] Toggling `speaking` on/off animates cleanly both ways, and `talking` loops seamlessly.
- [ ] All four `selected` x `speaking` combinations look right.
- [ ] Readable at 88px and 160px on `#0F0E1A`.
- [ ] No lime, no yellow-green, no national symbols.
- [ ] Path vertices <= 80, no stacked blur layers, 2-3 motes.
- [ ] Distinguishable from the other ten by silhouette/feature alone (imagine the accent color
      removed).

## If the editor integration cannot do something

Say so plainly instead of approximating silently - for example, if the MCP tools cannot build
a multi-layer state machine or set a Boolean input the way this spec asks. Report exactly what
was done automatically and exactly what still needs a manual step in the Rive Editor, so the
remaining work is a short, specific list rather than a guess.

## Deliverable

When done, send back:

1. The saved `.riv` (or confirm it is at `frontend/assets/rive/voice_characters.riv` on your
   machine).
2. The final artboard names and the state machine and input names, **only if any differ from
   this spec**. If they differ, the app needs a small code change to match, so flag it.
3. Anything the editor integration could not do, per the section above.

On the app side the file is optional: until it exists the onboarding screen shows a neutral
placeholder per voice, and once it is in `frontend/assets/rive/` the characters appear with no
other change (the `assets/rive/` folder is already bundled). Nothing in Settings changes.
