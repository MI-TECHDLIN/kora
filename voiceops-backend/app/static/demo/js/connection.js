// Thin WebSocket wrapper: JSON text frames and binary audio frames in, callbacks out.
// Reconnect policy lives in the controller (customer.js); this only reports what happened.

export class Connection {
  /**
   * @param {string} url
   * @param {{onOpen:()=>void, onJson:(data:string)=>void, onAudio:(buf:ArrayBuffer)=>void, onClose:(code:number)=>void}} h
   */
  constructor(url, h) {
    this.url = url;
    this.h = h;
    this.ws = null;
    this.gen = 0;
  }

  get isOpen() {
    return Boolean(this.ws) && this.ws.readyState === WebSocket.OPEN;
  }

  connect() {
    this.close();
    const gen = ++this.gen;
    let ws;
    try {
      ws = new WebSocket(this.url);
    } catch {
      queueMicrotask(() => gen === this.gen && this.h.onClose(1006));
      return;
    }
    ws.binaryType = "arraybuffer";
    this.ws = ws;
    ws.onopen = () => gen === this.gen && this.h.onOpen();
    ws.onmessage = (e) => {
      if (gen !== this.gen) return;
      if (typeof e.data === "string") this.h.onJson(e.data);
      else this.h.onAudio(e.data);
    };
    ws.onerror = () => {}; // onclose always follows and carries the code
    ws.onclose = (e) => {
      if (gen !== this.gen) return;
      this.ws = null;
      this.h.onClose(e.code);
    };
  }

  sendJson(obj) {
    if (this.isOpen) this.ws.send(JSON.stringify(obj));
  }

  sendBinary(buf) {
    // Drop audio rather than queue it when the socket is backed up: stale mic audio is worse than a gap.
    if (this.isOpen && this.ws.bufferedAmount < 64 * 1024) this.ws.send(buf);
  }

  close() {
    this.gen++; // silence the old socket's callbacks
    const ws = this.ws;
    this.ws = null;
    if (ws) {
      ws.onopen = ws.onmessage = ws.onerror = ws.onclose = null;
      try {
        ws.close(1000);
      } catch {
        // already closed
      }
    }
  }
}
