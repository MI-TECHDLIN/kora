// State for the read-only stage (projector) view. Mirrors the customer events
// without audio; pure, so it is unit tested.

import { CaptionModel } from "./captions.js";

export const STAGE = Object.freeze({ CONNECTING: "connecting", WAITING: "waiting", RINGING: "ringing", LIVE: "live", ENDED: "ended" });

export function initialStage() {
  return { phase: STAGE.CONNECTING, ring: null, captions: new CaptionModel(), summary: null, endReason: null, speaking: false, startedAt: null, error: "" };
}

/** @param {object} s @param {object|null} msg parsed server event (protocol.parseServerMessage) @param {number} now ms */
export function stageReduce(s, msg, now = 0) {
  if (!msg) return s;
  switch (msg.event) {
    case "waiting":
      // Keep the finished call on screen until the next ring, so the audience can read the summary.
      return s.phase === STAGE.ENDED || s.phase === STAGE.LIVE || s.phase === STAGE.RINGING ? s : { ...s, phase: STAGE.WAITING, error: "" };
    case "ring":
      return { ...initialStage(), phase: STAGE.RINGING, ring: { onBehalfOf: msg.onBehalfOf, customerName: msg.customerName } };
    case "connected":
      return { ...s, phase: STAGE.LIVE, startedAt: now };
    case "caption":
      if (s.phase !== STAGE.LIVE && s.phase !== STAGE.RINGING) return s;
      s.captions.apply(msg);
      return { ...s, phase: STAGE.LIVE, startedAt: s.startedAt ?? now, speaking: msg.speaker === "agent" && !msg.final };
    case "interrupted":
      s.captions.interrupt();
      return { ...s, speaking: false };
    case "ended":
      s.captions.finalizeAll();
      return { ...s, phase: STAGE.ENDED, summary: msg.summary, endReason: msg.reason, speaking: false };
    case "error":
      return { ...s, error: msg.message };
    default:
      return s;
  }
}
