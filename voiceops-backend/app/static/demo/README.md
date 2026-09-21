# Kora customer-call demo page

A self-contained, no-build web page that lets a delivery customer (or a judge) answer a call from
Kora in their phone's browser: two-way real-time voice, live captions, a summary at the end. No
phone carrier, card or third-party service. Plain HTML, CSS and ES modules; no framework, no CDN,
no network requests except the page's own WebSocket.

The backend serves this folder at `/demo` (see `docs/backend-handoff/customer-call-demo.md`).
The wire protocol is the "Wire protocol: customer page <-> backend" section of the demo spec:
`GET /ws/demo/customer` for the page and `GET /ws/demo/stage` for the read-only projector feed.

## Files

| Path | What |
|---|---|
| `customer.html` `customer.css` `customer.js` | The customer page: pairing, waiting, incoming call, in call, summary, error states |
| `stage.html` `stage.css` `stage.js` | Optional projector view: QR code, big live captions, call state and timer |
| `js/protocol.js` | Server-event parsing and the page state machine (pure) |
| `js/pcm.js` | PCM16 conversion, streaming resampler with anti-alias filter, 50 ms capture framing (pure) |
| `js/scheduler.js` | Gapless playback clock and barge-in source tracking (pure) |
| `js/captions.js`, `js/stage-state.js`, `js/qr.js` | Caption model, stage state, QR encoder (pure) |
| `js/audio.js`, `js/capture-worklet.js`, `js/orb.js`, `js/connection.js` | Browser-only: Web Audio, mic capture (AudioWorklet, ScriptProcessor fallback), the orb, the socket |
| `dev/mock_server.mjs` | Mock backend (static files + the protocol + a scripted conversation with synthesized audio) |
| `dev/*.test.mjs` | Unit and protocol tests |

## Run it locally (no key, no backend)

Needs Node 20+ (developed on Node 24). No `npm install`.

```bash
cd voiceops-backend/app/static/demo
node dev/mock_server.mjs                 # http://localhost:8787, demo code DEMO
                                         # options: --port 8787 --code DEMO --speed 1
```

1. Open `http://localhost:8787/` in a browser (localhost may use the microphone without HTTPS).
   The code is pre-filled from the link the server prints, or type `DEMO`.
2. Ring it: open `http://localhost:8787/dev/` (mock "driver" panel), or `curl localhost:8787/dev/ring`,
   or press Enter in the terminal running the mock.
3. Tap Answer. You hear a synthesized voice, see captions, and can talk over it to trigger barge-in.
   The call ends by itself with a summary card.

Ring variants on the panel: no summary, mid-call failure, server busy, driver hangs up.
The projector view is at `http://localhost:8787/stage.html?code=DEMO`.

Tests:

```bash
node --test "dev/*.test.mjs"    # or: npm test
```

## On a real phone

The microphone needs HTTPS (or localhost). Use the deployed backend (`https://<host>/demo/customer.html`),
or tunnel the mock/backend over HTTPS. For the stage QR to work from a phone, set "Customer page
address" under Setup on the stage page to the public HTTPS address (for example
`https://<host>/demo`); it is remembered in that browser.

## Manual device checklist

Things the automated tests cannot see. Run on one Android (Chrome) and one iPhone (Safari), against
the mock first, then the real backend.

- [ ] Page loads, Plus Jakarta Sans falls back cleanly, no horizontal scroll at 360, 390 and 430 px wide.
- [ ] The orb is smooth (no dropped frames) on the pairing, waiting, ringing and in-call screens, and glides between layouts.
- [ ] Orb is static-ish with "Reduce motion" enabled in the OS; screens change without sliding.
- [ ] Code prefilled from `?code=`; wrong code shows the inline error and shakes the field; the code disappears from the address bar.
- [ ] Waiting screen shows the connected pill; turning Wi-Fi off shows "Reconnecting…" and it recovers when back on.
- [ ] iPhone: after tapping "Wait for the call" the ringtone plays when the ring arrives; if not, the "Tap to enable ringtone" chip appears and works.
- [ ] Ring: full-screen incoming call, ringtone audible, phone vibrates (Android; iOS does not support vibration).
- [ ] Answer: mic prompt appears once, ringtone stops immediately, state goes Connecting then Listening.
- [ ] Denying the mic shows the "Microphone is blocked" steps and hangs up on the server side.
- [ ] Kora's voice is clear, has no gaps or clicks, and the orb pulses with her voice.
- [ ] Speaking over Kora cuts her off within about a quarter of a second (barge-in) and the cut caption ends with a dash.
- [ ] Kora does not hear herself (echo): test on speaker and on earpiece.
- [ ] Captions: Kora left and violet, customer right and grey; interim text is dimmer; the list stays scrolled to the newest line.
- [ ] Mute: Kora hears nothing while muted (mic meter flat); unmute recovers.
- [ ] Screen does not sleep during a 2+ minute call (Wake Lock).
- [ ] Locking the phone or switching tabs mid-call ends it cleanly; returning shows the summary, not a frozen screen.
- [ ] Hang up: mic indicator on the phone turns off; the summary card appears with the points.
- [ ] Driver-side hang up and timeout end the call with the right wording.
- [ ] "Call again" returns to waiting and the next ring works without reloading.
- [ ] Stage page: QR scans from 2 m on a projector or monitor and opens the customer page with the code; captions are readable from the back of the room.
- [ ] No lime green anywhere.

## What has and has not been verified

Verified by automated tests (`node --test`): PCM16 conversion, resampling (48 k, 44.1 k, 16 k to 24 k,
block-size independence, anti-aliasing), 50 ms framing, odd-byte network chunks, playback scheduling
maths, barge-in bookkeeping, every protocol event and state transition, the caption model, the stage
state, the QR encoder against a reference implementation, and the whole wire protocol end to end
against the mock server over a real WebSocket (hello, wrong code, ring, answer, audio, captions,
barge-in, hang ups, error scenarios, stage feed).

Not verifiable without a device (use the checklist): how anything looks, animation smoothness,
AudioWorklet/ScriptProcessor capture, actual microphone and speaker behavior, echo cancellation,
ringtone and vibration, wake lock, autoplay policies on iOS Safari, and scanning the QR code.
Nothing here has been run against the real AssemblyAI-backed backend.
