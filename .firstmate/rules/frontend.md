# Frontend Rules — Flutter

Scope: everything under `frontend/`. Do not touch `backend/` from a
frontend task.

---

## Stack

- **State:** Riverpod. Do not introduce Provider, Bloc, GetX, or setState
  for shared state.
- **Routing:** go_router. All routes declared in one router file.
- **Map:** `google_maps_flutter`
- **Audio out:** `just_audio`
- **Audio in:** `record`
- **Realtime:** `web_socket_channel`
- **Location:** `geolocator`
- **Icons:** `tabler_icons_plus` — never emoji, never Material icons for
  stat cards

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

Design tokens live in a single tokens file. Never hardcode a colour,
spacing value, or font size in a widget — reference the token.

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

Four screens:

0. **Splash** — giant editorial type with inline holographic pills,
   "Meet your co-rider for every delivery route", white "Get started" CTA
1. **Hook**
2. **Power**
3. **Trust**

---

## WebSocket Handling

- One connection, owned by a single Riverpod provider
- Handle: connect, reconnect with backoff, disconnect, error
- Never open a second socket from a widget
- Message types are frozen — see `contracts.md`

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

- Branch: `features/frontend/<feature-slug>` off `staging`
- Do not reformat files you did not otherwise change
- Do not upgrade package versions as part of a feature task
- Do not touch `backend/`
