// A tiny RFC 6455 server side, built-ins only (Node has a WebSocket client but no server).
// Enough for the mock: text/binary messages, fragmentation, ping/pong, close codes.

import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/** Encode one unmasked server frame. */
export function encodeFrame(opcode, payload) {
  const len = payload.length;
  let header;
  if (len < 126) header = Buffer.from([0x80 | opcode, len]);
  else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

/** Incremental frame decoder for client (masked) frames. */
export class FrameDecoder {
  constructor() {
    this.buf = Buffer.alloc(0);
  }

  /** @returns {{fin:boolean, opcode:number, payload:Buffer}[]} */
  push(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    const out = [];
    for (;;) {
      const b = this.buf;
      if (b.length < 2) break;
      const fin = (b[0] & 0x80) !== 0;
      const opcode = b[0] & 0x0f;
      const masked = (b[1] & 0x80) !== 0;
      let len = b[1] & 0x7f;
      let off = 2;
      if (len === 126) {
        if (b.length < 4) break;
        len = b.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (b.length < 10) break;
        len = Number(b.readBigUInt64BE(2));
        off = 10;
      }
      const maskLen = masked ? 4 : 0;
      if (b.length < off + maskLen + len) break;
      const payload = Buffer.from(b.subarray(off + maskLen, off + maskLen + len));
      if (masked) {
        const m = b.subarray(off, off + 4);
        for (let i = 0; i < payload.length; i++) payload[i] ^= m[i & 3];
      }
      out.push({ fin, opcode, payload });
      this.buf = b.subarray(off + maskLen + len);
    }
    return out;
  }
}

export class WsPeer extends EventEmitter {
  constructor(socket) {
    super();
    this.socket = socket;
    this.decoder = new FrameDecoder();
    this.fragments = [];
    this.fragOpcode = 0;
    this.closed = false;
    socket.on("data", (d) => this.#onData(d));
    socket.on("close", () => this.#finish(1006));
    socket.on("error", () => {});
  }

  sendText(text) {
    this.#write(encodeFrame(0x1, Buffer.from(text)));
  }

  sendJson(obj) {
    this.sendText(JSON.stringify(obj));
  }

  sendBinary(buf) {
    this.#write(encodeFrame(0x2, Buffer.from(buf)));
  }

  close(code = 1000) {
    if (this.closed) return;
    const p = Buffer.alloc(2);
    p.writeUInt16BE(code, 0);
    this.#write(encodeFrame(0x8, p));
    this.socket.end();
    this.#finish(code);
  }

  #write(frame) {
    if (!this.closed && this.socket.writable) this.socket.write(frame);
  }

  #finish(code) {
    if (this.closed) return;
    this.closed = true;
    this.emit("close", code);
  }

  #onData(chunk) {
    for (const f of this.decoder.push(chunk)) {
      if (f.opcode === 0x8) {
        const code = f.payload.length >= 2 ? f.payload.readUInt16BE(0) : 1005;
        this.#write(encodeFrame(0x8, f.payload.subarray(0, 2)));
        this.socket.end();
        this.#finish(code);
      } else if (f.opcode === 0x9) this.#write(encodeFrame(0xa, f.payload));
      else if (f.opcode === 0xa) continue;
      else {
        if (f.opcode !== 0) this.fragOpcode = f.opcode;
        this.fragments.push(f.payload);
        if (f.fin) {
          const data = Buffer.concat(this.fragments);
          this.fragments = [];
          this.emit("message", this.fragOpcode === 0x1 ? data.toString("utf8") : data, this.fragOpcode === 0x2);
        }
      }
    }
  }
}

/** Complete the HTTP upgrade handshake and return a WsPeer. */
export function acceptUpgrade(req, socket) {
  const key = req.headers["sec-websocket-key"];
  if (!key) {
    socket.destroy();
    return null;
  }
  const accept = createHash("sha1").update(key + GUID).digest("base64");
  socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  return new WsPeer(socket);
}
