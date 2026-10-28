import { socket } from '@kit.NetworkKit';

export interface SseHandlers {
  onFrame(json: string): void;
  onEventId(id: string): void;
  onState(state: string): void;
}

const BACKOFF_STEPS: number[] = [1000, 2000, 5000, 10000, 30000];

/**
 * 与电脑已有的 /api/events 事件流对接：HTTP GET + 逐帧解析，
 * 断开后按递增退避自动重连，并在重连时携带 Last-Event-ID 续传。
 */
export class SseClient {
  private handlers: SseHandlers;
  private baseUrl: string = '';
  private token: string = '';
  private host: string = '';
  private port: number = 8810;
  private useTls: boolean = false;
  private tcp: socket.TCPSocket | null = null;
  private tls: socket.TLSSocket | null = null;
  private stopped: boolean = true;
  private headerDone: boolean = false;
  private chunked: boolean = false;
  private chunkRemain: number = -1;
  private bodyBytes: number[] = [];
  private frameBytes: number[] = [];
  private lastEventId: string = '';
  private backoffIndex: number = 0;
  private reconnectTimer: number = -1;

  constructor(baseUrl: string, token: string, handlers: SseHandlers) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.token = token;
    this.handlers = handlers;
    this.parseUrl();
  }

  setToken(token: string): void {
    this.token = token;
  }

  start(): void {
    this.stopped = false;
    this.backoffIndex = 0;
    this.connectOnce();
  }

  stop(): void {
    this.stopped = true;
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    this.teardownSocket();
    this.handlers.onState('idle');
  }

  private parseUrl(): void {
    const lower = this.baseUrl.toLowerCase();
    this.useTls = lower.startsWith('https://');
    let rest = this.baseUrl.replace(/^https?:\/\//i, '');
    const slash = rest.indexOf('/');
    if (slash >= 0) {
      rest = rest.slice(0, slash);
    }
    let hostPart = rest;
    if (hostPart.startsWith('[')) {
      const close = hostPart.indexOf(']');
      if (close >= 0) {
        this.host = hostPart.slice(1, close);
        const after = hostPart.slice(close + 1);
        if (after.startsWith(':')) {
          this.port = parseInt(after.slice(1), 10);
        }
        return;
      }
    }
    const colon = hostPart.lastIndexOf(':');
    if (colon > 0 && hostPart.indexOf(':') === colon) {
      this.host = hostPart.slice(0, colon);
      const parsed = parseInt(hostPart.slice(colon + 1), 10);
      if (!Number.isNaN(parsed)) {
        this.port = parsed;
      }
    } else {
      this.host = hostPart;
      this.port = this.useTls ? 443 : 80;
    }
  }

  private connectOnce(): void {
    this.handlers.onState(this.backoffIndex === 0 ? 'connecting' : 'reconnecting');
    this.teardownSocket();
    this.headerDone = false;
    this.chunked = false;
    this.chunkRemain = -1;
    this.bodyBytes = [];
    this.frameBytes = [];
    if (this.useTls) {
      this.connectTls();
    } else {
      this.connectTcp();
    }
  }

  private connectTcp(): void {
    const tcp = socket.constructTCPSocketInstance();
    this.tcp = tcp;
    tcp.on('message', (info: socket.SocketMessageInfo) => {
      this.consume(new Uint8Array(info.message));
    });
    tcp.on('close', () => {
      this.onDrop();
    });
    tcp.on('error', () => {
      this.onDrop();
    });
    const target: socket.NetAddress = { address: this.host, port: this.port };
    const request: string = this.buildRequest();
    const sendOptions: socket.TCPSendOptions = { data: request };
    tcp.connect({ address: target, timeout: 6000 }).then((): void => {
      tcp.send(sendOptions).catch((): void => {
        this.onDrop();
      });
    }).catch((): void => {
      this.onDrop();
    });
  }

  private connectTls(): void {
    const tls = socket.constructTLSSocketInstance();
    this.tls = tls;
    tls.on('message', (info: socket.SocketMessageInfo) => {
      this.consume(new Uint8Array(info.message));
    });
    tls.on('close', () => {
      this.onDrop();
    });
    tls.on('error', () => {
      this.onDrop();
    });
    const target: socket.NetAddress = { address: this.host, port: this.port };
    const secure: socket.TLSSecureOptions = {};
    const connectOptions: socket.TLSConnectOptions = { address: target, secureOptions: secure };
    const request: string = this.buildRequest();
    tls.connect(connectOptions).then((): void => {
      tls.send(request).catch((): void => {
        this.onDrop();
      });
    }).catch((): void => {
      this.onDrop();
    });
  }

  private buildRequest(): string {
    const hostHeader = this.port === 80 || this.port === 443 ? this.host : `${this.host}:${this.port}`;
    const lines: string[] = [
      'GET /api/events HTTP/1.1',
      `Host: ${hostHeader}`,
      'Accept: text/event-stream',
      'Cache-Control: no-cache',
      `Authorization: Bearer ${this.token}`,
      'x-openmausbot-companion: 1'
    ];
    if (this.lastEventId.length > 0) {
      lines.push(`Last-Event-ID: ${this.lastEventId}`);
    }
    lines.push('Connection: keep-alive');
    return `${lines.join('\r\n')}\r\n\r\n`;
  }

  private teardownSocket(): void {
    if (this.tcp !== null) {
      this.tcp.off('message');
      this.tcp.off('close');
      this.tcp.off('error');
      this.tcp.close().catch(() => {
      });
      this.tcp = null;
    }
    if (this.tls !== null) {
      this.tls.off('message');
      this.tls.off('close');
      this.tls.off('error');
      this.tls.close().catch(() => {
      });
      this.tls = null;
    }
  }

  private onDrop(): void {
    if (this.stopped) {
      return;
    }
    this.teardownSocket();
    this.scheduleReconnect();
  }

  private scheduleReconnect(): void {
    const step = BACKOFF_STEPS[this.backoffIndex < BACKOFF_STEPS.length ? this.backoffIndex : BACKOFF_STEPS.length - 1];
    this.backoffIndex += 1;
    this.handlers.onState('reconnecting');
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      if (!this.stopped) {
        this.connectOnce();
      }
    }, step);
  }

  private consume(bytes: Uint8Array): void {
    for (let i = 0; i < bytes.length; i++) {
      this.bodyBytes.push(bytes[i]);
    }
    this.pump();
  }

  private pump(): void {
    if (!this.headerDone) {
      const headerEnd = this.indexOfPair(this.bodyBytes, 13, 10, 13, 10);
      if (headerEnd < 0) {
        return;
      }
      const headerText = utf8Decode(this.bodyBytes.slice(0, headerEnd));
      this.bodyBytes = this.bodyBytes.slice(headerEnd + 4);
      this.headerDone = true;
      const statusMatch = /^HTTP\/1\.[01] (\d+)/.exec(headerText);
      const status = statusMatch !== null ? parseInt(statusMatch[1], 10) : 0;
      this.chunked = /transfer-encoding:\s*chunked/i.test(headerText);
      if (status < 200 || status >= 300) {
        this.onDrop();
        return;
      }
      this.backoffIndex = 0;
      this.handlers.onState('online');
    }
    if (this.chunked) {
      this.pumpChunked();
    } else {
      this.appendFrameBytes(this.bodyBytes);
      this.bodyBytes = [];
    }
    this.pumpFrames();
  }

  private pumpChunked(): void {
    let progressed = true;
    while (progressed) {
      progressed = false;
      if (this.chunkRemain < 0) {
        const lineEnd = this.indexOfPair(this.bodyBytes, 13, 10);
        if (lineEnd >= 0) {
          const sizeText = utf8Decode(this.bodyBytes.slice(0, lineEnd)).trim();
          const size = parseInt(sizeText.split(';')[0], 16);
          this.bodyBytes = this.bodyBytes.slice(lineEnd + 2);
          if (Number.isNaN(size)) {
            this.onDrop();
            return;
          }
          this.chunkRemain = size;
          progressed = true;
        }
      } else {
        const need = this.chunkRemain === 0 ? 2 : this.chunkRemain + 2;
        if (this.bodyBytes.length >= need) {
          if (this.chunkRemain > 0) {
            this.appendFrameBytes(this.bodyBytes.slice(0, this.chunkRemain));
          }
          this.bodyBytes = this.bodyBytes.slice(this.chunkRemain + 2);
          this.chunkRemain = -1;
          progressed = true;
        }
      }
    }
  }

  private appendFrameBytes(bytes: number[]): void {
    for (let i = 0; i < bytes.length; i++) {
      this.frameBytes.push(bytes[i]);
    }
  }

  private pumpFrames(): void {
    while (true) {
      const at = this.indexOfNewlinePair(this.frameBytes);
      if (at < 0) {
        return;
      }
      const chunk = this.frameBytes.slice(0, at);
      this.frameBytes = this.frameBytes.slice(at + 2);
      const text = utf8Decode(chunk);
      this.handleFrameText(text);
    }
  }

  private handleFrameText(text: string): void {
    if (text.length === 0) {
      return;
    }
    const lines = text.split('\n');
    const dataLines: string[] = [];
    for (const rawLine of lines) {
      const line = rawLine.endsWith('\r') ? rawLine.slice(0, rawLine.length - 1) : rawLine;
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.push(line.slice(5).trimStart());
      } else if (line.startsWith('id:')) {
        const id = line.slice(3).trim();
        if (id.length > 0) {
          this.lastEventId = id;
          this.handlers.onEventId(id);
        }
      }
    }
    if (dataLines.length > 0) {
      this.handlers.onFrame(dataLines.join('\n'));
    }
  }

  private indexOfPair(bytes: number[], first: number, second: number, third: number = -1, fourth: number = -1): number {
    const pairLen = third >= 0 ? 4 : 2;
    for (let i = 0; i + pairLen <= bytes.length; i++) {
      if (bytes[i] === first && bytes[i + 1] === second) {
        if (pairLen === 2) {
          return i;
        }
        if (bytes[i + 2] === third && bytes[i + 3] === fourth) {
          return i;
        }
      }
    }
    return -1;
  }

  private indexOfNewlinePair(bytes: number[]): number {
    for (let i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] === 10 && bytes[i + 1] === 10) {
        return i;
      }
    }
    return -1;
  }
}

export function utf8Decode(bytes: number[]): string {
  const out: string[] = [];
  let i = 0;
  while (i < bytes.length) {
    const b = bytes[i];
    if (b < 128) {
      out.push(String.fromCharCode(b));
      i += 1;
    } else if (b >> 5 === 6 && i + 1 < bytes.length) {
      out.push(String.fromCharCode(((b & 31) << 6) | (bytes[i + 1] & 63)));
      i += 2;
    } else if (b >> 4 === 14 && i + 2 < bytes.length) {
      out.push(String.fromCharCode(((b & 15) << 12) | ((bytes[i + 1] & 63) << 6) | (bytes[i + 2] & 63)));
      i += 3;
    } else if (b >> 3 === 30 && i + 3 < bytes.length) {
      const code = ((b & 7) << 18) | ((bytes[i + 1] & 63) << 12) | ((bytes[i + 2] & 63) << 6) | (bytes[i + 3] & 63);
      const shifted = code - 0x10000;
      out.push(String.fromCharCode(0xd800 + (shifted >> 10), 0xdc00 + (shifted & 0x3ff)));
      i += 4;
    } else {
      out.push('\ufffd');
      i += 1;
    }
  }
  return out.join('');
}
