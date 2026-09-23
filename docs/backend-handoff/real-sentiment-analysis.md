# Design handoff — Honest sentiment scoring in the shift report

**For:** Maria (FastAPI + agentic workflows) · **Written:** 2026-09-17
**Status:** design doc; fixes 1 and 2 are implemented since, see the status update below.

> **Status update (2026-09-21, checked against the code on `staging`):** fixes 1 and 2 in §3 have
> landed in `app/intelligence/lemur_pipeline.py`: the fallback summary is prefixed as an estimate,
> `lemur_source` and `is_estimated` are surfaced at the root of `GET /v1/shift/{id}/report`, and
> the hardcoded Lagos list is gone. Still open: fix 3 (real Speech Understanding sentiment, which
> needs audio the app does not store; nothing calls it yet) and fix 4 (the pipeline still sends
> `anthropic/claude-3-5-sonnet`).

---

## TL;DR

The Summary screen's sentiment score is not what it appears to be, in two
different ways depending on which code path runs — and the project's own
"global, not regional" decision is being quietly violated in one of them.
Neither of these needs new infrastructure to fix; both are prompt/code
changes in `app/intelligence/lemur_pipeline.py`.

---

## 1. What actually happens today (verified by reading the code, not assuming)

`analyze_with_lemur()` in `app/intelligence/lemur_pipeline.py` has two paths:

### Path A — LeMUR call succeeds (the common case)

A real HTTP call goes to AssemblyAI's LeMUR endpoint. **This part is genuine
AssemblyAI usage.** But the prompt (`:99-107`) simply asks the underlying LLM
(`final_model: anthropic/claude-3-5-sonnet`) to *invent* a
`sentiment_score` as one field of a JSON blob: *"float from 0.0 to 1.0
reflecting driver confidence and calm."* That's an LLM's text-based guess
from a transcript, not AssemblyAI's dedicated **Speech Understanding
sentiment_analysis** feature — a separate, audio-aware model that scores
actual speech (tone, pacing) per utterance as POSITIVE/NEGATIVE/NEUTRAL
with a confidence value. The app never calls that endpoint at all (see
`FEATURE_STATUS.md` — `assemblyai_transcription_url` is defined in
`config.py` and never referenced anywhere else in the codebase).

So even on the "working" path, a precise-looking number like "82%
positive alignment" is an LLM's guess dressed as a measurement, not
something AssemblyAI's speech-analysis models actually measured from the
driver's voice.

### Path B — LeMUR call fails (`_fallback_nlp_analysis`, `:149-210`)

Triggered on **any** exception calling LeMUR — timeout, non-200, network
hiccup during a live demo. This path has **zero connection to any AI or
AssemblyAI API**:

```python
sentiment_score = 0.90
sentiment_score -= (len(incidents) * 0.08)
sentiment_score -= (failed_count * 0.05)
```

It's arithmetic on a keyword count, presented through the exact same
`"Overall sentiment scored at {int(sentiment_score * 100)}% positive
alignment."` sentence as the real path — a reader (or a judge) cannot
tell the two apart from the output alone.

**Worse: this fallback hardcodes Lagos, Nigeria locations** (`:174` -
`lagos_locations = ["broad street", "marina", "victoria island", "ikoyi",
"lekki", "yaba", "ikeja"]`) to detect "route issues." This directly
contradicts the project's own settled decision: *"VoiceOps [Kora] is
global, not Africa-specific"* (AGENTS.md's Tech Stack section) — the same
principle that got Africa's Talking dropped entirely. A driver in any
other city gets zero route-issue detection from this fallback, silently.

---

## 2. Why this matters for the hackathon specifically

The hackathon's whole premise is genuine AssemblyAI usage, not a wrapper
that occasionally calls an API and otherwise fakes its output. Right now:
- A LeMUR outage during a live demo silently degrades to fabricated
  numbers with no visible signal that anything changed.
- Even the non-degraded path presents an LLM's guess as if it were
  AssemblyAI's dedicated speech-sentiment product — understating what the
  *real* dual-integration story could be.

---

## 3. Proposed fixes, roughly in priority order

1. **Make the fallback visibly a fallback.** At minimum, don't reuse the
   exact same sentence template for both paths — e.g. prefix the fallback
   summary with something like *"(estimated while AI analysis was
   unavailable)"*, and consider surfacing `lemur_source` (already computed:
   `"assemblyai_lemur_api"` vs `"voiceops_speech_intelligence_engine"`) to
   the frontend so it can show a small "estimated" badge rather than
   presenting both as equally authoritative. The field already exists in
   `report_payload["failure_patterns"]["lemur_source"]` - it's just never
   read by anything today.
2. **Remove the Lagos-only location list from the fallback**, or replace
   it with something that doesn't silently favor one city. If a
   location-based route-issue heuristic is wanted for the fallback path at
   all, derive it from the delivery addresses already in Supabase for that
   shift, not a hardcoded city list — that's actually global by
   construction instead of by exclusion.
3. **Consider whether real Speech Understanding sentiment analysis is
   worth adding for Path A.** This is the bigger decision: AssemblyAI's
   sentiment_analysis parameter operates on submitted audio via their
   async transcription endpoint (`POST /v2/transcript`), not on
   already-transcribed text. Today the app only stores the driver/agent
   **transcript text** from the live Voice Agent session
   (`get_shift_voice_sessions`), not the raw audio — so wiring real
   sentiment analysis would mean deciding whether to start persisting
   session audio for post-shift re-analysis (storage + privacy tradeoff)
   or accept that LeMUR's transcript-based estimate is what's
   realistically achievable here. Either answer is legitimate; the
   important thing is picking one on purpose and describing it accurately
   to end users and judges, rather than an unlabeled guess masquerading as
   a measurement.
4. **Minor:** the LeMUR `final_model` is `anthropic/claude-3-5-sonnet`;
   this project's docs elsewhere reference `anthropic/claude-sonnet-5` as
   current. Worth checking against AssemblyAI's actual supported-model
   list for LeMUR before the deadline, independent of the sentiment issue.

---

## 4. What's explicitly NOT being asked here

This doc is not asking for a full Speech Understanding integration by
Sep 30 if that's not realistic — item 1 and 2 above are small, low-risk
fixes that remove the misleading parts without needing a scope decision.
Item 3 is the one genuine "decide, then implement" question; 1 and 2 are
safe to just do.
