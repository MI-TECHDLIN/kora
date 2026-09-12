# Frontend agent memory

Flutter app. Authority: repo-root `CLAUDE.md` and `.firstmate/rules/frontend.md`; this file only adds sharp edges they don't cover.

- **Tokens:** every colour/spacing/radius/size/duration/text style lives in `lib/core/theme/tokens.dart`. Reference a token, never a literal.
- **Lime is mic-hot only.** `VoiceOpsColors.live` (#C8F250) means "the mic is recording" — a driver-safety signal. Only the push-to-talk `recording` state uses it; never as an accent, never in the orb or the ColorScheme (tests enforce this).
- **Restrained glass:** blur is capped at `VoiceOpsGlass.blur`. Use `GlassCard(frosted: false)` for repeated items (chip grids, list rows); keep backdrop blur for a few large surfaces (nav bar, input bar).
- **Routing:** all routes in `lib/app/router.dart` (go_router). Read the active tab from `activeTabProvider`; navigate via go_router / `navigationProvider`, never by setting state. Global overlays sit above the router in `RootStack`, not as routes.
- **Auth gate:** every route sits behind a Supabase session (the router redirect sends a null/expired one to `/welcome`). Credentials come from `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` (`lib/core/config/supabase_config.dart`; anon key only, never service-role). Tests that pump `VoiceOpsApp` must override `authRepositoryProvider` — see `test/fake_auth.dart`.
- **go_router is pinned to ^17.5** — 18.x needs Flutter ≥3.44 and the captain's local SDK is older. Don't bump without checking his `flutter --version`.
- **`pubspec.lock` tracks the captain's SDK.** A plain `flutter analyze`/`test` in the Codespace runs `pub get` and re-resolves the lock; run `git checkout pubspec.lock` before committing (or pass `--no-pub` once `.dart_tool/` exists).
- **Co-rider orb:** `lib/mascot/mascot_display.dart` plays `assets/rive/corider.riv` (rive 0.14 / rive_native) and falls back to the Flutter placeholder orb when the file is missing or can't load — `flutter test` has no native runtime, so tests always see the placeholder. Moods fire as `CoRider` **view-model triggers** (`AgentState.riveKey`), not legacy SM inputs. `corider.riv` was generated directly in the open .riv format (editor export needs a paid Rive plan), to match `docs/voiceops-corider-orb-rive-spec-v2.md`; keep its artboard (`Holographic`/`Chrome`), state machine (`CoRider`) and trigger names if it's replaced by an editor export.
- **Font weights:** google_fonts registers one family per weight, so `style.copyWith(fontWeight: …)` silently keeps the old weight. Use `VoiceOpsText.weight(style, w)`.
- **Tests:** the orb and background animate forever — step time with `pump(duration)`, never `pumpAndSettle`. Use `test/test_fonts.dart` to stop google_fonts fetching, and size the view like a phone (see `test/widget_test.dart`). Its square test glyphs run far wider than real type, so for a visual check render a throwaway golden with the real TTFs (`fonts.gstatic.com/s/a/<hash>.ttf`, hashes in google_fonts' generated parts) loaded through `FontLoader` as `PlusJakartaSans_<weight>`; don't commit it.
- `const` widgets can't assert on `Color` equality in constructors (not a constant expression) — put such asserts in `build()`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
