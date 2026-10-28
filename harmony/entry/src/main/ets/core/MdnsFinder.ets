import { socket } from '@kit.NetworkKit';
import { utf8Decode } from './SseClient';

export class NearbyComputer {
  instance: string = '';
  name: string = '';
  address: string = '';
  port: number = 8810;

  display(): string {
    return this.name.length > 0 ? this.name : this.address;
  }

  target(): string {
    return `${this.address}:${this.port}`;
  }
}

interface DnsNameResult {
  name: string;
  next: number;
}

/**
 * 附近的电脑：向组播地址发一条 DNS-SD 查询（_openmausbot._tcp.local），
 * 电脑上的伴侣服务会以单播回应，与安卓应用的 Bonjour 发现对应。
 */
export class MdnsFinder {
  private udp: socket.UDPSocket | null = null;
  private found: Map<string, NearbyComputer> = new Map();
  private timer: number = -1;
  private running: boolean = false;

  start(onUpdate: (computers: NearbyComputer[]) => void): void {
    this.stop();
    this.running = true;
    this.found = new Map();
    const udp = socket.constructUDPSocketInstance();
    this.udp = udp;
    udp.on('message', (info: socket.SocketMessageInfo) => {
      if (!this.running) {
        return;
      }
      this.consume(new Uint8Array(info.message), onUpdate);
    });
    udp.on('error', () => {
    });
    const port = 42000 + Math.floor(Math.random() * 20000);
    udp.bind({ address: '0.0.0.0', port: port }).then(() => {
      const query = buildPtrQuery();
      const target: socket.NetAddress = { address: '224.0.0.251', port: 5353 };
      const options: socket.UDPSendOptions = { data: query, address: target };
      return udp.send(options);
    }).catch(() => {
    });
    this.timer = setTimeout(() => {
      this.running = false;
      onUpdate(this.snapshot());
    }, 3500);
  }

  stop(): void {
    this.running = false;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (this.udp !== null) {
      this.udp.off('message');
      this.udp.off('error');
      this.udp.close().catch(() => {
      });
      this.udp = null;
    }
  }

  private snapshot(): NearbyComputer[] {
    const list: NearbyComputer[] = [];
    this.found.forEach((computer: NearbyComputer) => {
      list.push(computer);
    });
    return list;
  }

  private consume(bytes: Uint8Array, onUpdate: (computers: NearbyComputer[]) => void): void {
    if (bytes.length < 12) {
      return;
    }
    const answers = (bytes[6] << 8) | bytes[7];
    const additionals = (bytes[10] << 8) | bytes[11];
    let offset = 12;
    const questions = (bytes[4] << 8) | bytes[5];
    for (let i = 0; i < questions; i++) {
      const skipped = skipName(bytes, offset);
      if (skipped < 0) {
        return;
      }
      offset = skipped + 4;
    }
    const total = answers + additionals;
    for (let i = 0; i < total && offset + 10 <= bytes.length; i++) {
      const nameResult = readName(bytes, offset);
      offset = nameResult.next;
      const type = (bytes[offset] << 8) | bytes[offset + 1];
      offset += 8;
      const rdLength = (bytes[offset] << 8) | bytes[offset + 1];
      offset += 2;
      const rdataStart = offset;
      if (type === 12) {
        const ptrResult = readName(bytes, rdataStart);
        this.takeInstance(ptrResult.name);
      } else if (type === 33) {
        if (rdLength >= 8) {
          const port = (bytes[rdataStart + 4] << 8) | bytes[rdataStart + 5];
          const targetResult = readName(bytes, rdataStart + 6);
          this.takeSrv(nameResult.name, port, targetResult.name);
        }
      } else if (type === 1) {
        if (rdLength === 4) {
          const ip = `${bytes[rdataStart]}.${bytes[rdataStart + 1]}.${bytes[rdataStart + 2]}.${bytes[rdataStart + 3]}`;
          this.takeA(nameResult.name, ip);
        }
      } else if (type === 16) {
        this.takeTxt(nameResult.name, bytes, rdataStart, rdLength);
      }
      offset = rdataStart + rdLength;
    }
    onUpdate(this.snapshot());
  }

  private takeInstance(instance: string): void {
    if (instance.length === 0) {
      return;
    }
    let entry = this.found.get(instance);
    if (entry === undefined) {
      entry = new NearbyComputer();
      entry.instance = instance;
      const firstLabel = instance.split('.')[0];
      entry.name = firstLabel;
      this.found.set(instance, entry);
    }
  }

  private takeSrv(name: string, port: number, target: string): void {
    const entry = this.matchEntry(name);
    if (entry !== null) {
      entry.port = port > 0 ? port : entry.port;
    }
  }

  private takeA(name: string, ip: string): void {
    for (const entry of this.found.values()) {
      if (entry.address.length === 0) {
        entry.address = ip;
      }
    }
  }

  private takeTxt(name: string, bytes: Uint8Array, start: number, length: number): void {
    const entry = this.matchEntry(name);
    if (entry === null) {
      return;
    }
    let cursor = start;
    const end = start + length;
    while (cursor < end) {
      const entryLength = bytes[cursor];
      cursor += 1;
      if (cursor + entryLength > end) {
        break;
      }
      const piece = utf8Decode(Array.from(bytes.slice(cursor, cursor + entryLength)));
      cursor += entryLength;
      if (piece.startsWith('name=')) {
        const value = piece.slice(5).trim();
        if (value.length > 0) {
          entry.name = value;
        }
      }
    }
  }

  private matchEntry(name: string): NearbyComputer | null {
    const direct = this.found.get(name);
    if (direct !== undefined) {
      return direct;
    }
    for (const entry of this.found.values()) {
      if (name.startsWith(entry.instance) || entry.instance.startsWith(name)) {
        return entry;
      }
    }
    return null;
  }
}

function skipName(bytes: Uint8Array, offset: number): number {
  let cursor = offset;
  let jumps = 0;
  while (cursor < bytes.length) {
    const length = bytes[cursor];
    if (length === 0) {
      return cursor + 1;
    }
    if ((length & 0xc0) === 0xc0) {
      return cursor + 2;
    }
    cursor += 1 + length;
    jumps += 1;
    if (jumps > 64) {
      return -1;
    }
  }
  return -1;
}

function readName(bytes: Uint8Array, offset: number): DnsNameResult {
  const labels: string[] = [];
  let cursor = offset;
  let next = -1;
  let jumps = 0;
  let visited = offset;
  while (cursor < bytes.length && jumps < 64) {
    const length = bytes[cursor];
    if (length === 0) {
      if (next < 0) {
        next = cursor + 1;
      }
      break;
    }
    if ((length & 0xc0) === 0xc0) {
      if (next < 0) {
        next = cursor + 2;
      }
      const pointer = ((length & 0x3f) << 8) | bytes[cursor + 1];
      if (pointer >= visited) {
        break;
      }
      visited = pointer;
      cursor = pointer;
      jumps += 1;
      continue;
    }
    if (cursor + 1 + length > bytes.length) {
      break;
    }
    const labelBytes: number[] = [];
    for (let i = 0; i < length; i++) {
      labelBytes.push(bytes[cursor + 1 + i]);
    }
    labels.push(utf8Decode(labelBytes));
    cursor += 1 + length;
  }
  if (next < 0) {
    next = cursor;
  }
  const result: DnsNameResult = { name: labels.join('.'), next: next };
  return result;
}

function buildPtrQuery(): ArrayBuffer {
  const bytes: number[] = [];
  bytes.push(0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
  appendLabel(bytes, '_openmausbot');
  appendLabel(bytes, '_tcp');
  appendLabel(bytes, 'local');
  bytes.push(0x00);
  bytes.push(0x00, 0x0c, 0x00, 0x01);
  return new Uint8Array(bytes).buffer;
}

function appendLabel(bytes: number[], label: string): void {
  bytes.push(label.length);
  for (let i = 0; i < label.length; i++) {
    bytes.push(label.charCodeAt(i));
  }
}
