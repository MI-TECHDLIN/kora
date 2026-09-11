# Frontend agent memory

Flutter app. Authority: repo-root `CLAUDE.md` and `.firstmate/rules/frontend.md`; this file only adds sharp edges they don't cover.

- **Tokens:** every colour/spacing/radius/size/duration/text style lives in `lib/core/theme/tokens.dart`. Reference a token, never a literal.
- **Lime is mic-hot only.** `VoiceOpsColors.live` (#C8F250) means "the mic is recording" — a driver-safety signal. Only the push-to-talk `recording` state uses it; never as an accent, never in the orb or the ColorScheme (tests enforce this).
- **Restrained glass:** blur is capped at `VoiceOpsGlass.blur`. Use `GlassCard(frosted: false)` for repeated items (chip grids, list rows); keep backdrop blur for a few large surfaces (nav bar, input bar).
- **Routing:** all routes in `lib/app/router.dart` (go_router). Read the active tab from `activeTabProvider`; navigate via go_router / `navigationProvider`, never by setting state. Global overlays sit above the router in `RootStack`, not as routes.
- **go_router is pinned to ^17.5** — 18.x needs Flutter ≥3.44 and the captain's local SDK is older. Don't bump without checking his `flutter --version`.
- **`pubspec.lock` tracks the captain's SDK.** A plain `flutter analyze`/`test` in the Codespace runs `pub get` and re-resolves the lock; run `git checkout pubspec.lock` before committing (or pass `--no-pub` once `.dart_tool/` exists).
- **Co-rider orb:** `lib/mascot/mascot_display.dart` is the only file that changes when the Rive asset lands (see its `TODO(rive)`); add `assets/rive/` to pubspec in that same change.
- **Tests:** the orb and background animate forever — step time with `pump(duration)`, never `pumpAndSettle`. Use `test/test_fonts.dart` to stop google_fonts fetching, and size the view like a phone (see `test/widget_test.dart`).
- `const` widgets can't assert on `Color` equality in constructors (not a constant expression) — put such asserts in `build()`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
