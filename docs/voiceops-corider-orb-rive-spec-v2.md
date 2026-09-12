# VoiceOps co-rider orb — Rive build spec (v2)

For use with the Rive Editor's official MCP integration (Claude Code, Cursor,
or Codex running locally alongside your open Rive Editor). Paste this whole
file as your starting prompt once you're ready to build.

**Direction locked: Nebula Drift** — soft glowing core, drifting particles,
each mood gets its own distinct silhouette (not just a tinted circle).
Direction board (for reference, CSS mockups only): https://fdc16235.ht-ml.app/
— password: xq9q-xgww-bj9n

## Build steps, in order

1. Create **2 artboards**, both **500 × 500px, transparent background** — one
   named `Holographic`, one named `Chrome` (names are your call, these are
   just clear defaults). Transparent fill is load-bearing: the orb renders
   over the map, cards, and onboarding backgrounds — any solid artboard color
   will show as a hard square around it.
2. On each artboard, build the Nebula Drift base — a soft glowing core
   (~350–400px diameter, artboard-centered) plus a few drifting particle
   motes orbiting it, in that artboard's material palette (see "Material
   palette" for hex values). Center matters: Flutter scales this artboard
   into 3 sizes (150/60/40dp) with `BoxFit.contain`, so the orb's visual
   center must be the artboard's geometric center.
3. Add **one State Machine per artboard**, any name (default: `CoRider`),
   with exactly the 7 trigger inputs listed below — spelling and case must
   match exactly. See "State machine wiring" for how they connect.
4. For each of the 7 triggers, keyframe a distinct silhouette for the core
   shape (see "Shape per mood"), blending smoothly (~600ms, cubic ease-in-out)
   rather than hard-cutting. Keep the particle layer constant across all 7 —
   only the core shape and its mood tint change.
5. Preview at **40px, 60px, and 150px** against a dark background (`#0F0E1A`)
   — check silhouette recognition and particle contrast at each. Simplify any
   silhouette that turns to noise at 40px (see "Celebrating fallback").
6. Tell me the final artboard names, the state machine name, and where the
   `.riv` file ended up (or hand it to me directly) — that's all I need to
   wire it into the app.

## Artboard technical specs

- **Dimensions:** 500 × 500px, both artboards
- **Background:** transparent (no fill)
- **Origin / center:** orb's visual center = artboard's geometric center (250, 250)
- **Safe area for resting shape:** ~400 × 400px centered — leaves ~50px on
  each side for celebrating's bloom to extend past the resting circle without
  clipping
- **Target device DPR:** up to 3x (Android xxhdpi) — 500px vector scales
  cleanly down to 40dp and up to 150dp @ 3x (~450px physical)

## Rive setup directives

Not tutorial — these are the specific techniques to use.

- **Shape morphing:** per-vertex keyframing on a single path per mood —
  keyframe the same path's point positions differently across each mood's
  animation. Rive interpolates between them automatically when the State
  Machine blends. Use bones (Rigging panel) only if a mood needs organic
  flowing motion that direct keyframing can't produce.
- **Drifting particles:** Rive has no built-in particle emitter — build 3–5
  small circle shapes as individual groups, each on a continuous slow
  rotate-and-drift loop. Put them on a dedicated animation layer (weight 1,
  always playing), separate from the mood layer, so motes keep drifting
  regardless of which mood is active. See "Particle layer specs" for concrete
  numbers.
- **The 7 inputs:** **Trigger** type specifically — not Boolean, not Number.
  The Flutter app fires them via
  `controller.findSMI<SMITrigger>(name)?.fire()` once per mood change.
- **Transitions:** ~600ms duration, **Cubic ease-in-out** curve (not Quad,
  not Sine, not Linear). Cubic matches `Curves.easeInOutCubic` in Flutter,
  which is what `VoiceOpsMotion.orbMorph` already uses — the orb morph will
  visually match surrounding UI motion.
- **Preview:** Rive's Preview pane resized to 40 / 60 / 150px, on a dark
  background matching the app.

## State machine wiring

- **Entry state:** `idle` — the state machine starts here on first render.
- **Transitions:** all 7 mood states reachable from **Any State** — a trigger
  fired mid-animation jumps directly to its target, doesn't queue behind a
  return-to-idle.
- **Trigger re-fire behavior:** if a trigger fires while its own state is
  already active, the animation replays from start. Set each non-idle state's
  animation to **One Shot**; `idle` is **Loop** (see "Idle breathing loop").
- **Return to idle:** each of the 6 non-idle states transitions back to
  `idle` on completion — add a transition from the state to `idle` with
  "Exit Time" set to 1.0 (animation end). This way a `celebrating` fire plays
  the bloom, then settles back to idle automatically without the app needing
  to fire `idle` explicitly.

## Idle breathing loop

`idle` is not static — a frozen sphere reads as broken, not resting.

- Subtle scale: **0.98 → 1.02 → 0.98 over 2.4s**, cubic ease-in-out, looping
- No color change during breath
- Particle layer continues its own loop independently

This is the "slowest pulse" the mood color table implies for idle, encoded
concretely.

## Particle layer specs

Load-bearing — this is the connective thread that keeps all 7 moods reading
as "the same character."

- **Count:** 3–5 motes, fixed across all moods
- **Mote radius:** 4–8px at the 500×500 artboard scale, varied (not uniform)
- **Orbit radii:** varied per mote, not concentric — some closer, some
  farther, some at oblique offsets
- **Rotation periods:** deliberately desynced — e.g. 8s, 11s, 14s. Motes
  sharing a period reads as mechanical.
- **Layer weight:** 1 (always fully visible, never blends out)
- **Behavior across moods:** unchanged — mood transitions do not touch the
  particle layer

## Performance rule

VoiceOps targets a smooth 60fps on mid-range Android, and the rest of the
frontend already makes real tradeoffs for that (capped blur, unblurred glass
on repeated elements). Keep the orb light the same way:

- **Vertex budget:** total path vertices across the core shape ≤ 60. Rive's
  mesh binding tool shows the count.
- **No stacking:** no stacking of multiple blurred/glow layers per mood —
  visual richness comes from color and shape, not filter effects.
- **Particle count:** 3–5, not dozens.

## Material palette

The current Flutter placeholder uses these hex values per material. Starting
point — override freely as long as lime stays out.

- **Holographic:** `#C4B5FD`, `#F9A8D4`, `#7DD3FC`, `#A7F3D0`
- **Chrome:** `#EDEBF5`, `#8E8AA6`, `#2B2740`, `#D3CFE6`, `#5E5A78`
- **Specular highlight (both):** `#FFFFFF`

## What must exist (load-bearing — the Flutter code depends on these exactly)

- **2 artboards** — one per orb material:
  - Holographic bubble (used in onboarding)
  - Chrome / mercury (used in the main app)
- **1 state machine per artboard**, any name you like, with exactly **7
  trigger inputs**, spelled exactly as below (case-sensitive — sourced from
  `AgentState.riveKey` in `lib/mascot/mascot_state.dart`):

```
idle
thinking
calling
mapping
task
summarizing
celebrating
```

## Shape per mood

Each of the 7 moods gets its own recognizable silhouette, not a shared circle
with only color/glow changing. Built as one mesh (per-vertex keyframing or a
bone rig if needed) and 7 keyframed shape states on the state machine,
blended between rather than 7 separate static artboards. ~600ms cubic
ease-in-out per transition — matches `VoiceOpsMotion.orbMorph` in
`core/theme/tokens.dart`.

Starting silhouettes — your artistic call, these are the jumping-off point:

| Mood          | Suggested silhouette                                       |
|---------------|--------------------------------------------------------------|
| idle          | Soft, near-perfect sphere — calm resting state                |
| thinking      | Slight elongation into a teardrop, slowly rotating            |
| calling       | Sphere with gentle outward pulse rings (like a connection)    |
| mapping       | Sphere with a subtle directional lean/point (route-seeking)   |
| task          | Slightly faceted edges — precise, working                     |
| summarizing   | Sphere gently flattening/settling — winding down              |
| celebrating   | Brief starburst/bloom — the one moment it truly departs from round |

### Celebrating fallback (for 40dp legibility)

The starburst is the highest-frequency shape and the most likely to degrade
at 40dp. If it reads as noise at that size, pick one at author time (don't
try to LOD-swap at runtime):

- Reduce from 6–8 points to a **4-point cross-bloom**, OR
- Replace with a **bright ring-pulse** — a concentric ring expanding from the
  sphere

Both preserve the "burst" semantics with fewer high-frequency edges.

## Mood color reference (with hex — starting point, not mandatory)

| Mood          | Hex                        | Feel                                  |
|---------------|----------------------------|----------------------------------------|
| idle          | none (untinted)            | Resting — slowest pulse, least glow    |
| thinking      | `#C4B5FD` (violet)         | Processing — brisk spin                |
| calling       | `#A7F3D0` (emerald)        | Active call — steady pulse             |
| mapping       | `#7DD3FC` (blue)           | Routing — moderate spin                |
| task          | `#F59E0B` (amber)          | Working — brisk pulse                  |
| summarizing   | `#F59E0B` @ ~50% opacity   | Wrapping up — calm                     |
| celebrating   | `#F9A8D4` (pink)           | Done — fastest pulse, most glow, most spin |

Values chosen to reuse Holographic palette hues where possible — keeps the
orb visually consistent with the rest of the app's accent language.

## Hard rule

Never use lime `#C8F250` anywhere in the orb, either material, any state.
That color is reserved exclusively for the push-to-talk "mic is live"
indicator — a driver must be able to tell at a glance that the mic is hot,
so nothing else in the app may use it.

## Sizes it has to read at

| Context                     | Size  | Notes                                 |
|------------------------------|-------|----------------------------------------|
| Home screen hero             | 150dp | Full detail visible here               |
| Floating bubble (other tabs) | 60dp  | Must still read clearly                |
| Settings tab bubble          | 40dp  | Smallest — shape legibility tested hardest here |

Preview inside Rive at the corresponding px (approximate at 1x DPR — 40px,
60px, 150px) against a dark background (`#0F0E1A` or similar), not at full
editor zoom.

## Deliverable

When done, send back:

1. The `.riv` file (or its path if placing directly in
   `frontend/assets/rive/` on your machine)
2. Final artboard names + state machine name, if changed from `Holographic` /
   `Chrome` / `CoRider`

Two files change on our side once that lands, both small:
`lib/mascot/mascot_display.dart` (swapping the placeholder painter for a
`RiveAnimation.asset(...)` call using those names) and `pubspec.yaml` (adding
the `assets/rive/` line — today it's only a TODO comment there, not a live
entry, left that way deliberately so the build never points at a missing
folder). Nothing else in the app touches the orb directly.
