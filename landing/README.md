# Kora landing page

A static, dependency-free marketing site for Kora with an interactive phone preview in the hero. Plain HTML, CSS and ES modules: there is no build step and no package to install, so the folder deploys to Cloudflare Pages exactly as it is.

- Design system: the app's own tokens, Plus Jakarta Sans, the Kora mark and the co-rider orb, so the page reads as an extension of the app.
- Hero preview: a scripted, fully client-side recreation of the app's screens. No backend, no API keys, no network calls.
- International by design: generic couriers, neutral sample addresses, metric units, 24-hour times, no currency and no region-specific names.

## Run it locally

Any static server works. The icon sprite and the media manifest are fetched over HTTP, so opening `index.html` from `file://` will not show icons.

```sh
python3 -m http.server 8080 --directory landing
# then open http://localhost:8080
```

## Deploy to Cloudflare Pages

This PR does not deploy anything or touch Cloudflare or DNS. When the domain is ready:

1. Cloudflare dashboard, **Workers & Pages**, **Create**, **Pages**, **Connect to Git**, pick `MI-TECHDLIN/kora`.
2. Build settings:

   | Setting | Value |
   |---|---|
   | Production branch | `main` (previews build from other branches) |
   | Framework preset | **None** |
   | Root directory (advanced) | `landing` |
   | Build command | *leave empty* |
   | Build output directory | `.` (the root directory itself; `/` is equivalent) |
   | Build watch paths (advanced) | `landing/*`, so app and backend commits do not trigger a build |

3. `_headers` (security headers, a CSP, font caching) and `404.html` are picked up automatically from the output root. `404.html` matters: without it Pages treats the site as a single-page app and answers every unknown path, including a missing screenshot, with `index.html`.
4. Attach the domain: the Pages project, **Custom domains**, **Set up a custom domain**, enter the domain (and `www` if wanted). The domain is registered at name.com and its nameservers are on Cloudflare, so Cloudflare creates the DNS record and certificate itself. For an apex domain it uses CNAME flattening; add a redirect from `www` to the apex (or the reverse) under **Rules**, **Redirect Rules**.

### Before launch

- [x] Set the Android link in `js/config.js` (`androidUrl`) to the release page, `https://github.com/MI-TECHDLIN/kora/releases/latest`, where visitors pick the right APK from the notes. While it is empty every "Android" button shows a visible "coming soon" state instead of a dead link.
- [ ] Make `og:image` and `twitter:image` in `index.html` absolute, `https://<domain>/assets/og-image.jpg`. Crawlers do not resolve relative image URLs.
- [ ] Optionally add `<link rel="canonical" href="https://<domain>/">`.
- [x] Real screenshots and clips are in `assets/media/` (below) and `assets/og-image.jpg` is final artwork, masked from the captain's captures. Swap in higher-fidelity takes the same way: same filenames, no code change.
- [ ] Optionally set `js/config.js`'s `demoReelUrl` to an external embed (e.g. a YouTube upload) once one exists, to serve that instead of the packaged `clip-demo-reel.mp4`.
- [ ] If analytics or another embed host is added later, extend the Content-Security-Policy in `_headers` to allow it.

## Layout

```
landing/
├── index.html              all sections, meta and Open Graph tags
├── 404.html
├── _headers                Cloudflare Pages headers + CSP
├── css/
│   ├── tokens.css          design tokens, mirrors frontend/lib/core/theme/tokens.dart
│   ├── site.css            page layout and components
│   └── phone.css           the phone preview (measurements in app "dp")
├── js/
│   ├── config.js           the one file to edit at release time (Android URL)
│   ├── main.js             wiring: CTA states, scroll reveals, prompts, mic, demo story, media loader
│   ├── phone.js            the phone: screens, overlays, state, event emitter
│   ├── flows.js            scripted flows + the keyword intent matcher
│   ├── orb.js              canvas port of the co-rider orb
│   ├── voices.js           the 11 voices' data: label, accent group, silhouette/colour/feature, preview asset
│   ├── voice_characters.js SVG renderer for the voice characters (ported from the app's Rive generator)
│   ├── voice_picker.js     the "Choose Kora's voice" picker: selection, audio, live region
│   └── js-flag.js          adds .js to <html> before first paint
├── assets/
│   ├── fonts/              Plus Jakarta Sans (variable, latin) + its OFL licence
│   ├── brand/              favicon and app icons, copied from the repo's brand assets
│   ├── icons.svg           Tabler icon sprite (MIT), the same set the app uses
│   ├── kora-mark.svg       copy of docs/brand/kora-mark.svg
│   ├── og-image.jpg        social image (1200 x 630), a real masked app frame composed in
│   ├── media/              screenshots and clips (manifest.json)
│   └── audio/voices/       voice preview clips, copied from frontend/assets/audio/voice_previews/
├── tools/og-image.html     source of og-image.jpg
└── docs/screenshots/       verification screenshots for the PR
```

## Media

`assets/media/manifest.json` maps each id to its filename, dimensions and alt text; edit it only to rename a file, change its alt text, or add a new item (a new item also needs a `<figure data-media="<id>">` in `index.html`). A slot with no entry (or a `fetch`/decode failure) keeps its loading skeleton rather than showing a dead placeholder — there is no `clip-call-customer` entry because no source exists for it; add the figure and manifest entry together when one does.

Files are lazy-loaded, and phone clips are muted, loop, and start and pause with visibility; the demo reel is native controls, unmuted and never autoplays (it has narration) — see `js/main.js`'s `initMedia`. Under `prefers-reduced-motion` phone clips also show controls instead of autoplaying.

| File in `assets/media/` | Kind | Dimensions | Notes |
|---|---|---|---|
| `clip-demo-reel.mp4` (+ `.jpg` poster) | Video | 1280 × 720 | The full explainer, narrated, ~7.3 MB |
| `clip-next-delivery.mp4` (+ `.webm`, `.jpg`) | Video | 864 × 1844 | Driver asks for the next stop, route draws |
| `clip-order-offer.mp4` (+ `.webm`, `.jpg`) | Video | 864 × 1844 | A new order is offered; the driver accepts it (not auto-accept) |
| `clip-wake-followup.mp4` (+ `.webm`, `.jpg`) | Video | 864 × 1920 | A follow-up question answered without repeating the wake word |
| `clip-shift-summary.mp4` (+ `.webm`, `.jpg`) | Video | 864 × 1844 | The shift summary screen |
| `screen-voice.jpg` | Image | 864 × 1844 | Voice screen: chrome orb, next stop, target, lime listening button |
| `screen-map.jpg` | Image | 864 × 1844 | Map with route and trip card |
| `screen-order-offer.jpg` | Image | 720 × 1524 | The offer card itself: countdown, distance, time window, Accept/Decline |
| `screen-summary.jpg` | Image | 864 × 1844 | Today's activity, target, queue |
| `screen-settings.jpg` | Image | 720 × 1379 | Auto-accept rules and the wake word controls (sensitivity, wake on greetings) |
| `assets/og-image.jpg` | Image | 1200 × 630 | Social card, regenerated from `tools/og-image.html` with a real screen composed in |

All of the above are the captain's real phone captures and screenshots, privacy-masked — the four phone clips (`clip-next-delivery`, `clip-order-offer`, `clip-wake-followup`, `clip-shift-summary`) and the three video-frame stills (`screen-voice`, `screen-map`, `screen-summary`) reuse the explainer video project's frame-accurate masks (see its `BUILD-NOTES.md`, "Masking applied", for the exact windows). `screen-order-offer` and `screen-settings` come from two later phone screenshots instead, masked separately (address, distance line, next-stop name and address, and the status bar redacted with a frosted box, same treatment). No address, name, or status bar survives; nothing region-specific is on screen, keeping the page international. Swap in new captures the same way: same filenames under `assets/media/`, no code change, and mask any real name/address/street label before shipping them.

## Design system

`css/tokens.css` is the only place colours, radii, spacing, motion and type sizes live, and every custom property names the constant in `frontend/lib/core/theme/tokens.dart` it copies. Change `tokens.dart` first, then mirror it. Brand rules from `docs/brand/README.md` carry over:

- Dark-first: `--kora-canvas` with slow violet glows, as `GradientOrbBackground`.
- Violet is the accent. **Lime is the mic-hot state only**: it appears once, on the phone's push-to-talk button while it is recording. Nothing else on the page, and nothing in the orb, uses it.
- The hero headline follows the onboarding splash: light editorial type with a holographic pill (`KoraMood.holographic`). The Android card uses the same film with dark ink.
- The Kora mark is `docs/brand/kora-mark.svg`, unmodified. The favicon is the app icon treatment (mark `#F4F1FF` on `#8B5CF6`).
- The mascot is always the **co-rider**, never "co-pilot" or "assistant".

The orb (`js/orb.js`) is a canvas port of the app's drawn orb (`frontend/lib/mascot/mascot_display.dart`): the same eight moods, palettes, breathing and morph timing, plus the drifting motes from `docs/voiceops-corider-orb-rive-spec-v2.md`. The app's `assets/rive/corider.riv` exists but is not used: the Rive web runtime would add a WebAssembly download for a decoration, and the drawn orb is what the app itself falls back to.

### Icons

`assets/icons.svg` is a sprite of [Tabler Icons](https://tabler.io/icons) (MIT), the set the app uses through `tabler_icons_plus`. To add one, paste its `<symbol id="i-<name>" viewBox="0 0 24 24">` into the sprite (outline icons; use `<name>-f` for a filled one) and reference it with `<svg class="i"><use href="assets/icons.svg#i-<name>"/></svg>`.

## The phone preview

`js/phone.js` rebuilds the app's screens in HTML and CSS at the app's own measurements, then scales the device to fit. Each block copies the Flutter widget it stands in for (listed at the top of the file): Voice, Map (route card, stops, position dot), Summary (activity, daily target, order queue), Settings (auto-accept), the task-progress card with reasoning, the order offer card with countdown, the call card, the co-rider bubble on other tabs, and the four-state push-to-talk button. Task-step labels and reasoning strings are the relay's own (`voiceops-backend/app/api/websocket/events.py`, `reasoning.py`). Sample data lives at the top of `phone.js`.

It also emits the same event names the real WebSocket sends (`agent_state`, `task_step`, `screen_navigate`, `map_route`, `call_started`, `order_offer`, `queue_updated`, …; see `docs/contracts/interface.md`), which the "Ride a shift" section shows as a live log.

Input to the phone:

- Six prompt chips (the four headline prompts first). Each plays its corresponding preview flow.
- The push-to-talk button plays the next headline prompt; tapping it while Kora is speaking interrupts her.
- Optional real speech: where the browser has the Web Speech API a "Say it" mic button appears beside the prompt chips. `js/flows.js` scores the spoken text against keyword rules and plays the nearest flow, or answers with a hint listing what the preview can do. Speech recognition is never required and never starts by itself; if it is blocked or unsupported the chips work the same. Browser speech recognition may send audio to the browser vendor's servers, which the page says next to the button. The simulation itself makes no requests.

To add a flow: write an `async` function in `flows.js` using the phone helpers (`step`, `setMood`, `setTab`, `showRoute`, `speak`, …), add a keyword rule to `RULES`, and, if it should be a chip, an entry in `PROMPTS`.

## Voices

The "Choose Kora's voice" section (`#voices`) mirrors the app's post-sign-up voice step
(`frontend/lib/features/voice_onboarding/`, character art per
`docs/kora-voice-characters-rive-spec.md`): the eleven voices grouped by accent, each drawn as
its own character, the selected one ringed, and a single preview bar below it
("*Name* - Tap to hear a short preview") instead of a play button per card.

- `js/voices.js` is the data: label, accent group, and the exact silhouette/colour/feature
  parameters copied from `frontend/tool/rive/build_voice_characters.js`'s `CAST` table (the
  generator for `assets/rive/voice_characters.riv`), so the web picker draws the same eleven
  characters rather than a different mascot set. The list is the intersection of the app's
  `CoRiderVoice` enum, the backend's `VOICES` allowlist
  (`voiceops-backend/app/agents/agent_config.py`) and the bundled preview clips - all three
  agree on the same 11 today; if they ever diverge, narrow this list to the intersection and
  say so in the PR.
- `js/voice_characters.js` renders a character as an SVG string: the same superellipse body
  formula and Catmull-Rom smoothing as the generator, ported to plain JS/SVG. Selection and
  speaking are CSS classes (`.is-selected`, `.is-speaking`) driving the same ring/lift/talk
  states the spec describes for the `.riv` version; `prefers-reduced-motion` turns them off.
- `js/voice_picker.js` mounts the grid and the preview bar, plays `assets/audio/voices/<id>.mp3`
  on tap (never on selection or on load - `Audio.preload = "none"`, no file fetched until a
  driver asks), stops the previous clip before starting another, and disables a voice's button
  if its clip fails to load. An `aria-live` region announces "Playing *Name*."
- Selecting a voice calls `Phone.setVoice(label)` on both phones (`js/phone.js`): it updates the
  "CO-RIDER VOICE" row on the Settings screen and the label shown while the orb's mood is
  `speaking` (`"<Name> speaking..."` instead of the generic "Speaking..."). The phone never
  picks its own voice.
- The preview clips themselves are `frontend/assets/audio/voice_previews/*.mp3`, copied
  verbatim (already 96 kbps mono, 3-6s, ~55-72 KB each - no re-encode needed); see that
  folder's README for how they were generated and what they say.

## Accessibility and performance

- Keyboard: skip link, visible focus rings, every control is a real button or link; the phone's tabs, push-to-talk button and offer buttons are focusable, and inactive phone screens are `inert`. Kora's replies are also announced through a polite live region. The voice picker is the same pattern: real buttons, `aria-pressed` on the selected character and the preview button, and a live region announcing "Playing *Name*."
- `prefers-reduced-motion`: scroll reveals, drifting glows, orb motion, route drawing, typing and the voice characters' breathing/blinking/talking are removed or shortened; flows still play.
- Contrast: text uses the app's tokens; page CTAs are white paper with dark ink; Lighthouse's contrast audit passes.
- Weight: no framework and no build. About 24 KB of script and 40 KB of HTML, CSS and script together (gzipped), plus one 27 KB font. Media is lazy-loaded; the demo phone builds only when it nears the viewport; orbs animate only while visible. Voice preview audio (~700 KB across all 11 clips) is never fetched until a driver taps a voice's preview button - nothing is preloaded.
- A local Lighthouse run (mobile) scored 100 for Accessibility, Best Practices and SEO.

## Not in scope here

Deployment, DNS and Cloudflare resources (the captain connects them), and the repository README rewrite.
