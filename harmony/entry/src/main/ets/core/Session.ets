import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { LianbanClient } from '../api/LianbanClient';
import { PhoneSecretSealInput, sealPhoneSecret } from '../api/PhoneSecret';
import { SseClient, SseHandlers } from './SseClient';
import {
  BotItem, ChatMessage, Computer, ComputerJson, EndpointItem, ThreadItem,
  friendlyComputerName, parseMessage, rowsOf, textOf
} from '../model/Models';

export interface SessionUi {
  onBots(bots: BotItem[]): void;
  onMessages(threadId: string, messages: ChatMessage[]): void;
  onConnectionState(state: string): void;
  onServerName(name: string): void;
}

const STORE_NAME = 'lianban';
const COMPUTERS_KEY = 'computers';

interface ComputersWrapper {
  computers: ComputerJson[];
}

/**
 * 已配对电脑的会话：凭证保存在本机，切换电脑只换当前连接，
 * 不影响其他已保存的配对。对话、进度与电脑是同一份数据。
 */
export class Session {
  computers: Computer[] = [];
  current: Computer | null = null;
  client: LianbanClient | null = null;
  connectionState: string = 'offline';
  private ui: SessionUi | null = null;
  private sse: SseClient | null = null;
  private pollTimer: number = -1;
  private bots: BotItem[] = [];
  private threads: Map<string, ChatMessage[]> = new Map();
  private openBotId: string = '';
  private openThreadId: string = '';
  private pref: preferences.Preferences | null = null;
  private refreshing: boolean = false;

  attachUi(ui: SessionUi): void {
    this.ui = ui;
    ui.onConnectionState(this.connectionState);
    if (this.current !== null) {
      ui.onServerName(this.current.serverName);
    }
  }

  detachUi(): void {
    this.ui = null;
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    if (this.pref === null) {
      this.pref = await preferences.getPreferences(context, STORE_NAME);
    }
    const saved = await this.pref.get(COMPUTERS_KEY, '[]');
    if (typeof saved !== 'string') {
      return;
    }
    try {
      const parsed: Object = JSON.parse(saved) as Object;
      const rows = rowsOf(parsed, 'computers');
      this.computers = [];
      for (const row of rows) {
        this.computers.push(Computer.fromJson(row as Record<string, Object>));
      }
    } catch (_error) {
      this.computers = [];
    }
  }

  async save(): Promise<void> {
    if (this.pref === null) {
      return;
    }
    const rows: ComputerJson[] = [];
    for (const computer of this.computers) {
      rows.push(computer.toJson());
    }
    const wrapper: ComputersWrapper = { computers: rows };
    await this.pref.put(COMPUTERS_KEY, JSON.stringify(wrapper));
    await this.pref.flush();
  }

  async addPairedComputer(baseUrl: string, token: string, serverName: string, kind: string, endpoints: EndpointItem[], deviceId: string, secretPublicKey: string): Promise<Computer> {
    const computer = new Computer();
    computer.id = `c_${Date.now().toString(36)}_${Math.floor(Math.random() * 100000).toString(36)}`;
    computer.baseUrl = baseUrl.replace(/\/+$/, '');
    computer.token = token;
    computer.serverName = friendlyComputerName(serverName.length > 0 ? serverName : '我的电脑');
    computer.kind = kind;
    computer.deviceId = deviceId;
    computer.secretPublicKey = secretPublicKey;
    computer.pairedAt = Date.now();
    for (const item of endpoints) {
      if (item.url.length > 0 && item.url !== computer.baseUrl) {
        computer.alternates.push(item.url);
      }
    }
    this.computers.push(computer);
    await this.save();
    return computer;
  }

  async removeComputer(id: string): Promise<void> {
    const target = this.findComputer(id);
    if (target !== null && target.token.length > 0) {
      const notifier = this.current !== null && this.current.id === id && this.client !== null
        ? this.client
        : new LianbanClient(target.baseUrl, target.token);
      try {
        await notifier.forgetSelf();
      } catch (_error) {
      }
    }
    const before = this.computers.length;
    this.computers = this.computers.filter((item: Computer) => item.id !== id);
    if (this.computers.length === before) {
      return;
    }
    if (this.current !== null && this.current.id === id) {
      this.disconnect();
      this.current = null;
    }
    await this.save();
  }

  hasComputers(): boolean {
    return this.computers.length > 0;
  }

  findComputer(id: string): Computer | null {
    for (const computer of this.computers) {
      if (computer.id === id) {
        return computer;
      }
    }
    return null;
  }

  disconnect(): void {
    this.stopPoll();
    if (this.sse !== null) {
      this.sse.stop();
      this.sse = null;
    }
    this.connectionState = 'offline';
    if (this.ui !== null) {
      this.ui.onConnectionState('offline');
    }
  }

  async useComputer(computer: Computer): Promise<void> {
    this.disconnect();
    this.current = computer;
    this.threads = new Map();
    this.openBotId = '';
    this.openThreadId = '';
    this.bots = [];
    this.client = await this.dialComputer(computer);
    if (this.ui !== null) {
      this.ui.onServerName(computer.serverName);
      this.ui.onBots([]);
    }
    await this.hydrate();
    this.startEvents();
  }

  private async dialComputer(computer: Computer): Promise<LianbanClient> {
    const primary = new LianbanClient(computer.baseUrl, computer.token);
    const healthy = await primary.health();
    if (healthy) {
      return primary;
    }
    for (const alternate of computer.alternates) {
      const candidate = new LianbanClient(alternate, computer.token);
      if (await candidate.health()) {
        computer.baseUrl = alternate.replace(/\/+$/, '');
        await this.save();
        return candidate;
      }
    }
    return primary;
  }

  private hydratePending: boolean = false;

  async hydrate(): Promise<void> {
    if (this.client === null) {
      return;
    }
    if (this.refreshing) {
      this.hydratePending = true;
      return;
    }
    this.refreshing = true;
    try {
      const bots = await this.client.listBots();
      this.applyBots(bots);
      if (this.openThreadId.length > 0) {
        const page = await this.client.threadMessages(this.openThreadId);
        this.threads.set(this.openThreadId, page.messages);
        this.emitMessages(this.openThreadId);
      }
    } catch (_error) {
    } finally {
      this.refreshing = false;
      if (this.hydratePending) {
        this.hydratePending = false;
        this.hydrate();
      }
    }
  }

  private startEvents(): void {
    if (this.client === null) {
      return;
    }
    const handlers: SseHandlersBridge = new SseHandlersBridge(this);
    this.sse = new SseClient(this.client.baseUrl, this.client.token, handlers);
    this.sse.start();
    this.startPoll();
    this.refreshEndpoints();
  }

  private startPoll(): void {
    this.stopPoll();
    this.pollTimer = setInterval(() => {
      const bot = this.currentBot();
      if (this.connectionState !== 'online' || (bot !== null && bot.busy)) {
        this.hydrate();
      }
    }, 2000);
  }

  private stopPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private async refreshEndpoints(): Promise<void> {
    if (this.client === null || this.current === null) {
      return;
    }
    try {
      const snapshot = await this.client.endpointSnapshot();
      const shownName = friendlyComputerName(snapshot.serverName);
      if (shownName.length > 0 && shownName !== this.current.serverName) {
        this.current.serverName = shownName;
        if (this.ui !== null) {
          this.ui.onServerName(snapshot.serverName);
        }
      }
      const urls: string[] = [];
      for (const item of snapshot.endpoints) {
        if (item.url.length > 0 && item.url !== this.current.baseUrl && !urls.includes(item.url)) {
          urls.push(item.url);
        }
      }
      if (urls.length > 0) {
        this.current.alternates = urls;
        await this.save();
      }
    } catch (_error) {
    }
  }

  onSseState(state: string): void {
    const becameOnline = state === 'online' && this.connectionState !== 'online';
    this.connectionState = state;
    if (this.ui !== null) {
      this.ui.onConnectionState(state);
    }
    if (becameOnline) {
      this.hydrate();
    }
  }

  onSseFrame(json: string): void {
    let frame: Object;
    try {
      frame = JSON.parse(json) as Object;
    } catch (_error) {
      return;
    }
    const kind = textOf(frame, 'kind');
    if (kind === 'hello') {
      this.hydrate();
      return;
    }
    if (kind === 'bot' || kind === 'bot.queued' || kind === 'bots.order' || kind === 'bot.deleted' || kind === 'group') {
      this.hydrate();
      return;
    }
    if (kind === 'message' || kind === 'message.patch') {
      const threadId = textOf(frame, 'threadId');
      const messageRow = (frame as Record<string, Object>)['message'];
      if (messageRow === undefined || messageRow === null || typeof messageRow !== 'object') {
        return;
      }
      const message = parseMessage(messageRow);
      this.foldMessage(threadId, message);
      if (threadId !== this.openThreadId) {
        this.markLocalUnread(threadId);
        this.emitBots();
      }
      return;
    }
    if (kind === 'thread') {
      if (this.openThreadId.length > 0) {
        this.hydrate();
      }
      return;
    }
  }

  private foldMessage(threadId: string, message: ChatMessage): void {
    if (threadId.length === 0 || message.id.length === 0) {
      return;
    }
    let list = this.threads.get(threadId);
    if (list === undefined) {
      list = [];
      this.threads.set(threadId, list);
    }
    let replaced = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === message.id) {
        list[i] = message;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      list.push(message);
    }
    if (threadId === this.openThreadId) {
      this.emitMessages(threadId);
    }
    this.updatePreview(threadId, message);
  }

  private updatePreview(threadId: string, message: ChatMessage): void {
    for (const bot of this.bots) {
      if (bot.threadId === threadId) {
        if (message.text.length > 0) {
          bot.preview = message.text;
          bot.previewAt = message.at;
        }
        break;
      }
    }
  }

  private markLocalUnread(threadId: string): void {
    for (const bot of this.bots) {
      if (bot.threadId === threadId) {
        bot.unread = true;
        break;
      }
    }
  }

  private applyBots(bots: BotItem[]): void {
    const merged: BotItem[] = [];
    for (const fresh of bots) {
      let kept: BotItem | null = null;
      for (const old of this.bots) {
        if (old.id === fresh.id) {
          kept = old;
          break;
        }
      }
      if (kept !== null) {
        kept.merge(fresh);
        merged.push(kept);
      } else {
        merged.push(fresh);
      }
    }
    this.bots = merged;
    this.emitBots();
  }

  private emitBots(): void {
    if (this.ui !== null) {
      const copy: BotItem[] = [];
      for (const bot of this.bots) {
        copy.push(bot);
      }
      this.ui.onBots(copy);
    }
  }

  private emitMessages(threadId: string): void {
    if (this.ui !== null) {
      const list = this.threads.get(threadId);
      if (list === undefined) {
        return;
      }
      const copy: ChatMessage[] = [];
      for (const message of list) {
        copy.push(message);
      }
      this.ui.onMessages(threadId, copy);
    }
  }

  async openThread(bot: BotItem, threadId: string): Promise<void> {
    this.openBotId = bot.id;
    this.openThreadId = threadId;
    if (this.client === null || threadId.length === 0) {
      return;
    }
    if (bot.unread && threadId === bot.threadId) {
      bot.unread = false;
      this.emitBots();
    }
    try {
      await this.client.markRead(bot.id, threadId);
    } catch (_error) {
    }
    await this.hydrate();
  }

  async createThread(bot: BotItem): Promise<ThreadItem> {
    if (this.client === null) {
      throw new Error('还没有连上电脑');
    }
    const created = await this.client.createThread(bot.id);
    await this.hydrate();
    return created;
  }

  closeBot(): void {
    this.openBotId = '';
    this.openThreadId = '';
  }

  isOpen(bot: BotItem): boolean {
    return bot.threadId.length > 0 && bot.threadId === this.openThreadId;
  }

  messagesOf(threadId: string): ChatMessage[] {
    const list = this.threads.get(threadId);
    return list === undefined ? [] : list;
  }

  currentBot(): BotItem | null {
    for (const bot of this.bots) {
      if (bot.id === this.openBotId) {
        return bot;
      }
    }
    return null;
  }

  async send(text: string): Promise<void> {
    if (this.client === null || this.openBotId.length === 0 || this.openThreadId.length === 0) {
      throw new Error('还没有打开任何对话');
    }
    await this.client.send(this.openBotId, this.openThreadId, text);
    await this.hydrate();
  }

  async respondCard(requestId: string, behavior: string, answer: string = ''): Promise<void> {
    if (this.client === null || this.openBotId.length === 0 || this.openThreadId.length === 0) {
      return;
    }
    await this.client.respond(this.openBotId, this.openThreadId, requestId, behavior, answer);
    await this.hydrate();
  }

  async alwaysAllowCard(allowKey: string): Promise<void> {
    if (this.client === null || this.openBotId.length === 0 || this.openThreadId.length === 0) {
      return;
    }
    await this.client.alwaysAllow(this.openBotId, this.openThreadId, allowKey);
    await this.hydrate();
  }

  async dismissSecret(messageId: string): Promise<void> {
    if (this.client === null || this.openBotId.length === 0 || this.openThreadId.length === 0) {
      return;
    }
    await this.client.dismissSecret(this.openBotId, messageId, this.openThreadId);
    await this.hydrate();
  }

  async provideSecret(messageId: string, target: string, requestKey: string, value: string): Promise<void> {
    if (this.client === null || this.current === null || this.openBotId.length === 0 || this.openThreadId.length === 0) {
      throw new Error('还没有连上电脑');
    }
    if (this.current.secretPublicKey.length === 0 || this.current.deviceId.length === 0) {
      throw new Error('这台电脑还没有公布密钥。请重新扫电脑上的配对二维码。');
    }
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      throw new Error('请先输入要保存的内容');
    }
    const input = new PhoneSecretSealInput();
    input.publicKey = this.current.secretPublicKey;
    input.deviceId = this.current.deviceId;
    input.botId = this.openBotId;
    input.threadId = this.openThreadId;
    input.messageId = messageId;
    input.target = target;
    input.requestKey = requestKey;
    const envelope = sealPhoneSecret(input, trimmed);
    await this.client.provideSecret(
      this.openBotId, messageId, this.openThreadId, envelope.keyId, this.current.deviceId,
      target, requestKey, envelope.encapsulatedKey, envelope.ciphertext);
    await this.hydrate();
  }

  async signInCard(messageId: string, done: boolean): Promise<void> {
    if (this.client === null || this.openBotId.length === 0 || this.openThreadId.length === 0) {
      return;
    }
    await this.client.signInCardDone(this.openBotId, messageId, this.openThreadId, done);
    await this.hydrate();
  }

  async interrupt(): Promise<void> {
    if (this.client === null || this.openBotId.length === 0 || this.openThreadId.length === 0) {
      return;
    }
    try {
      await this.client.interrupt(this.openBotId, this.openThreadId);
      await this.hydrate();
    } catch (_error) {
    }
  }

  pairClient(baseUrl: string): LianbanClient {
    return new LianbanClient(baseUrl);
  }
}

class SseHandlersBridge implements SseHandlers {
  private session: Session;

  constructor(session: Session) {
    this.session = session;
  }

  onFrame(json: string): void {
    this.session.onSseFrame(json);
  }

  onEventId(_id: string): void {
  }

  onState(state: string): void {
    this.session.onSseState(state);
  }
}

export const session: Session = new Session();
