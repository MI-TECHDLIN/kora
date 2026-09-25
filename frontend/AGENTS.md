# Frontend agent memory

Flutter app. Authority: repo-root `CLAUDE.md` and `.firstmate/rules/frontend.md`; this file only adds sharp edges they don't cover.

- **Tokens:** every colour/spacing/radius/size/duration/text style lives in `lib/core/theme/tokens.dart`. Reference a token, never a literal.
- **Lime is mic-hot only.** `KoraColors.live` (#C8F250) means "the mic is recording" — a driver-safety signal. Only the push-to-talk `recording` state uses it; never as an accent, never in the orb or the ColorScheme (tests enforce this).
- **Restrained glass:** blur is capped at `KoraGlass.blur`. Use `GlassCard(frosted: false)` for repeated items (chip grids, list rows); keep backdrop blur for a few large surfaces (nav bar, input bar).
- **Routing:** all routes in `lib/app/router.dart` (go_router). Read the active tab from `activeTabProvider`; navigate via go_router / `navigationProvider`, never by setting state. Global overlays sit above the router in `RootStack`, not as routes.
- **Auth gate:** every route sits behind a Supabase session (the router redirect sends a null/expired one to `/welcome`). Credentials come from `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` (`lib/core/config/supabase_config.dart`; anon key only, never service-role). Tests that pump `KoraApp` must override both `authRepositoryProvider` (`test/fake_auth.dart`) and `koraApiProvider` (`FakeKoraApi` in `test/fake_voice.dart`) — `DriverProfileNotice` sits above every route and calls `KoraApi.ensureDriverProfile()` on sign-in and on session restore, so a real `koraApiProvider` would reach for the network in any test that pumps the full app.
- **Driver-row creation is backend-owned:** `POST /v1/driver/ensure-profile` (idempotent; called by `DriverProfileSync` in `lib/providers/auth_provider.dart`) creates the signed-in driver's `drivers` row — not the client Supabase insert this replaced. `drivers.phone` is nullable (Google sign-in never provides one). A confirmed-failed attempt shows as a persistent, retryable banner (`DriverProfileNotice`), not a one-shot SnackBar.
- **Backend:** REST and the voice socket need `--dart-define=VOICEOPS_API_URL=…` (`lib/core/config/backend_config.dart`). `voiceSessionProvider` is the only WebSocket owner. Tests that tap push-to-talk, open the Map tab, or show onboarding add `offlineOverrides()` from `test/fake_voice.dart`, which fakes the socket, mic, speaker, REST, GPS, map tiles and saved onboarding flag (a real `AudioRecorder()` hits a platform channel in its constructor, and onboarding checks the mic).
- **OS permissions** are asked only from onboarding's Power screen (`OnboardingFlow`: mic via `VoiceRecorder`, location via `LocationSource.requestPermission`). `LocationSource.watch()` never prompts; after onboarding only a driver tap asks again (the map's "Allow" chip, the mic button). Onboarding completion is read in `main.dart` before the first frame (`onboardingCompletedAtLaunchProvider`) so the router never flashes it.
- **Map stack: MapLibre Native (`maplibre_gl`), not flutter_map.** Migrated
  2026-09 (`frontend/lib/features/map/`); `flutter_map`/`vector_map_tiles`
  are gone. Keep `maplibre_gl` pinned exactly to 0.22.0: 0.23+ requires JDK
  21 while the project and Android Studio toolchain use JDK 17. Use
  `maplibre_gl`, not the newer `maplibre` package, because the
  latter needs Flutter ≥3.44/Dart ^3.12.0, above the captain's pinned SDK
  (see the go_router note below) — recheck that constraint before ever
  switching packages. MapLibre renders the camera and base tiles on the
  platform side, outside the widget tree, so `map_screen.dart` carries its
  own padding-aware camera math (`data/mercator.dart`, pure Web Mercator, no
  MapLibre dependency) and draws `StopPin`/`PositionMarker` as ordinary
  `Positioned` overlay widgets projected onto the native camera every
  `onCameraMove` tick, instead of platform-rendered symbols — chosen over
  pre-rendered `addImage` icons specifically to keep their live
  AnimatedContainer/Transform.rotate behavior unchanged. `MapScreen`
  programs against `KoraMapController` (`data/kora_map_controller.dart`),
  not `MapLibreMapController` directly: a real `MapLibreMap` widget throws
  in plain `flutter_test` (no engine behind its platform channel on the
  host/VM test target), so every test drives the screen through
  `FakeKoraMapController`/`fakeKoraMapViewBuilder` (`test/fake_map_controller.dart`)
  instead. That also means the style-load skeleton/timeout/retry UI in
  `openfreemap_layer.dart` has no widget-test coverage — it needs a real
  device or simulator to verify.
- **go_router is pinned to ^17.5** — 18.x needs Flutter ≥3.44 and the captain's local SDK is older. Don't bump without checking his `flutter --version`.
- **`pubspec.lock` tracks the captain's SDK (Dart 3.11).** A plain `flutter analyze`/`test` in the Codespace runs `pub get` and re-resolves the lock; run `git checkout pubspec.lock` before committing (or pass `--no-pub` once `.dart_tool/` exists). When adding a dependency, restore the SDK-pinned entries (`matcher`, `meta`, `test_api`, `vector_math`) from the previous lock, and keep `sdks: dart` at its old floor by pinning any transitive package that raised it (e.g. `synchronized` 3.4.0).
- **fakeAsync:** don't `await` a `StreamSubscription.cancel()` or a cancelled `StreamController.close()` in code tested on fake time. Those futures complete in the root zone, so the awaiting code stalls until the test ends.
- **Co-rider orb:** `lib/mascot/mascot_display.dart` plays `assets/rive/corider.riv` (rive 0.14 / rive_native) and falls back to the Flutter placeholder orb when the file is missing or can't load — `flutter test` has no native runtime, so tests always see the placeholder. Moods fire as `CoRider` **view-model triggers** (`AgentState.riveKey`), not legacy SM inputs. `corider.riv` was generated directly in the open .riv format (editor export needs a paid Rive plan), to match `docs/voiceops-corider-orb-rive-spec-v2.md`; keep its artboard (`Holographic`/`Chrome`), state machine (`CoRider`) and trigger names if it's replaced by an editor export. Its generator isn't in the repo, and it has no `speaking` trigger yet: a mood whose trigger is missing silently does nothing on device, so a new `AgentState` also needs the `.riv` rebuilt.
- **Voice characters:** `assets/rive/voice_characters.riv` is generated by `node tool/rive/build_voice_characters.js` (run from `frontend/`), not authored in the Rive editor. Edit the `CAST` table there and rebuild; `tool/rive/dump.js` inspects a `.riv`, `tool/rive/defs.js` regenerates the runtime schema. Contract (artboard = voice enum name, state machine `Voice`, Bool inputs `selected`/`speaking`) is in `docs/kora-voice-characters-rive-spec.md`. To render it in a throwaway `flutter test`, use `Factory.flutter` and put a release `rive_native.dll` at `build/rive_native/windows/bin/lib/debug/`; delete that folder before running the real suite, because with the DLL present any test reaching `Factory.rive` kills the tester ("did not complete").
- **Orb mood has two sources.** The backend's `agent_state` events set the base mood; `speaking` is inferred client-side from reply audio actually playing (`VoiceSession._setPtt` → `AgentStateNotifier.setSpeaking`) and overlays the base until playback ends. The contract has no `speaking` state yet — proposal in `docs/backend-handoff/agent-state-speaking.md`.
- **Font weights:** google_fonts registers one family per weight, so `style.copyWith(fontWeight: …)` silently keeps the old weight. Use `KoraText.weight(style, w)`.
- **Tests:** the orb and background animate forever — step time with `pump(duration)`, never `pumpAndSettle`. Use `test/test_fonts.dart` to stop google_fonts fetching, and size the view like a phone (see `test/widget_test.dart`). Its square test glyphs run far wider than real type, so for a visual check render a throwaway golden with the real TTFs (`fonts.gstatic.com/s/a/<hash>.ttf`, hashes in google_fonts' generated parts) loaded through `FontLoader` as `PlusJakartaSans_<weight>`; don't commit it.
- `const` widgets can't assert on `Color` equality in constructors (not a constant expression) — put such asserts in `build()`.
- **Order queue + daily target:** `orderQueueProvider` (`lib/providers/order_queue_provider.dart`) is the one source for Home's Next Orders card / target indicator and Summary's overview, target card and queue checklist; never keep a second copy. It is seeded by `GET /v1/shift/{id}/queue`, replaced by `queue_updated` socket events (`VoiceSession._dispatch`), and reset from `ShiftNotifier` (new shift, sign-out). "Active" is a presentation state (lowest-sequence pending), never a stored status. The target is the `daily_delivery_target` driver preference (touch and voice write the same row). Home's two cards default ON and hide themselves when there is no queue or target.
- **Post-sign-up voice step vs. pre-sign-up onboarding:** `features/voice_onboarding/` (gated by `voiceOnboardingProvider` in `providers/voice_onboarding_provider.dart`) is a distinct, one-time screen shown right after a successful sign-up, never the pre-sign-up `onboardingProvider` flow. It only turns on when `SignUpScreen` calls `showIfNeverShown()` after `SignUpResult.signedIn` — never merely because a session exists — so a plain sign-in never shows it. Settings keeps its own smaller, separate picker (`features/settings/widgets/co_rider_voice_picker.dart`); the two are deliberately never shared. Both preview a voice by reusing `voiceSessionProvider`/`pushToTalkProvider` (the same mechanism the main push-to-talk button uses), never a separate audio pipeline. Per-voice character art comes from `assets/rive/voice_characters.riv` via `widgets/voice_character_rive.dart`, falling back to a placeholder (tinted circle + initial) when the file or runtime is unavailable (always, in `flutter test`); don't touch the single-orb `MascotDisplay` for this.
- **Wake word:** every tunable (capture, input gain, Normal/High profiles) is in `lib/core/wake/wake_tuning.dart`; the wake stream's gain (`WakeInputGain`) never touches the AssemblyAI stream. "Cora" tokenises identically to "Kora" in the bundled lexicon, so the engine sends one keyword line per token sequence. Measure changes with `tool/wake_far_field_eval.py` (synthetic only; phones still need testing).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
