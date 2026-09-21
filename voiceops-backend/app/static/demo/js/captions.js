// Caption model: turns a stream of interim/final caption events into an
// ordered list of lines, one open line per speaker.

const MAX_LINES = 40;

export class CaptionModel {
  constructor(max = MAX_LINES) {
    this.max = max;
    this.lines = [];
    this.seq = 0;
  }

  /** @returns {object|null} the affected line, or null if the event was ignored. */
  apply({ speaker, text, final }) {
    if (speaker !== "agent" && speaker !== "customer") return null;
    const clean = typeof text === "string" ? text.trim() : "";
    if (!clean) return null;
    let line = this.#openLine(speaker);
    if (!line) {
      line = { id: ++this.seq, speaker, text: clean, final: false, interrupted: false };
      this.lines.push(line);
      if (this.lines.length > this.max) this.lines.shift();
    } else {
      line.text = clean;
    }
    if (final) line.final = true;
    return line;
  }

  /** Customer talked over Kora: her current line is cut off. */
  interrupt() {
    const line = this.#openLine("agent");
    if (!line) return null;
    line.final = true;
    line.interrupted = true;
    return line;
  }

  /** Close every open line, e.g. when the call ends. */
  finalizeAll() {
    for (const l of this.lines) l.final = true;
  }

  clear() {
    this.lines = [];
  }

  #openLine(speaker) {
    for (let i = this.lines.length - 1; i >= 0; i--) {
      const l = this.lines[i];
      if (l.speaker === speaker) return l.final ? null : l;
    }
    return null;
  }
}
