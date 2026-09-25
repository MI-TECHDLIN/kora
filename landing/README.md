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

- [ ] Set the Android link in `js/config.js` (`androidUrl`). While it is empty every "Android" button shows a visible "coming soon" state instead of a dead link.
- [ ] Make `og:image` and `twitter:image` in `index.html` absolute, `https://<domain>/assets/og-image.jpg`. Crawlers do not resolve relative image URLs.
- [ ] Optionally add `<link rel="canonical" href="https://<domain>/">`.
- [ ] Drop the real screenshots and clips into `assets/media/` (below), and replace `assets/og-image.jpg` with final artwork.
- [ ] If analytics or an embed is added later, extend the Content-Security-Policy in `_headers` to allow it.

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
│   └── js-flag.js          adds .js to <html> before first paint
├── assets/
│   ├── fonts/              Plus Jakarta Sans (variable, latin) + its OFL licence
│   ├── brand/              favicon and app icons, copied from the repo's brand assets
│   ├── icons.svg           Tabler icon sprite (MIT), the same set the app uses
│   ├── kora-mark.svg       copy of docs/brand/kora-mark.svg
│   ├── og-image.jpg        placeholder social image (1200 x 630)
│   └── media/              screenshots and clips drop in here (manifest.json)
├── tools/og-image.html     source of the placeholder social image
└── docs/screenshots/       verification screenshots for the PR
```

## Placeholders to replace

Everything below is a clearly marked placeholder on the page (dashed frame, "Placeholder" badge, the expected filename and size). Add the file under `assets/media/` with exactly this name and it replaces the placeholder on the next load: no code change. `assets/media/manifest.json` maps each id to its filename, dimensions and alt text; edit it only to rename a file, change its alt text, or add a new item (a new item also needs a `<figure data-media="<id>">` in `index.html`).

Files are lazy-loaded, and clips start and pause with visibility. Under `prefers-reduced-motion` clips do not autoplay and show controls.

| File in `assets/media/` | Kind | Dimensions | Notes |
|---|---|---|---|
| `clip-demo-reel.mp4` (+ `.webm`, `.jpg` poster) | Video | 1920 × 1080 | Full shift, 60 to 90 s. Muted loop, H.264, keep under about 10 MB |
| `clip-next-delivery.mp4` (+ `.webm`, `.jpg`) | Video | 1080 × 2400 | Ask for the next stop, route draws. 15 s or less, about 4 MB |
| `clip-auto-accept.mp4` (+ `.webm`, `.jpg`) | Video | 1080 × 2400 | Auto-accept on, an order taken out loud |
| `clip-call-customer.mp4` (+ `.webm`, `.jpg`) | Video | 1080 × 2400 | Call and text the customer |
| `screen-voice.png` | Image | 1080 × 2400 | Voice screen: orb, next stop, target, conversation |
| `screen-map.png` | Image | 1080 × 2400 | Map with route and trip card |
| `screen-order-offer.png` | Image | 1080 × 2400 | Order offer card |
| `screen-summary.png` | Image | 1080 × 2400 | Today's activity, target, queue |
| `screen-settings.png` | Image | 1080 × 2400 | Auto-accept rules on |

Posters are optional (`.jpg`, 540 × 1200 for phone clips). PNG, WebP or JPG all work for screenshots as long as the filename in the manifest matches. Outside `assets/media/`:

| File | Dimensions | Notes |
|---|---|---|
| `assets/og-image.jpg` | 1200 × 630 | Placeholder social card, regenerate from `tools/og-image.html` or replace |

Use real app captures on a real device with neutral sample data (generic names, no local currency or place names) so the page stays international.

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

- Six prompt chips (the four headline prompts first) and a free-text box. `js/flows.js` scores the text against keyword rules and plays the nearest flow, or answers with a hint listing what the preview can do.
- The push-to-talk button plays the next headline prompt; tapping it while Kora is speaking interrupts her.
- Optional real speech: where the browser has the Web Speech API a mic button appears beside the text box. It is never required and never starts by itself; if it is blocked or unsupported the chips work the same. Browser speech recognition may send audio to the browser vendor's servers, which the page says next to the button. The simulation itself makes no requests.

To add a flow: write an `async` function in `flows.js` using the phone helpers (`step`, `setMood`, `setTab`, `showRoute`, `speak`, …), add a keyword rule to `RULES`, and, if it should be a chip, an entry in `PROMPTS`.

## Accessibility and performance

- Keyboard: skip link, visible focus rings, every control is a real button or link; the phone's tabs, push-to-talk button and offer buttons are focusable, and inactive phone screens are `inert`. Kora's replies are also announced through a polite live region.
- `prefers-reduced-motion`: scroll reveals, drifting glows, orb motion, route drawing and typing are removed or shortened; flows still play.
- Contrast: text uses the app's tokens; page CTAs are white paper with dark ink; Lighthouse's contrast audit passes.
- Weight: no framework and no build. About 24 KB of script and 40 KB of HTML, CSS and script together (gzipped), plus one 27 KB font. Media is lazy-loaded; the demo phone builds only when it nears the viewport; orbs animate only while visible.
- A local Lighthouse run (mobile) scored 100 for Accessibility, Best Practices and SEO.

## Not in scope here

Deployment, DNS and Cloudflare resources (the captain connects them), real screenshots and clips, and the repository README rewrite.
