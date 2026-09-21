# Frontend Rules — Flutter

Scope: everything under `frontend/`. Do not touch `backend/` from a
frontend task.

---

## Stack

- **State:** Riverpod (`flutter_riverpod`). Do not introduce Provider, Bloc,
  GetX, or setState for shared state.
- **Routing:** go_router. All routes declared in one router file
  (`lib/app/router.dart`).
- **Map:** `flutter_map` + OpenFreeMap vector tiles (`vector_map_tiles`),
  no API key. Never `google_maps_flutter`
- **Realtime:** `web_socket_channel`
- **Icons:** `tabler_icons_plus` — never emoji, never Material icons for
  stat cards
- **Type:** `google_fonts` (Plus Jakarta Sans)
- **Co-rider:** `rive`, plays the co-rider `.riv`
- **Auth / data:** `supabase_flutter`
- **Audio out:** `just_audio`, **Audio in:** `record`, **Location:**
  `geolocator`

Do not add a package without checking whether one of the above already
covers the need.

---

## Design System

Dark-mode-first. The main app assumes a dark surface; the map is styled
to match.

- **Typography:** Plus Jakarta Sans. This is a substitute for Circular Std
  and Sofia Pro, which are proprietary. If font files are later supplied,
  swap them in the token file only.
- **Mascot:** always called the **co-rider**. Never "co-pilot",
  "assistant", "bot", or "AI helper" — in code, comments, or UI copy.
- **Orb materials:** holographic bubble orb in onboarding,
  chrome/mercury orb in the main app. These are two distinct moods; do
  not unify them.
- **Mascot implementation:** `MascotDisplay` plays
  `assets/rive/corider.riv` and falls back to a drawn orb if it cannot
  load. Ez authors the `.riv` files; do not edit them.

Design tokens live in a single tokens file
(`lib/core/theme/tokens.dart`, summarised in SDD §8). Never hardcode a
colour, spacing value, or font size in a widget — reference the token.
Lime (`KoraColors.live`) is reserved for the mic-hot state.

---

## Push-to-Talk Button

The central interaction of the whole app.

- Large circular, **minimum 80×80px** touch target
- Four states: `idle → recording → processing → speaking`
- Every state needs a distinct visual treatment
- State is driven by the voice provider, not local widget state

Do not reduce the size, and do not collapse the four states into fewer.

---

## Home Screen Layout

```
┌─────────────────────────┐
│  Map                45% │
├─────────────────────────┤
│  Next stop card         │
├─────────────────────────┤
│  Transcript display     │
├─────────────────────────┤
│  Push-to-talk button    │
├─────────────────────────┤
│  Bottom nav             │
└─────────────────────────┘
```

Map occupies the top 45%. Preserve this proportion.

---

## Onboarding

Three screens, shown before the auth gate (the router checks onboarding
first):

0. **Splash** — giant editorial type with inline holographic pills,
   "Meet your co-rider for every delivery route", white "Get started" CTA
1. **Hook**
2. **Power** — its Next button completes onboarding and hands off to the
   auth welcome screen ("Get started" → sign-up)

The fourth screen, Trust, was retired on 2026-09-12. Do not bring it back:
its "time to drive" moment doesn't fit before sign-up.

---

## WebSocket Handling

- One connection, owned by a single Riverpod provider
- Handle: connect, reconnect with backoff, disconnect, error
- Never open a second socket from a widget
- Message types are frozen — see `docs/contracts/interface.md` §1
- Agent navigation renders **in-app**: `screen_navigate` switches the tab
  and `map_route` draws the route on the Flutter map. Never launch an
  external maps app or deep link

If the socket drops mid-shift, the UI must show a clear degraded state,
not fail silently.

---

## Required UI States

Every screen that loads data needs all four:

- **loading** — never a bare spinner on a blank screen
- **empty** — meaningful copy, not "No data"
- **error** — actionable, with a retry path
- **success**

A screen that only handles the success path is not complete.

---

## Verification

Before declaring a frontend task done:

```bash
cd frontend
flutter analyze
flutter test          # if tests exist for the touched area
```

For UI changes, describe the rendered result — a task is not complete
because it compiles.

---

## Scope Discipline

- Branch: `features/frontend/<feature-slug>` off `staging`. PR back into
  `staging`
- Do not reformat files you did not otherwise change
- Do not upgrade package versions as part of a feature task
- Do not touch `backend/`
