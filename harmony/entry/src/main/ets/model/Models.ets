export interface ComputerJson {
  id: string;
  serverName: string;
  baseUrl: string;
  token: string;
  kind: string;
  pairedAt: number;
  alternates: string[];
  deviceId: string;
  secretPublicKey: string;
}

export class Computer {
  id: string = '';
  serverName: string = '';
  baseUrl: string = '';
  token: string = '';
  kind: string = 'lan';
  pairedAt: number = 0;
  alternates: string[] = [];
  deviceId: string = '';
  secretPublicKey: string = '';

  static fromJson(row: Record<string, Object>): Computer {
    const item = new Computer();
    item.id = textOf(row, 'id');
    item.serverName = friendlyComputerName(textOf(row, 'serverName'));
    item.baseUrl = textOf(row, 'baseUrl');
    item.token = textOf(row, 'token');
    item.kind = textOf(row, 'kind');
    item.pairedAt = numberOr(row, 'pairedAt', 0);
    item.deviceId = textOf(row, 'deviceId');
    item.secretPublicKey = textOf(row, 'secretPublicKey');
    const savedAlternates = row['alternates'];
    if (Array.isArray(savedAlternates)) {
      for (const one of savedAlternates as Object[]) {
        if (typeof one === 'string') {
          item.alternates.push(one);
        }
      }
    }
    return item;
  }

  toJson(): ComputerJson {
    const out: ComputerJson = {
      id: this.id,
      serverName: this.serverName,
      baseUrl: this.baseUrl,
      token: this.token,
      kind: this.kind,
      pairedAt: this.pairedAt,
      alternates: this.alternates,
      deviceId: this.deviceId,
      secretPublicKey: this.secretPublicKey
    };
    return out;
  }
}

export class EndpointItem {
  url: string = '';
  kind: string = '';
  priority: number = 0;
}

export class PairOutcome {
  ok: boolean = false;
  token: string = '';
  serverName: string = '';
  deviceId: string = '';
  error: string = '';
  endpoints: EndpointItem[] = [];
}

export class ThreadItem {
  threadId: string = '';
  title: string = '';
  createdAt: number = 0;
  model: string = '';
}

export class BotItem {
  id: string = '';
  name: string = '';
  title: string = '';
  threadId: string = '';
  unread: boolean = false;
  busy: boolean = false;
  colorName: string = '';
  preview: string = '';
  previewAt: number = 0;
  tasks: ThreadItem[] = [];

  merge(other: BotItem): void {
    this.name = other.name;
    this.title = other.title;
    this.threadId = other.threadId;
    this.unread = other.unread;
    this.busy = other.busy;
    this.colorName = other.colorName;
    this.tasks = other.tasks;
    if (other.preview.length > 0) {
      this.preview = other.preview;
      this.previewAt = other.previewAt;
    }
  }
}

export class CardView {
  kind: string = 'none';
  title: string = '';
  subtitle: string = '';
  options: string[] = [];
  requestType: string = '';
  requestId: string = '';
  answered: string = '';
  answeredText: string = '';
  dismissed: boolean = false;
  expired: boolean = false;
  allowKey: string = '';
  fixedOptions: boolean = false;
  signInUrl: string = '';
  signInSite: string = '';
  signInReason: string = '';
  signInDone: boolean = false;
  signInCancelled: boolean = false;
  secretLabel: string = '';
  secretDescription: string = '';
  secretProvided: boolean = false;
  secretDismissed: boolean = false;
  secretTarget: string = '';
  secretRequestKey: string = '';

  get pending(): boolean {
    return this.requestId.length > 0 && this.answered.length === 0 && !this.dismissed && !this.expired;
  }

  get settled(): boolean {
    return this.answered.length > 0 || this.dismissed || this.expired || this.signInDone || this.signInCancelled
      || this.secretProvided || this.secretDismissed;
  }
}

export class ChatMessage {
  id: string = '';
  role: string = '';
  kind: string = 'text';
  text: string = '';
  at: number = 0;
  toolName: string = '';
  toolSummary: string = '';
  toolOk: boolean = true;
  requestPending: boolean = false;
  card: CardView = new CardView();
}

export class ThreadPage {
  messages: ChatMessage[] = [];
  hasMore: boolean = false;
}

export class PairingInvite {
  ok: boolean = false;
  address: string = '';
  token: string = '';
  code: string = '';
  name: string = '';
  kind: string = 'lan';
  secretKey: string = '';
  error: string = '';

  baseUrl(): string {
    if (this.address.startsWith('https://') || this.address.startsWith('http://')) {
      return this.address;
    }
    return `http://${this.address}`;
  }
}

export function friendlyComputerName(name: string): string {
  const trimmed = name.trim();
  if (trimmed.length === 0 || trimmed.indexOf('OpenMaus') === 0) {
    return '联伴';
  }
  return trimmed;
}

export function textOf(source: Object, key: string): string {
  const record = source as Record<string, Object>;
  const value = record[key];
  return typeof value === 'string' ? value : '';
}

export function numberOr(source: Object, key: string, fallback: number): number {
  const record = source as Record<string, Object>;
  const value = record[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

export function boolOr(source: Object, key: string, fallback: boolean): boolean {
  const record = source as Record<string, Object>;
  const value = record[key];
  return typeof value === 'boolean' ? value : fallback;
}

export function rowsOf(source: Object, key: string): Object[] {
  const record = source as Record<string, Object>;
  const value = record[key];
  return Array.isArray(value) ? value as Object[] : [];
}

export function parseBot(row: Object): BotItem {
  const bot = new BotItem();
  bot.id = textOf(row, 'id');
  bot.name = textOf(row, 'name');
  bot.title = textOf(row, 'title');
  bot.threadId = textOf(row, 'threadId');
  bot.unread = boolOr(row, 'unread', false);
  bot.busy = boolOr(row, 'busy', false);
  bot.colorName = textOf(row, 'color');
  const taskRows = rowsOf(row, 'tasks');
  for (const taskRow of taskRows) {
    const task = new ThreadItem();
    task.threadId = textOf(taskRow, 'threadId');
    task.title = textOf(taskRow, 'title');
    if (task.title.length === 0) {
      task.title = '未命名对话';
    }
    task.createdAt = numberOr(taskRow, 'createdAt', 0);
    const selection = (taskRow as Record<string, Object>)['modelSelection'];
    if (selection !== undefined && selection !== null && typeof selection === 'object') {
      task.model = textOf(selection, 'model');
    }
    if (task.threadId.length > 0) {
      bot.tasks.push(task);
    }
  }
  if (bot.tasks.length === 0 && bot.threadId.length > 0) {
    const only = new ThreadItem();
    only.threadId = bot.threadId;
    only.title = '当前对话';
    bot.tasks.push(only);
  }
  const messages = rowsOf(row, 'messages');
  if (messages.length > 0) {
    const last = parseMessage(messages[messages.length - 1]);
    bot.preview = last.text.length > 0 ? last.text : previewForCard(last);
    bot.previewAt = last.at;
  }
  return bot;
}

export function previewForCard(message: ChatMessage): string {
  if (message.card.kind !== 'none') {
    if (message.card.title.length > 0) {
      return `[卡片] ${message.card.title}`;
    }
    if (message.card.signInSite.length > 0) {
      return `[登录请求] ${message.card.signInSite}`;
    }
    if (message.card.secretLabel.length > 0) {
      return `[凭证请求] ${message.card.secretLabel}`;
    }
  }
  if (message.toolName.length > 0) {
    return `[工具] ${message.toolName}`;
  }
  return '';
}

export function parseCard(message: ChatMessage, row: Object): void {
  const record = row as Record<string, Object>;
  const cardRow = record['card'];
  if (cardRow !== undefined && cardRow !== null && typeof cardRow === 'object') {
    const card = new CardView();
    card.kind = 'options';
    card.title = textOf(cardRow, 'title');
    card.subtitle = textOf(cardRow, 'subtitle');
    card.requestType = textOf(cardRow, 'requestType');
    card.requestId = textOf(cardRow, 'requestId');
    card.answered = textOf(cardRow, 'answered');
    card.answeredText = textOf(cardRow, 'answeredText');
    card.dismissed = boolOr(cardRow, 'dismissed', false);
    card.expired = boolOr(cardRow, 'expired', false);
    card.allowKey = textOf(cardRow, 'allowKey');
    card.fixedOptions = boolOr(cardRow, 'fixedOptions', false);
    const options = rowsOf(cardRow, 'options');
    const names: string[] = [];
    for (const option of options) {
      if (typeof option === 'string') {
        names.push(option);
      }
    }
    card.options = names;
    message.card = card;
    return;
  }
  const signInRow = record['signIn'];
  if (signInRow !== undefined && signInRow !== null && typeof signInRow === 'object') {
    const card = new CardView();
    card.kind = 'signin';
    card.signInUrl = textOf(signInRow, 'url');
    card.signInSite = textOf(signInRow, 'site');
    card.signInReason = textOf(signInRow, 'reason');
    card.signInDone = boolOr(signInRow, 'done', false);
    card.signInCancelled = boolOr(signInRow, 'cancelled', false);
    message.card = card;
    return;
  }
  const secretRow = record['secret'];
  if (secretRow !== undefined && secretRow !== null && typeof secretRow === 'object') {
    const card = new CardView();
    card.kind = 'secret';
    card.secretLabel = textOf(secretRow, 'label');
    card.secretDescription = textOf(secretRow, 'description');
    card.secretProvided = boolOr(secretRow, 'provided', false);
    card.secretDismissed = boolOr(secretRow, 'dismissed', false);
    card.secretTarget = textOf(secretRow, 'target');
    card.secretRequestKey = textOf(secretRow, 'requestKey');
    message.card = card;
  }
}

export function parseMessage(row: Object): ChatMessage {
  const message = new ChatMessage();
  message.id = textOf(row, 'id');
  message.role = textOf(row, 'role');
  message.kind = textOf(row, 'kind');
  message.text = textOf(row, 'text');
  message.at = numberOr(row, 'at', 0);
  message.requestPending = boolOr(row, 'requestPending', false);
  const record = row as Record<string, Object>;
  const toolRow = record['tool'];
  if (toolRow !== undefined && toolRow !== null && typeof toolRow === 'object') {
    message.toolName = textOf(toolRow, 'name');
    message.toolSummary = textOf(toolRow, 'summary');
    message.toolOk = boolOr(toolRow, 'ok', true);
  }
  parseCard(message, row);
  return message;
}

export function transportKindOf(baseUrl: string): string {
  const lower = baseUrl.toLowerCase();
  if (lower.startsWith('https://')) {
    return 'hosted';
  }
  const hostPart = lower.replace(/^https?:\/\//, '').split('/')[0].split(':')[0];
  if (hostPart.endsWith('.ts.net')) {
    return 'tailnet';
  }
  return 'lan';
}

export function transportLabelOf(kind: string): string {
  if (kind === 'hosted') {
    return 'HTTPS 连接';
  }
  if (kind === 'tailnet') {
    return 'Tailscale 连接';
  }
  return '局域网连接';
}

export function transportNoteOf(kind: string): string {
  if (kind === 'hosted') {
    return '经加密的 HTTPS 通道连接这台电脑，外出时也可用。';
  }
  if (kind === 'tailnet') {
    return '通过你的 Tailscale 网络连接，路径已加密。';
  }
  return '通过当前 Wi-Fi 局域网直连。请在可信任的网络使用。';
}

export function decodeEndpointsField(encoded: string): EndpointItem[] {
  const items: EndpointItem[] = [];
  if (encoded.length === 0) {
    return items;
  }
  try {
    const normalized = encoded.replace(/-/g, '+').replace(/_/g, '/');
    const json = decodeBase64Url(normalized);
    const parsed: Object = JSON.parse(json) as Object;
    const array = Array.isArray(parsed) ? parsed as Object[] : [];
    for (const row of array) {
      const item = new EndpointItem();
      item.url = textOf(row, 'url');
      item.kind = textOf(row, 'kind');
      item.priority = numberOr(row, 'priority', 0);
      items.push(item);
    }
  } catch (_error) {
  }
  return items;
}

function decodeBase64Url(value: string): string {
  let binary = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let i = 0;
  while (i < value.length) {
    const a = chars.indexOf(value[i]);
    const b = chars.indexOf(value[i + 1]);
    const c = chars.indexOf(value[i + 2]);
    const d = chars.indexOf(value[i + 3]);
    const first = a >= 0 && b >= 0 ? String.fromCharCode((a << 2) | (b >> 4)) : '';
    const second = b >= 0 && c >= 0 ? String.fromCharCode(((b & 15) << 4) | (c >> 2)) : '';
    const third = c >= 0 && d >= 0 ? String.fromCharCode(((c & 3) << 6) | d) : '';
    binary += first + second + third;
    i += 4;
  }
  return binary;
}

export function parsePairingLink(link: string): PairingInvite {
  const invite = new PairingInvite();
  const trimmed = link.trim();
  const prefix = 'openmausbot://pair?';
  const query = trimmed.startsWith(prefix) ? trimmed.slice(prefix.length)
    : trimmed.startsWith('openmausbot://pair') ? ''
      : trimmed;
  const params: Record<string, string> = {};
  if (query.length > 0) {
    const pairs = query.split('&');
    for (const pair of pairs) {
      const at = pair.indexOf('=');
      if (at > 0) {
        const key = pair.slice(0, at);
        const value = decodePercent(pair.slice(at + 1));
        params[key] = value;
      }
    }
  }
  const address = params['address'] ?? '';
  const token = params['token'] ?? '';
  if (address.length === 0 || token.length === 0) {
    invite.error = '配对链接里缺少地址或凭证';
    return invite;
  }
  invite.ok = true;
  invite.address = address;
  invite.token = token;
  invite.code = params['code'] ?? '';
  invite.name = params['name'] ?? '';
  invite.secretKey = params['secretKey'] ?? '';
  invite.kind = transportKindOf(invite.baseUrl());
  return invite;
}

function decodePercent(value: string): string {
  try {
    const bytes: number[] = [];
    let i = 0;
    while (i < value.length) {
      if (value[i] === '%' && i + 2 < value.length + 1) {
        const hex = value.slice(i + 1, i + 3);
        const code = parseInt(hex, 16);
        if (!Number.isNaN(code)) {
          bytes.push(code);
          i += 3;
          continue;
        }
      }
      const code = value.charCodeAt(i);
      if (code < 128) {
        bytes.push(code);
      } else {
        bytes.push(code >> 6 | 192);
        bytes.push(code & 63 | 128);
      }
      i += 1;
    }
    const out: string[] = [];
    let j = 0;
    while (j < bytes.length) {
      const b = bytes[j];
      if (b < 128) {
        out.push(String.fromCharCode(b));
        j += 1;
      } else if (b >> 5 === 6) {
        out.push(String.fromCharCode(((b & 31) << 6) | (bytes[j + 1] & 63)));
        j += 2;
      } else {
        out.push(String.fromCharCode(((b & 15) << 12) | ((bytes[j + 1] & 63) << 6) | (bytes[j + 2] & 63)));
        j += 3;
      }
    }
    return out.join('');
  } catch (_error) {
    return value;
  }
}
