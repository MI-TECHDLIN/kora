# VoiceOps — Project Synopsis v2
*For sharing with teammates, collaborators, or anyone who needs the full picture fast.*

---on

## What is VoiceOps?

VoiceOps is a voice-first AI agent built for last-mile delivery drivers. You speak one command, and the agent handles everything simultaneously — checking your route, contacting the customer, updating task status, sending an SMS — all in parallel, all hands-free.

The driver never touches the phone.

---

## The Big Idea

Most delivery apps treat the driver like someone sitting at a desk. VoiceOps treats them like someone doing 60km/h through traffic. The entire experience is designed around voice, and an expressive animated AI mascot makes it feel like you're talking to something genuinely intelligent — not just a chatbot.

The mascot isn't decorative. It changes emotion based on what the agent is actually doing. When it's thinking, it looks like it's thinking. When it's calling a customer, it looks like it's calling. When the task is done, it celebrates. The driver always knows what's happening without looking at text.

---

## The Signature Feature: Agent-Driven Navigation

The app navigates itself. When you ask about your route, the app automatically goes to the map screen and draws the route in real time. When you ask for your shift summary, it goes to the summary screen and generates it in front of you. The driver never has to switch screens manually.

A live task progress card slides up whenever the agent is working, showing each step as it happens — just like watching Claude search and process. The driver sees everything.

---

## The Screens

**Onboarding (3 screens)** — Fast, judge-friendly intro. The mascot shows a different emotion on each screen. Judges understand the product in under 60 seconds.

**Main Driver UI** — Where the driver lives. Voice input at the bottom, mascot center stage, task progress card slides up over the action buttons when the agent fires.

**Map Screen** — The agent navigates here automatically for location tasks. Delivery pins drop one by one. The route line draws itself. ETA slides up when ready. The mascot shrinks to a floating bubble in the corner.

**Summary Screen** — Post-shift intelligence powered by AssemblyAI LeMUR. Stats count up, AI narrative appears like a typewriter, customer highlights surface. The mascot is relaxed and celebrating.

**Settings** — Driver profile, voice preferences, connected platforms (Onfleet, Vonage, LiveKit).

---

## The Tech

- **AssemblyAI Voice Agent API** — The core of everything. Real-time voice transcription and intent extraction. This is the mandatory hackathon technology and it's front and center in the product.
- **AssemblyAI LeMUR** — Generates the post-shift summary by analyzing the full shift transcript.
- **FastAPI + asyncio** — The backend brain. Runs all tool calls in parallel (not one by one), keeping response time under 500ms.
- **Flutter + Riverpod** — The frontend. One codebase, clean state management, smooth 60fps animations.
- **Rive** — The mascot animation engine. A State Machine in Rive means Flutter can trigger emotion changes in under 100ms just by sending a string.
- **LiveKit** — Outbound customer calls via SIP/PSTN on the free tier.
- **Vonage** — Global SMS, free trial.
- **Google Maps** — Routing and live map animations.
- **Supabase** — Auth and data storage.
- **Railway** — FastAPI hosting.
- **Onfleet** — Logistics platform with MockAdapter fallback.

**What we deliberately dropped:**
- n8n from the real-time path (too slow — HTTP only, 2-3s latency vs 200ms with asyncio)
- Twilio (too expensive)
- Africa's Talking (regional only, VoiceOps is global)ad
- Lottie for the mascot (no interactive state machine support)
- Spline/Blender (too heavy for mobile)

---

## The Team

**me** — Flutter frontend, UI/UX, mascot design pipeline (Figma → Rive → Flutter)
**Teammate** — FastAPI backend, agentic workflows, AssemblyAI integration, WebSocket event system

Clear separation. Defined interface contract. No stepping on each other.

---

## Timeline

- **Sept 14** — Core voice pipeline alive end-to-end (speak → FastAPI → log)
- **Sept 18** — Agent-driven navigation working, map screen populating from voice
- **Sept 22** — All screens complete, Rive mascot integrated
- **Sept 27** — Polish, demo rehearsal, submission prep
- **Sept 30** — Submission deadline

---

## What Judges Will See in the Demo

A driver says one voice command. The app navigates itself to the right screen. The mascot changes emotion. A progress card shows each step the agent is executing in real time. The task completes. The mascot celebrates. The whole thing takes about 8 seconds and requires zero manual interaction.

That's the demo. That's VoiceOps.

