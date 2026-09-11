# VoiceOps — Software Design Document v2.0
**Hackathon:** AssemblyAI Voice Agent Hackathon | Sept 1–30, 2026
**Last updated:** September 2026

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
│  │  │  MainNavigator (Bottom Nav — 4 tabs)│    │   │
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

### 2.1 Root Stack Pattern
The root of the app is a `Stack` widget, not a simple Navigator. This allows global overlays (mascot, task card, call overlay) to sit above all screens permanently.

```dart
// main.dart
class VoiceOpsApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ProviderScope(
        child: RootStack(),
      ),
    );
  }
}

// root_stack.dart
class RootStack extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showOnboarding = ref.watch(onboardingProvider);
    
    return Stack(
      children: [
        // Layer 1: Main app screens
        showOnboarding ? OnboardingFlow() : MainNavigator(),
        
        // Layer 2: Mascot — always visible, always on top of screens
        MascotOverlay(),
        
        // Layer 3: Task progress card — slides up globally
        TaskProgressCard(),
        
        // Layer 4: Call overlay — appears over everything when LiveKit active
        CallOverlay(),
      ],
    );
  }
}
```

### 2.2 Bottom Navigation
```dart
// main_navigator.dart
class MainNavigator extends ConsumerWidget {
  final tabs = [
    VoiceScreen(),   // Tab 0 — 🎙️ Voice
    MapScreen(),     // Tab 1 — 🗺️ Map
    SummaryScreen(), // Tab 2 — 📊 Summary
    SettingsScreen() // Tab 3 — ⚙️ Settings
  ];
}
```

### 2.3 Agent-Driven Navigation
FastAPI emits `screen_navigate` events that Riverpod catches and auto-switches tabs:

```dart
// navigation_provider.dart
final navigationProvider = StateNotifierProvider<NavigationNotifier, int>((ref) {
  return NavigationNotifier();
});

class NavigationNotifier extends StateNotifier<int> {
  NavigationNotifier() : super(0);
  
  void navigateForAgent(String screenKey) {
    switch (screenKey) {
      case 'map':      state = 1; break;
      case 'summary':  state = 2; break;
      case 'settings': state = 3; break;
      default:         state = 0; break;
    }
  }
}
```

---

## 3. Riverpod State Structure

```
providers/
├── agent_state_provider.dart      // Current agent state (idle|thinking|calling|mapping|etc)
├── navigation_provider.dart       // Current tab index — writable by agent events
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
  translating,
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
[Middle: Headline "Your hands-free co-pilot for every delivery"]
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
    │   ├── HeadlineText("Your hands-free co-pilot...")
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

**Layout:**
```
[Status bar]
[Top nav: hamburger menu | greeting | settings icon]
[Greeting: "Hello, [Name]! How can I help?"]
[Mascot: center stage, 210px height, animated]
[Mascot state label: slides up below character]
[Mid area 98px: action chips behind / task card slides over]
  [Chip: 🖼️ Create image] [Chip: 💡 Give ideas]
  [Chip: 📋 Do task]      [Chip: 🌐 Translate]
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
| translating | `taskState = translating` | sway | glasses | one raised | hmm | globe + letters |
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
      case AgentState.translating: return 'translating';
      case AgentState.summarizing: return 'summarizing';
      case AgentState.celebrating: return 'celebrating';
    }
  }
}
```

### 6.1 Onboarding Orb — Temporary Placeholder (until Rive asset is ready)
**Status (Sept 2026):** Using the CSS/SVG holographic orb from `voiceops-onboarding-concept.html` as a stand-in in Flutter until a real Rive character is produced for onboarding. This is separate from the main-app chrome orb above, which remains pending regardless.

**Implementation approach:** Port the same visual logic to Flutter natively rather than embedding a WebView:
- Layered blob effect → `Stack` of blurred `Container`s with `RadialGradient`, animated via `AnimationController` (independent timing per blob, matching the CSS drift keyframes)
- Blend mode → `BackdropFilter`/`ColorFiltered` with `BlendMode.screen`
- Breathing scale → `AnimatedBuilder` + `Transform.scale`, 4.5s cycle
- Grain texture → static noise `Image` asset at low opacity, `BlendMode.overlay`
- Lives behind the same `MascotDisplay` widget interface as the main-app orb, so swapping in the real `.riv` file later only touches that one widget — no changes needed to layout, state wiring, or the overlay system.

**Swap trigger:** Replace `MascotDisplay` internals with `RiveAnimation.asset()` once the onboarding Rive character is delivered. No other code changes required.

---

## 7. FastAPI → Flutter Event Contract

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

```dart
// theme/tokens.dart
class VoiceOpsColors {
  // Primary palette
  static const primary       = Color(0xFF7C3AED);  // purple
  static const primaryLight  = Color(0xFFA78BFA);
  static const primaryDark   = Color(0xFF4C1D95);
  
  // Gradient stops
  static const grad1 = Color(0xFFC084FC);  // violet
  static const grad2 = Color(0xFF818CF8);  // indigo
  static const grad3 = Color(0xFFF472B6);  // pink (creating state)
  static const grad4 = Color(0xFF34D399);  // green (task done)
  static const grad5 = Color(0xFF38BDF8);  // sky (translating)
  
  // Surfaces
  static const glassWhite  = Color(0x62FFFFFF);  // 38% white
  static const glassBorder = Color(0xBFFFFFFF);  // 75% white
  
  // Text
  static const textPrimary = Color(0xFF3B0764);
  static const textMuted   = Color(0xFF7C3AED);
  
  // Semantic
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFF59E0B);
}

class VoiceOpsSpacing {
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
}

class VoiceOpsRadius {
  static const sm   = 14.0;
  static const md   = 18.0;
  static const lg   = 28.0;
  static const card = 20.0;
  static const pill = 54.0;  // phone frame
}
```

---

## 9. Folder Structure

```
lib/
├── main.dart
├── app/
│   └── root_stack.dart
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
├── rive/
│   └── voiceops_mascot.riv
└── fonts/
    └── Inter/
```

---

## 10. GitHub Branching Strategy

```
main
  └── dev
        ├── staging
        ├── features/frontend/onboarding
        ├── features/frontend/voice-screen
        ├── features/frontend/map-screen
        ├── features/frontend/summary-screen
        ├── features/frontend/settings-screen
        ├── features/frontend/mascot-overlay
        ├── features/frontend/task-progress-card
        ├── features/backend/voice-agent
        ├── features/backend/websocket-events
        ├── features/backend/lemur-summary
        └── features/ai/agent-workflows
```

**Merge rules:**
- `features/*` → `dev` via PR only
- `dev` → `staging` at each integration checkpoint
- `staging` → `main` only after checkpoint sign-off
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
- [ ] Ez: Rive mascot integrated, all 8 states wired to Riverpod
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

