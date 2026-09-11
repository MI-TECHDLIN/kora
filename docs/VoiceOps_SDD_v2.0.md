# VoiceOps — Software Design Document v2.0
**Hackathon:** AssemblyAI Voice Agent Hackathon | Sept 1–30, 2026
**Last updated:** September 2026

> **Superseded by PRD v4.0 / CLAUDE.md. Historical reference only.** Where this document
> disagrees with `docs/product/VoiceOps_PRD_v4.0.md`, `CLAUDE.md`, or `.firstmate/rules/`, those
> win. Interfaces live in `docs/contracts/interface.md`, which supersedes §7. On 2026-09-11,
> §2 (navigation), §3 and §6 (agent states), §4.1 (terminology), §4.4 (action chips), §6.1 (orb
> placeholder), §8 (design tokens), §9 (folders, fonts), and §10 (branching) were brought in line
> with current decisions. Everything else is unrevised v2.0.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App (Root)                 │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │              Root Stack                      │   │
│  │                                              │   │
│  │  ┌─────────────────────────────────────┐    │   │
│  │  │  OnboardingFlow (first launch only) │    │   │
│  │  └─────────────────────────────────────┘    │   │
│  │                                              │   │
│  │  ┌─────────────────────────────────────┐    │   │
│  │  │  MainShell (go_router — 4 tabs)     │    │   │
│  │  │  · Voice (Main Driver UI)           │    │   │
│  │  │  · Map                              │    │   │
│  │  │  · Summary                          │    │   │
│  │  │  · Settings                         │    │   │
│  │  └─────────────────────────────────────┘    │   │
│  │                                              │   │
│  │  ┌─────────────────────────────────────┐    │   │
│  │  │  MascotOverlay (always on top)      │    │   │
│  │  │  Rive State Machine — persistent    │    │   │
│  │  └─────────────────────────────────────┘    │   │
│  │                                              │   │
│  │  ┌─────────────────────────────────────┐    │   │
│  │  │  TaskProgressCard (global overlay)  │    │   │
│  │  │  Slides up when agent is working    │    │   │
│  │  └─────────────────────────────────────┘    │   │
│  │                                              │   │
│  │  ┌─────────────────────────────────────┐    │   │
│  │  │  CallOverlay (when LiveKit active)  │    │   │
│  │  └─────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

---

## 2. Navigation Architecture

Routing is **go_router** (`frontend/lib/app/router.dart`). This replaces the earlier Riverpod
`IndexedStack` design.

### 2.1 Root Stack Pattern
`RootStack` wraps the router's output through `MaterialApp.router(builder:)`. That way the global
overlays (co-rider, task card, call overlay) sit above every route at once. They are overlays,
not routes.

```dart
// main.dart
class VoiceOpsApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: buildVoiceOpsTheme(),               // dark-mode-first: the only theme
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => RootStack(child: child!),
    );
  }
}

// root_stack.dart
Stack(
  children: [
    child,                     // Layer 1: the router (onboarding or the main shell)
    const MascotOverlay(),     // Layer 2: co-rider bubble on Map / Summary / Settings
    const TaskProgressCard(),  // Layer 3: slides up globally
    // Layer 4: CallOverlay (not built yet, see §5.3)
  ],
)
```

### 2.2 Routes and the Bottom-Nav Shell
Every route is declared in `app/router.dart`:

| Route | Screen | Orb material |
|---|---|---|
| `/onboarding` | `OnboardingFlow` | holographic |
| `/voice` | `VoiceScreen` (tab 0) | chrome |
| `/map` | `MapScreen` (tab 1) | chrome |
| `/summary` | `SummaryScreen` (tab 2) | chrome |
| `/settings` | `SettingsScreen` (tab 3) | chrome |

The four tabs are branches of a single `StatefulShellRoute.indexedStack`, so each tab keeps its
own navigator and state alive. `MainShell` lays out the active branch and the Tabler-icon bottom
nav. Tapping a tab calls `navigationShell.goBranch(i)`, and re-tapping the active tab pops it
back to its root. A `redirect` guard keeps first-launch users on `/onboarding` until
`onboardingProvider` clears. `OrbMaterialScope` sets the orb material per route. Pages
cross-fade over the shared gradient background.

### 2.3 Agent-Driven Navigation
The backend's `screen_navigate` event (`docs/contracts/interface.md` §1) goes through
`navigationProvider`, which drives go_router. It never sets widget state:

```dart
// providers/navigation_provider.dart
final navigationProvider = Provider<NavigationActions>(
  (ref) => NavigationActions(ref.watch(routerProvider)),
);

class NavigationActions {
  void goTo(MainTab tab) => _router.go(tab.path);

  /// 'voice' | 'map' | 'summary' | 'settings'; unknown keys fall back to voice.
  void navigateForAgent(String screenKey) => goTo(
    MainTab.values.firstWhere((t) => t.name == screenKey,
        orElse: () => MainTab.voice),
  );
}
```

Read the current tab from `activeTabProvider`, which is derived from go_router. Route display
happens **in-app** on the Map tab (§4.5). The agent never hands the driver off to an external
maps app.

---

## 3. Riverpod State Structure

```
providers/
├── agent_state_provider.dart      // Current agent state (idle|thinking|calling|mapping|etc)
├── navigation_provider.dart       // go_router actions for agent navigation (§2.3)
├── task_progress_provider.dart    // Live task steps from FastAPI
├── mascot_state_provider.dart     // Rive animation state — derived from agent state
├── onboarding_provider.dart       // Has user completed onboarding?
├── map_provider.dart              // Delivery stops, route, ETA
├── summary_provider.dart          // Post-shift LeMUR data
├── voice_session_provider.dart    // AssemblyAI session status
└── auth_provider.dart             // Driver profile / Supabase auth
```

### Agent State Enum
```dart
enum AgentState {
  idle,
  thinking,
  calling,
  mapping,      // navigating/routing
  taskWorking,  // general task execution
  summarizing,  // LeMUR processing
  celebrating,  // task complete
}
```

---

## 4. Screen Specifications

### 4.1 Onboarding Screen 1 — The Hook
**Mascot emotion:** Excited / welcoming (raised brows, wide eyes, big smile, blush)
**Layout:**
```
[Background: gradient orb system — purple/pink/lavender]
[Top 40%: Mascot animated — floating, welcoming accessories]
[Middle: Headline "Your hands-free co-rider for every delivery"]
[Below: Subtext — one line, what VoiceOps does]
[Bottom: Progress dots (3 dots, first filled) + Next button]
```
**Widget tree:**
```dart
OnboardingScreen1
└── Stack
    ├── GradientOrbBackground()
    ├── Column
    │   ├── RiveCharacter(state: 'excited')     // mascot
    │   ├── HeadlineText("Your hands-free co-rider...")
    │   ├── SubtextWidget()
    │   └── Spacer
    └── OnboardingControls(currentPage: 0)      // dots + button
```

---

### 4.2 Onboarding Screen 2 — The Power
**Mascot emotion:** Focused / thinking (rings, determined brows)
**Layout:**
```
[Background: same gradient system]
[Top 35%: Mascot in thinking state + pulse rings]
[Mini task card: shows 3 parallel tasks firing simultaneously]
[Headline: "Just speak. It handles everything."]
[Below: Highlight 3 actions with icons]
[Bottom: Progress dots (dot 2 filled) + Next]
```
**Key feature:** The mini task card on this screen is a static demo of the live card — this shows judges the core capability before they even reach the main screen.

---

### 4.3 Onboarding Screen 3 — The Trust
**Mascot emotion:** Happy / celebrating (full smile, blush, star eyes)
**Layout:**
```
[Background: slightly brighter gradient]
[Mascot: bouncing, celebrating emotion]
[Headline: "Built for drivers. Not desks."]
[3 trust icons: 🎙️ Voice-first | ⚡ Real-time | 🔒 Reliable]
[CTA Button: "Start Driving" — purple gradient, full width]
[Bottom: Progress dots (all 3 filled)]
```

---

### 4.4 Main Driver UI (Voice Screen)
**Primary interaction screen. Driver spends 80% of time here.**

> The target home layout is `.firstmate/rules/frontend.md` § Home Screen Layout (map 45%, next-stop
> card, transcript, push-to-talk, bottom nav). The layout below describes the current shell.
> Action chips are real driver commands from PRD §7, never generic AI-assistant actions.

**Layout:**
```
[Status bar]
[Top nav: hamburger menu | greeting | settings icon]
[Greeting: "Hello, [Name]! How can I help?"]
[Mascot: center stage, 210px height, animated]
[Mascot state label: slides up below character]
[Mid area 98px: action chips behind / task card slides over]
  [Chip: Find my next stop]      [Chip: What's left on my list]
  [Chip: Call the customer]     [Chip: Give me my summary]
[Input row: + | "Ask me anything..." | 🎤 voice button]
```

**Widget tree:**
```dart
VoiceScreen
└── Column
    ├── StatusBar()
    ├── TopNav()
    ├── GreetingWidget()
    ├── MascotSection(height: 210)
    │   ├── MascotWrap (animated wrapper)
    │   │   ├── AccessoryLayer()    // floating emojis/items
    │   │   └── RiveCharacter()     // main Rive animation
    │   └── MascotStateLabel()
    ├── MidArea(height: 98)         // fixed height container
    │   ├── ActionChipsGrid()       // behind
    │   └── TaskProgressCard()      // slides up over chips
    └── VoiceInputRow()
```

---

### 4.5 Map Screen
**Agent navigates here automatically for location/routing tasks.**

**Layout:**
```
[Full screen Google Map]
[Delivery stop pins — drop sequentially when agent processes]
[Animated route line — draws itself with dash animation]
[Top overlay: current stop card (glassmorphism)]
[Bottom sheet: stops list — swipeable cards]
[Floating voice button: bottom right — always accessible]
[Mascot: compact bubble — top left corner when agent is active]
[ETA card: slides up from bottom when route ready]
```

**Widget tree:**
```dart
MapScreen
└── Stack
    ├── GoogleMap(
    │   markers: deliveryStops,
    │   polylines: animatedRoute,
    │   onMapCreated: _onMapCreated,
    │   )
    ├── Positioned(top) → CurrentStopCard()
    ├── Positioned(bottom) → StopsBottomSheet()
    ├── Positioned(bottomRight) → FloatingVoiceButton()
    ├── Positioned(topLeft) → CompactMascotBubble()   // when agent active on map
    └── ETACard()  // slides up when route complete
```

**Agent-driven map animations:**
```dart
// When FastAPI sends route data:
void onRouteReceived(RouteData route) {
  // 1. Pins drop one by one with staggered delay
  for (var i = 0; i < route.stops.length; i++) {
    Future.delayed(Duration(milliseconds: i * 300), () {
      _addPin(route.stops[i]);
    });
  }
  // 2. Route line draws with animated dash
  _animateRouteLine(route.polyline);
  // 3. ETA card slides up
  _showETACard(route.eta);
}
```

---

### 4.6 Summary Screen
**Agent navigates here for post-shift reporting. LeMUR powers the content.**

**Layout:**
```
[Background: softer gradient — calmer than main UI]
[Top: Mascot in relaxed/analyzing state]
[Summary header card: Today's date + shift duration]
[Stats row: [📦 Deliveries] [🛣️ Distance] [⏱️ Time]]
  → each stat counts up with animation
[AI Summary card: LeMUR narrative — types in like typewriter]
[Flagged issues section: appears if any]
[Customer highlights: top interactions]
[Bottom: "End Shift" button]
```

**Widget tree:**
```dart
SummaryScreen
└── SingleChildScrollView
    └── Column
        ├── SummaryMascot(state: 'relaxed')
        ├── ShiftHeaderCard()
        ├── StatsRow(
        │   deliveries: AnimatedCounter(),
        │   distance: AnimatedCounter(),
        │   duration: AnimatedCounter(),
        │   )
        ├── LeMURSummaryCard(text: streamingText)   // typewriter effect
        ├── FlaggedIssuesSection()
        ├── CustomerHighlightsSection()
        └── EndShiftButton()
```

---

### 4.7 Settings Screen
**Manual screen. Agent is passive here.**

**Sections:**
```
[Driver Profile]
  - Name, photo, vehicle info
  
[Voice Preferences]
  - Language selection
  - Wake word toggle
  - Voice speed
  
[Connected Platforms]
  - Onfleet connection status
  - Vonage SMS toggle
  - LiveKit call toggle
  
[Notifications]
  - Delivery alerts
  - Customer message alerts
  
[App Preferences]
  - Theme (Light/Dark)
  - Mascot personality toggle (calm / energetic)
```

---

## 5. Global Overlay Components

### 5.1 MascotOverlay
Persistent above all screens. Changes size based on context.

| Context | Size | Position | Behavior |
|---------|------|----------|----------|
| Voice Screen | Full (210px) | Center | Full expression + accessories |
| Map Screen | Compact bubble (60px) | Top left | Simple emotion dot |
| Summary Screen | Medium (140px) | Top center | Relaxed animations |
| Settings | Tiny bubble (40px) | Top right | Idle only |
| Call active | Medium (120px) | Center overlay | Calling emotion |

```dart
class MascotOverlay extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(navigationProvider);
    final agentState = ref.watch(agentStateProvider);
    
    return AnimatedPositioned(
      duration: Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      // Position and size change based on current screen
      child: AnimatedContainer(
        duration: Duration(milliseconds: 400),
        child: RiveCharacter(state: agentState),
      ),
    );
  }
}
```

### 5.2 TaskProgressCard (Global)
```dart
class TaskProgressCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(taskProgressProvider);
    final show = steps.isNotEmpty;
    
    return AnimatedSlide(
      offset: show ? Offset(0, 0) : Offset(0, 1.1),
      duration: Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      child: TaskCard(steps: steps),
    );
  }
}
```

### 5.3 CallOverlay
```dart
// Appears when LiveKit SIP call is active
class CallOverlay extends ConsumerWidget {
  // Full screen translucent overlay
  // Mascot in calling emotion center
  // Caller info + waveform animation
  // End call button
}
```

---

## 6. Rive State Machine Specification

**Status:** the co-rider is an orb placeholder today (`MascotDisplay`, §6.1). This Rive spec is the
planned swap-in.

**File:** `assets/rive/voiceops_mascot.riv`
**State Machine Name:** `AgentStateMachine`
**Input type:** String enum `taskState`

| State | Trigger | Body Animation | Eye Type | Brow | Mouth | Accessories |
|-------|---------|---------------|----------|------|-------|-------------|
| idle | default | float loop | normal | gentle arch | smile | none |
| thinking | `taskState = thinking` | pulse + scale | three dots | curious | open "o" | pulse rings |
| calling | `taskState = calling` | side bounce | happy squint | raised | wide smile | phone waves |
| mapping | `taskState = mapping` | sway | focused normal | slight furrow | neutral | globe orbit |
| taskWorking | `taskState = task` | wiggle | squint determined | angled in | flat line | clipboard |
| summarizing | `taskState = summarizing` | slow float | thoughtful | relaxed | slight smile | sparkles |
| celebrating | `taskState = celebrating` | big bounce | star eyes | raised high | huge smile | confetti |

**Flutter binding:**
```dart
// mascot_controller.dart
class MascotController {
  late RiveAnimationController _controller;
  SMIString? _stateInput;
  
  void setState(AgentState state) {
    _stateInput?.change(state.riveKey);
  }
}

extension on AgentState {
  String get riveKey {
    switch (this) {
      case AgentState.idle:        return 'idle';
      case AgentState.thinking:    return 'thinking';
      case AgentState.calling:     return 'calling';
      case AgentState.mapping:     return 'mapping';
      case AgentState.taskWorking: return 'task';
      case AgentState.summarizing: return 'summarizing';
      case AgentState.celebrating: return 'celebrating';
    }
  }
}
```

### 6.1 Co-rider Orb: Placeholder Until the Rive Asset Is Ready
**Status (Sept 2026):** `frontend/lib/mascot/mascot_display.dart` paints the co-rider as an
animated orb with `CustomPaint`. The orb morphs its tint, glow, pulse, and spin for each
`AgentState`. It comes in two materials, chosen through `OrbMaterialScope`: the **holographic
bubble** in onboarding and **chrome/mercury** in the main app.

**Swap trigger:** when the `.riv` file is delivered, replace the internals of `MascotDisplay`
with `RiveAnimation.asset()` (the commented `TODO(rive)` path in that file) and add
`assets/rive/` to `pubspec.yaml` in the same change. Callers keep passing `state` and `size`, so
nothing else changes: not the layout, the state wiring, or the overlay system.

---

## 7. FastAPI → Flutter Event Contract

> **Superseded by `docs/contracts/interface.md` §1**, the authoritative WebSocket catalogue. The
> sketch below is the original v2.0 list and is kept for history.

Events emitted by FastAPI via WebSocket to Flutter:

```json
// Agent state change
{ "event": "agent_state", "state": "thinking" }

// Navigate to screen
{ "event": "screen_navigate", "screen": "map" }

// Task step update  
{ "event": "task_step", "step": "Checking delivery route", "status": "active" }
{ "event": "task_step", "step": "Checking delivery route", "status": "complete" }

// Route data for map
{ "event": "map_route", "stops": [...], "polyline": "...", "eta": "12 min" }

// Call started
{ "event": "call_started", "customer": "John D.", "stop": 3 }

// LeMUR summary chunk (streaming)
{ "event": "summary_chunk", "text": "Today you completed..." }
```

**Flutter WebSocket handler:**
```dart
// websocket_provider.dart
void _handleEvent(Map<String, dynamic> event) {
  switch (event['event']) {
    case 'agent_state':
      ref.read(agentStateProvider.notifier).setState(event['state']);
      break;
    case 'screen_navigate':
      ref.read(navigationProvider.notifier).navigateForAgent(event['screen']);
      break;
    case 'task_step':
      ref.read(taskProgressProvider.notifier).updateStep(event);
      break;
    case 'map_route':
      ref.read(mapProvider.notifier).setRoute(event);
      break;
    case 'call_started':
      ref.read(callProvider.notifier).startCall(event);
      break;
    case 'summary_chunk':
      ref.read(summaryProvider.notifier).appendChunk(event['text']);
      break;
  }
}
```

---

## 8. Design Tokens

**Dark-mode-first. The dark theme is the only theme.** The reference implementation is
`frontend/lib/core/theme/tokens.dart`, and where this summary and that file differ, the file
wins. Every colour, spacing, radius, size, duration, and text style lives in that file. Widgets
reference tokens and never hardcode literals.

### 8.1 Colour: `VoiceOpsColors`

| Group | Token | Value | Use |
|---|---|---|---|
| Surfaces | `canvas` | `#07060B` | app background, darkest |
| | `raised` | `#0E0B18` | cards, nav-bar fill |
| | `elevated` | `#151126` | elevated surfaces |
| | `overlay` | `#1D1834` | highest surfaces |
| Brand violet | `primary` | `#8B5CF6` | the accent |
| | `primaryLight` | `#C4B5FD` | icons and labels on dark |
| | `primaryDark` | `#4C1D95` | deep violet |
| | `primaryTint` | primary @ 16% | pill fills |
| | `primaryGlow` | primary @ 35% | selection, glow |
| **Live (mic-hot)** | `live` | **`#C8F250`** | push-to-talk `recording` state **only** |
| | `liveGlow` | live @ 40% | recording halo only |
| Accents (sparing, cards) | `pink` / `blue` / `amber` | `#F9A8D4` / `#7DD3FC` / `#FBBF24` | |
| Semantic | `success` / `danger` | `#34D399` / `#F87171` | done / error states |
| Text | `textPrimary` / `textMuted` / `textFaint` | `#F4F1FF` / `#A7A1C4` / `#7C7797` | `textFaint` is ≥ 4.5:1 on canvas |
| | `onPrimary` / `onAccent` | `#FFFFFF` / canvas | ink on violet / on pastel accents |
| Lines | `divider` / `scrim` | white @ 8% / canvas @ 70% | |

**Lime is reserved.** `live` (`#C8F250`) means "the mic is hot". It is a driver-safety signal,
so nothing else in the app may be lime: not an accent, not the orb, and not the Material
`ColorScheme`. Tests enforce this.

### 8.2 Restrained glass: `VoiceOpsGlass`
Blur is capped at **12** and must never go higher. Fill is white @ 5%, the border is a white
@ 12% 1 px hairline, and the shadow is a soft violet (primary @ 18%, blur 24, y-offset 8).
Repeated items (chip grids, list rows) use unblurred glass (`GlassCard(frosted: false)`). Keep
the backdrop blur for a few large surfaces such as the nav bar and input bar. Readability and
60 fps on a mid-range Android come before the effect.

### 8.3 Orb palettes: `VoiceOpsOrbColors`
- **Holographic** (onboarding): lavender `#C4B5FD` → pink `#F9A8D4` → sky `#7DD3FC` → mint `#A7F3D0`
- **Chrome** (main app): mercury greys `#EDEBF5`, `#8E8AA6`, `#2B2740`, `#D3CFE6`, `#5E5A78`

### 8.4 Spacing, radius, size, motion

| Scale | Tokens |
|---|---|
| `VoiceOpsSpacing` | xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · gutter 22 |
| `VoiceOpsRadius` | control 14 · card 20 · sheet 28 · pill 999 |
| `VoiceOpsSize` | touchTarget 48 · control 52 · pushToTalk 88 (min 80) · orbHero 150 · orbBubble 60 · orbBubbleSmall 40 · icons 16/20/24/32 |
| `VoiceOpsMotion` | fast 150 ms · base 250 ms · slow 400 ms · orbMorph 600 ms · curves `easeOutCubic` / `easeInOutCubic` |

### 8.5 Type: `VoiceOpsText` (Plus Jakarta Sans via `google_fonts`)
display 40 / w800 · headline 24 / w700 · title 17 / w600 · body 15 / w400 (+ `bodyMuted`) ·
label 13 / w600 · caption 11 / w700 (uppercase status pills) · numeric 28 / w700 with tabular
figures. Plus Jakarta Sans stands in for Circular Std / Sofia Pro. If licensed files arrive, swap
them in `tokens.dart` only.

---

## 9. Folder Structure

```
lib/
├── main.dart
├── app/
│   ├── router.dart                  // every route (go_router)
│   ├── main_shell.dart              // bottom-nav shell
│   └── root_stack.dart              // global overlays above the router
├── core/
│   ├── theme/
│   │   └── tokens.dart
│   └── widgets/
│       ├── glass_card.dart          // reusable glassmorphism card
│       ├── gradient_orb_bg.dart     // animated background
│       └── voice_input_bar.dart
├── features/
│   ├── onboarding/
│   │   ├── screens/
│   │   │   ├── onboarding_screen_1.dart
│   │   │   ├── onboarding_screen_2.dart
│   │   │   └── onboarding_screen_3.dart
│   │   └── widgets/
│   │       └── onboarding_controls.dart
│   ├── voice/
│   │   ├── screens/
│   │   │   └── voice_screen.dart
│   │   └── widgets/
│   │       ├── action_chips_grid.dart
│   │       └── greeting_widget.dart
│   ├── map/
│   │   ├── screens/
│   │   │   └── map_screen.dart
│   │   └── widgets/
│   │       ├── stops_bottom_sheet.dart
│   │       ├── eta_card.dart
│   │       └── floating_voice_button.dart
│   ├── summary/
│   │   ├── screens/
│   │   │   └── summary_screen.dart
│   │   └── widgets/
│   │       ├── stats_row.dart
│   │       ├── lemur_summary_card.dart
│   │       └── flagged_issues.dart
│   └── settings/
│       └── screens/
│           └── settings_screen.dart
├── mascot/
│   ├── mascot_overlay.dart          // global persistent overlay
│   ├── mascot_controller.dart       // Rive state machine controller
│   ├── compact_mascot_bubble.dart   // small version for map/settings
│   └── mascot_state.dart            // AgentState enum
├── overlays/
│   ├── task_progress_card.dart      // global task progress
│   └── call_overlay.dart            // LiveKit call screen
└── providers/
    ├── agent_state_provider.dart
    ├── navigation_provider.dart
    ├── task_progress_provider.dart
    ├── map_provider.dart
    ├── summary_provider.dart
    ├── voice_session_provider.dart
    └── onboarding_provider.dart

assets/
└── rive/
    └── voiceops_mascot.riv          // added together with the .riv, not before (§6.1)
```

Fonts are not bundled. Plus Jakarta Sans loads through `google_fonts`, and tests disable
runtime fetching.

---

## 10. GitHub Branching Strategy

This is the same flow as `CLAUDE.md` and `AGENTS.md`:

```
main
 └── dev
      └── staging                         ← live integration branch
           ├── features/frontend/<slug>
           ├── features/backend/<slug>
           └── features/ai/<slug>
```

**Merge rules:**
- Cut feature branches from `staging`, named `features/<layer>/<slug>`
- Features land in `staging` via PR. `staging` is the live integration branch. It was brought
  level with `main` on 2026-09-11
- Promote upward by PR only: `staging → dev`, then `dev → main`
- No direct pushes to `main` or `dev`

---

## 11. Integration Checkpoints

### Checkpoint 1 — Sept 14
**Goal:** Core voice pipeline alive end-to-end
- [ ] Ez: Project setup complete, design tokens, GlassCard widget, GradientOrbBg
- [ ] Ez: Voice screen shell (static, no Rive yet)
- [ ] Ez: Bottom nav with 4 tabs wired up
- [ ] Teammate: FastAPI WebSocket endpoint live
- [ ] Teammate: AssemblyAI Voice Agent connected, transcription working
- [ ] **Test:** Speak → FastAPI receives → logs to console

### Checkpoint 2 — Sept 18
**Goal:** Agent-driven navigation + map screen working
- [ ] Ez: Rive mascot integrated, every `AgentState` wired to Riverpod
- [ ] Ez: Task progress card global overlay working
- [ ] Ez: Map screen with Google Maps, pin drop animation, route draw
- [ ] Ez: Agent-driven navigation (FastAPI screen_navigate → tab switch)
- [ ] Teammate: Tool calls executing (Onfleet, Google Maps API)
- [ ] Teammate: WebSocket events emitting correctly per contract
- [ ] **Test:** "Find my next stop" → app navigates to map → pins drop → route draws

### Checkpoint 3 — Sept 22
**Goal:** Full app screens complete
- [ ] Ez: Onboarding 3 screens complete with mascot emotions
- [ ] Ez: Summary screen with animated stat counters
- [ ] Ez: Settings screen
- [ ] Ez: Call overlay (LiveKit UI)
- [ ] Teammate: LeMUR summary generation streaming
- [ ] Teammate: LiveKit SIP outbound call
- [ ] **Test:** Full shift simulation — voice in → tasks → map → call → summary

### Checkpoint 4 — Sept 27
**Goal:** Polish + demo-ready
- [ ] Ez: All animations smooth, no jank
- [ ] Ez: Onboarding fully polished
- [ ] Ez: Demo mode / MockAdapter for offline fallback
- [ ] Teammate: Error handling, latency optimized
- [ ] Both: Full end-to-end demo rehearsed
- [ ] **Test:** Record demo video, identify and fix all rough edges

---

## 12. Frontend Team To-Do (Ez)

**Week 1 (Sept 8–14):**
- [ ] Create Flutter project, set up Riverpod
- [ ] Install all dependencies (rive, google_maps_flutter, supabase_flutter, riverpod)
- [ ] Build design token file (colors, spacing, radius)
- [ ] Build GlassCard reusable widget
- [ ] Build GradientOrbBackground widget
- [ ] Build Voice screen shell (static layout)
- [ ] Set up bottom nav with 4 tabs
- [ ] Set up GitHub branches

**Week 2 (Sept 14–18):**
- [ ] Integrate Rive mascot (placeholder .riv first)
- [ ] Wire Rive State Machine to Riverpod agentStateProvider
- [ ] Build MascotOverlay global widget
- [ ] Build TaskProgressCard global overlay
- [ ] Build Map screen (Google Maps + animations)
- [ ] Wire navigationProvider to bottom nav
- [ ] Handle screen_navigate WebSocket event

**Week 3 (Sept 18–22):**
- [ ] Build all 3 onboarding screens
- [ ] Build Summary screen with LeMUR stream + animated counters
- [ ] Build Settings screen
- [ ] Build CallOverlay
- [ ] Build CompactMascotBubble for map/settings

**Week 4 (Sept 22–27):**
- [ ] Animation polish pass
- [ ] Performance pass (no jank, <100ms state transitions)
- [ ] Demo mode with MockAdapter
- [ ] End-to-end demo rehearsal
- [ ] Final submission assets (screenshots, demo video)

