# VoiceOps — Technical Feasibility Document v2.0
**Last updated:** September 2026

> **Superseded by PRD v4.0 / CLAUDE.md. Historical reference only.** Where this document
> disagrees with `docs/product/VoiceOps_PRD_v4.0.md`, `CLAUDE.md`, or `.firstmate/rules/`, those
> win. The main differences: navigation is go_router (SDD §2), the UI is dark-mode-first (SDD §8),
> the co-rider is an orb placeholder until the Rive asset lands, and interfaces live in
> `docs/contracts/interface.md`. The risk register (§10) and performance targets (§9) still
> hold. §4 and §8 were touched on 2026-09-11.

---

## 1. Overview

This document covers the technical feasibility of all VoiceOps features, including the new Agent-Driven Navigation system, Rive mascot integration, expanded screen set, and map animations. All features are confirmed feasible within the hackathon timeline.

---

## 2. Agent-Driven Navigation — Feasibility

**Verdict: ✅ Fully feasible**

The core pattern is a Root Stack in Flutter with Riverpod-managed navigation state. FastAPI emits WebSocket events that trigger tab switches and mascot state changes simultaneously. No new libraries required beyond what is already in the stack.

**Latency profile:**
- FastAPI intent detection → event emit: ~50ms
- WebSocket delivery to Flutter: ~20ms
- Riverpod state update → widget rebuild: ~16ms (one frame)
- Total navigation lag: ~86ms — imperceptible to driver

**Critical requirement:** The WebSocket connection must be maintained throughout the session. FastAPI must emit `screen_navigate` before or simultaneously with tool call execution so the screen is ready when data arrives.

---

## 3. Rive Mascot — Feasibility

**Verdict: ✅ Fully feasible — recommended approach**

Rive runs on Flutter's Impeller render thread, completely independent of Dart's main isolate. Mascot animations will never cause UI jank even during heavy agent processing.

**Integration path:**
```
Figma character design
  → Export as SVG layers (body, ears, eyes, brows, mouth, accessories)
  → Import into Rive (rive.app)
  → Add bones/IK rig to body parts
  → Create animations per state (idle loop, bounce, wiggle, etc.)
  → Build State Machine with String input "taskState"
  → Wire transitions between all states
  → Export .riv file
  → Drop into Flutter assets/rive/
  → RiveAnimation.asset() widget + SMIString controller
```

**State machine input:**
```dart
SMIString? _stateInput;

void _onRiveInit(Artboard artboard) {
  final controller = StateMachineController.fromArtboard(
    artboard, 
    'AgentStateMachine'
  );
  artboard.addController(controller!);
  _stateInput = controller.findInput<String>('taskState') as SMIString;
}

void updateMascotState(String state) {
  _stateInput?.change(state);
}
```

**Mascot sizes across screens:**
- Voice screen (full): 210px height Rive widget
- Map screen (bubble): 60px circular Rive widget, clipped
- Summary screen (medium): 140px Rive widget
- Settings (tiny): 40px, idle state only

---

## 4. Map Screen Animations — Feasibility

**Verdict: ✅ Feasible with google_maps_flutter**

**Pin drop animation (staggered):**
```dart
// Pins added sequentially with delay
for (var i = 0; i < stops.length; i++) {
  await Future.delayed(Duration(milliseconds: i * 300));
  setState(() {
    _markers.add(Marker(
      markerId: MarkerId('stop_$i'),
      position: stops[i].latLng,
      icon: _customPinIcon,
    ));
  });
}
```

**Route line draw animation:**
Google Maps polylines don't natively animate, so we simulate it by progressively revealing polyline points:
```dart
void _animateRouteLine(List<LatLng> fullRoute) {
  int pointsToShow = 0;
  Timer.periodic(Duration(milliseconds: 16), (timer) {
    pointsToShow = min(pointsToShow + 3, fullRoute.length);
    setState(() {
      _routePolyline = Polyline(
        polylineId: PolylineId('route'),
        points: fullRoute.sublist(0, pointsToShow),
        color: VoiceOpsColors.primary,  // token, never a literal
        width: 4,
      );
    });
    if (pointsToShow >= fullRoute.length) timer.cancel();
  });
}
```

**ETA card slide-up:**
Standard Flutter `AnimatedSlide` widget, triggered when route data arrives.

---

## 5. Summary Screen — LeMUR Streaming Feasibility

**Verdict: ✅ Feasible**

LeMUR generates the post-shift summary as a streaming text response. FastAPI pipes chunks via WebSocket to Flutter which appends to a `StringBuffer` and triggers a typewriter-effect widget rebuild.

```dart
// Flutter side
final _summaryBuffer = StringBuffer();

void onSummaryChunk(String chunk) {
  _summaryBuffer.write(chunk);
  ref.read(summaryProvider.notifier).update(_summaryBuffer.toString());
}

// Widget
Text(
  summary,
  // Appears to type as chunks arrive
)
```

**Stat counter animation:**
```dart
AnimatedCount(
  begin: 0,
  end: deliveryCount,
  duration: Duration(milliseconds: 1200),
  curve: Curves.easeOut,
)
```

---

## 6. Call Overlay — LiveKit Feasibility

**Verdict: ✅ Feasible on LiveKit Build tier (free)**

LiveKit SIP/PSTN is used exclusively for outbound customer calls triggered by the `call_customer` tool. The Flutter side shows the overlay UI while LiveKit handles the actual call audio on the backend.

**Flutter UI only — no LiveKit Flutter SDK needed for hackathon:**
- Flutter shows the call overlay (mascot in calling state, customer name, waveform animation, end call button)
- The actual call audio is managed entirely by FastAPI + LiveKit server
- Flutter sends "end call" event to FastAPI via WebSocket
- FastAPI terminates the LiveKit room

This keeps the Flutter implementation clean and avoids LiveKit Flutter SDK complexity for the hackathon.

---

## 7. Real-Time Voice Pipeline — Confirmed Architecture

```
Driver speaks
    ↓
AssemblyAI Voice Agent API (WebSocket stream)
    ↓ ~200-400ms
FastAPI receives transcript + intent
    ↓
asyncio.gather() — parallel tool execution
    ├── Onfleet API call
    ├── Google Maps/Directions API
    └── Vonage SMS (if needed)
    ↓ ~200-500ms total (parallel not sequential)
FastAPI emits WebSocket events to Flutter
    ├── agent_state event → mascot changes
    ├── screen_navigate event → tab switches
    ├── task_step events → progress card updates
    └── domain-specific events (map_route, call_started, etc.)
    ↓
Flutter UI updates across all layers simultaneously
```

**Why n8n is excluded from real-time path:**
n8n is HTTP-only with no WebSocket support and adds 2,000–3,500ms latency. It is used only for async post-shift workflows (report generation, data archiving) triggered after the shift ends.

---

## 8. Confirmed Tech Stack

| Layer | Technology | Version | Notes |
|-------|-----------|---------|-------|
| Frontend | Flutter | 3.x | Dart, Riverpod state |
| State management | Riverpod | ^2.0 | ConsumerWidget, StateNotifier |
| Mascot animation | Rive | ^0.12.0 | State Machine, SMIString |
| Maps | google_maps_flutter | ^2.5 | Custom pins, polylines |
| Backend | FastAPI | Latest | asyncio, WebSockets |
| Database | Supabase | Latest | Auth + data storage |
| Hosting | Railway | — | FastAPI deployment |
| Voice input | AssemblyAI Voice Agent API | — | ~$4.50/hr, core requirement |
| Post-shift AI | AssemblyAI Speech Understanding + LeMUR | — | Topic detection (failure patterns), sentiment, LeMUR report prompts + streaming summary. Not built yet |
| Outbound calls | LiveKit SIP/PSTN | Build tier | Free for hackathon |
| SMS | Vonage | Free trial | Global coverage |
| Logistics | Onfleet | — | MockAdapter fallback |

---

## 9. Performance Targets

| Metric | Target | Approach |
|--------|--------|----------|
| Voice → agent response | < 500ms | asyncio.gather parallel calls |
| Mascot state transition | < 100ms | Rive on Impeller thread |
| Screen navigation | < 100ms | Riverpod + AnimatedSwitcher |
| Map route draw | < 2s | Progressive polyline reveal |
| App cold start | < 3s | Lazy loading, minimal main.dart |
| LeMUR summary first token | < 3s | Streaming chunks, show progress |

---

## 10. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Rive file not ready in time | Medium | High | Use placeholder SVG mascot initially, swap .riv when ready |
| Google Maps API key quota | Low | Medium | Enable billing, use MockAdapter for demo |
| AssemblyAI latency spike | Low | High | Local fallback transcript for demo if needed |
| LiveKit call quality | Low | Medium | Call overlay UI works without real call for demo |
| Onfleet API limits | Medium | Low | MockAdapter returns realistic fake data |
| WebSocket drop during demo | Low | High | Auto-reconnect logic in FastAPI + Flutter |

