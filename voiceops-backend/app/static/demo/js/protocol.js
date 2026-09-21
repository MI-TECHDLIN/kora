// Wire protocol handling and the page's state machine. Pure and DOM-free.
// The contract is the "Wire protocol" section of the demo spec: this file is
// the only place that interprets server events.

import { CaptionModel } from "./captions.js";

export const CLOSE_BAD_CODE = 4401;

export const PHASE = Object.freeze({
  PAIRING: "pairing", // asking for the demo code
  CONNECTING: "connecting", // socket opening, hello sent
  WAITING: "waiting", // paired, idle
  RINGING: "ringing", // incoming call
  ANSWERING: "answering", // tapped Answer, mic + upstream session starting
  INCALL: "incall",
  SUMMARY: "summary",
  ERROR: "error",
});

export const ERROR_KIND = Object.freeze({
  BAD_CODE: "bad-code",
  MIC_DENIED: "mic-denied",
  MIC_MISSING: "mic-missing",
  DISCONNECTED: "disconnected",
  UNREACHABLE: "unreachable",
  SERVER: "server",
  UNSUPPORTED: "unsupported",
});

// A late "waiting" (e.g. after a reconnect) must not wipe a live call, a summary or an error.
const LIVE_OR_HELD = [PHASE.RINGING, PHASE.ANSWERING, PHASE.INCALL, PHASE.SUMMARY, PHASE.ERROR];

const END_REASONS = ["customer_hangup", "driver_hangup", "agent_done", "timeout", "error"];

/** Parse one JSON text frame. Returns null for anything that is not a known event. */
export function parseServerMessage(data) {
  let msg;
  try {
    msg = typeof data === "string" ? JSON.parse(data) : null;
  } catch {
    return null;
  }
  if (!msg || typeof msg !== "object" || typeof msg.event !== "string") return null;
  switch (msg.event) {
    case "waiting":
    case "connected":
    case "interrupted":
      return { event: msg.event };
    case "ring":
      return {
        event: "ring",
        caller: str(msg.caller) || "Kora",
        onBehalfOf: str(msg.on_behalf_of),
        customerName: str(msg.customer_name),
      };
    case "caption":
      return {
        event: "caption",
        speaker: msg.speaker,
        text: str(msg.text),
        final: msg.final === true,
      };
    case "ended":
      return {
        event: "ended",
        reason: END_REASONS.includes(msg.reason) ? msg.reason : "error",
        summary: normalizeSummary(msg.summary),
      };
    case "error":
      return { event: "error", message: str(msg.message) || "Something went wrong." };
    default:
      return null;
  }
}

function str(v) {
  return typeof v === "string" ? v.trim() : "";
}

function normalizeSummary(s) {
  if (!s || typeof s !== "object") return null;
  const headline = str(s.headline);
  const points = Array.isArray(s.points) ? s.points.map(str).filter(Boolean) : [];
  if (!headline && !points.length) return null;
  return { headline, points };
}

export function initialState({ code = "" } = {}) {
  return {
    phase: PHASE.PAIRING,
    code,
    ring: null, // {caller, onBehalfOf, customerName}
    captions: new CaptionModel(),
    summary: null,
    endReason: null,
    error: null, // {kind, message}
    muted: false,
    /** True while the reducer wants the audio agent to drop queued speech. */
    flushAudio: false,
    seq: 0,
  };
}

/**
 * Reducer. Never mutates the previous `state` object (the CaptionModel is the
 * one intentionally mutable member and is replaced when a call starts).
 * Actions:
 *   {type:"submit-code", code}      user entered / restored a code
 *   {type:"socket-open"}            transport open, hello has been sent
 *   {type:"socket-close", code}     transport closed
 *   {type:"server", msg}            parsed server event (parseServerMessage)
 *   {type:"answer"}                 tapped Answer
 *   {type:"decline"}                tapped Decline while ringing
 *   {type:"hangup"}                 tapped hang up during the call
 *   {type:"mic-failed", kind}       getUserMedia failed
 *   {type:"toggle-mute"}
 *   {type:"reset"}                  "Call again" / dismiss an error: back to waiting
 *   {type:"unreachable"}            gave up reconnecting on first connect
 */
export function reduce(state, action) {
  const next = { ...state, flushAudio: false, seq: state.seq + 1 };
  switch (action.type) {
    case "submit-code":
      return { ...next, code: action.code, phase: PHASE.CONNECTING, error: null };

    case "socket-open":
      return state.phase === PHASE.CONNECTING || state.phase === PHASE.PAIRING ? { ...next, phase: PHASE.CONNECTING } : next;

    case "socket-close": {
      if (action.code === CLOSE_BAD_CODE) {
        return { ...next, phase: PHASE.PAIRING, error: err(ERROR_KIND.BAD_CODE, "That code isn't right. Check it and try again.") };
      }
      switch (state.phase) {
        case PHASE.RINGING:
        case PHASE.ANSWERING:
        case PHASE.INCALL:
          return endCall(next, "error", null, err(ERROR_KIND.DISCONNECTED, "The connection dropped, so the call ended."));
        case PHASE.WAITING:
          return { ...next, phase: PHASE.CONNECTING }; // transport layer reconnects
        default:
          return next;
      }
    }

    case "server":
      return reduceServer(next, state, action.msg);

    case "answer":
      return state.phase === PHASE.RINGING ? { ...next, phase: PHASE.ANSWERING, captions: new CaptionModel(), muted: false } : next;

    case "decline":
      return state.phase === PHASE.RINGING ? { ...next, phase: PHASE.WAITING, ring: null } : next;

    case "hangup":
      if (state.phase === PHASE.INCALL || state.phase === PHASE.ANSWERING) {
        return endCall(next, "customer_hangup", state.summary, null);
      }
      return next;

    case "mic-failed":
      return {
        ...next,
        phase: PHASE.ERROR,
        ring: null,
        error:
          action.kind === "missing"
            ? err(ERROR_KIND.MIC_MISSING, "No microphone was found on this device.")
            : err(ERROR_KIND.MIC_DENIED, "Microphone access is blocked, so Kora can't hear you."),
      };

    case "toggle-mute":
      return state.phase === PHASE.INCALL ? { ...next, muted: !state.muted } : next;

    case "unreachable":
      return { ...next, phase: PHASE.ERROR, error: err(ERROR_KIND.UNREACHABLE, "Can't reach Kora right now. Check that the demo is running and try again.") };

    case "reset":
      return { ...next, phase: state.code ? PHASE.CONNECTING : PHASE.PAIRING, ring: null, summary: null, endReason: null, error: null, muted: false };

    default:
      return next;
  }
}

function reduceServer(next, prev, msg) {
  if (!msg) return next;
  switch (msg.event) {
    case "waiting":
      if (LIVE_OR_HELD.includes(prev.phase)) return next;
      return { ...next, phase: PHASE.WAITING, ring: null, error: null };

    case "ring":
      if (prev.phase === PHASE.INCALL || prev.phase === PHASE.ANSWERING) return next;
      return {
        ...next,
        phase: PHASE.RINGING,
        ring: { caller: msg.caller, onBehalfOf: msg.onBehalfOf, customerName: msg.customerName },
        captions: new CaptionModel(),
        summary: null,
        endReason: null,
        error: null,
      };

    case "connected":
      return prev.phase === PHASE.ANSWERING ? { ...next, phase: PHASE.INCALL } : next;

    case "caption": {
      if (prev.phase !== PHASE.INCALL && prev.phase !== PHASE.ANSWERING) return next;
      prev.captions.apply(msg);
      return { ...next, phase: prev.phase === PHASE.ANSWERING ? PHASE.INCALL : prev.phase };
    }

    case "interrupted":
      if (prev.phase === PHASE.INCALL || prev.phase === PHASE.ANSWERING) prev.captions.interrupt();
      return { ...next, flushAudio: true };

    case "ended":
      if (prev.phase === PHASE.WAITING || prev.phase === PHASE.CONNECTING || prev.phase === PHASE.PAIRING) {
        return next; // decline echo or stale event: nothing to show
      }
      return endCall(next, msg.reason, msg.summary, null);

    case "error":
      if (prev.phase === PHASE.RINGING || prev.phase === PHASE.ANSWERING || prev.phase === PHASE.INCALL) {
        return endCall(next, "error", null, err(ERROR_KIND.SERVER, msg.message));
      }
      return { ...next, phase: PHASE.ERROR, ring: null, error: err(ERROR_KIND.SERVER, msg.message) };

    default:
      return next;
  }
}

function endCall(next, reason, summary, error) {
  next.captions.finalizeAll();
  return { ...next, phase: PHASE.SUMMARY, ring: next.ring, summary: summary || null, endReason: reason, error, flushAudio: true };
}

function err(kind, message) {
  return { kind, message };
}

/** Headline shown on the summary card when the server sent no summary. */
export function fallbackHeadline(reason) {
  switch (reason) {
    case "customer_hangup":
      return "You ended the call";
    case "driver_hangup":
      return "The driver ended the call";
    case "timeout":
      return "The call reached its time limit";
    case "error":
      return "The call couldn't be completed";
    default:
      return "Call finished";
  }
}

/** "0:07", "12:03" */
export function formatDuration(totalSeconds) {
  const s = Math.max(0, Math.floor(totalSeconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/** Build the WebSocket URL for the page's own origin. */
export function socketUrl(loc, path = "/ws/demo/customer") {
  const scheme = loc.protocol === "https:" ? "wss:" : "ws:";
  return `${scheme}//${loc.host}${path}`;
}

/** Reconnect delay: 1s, 2s, 4s, capped at 8s, with a little jitter. */
export function backoffDelay(attempt, random = Math.random) {
  const base = Math.min(8000, 1000 * 2 ** Math.max(0, attempt));
  return Math.round(base * (0.85 + random() * 0.3));
}
