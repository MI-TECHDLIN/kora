# VoiceOps — Product Requirements Document v4.0
**Hackathon:** AssemblyAI Voice Agent Hackathon (lablab.ai) | Sept 1–30, 2026 | $10,000 prize pool
**Last updated:** September 2026

---

## 1. Product Vision

VoiceOps is a voice-first autonomous agent platform for last-mile logistics drivers. A single voice command triggers parallel tool execution across logistics platforms, maps, customer communication, and shift intelligence — all surfaced through an expressive animated AI mascot that gives drivers a genuine sense of communicating with an intelligent presence.

Drivers never touch their phone. The agent navigates the app for them.

---

## 2. Problem Statement

Last-mile delivery drivers operate in high-pressure, hands-free environments. Existing logistics apps require constant manual interaction — checking maps, calling customers, updating task statuses — all while driving. VoiceOps eliminates that friction entirely through a persistent voice agent that sees, acts, and communicates across the entire app autonomously.

---

## 3. Target Users

- Last-mile delivery drivers using Onfleet or similar logistics platforms
- Drivers managing 10–40 stops per shift
- Hackathon judges evaluating voice AI + autonomous agent capability

---

## 4. Core Features

### 4.1 Voice Agent (Primary)
- Always-on voice input via AssemblyAI Voice Agent API
- Single command triggers parallel tool calls simultaneously
- Real-time task progress visible to driver at all times
- Hands-free from session start to shift end

### 4.2 Expressive AI Mascot
- Rive-animated character with full State Machine
- 8+ distinct emotional states tied directly to agent events
- Persistent floating overlay — travels across all screens with the agent
- Emotion changes on every state transition (idle → thinking → executing → done)

### 4.3 Agent-Driven Navigation (Signature Feature)
- App navigates itself based on what the agent is doing
- No manual screen switching required by the driver
- Agent goes to map screen when routing, summary screen when reporting, call overlay when calling
- Mascot follows the agent to every screen as a persistent overlay

### 4.4 Live Task Progress Card
- Slides up from bottom when agent begins work
- Shows step-by-step agent actions in real time
- Spinning ring for active step, checkmark for completed, dim for pending
- "All complete" badge when done, card slides back down

### 4.5 Map Screen (Agent-Controlled)
- Google Maps integration with live delivery stops
- Route line draws itself with animated dash effect when agent navigates
- Delivery pins drop sequentially as agent processes stops
- ETA card slides up on route completion
- Voice button overlay so driver stays voice-first on map screen
- Mascot floats as compact bubble in corner during map tasks

### 4.6 Post-Shift Summary (LeMUR Powered)
- Triggered by voice ("give me my summary") or end-of-shift detection
- AssemblyAI LeMUR generates intelligent shift narrative
- Summary cards appear one by one as LeMUR processes
- Stats animate counting up (deliveries, distance, duration)
- Flagged issues, customer interaction highlights
- Mascot in relaxed/celebrating emotion throughout

### 4.7 Onboarding Flow (3 Screens) — Finalized Concept v1
**Mascot is referred to as the driver's "co-rider" throughout onboarding and in-app copy** — not "co-pilot" (implies hierarchy/cockpit) or "assistant" (too generic). Locked terminology, September 2026.

Visual material for onboarding: **holographic bubble orb** (translucent, iridescent, continuous hue-rotation) — distinct from the chrome/mercury orb used in the main app (see §4.2).

- **Screen 1 — The Hook** (dark navy background)
  - Eyebrow pill: "Waking up your co-rider"
  - Orb: breathing gently at rest, warm and unhurried
  - Headline: "Say the word. It's already moving."
  - Subtext: "One sentence starts your whole shift — no taps, no glancing down."
- **Screen 2 — The Power** (lavender gradient background)
  - Header: avatar + "Hello, [Name] — here's what it caught already"
  - Layered card stack (not a flat grid): "Next stop" card behind, "Mic access" action-required card in front (red dot, explains *why*: "so it can hear you over road noise"), colorful holographic "Live route" teaser card peeking from the side
  - Headline: "Three things happen at once. You do nothing."
- **Screen 3 — The Trust** (dark navy background)
  - Check pill: "✓ Voice calibrated"
  - Orb settles, smaller and calmer
  - Headline: "It knows your voice. Time to drive."
  - Stat row confirms readiness: Voice: Ready · Route: Loaded · Hands: Free
  - CTA card: "Your voice, your co-rider" + "Start driving →" button
- Swipeable with progress dots, no skip button
- Copy is grounded in an actual driver's moment, not generic AI-assistant language

### 4.8 Settings & Preferences
- Driver profile
- Voice language preference
- Notification settings
- Connected platform configuration (Onfleet)
- SMS/call preferences (Vonage)

---

## 5. Screen Inventory

| Screen | Type | Mascot Emotion | Agent Role |
|--------|------|---------------|-----------|
| Onboarding 1 | Static flow | Excited / welcoming | N/A |
| Onboarding 2 | Animated | Focused / working | Demo only |
| Onboarding 3 | Static flow | Happy / celebrating | N/A |
| Main Driver UI | Primary | All states | Always active |
| Map Screen | Agent-driven | Compact bubble / navigating | Route + location tasks |
| Summary Screen | Agent-driven | Relaxed / analyzing | LeMUR post-shift |
| Settings | Manual | Idle bubble | Passive |

---

## 6. Agent-Driven Navigation Flow

```
Driver speaks command
        ↓
AssemblyAI transcribes → FastAPI receives intent
        ↓
Agent identifies required screen context
        ↓
FastAPI emits screen_navigate event to Flutter
        ↓
Flutter navigates to relevant screen automatically
        ↓
Mascot transitions emotion + floats to new screen
        ↓
Task progress card shows live agent steps
        ↓
Agent completes → mascot celebrates → card closes
```

---

## 7. Voice Command → Screen Mapping

| Voice Command | Auto-Navigate To | Agent Action |
|--------------|-----------------|--------------|
| "Find my next stop" | Map Screen | Route calculation + pin drop |
| "Navigate to stop 3" | Map Screen | Live turn-by-turn |
| "Call the customer" | Call Overlay | LiveKit SIP outbound |
| "What's left on my list" | Task overlay on current screen | Onfleet task fetch |
| "Give me my summary" | Summary Screen | LeMUR processing |
| "Update my status" | Stays on current | Onfleet status update |

---

## 8. AssemblyAI Integration Requirements

| Feature | AssemblyAI Product | Notes |
|---------|-------------------|-------|
| Real-time voice input | Voice Agent API | ~$4.50/hr, primary interaction |
| Post-shift summary | Speech Understanding + LeMUR | Async, triggered end-of-shift |
| Shift transcript | Speech-to-Text | Stored in Supabase |

AssemblyAI is a **mandatory core technology** per hackathon rules. It must be prominently featured in the demo.

---

## 9. Non-Functional Requirements

- Voice response latency: < 500ms (FastAPI asyncio.gather parallel execution)
- Map route draw animation: < 2s after command
- Mascot state transition: < 100ms (Rive State Machine)
- Onboarding completion: < 60 seconds
- App cold start: < 3 seconds

---

## 10. Out of Scope (Hackathon)

- Multi-driver fleet management
- Offline-first full sync
- Custom logistics platform integrations beyond Onfleet
- Turn-by-turn audio navigation (visual only for hackathon)
- n8n real-time workflows (async post-shift only)

---

## 11. Success Criteria (Hackathon Demo)

- [ ] Judge speaks a command and watches the app act autonomously
- [ ] Mascot visibly changes emotion during agent execution
- [ ] Map screen populates itself from a voice command
- [ ] Task progress card shows live steps in real time
- [ ] Post-shift summary generates from LeMUR with animated reveal
- [ ] Onboarding communicates the product in under 60 seconds
- [ ] AssemblyAI is clearly the core technology powering voice input

