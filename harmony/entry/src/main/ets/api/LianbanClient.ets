import { http } from '@kit.NetworkKit';
import {
  BotItem, ChatMessage, EndpointItem, PairOutcome, ThreadItem, ThreadPage,
  boolOr, numberOr, parseBot, parseMessage, rowsOf, textOf
} from '../model/Models';

interface PairBody {
  credential: string;
  deviceName: string;
}

interface SendBody {
  text: string;
  threadId: string;
}

interface RespondBody {
  requestId: string;
  behavior: string;
  message?: string;
  threadId?: string;
}

interface AlwaysAllowBody {
  allowKey: string;
  threadId: string;
}

interface ThreadOnlyBody {
  threadId: string;
}

interface NewThreadBody {
  title: string;
}

interface SecretEnvelopeBody {
  version: number;
  threadId: string;
  keyId: string;
  deviceId: string;
  target: string;
  requestKey: string;
  encapsulatedKey: string;
  ciphertext: string;
}

interface HttpRequestHeader {
  'Content-Type': string;
  Authorization?: string;
}

export class EndpointSnapshot {
  serverName: string = '';
  endpoints: EndpointItem[] = [];
}

/**
 * 与电脑上伴侣服务（默认端口 8810）通信的客户端。
 * 协议与上游伴侣应用一致：配对后所有请求携带 Bearer 令牌。
 */
export class LianbanClient {
  baseUrl: string = '';
  token: string = '';

  constructor(baseUrl: string, token: string = '') {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.token = token;
  }

  async health(): Promise<boolean> {
    try {
      const data = await this.request('/api/health', 'GET') as Object;
      return textOf(data, 'app') === 'openmausbot';
    } catch (_error) {
      return false;
    }
  }

  async pair(credential: string): Promise<PairOutcome> {
    const outcome = new PairOutcome();
    const body: PairBody = { credential: credential.trim(), deviceName: '联伴鸿蒙' };
    let data: Object;
    try {
      data = await this.request('/api/pair', 'POST', body) as Object;
    } catch (error) {
      outcome.error = error instanceof Error ? error.message : '配对失败';
      return outcome;
    }
    outcome.ok = true;
    outcome.token = textOf(data, 'token');
    outcome.serverName = textOf(data, 'serverName');
    const deviceRow = (data as Record<string, Object>)['device'];
    if (deviceRow !== undefined && deviceRow !== null && typeof deviceRow === 'object') {
      outcome.deviceId = textOf(deviceRow, 'id');
    }
    const endpointRows = rowsOf(data, 'endpoints');
    for (const row of endpointRows) {
      const item = new EndpointItem();
      item.url = textOf(row, 'url');
      item.kind = textOf(row, 'kind');
      item.priority = numberOr(row, 'priority', 0);
      outcome.endpoints.push(item);
    }
    if (outcome.token.length === 0) {
      outcome.ok = false;
      outcome.error = '电脑没有返回访问凭证';
    }
    return outcome;
  }

  async listBots(): Promise<BotItem[]> {
    const data = await this.request('/api/bots?messages=20', 'GET') as Object;
    const rows = rowsOf(data, 'bots');
    const bots: BotItem[] = [];
    for (const row of rows) {
      bots.push(parseBot(row));
    }
    return bots;
  }

  async threadMessages(threadId: string, before: string = ''): Promise<ThreadPage> {
    const page = new ThreadPage();
    let path = `/api/threads/${threadId}/messages?limit=40`;
    if (before.length > 0) {
      path = `${path}&before=${before}`;
    }
    const data = await this.request(path, 'GET') as Object;
    page.hasMore = boolOr(data, 'hasMore', false);
    const rows = rowsOf(data, 'messages');
    for (let i = 0; i < rows.length; i++) {
      page.messages.push(parseMessage(rows[i]));
    }
    return page;
  }

  async createThread(botId: string): Promise<ThreadItem> {
    const body: NewThreadBody = { title: '新对话' };
    const data = await this.request(`/api/bots/${botId}/tasks`, 'POST', body) as Object;
    const item = new ThreadItem();
    const taskRow = (data as Record<string, Object>)['task'];
    if (taskRow !== undefined && taskRow !== null && typeof taskRow === 'object') {
      item.threadId = textOf(taskRow, 'threadId');
      item.title = textOf(taskRow, 'title');
    }
    if (item.title.length === 0) {
      item.title = '新对话';
    }
    return item;
  }

  async send(botId: string, threadId: string, text: string): Promise<void> {
    const body: SendBody = { text: text, threadId: threadId };
    await this.request(`/api/bots/${botId}/messages`, 'POST', body);
  }

  async respond(botId: string, threadId: string, requestId: string, behavior: string, message: string = ''): Promise<void> {
    const body: RespondBody = { requestId: requestId, behavior: behavior, threadId: threadId };
    if (message.length > 0) {
      body.message = message;
    }
    await this.request(`/api/bots/${botId}/respond`, 'POST', body);
  }

  async alwaysAllow(botId: string, threadId: string, allowKey: string): Promise<void> {
    const body: AlwaysAllowBody = { allowKey: allowKey, threadId: threadId };
    await this.request(`/api/bots/${botId}/always-allow`, 'POST', body);
  }

  async markRead(botId: string, threadId: string): Promise<void> {
    const body: ThreadOnlyBody = { threadId: threadId };
    await this.request(`/api/bots/${botId}/read`, 'POST', body);
  }

  async interrupt(botId: string, threadId: string): Promise<void> {
    const body: ThreadOnlyBody = { threadId: threadId };
    await this.request(`/api/bots/${botId}/interrupt`, 'POST', body);
  }

  async provideSecret(botId: string, messageId: string, threadId: string, keyId: string, deviceId: string,
    target: string, requestKey: string, encapsulatedKey: string, ciphertext: string): Promise<void> {
    const body: SecretEnvelopeBody = {
      version: 1,
      threadId: threadId,
      keyId: keyId,
      deviceId: deviceId,
      target: target,
      requestKey: requestKey,
      encapsulatedKey: encapsulatedKey,
      ciphertext: ciphertext
    };
    await this.request(`/api/bots/${botId}/secret-cards/${messageId}/provide`, 'POST', body);
  }

  async dismissSecret(botId: string, messageId: string, threadId: string): Promise<void> {
    const body: ThreadOnlyBody = { threadId: threadId };
    await this.request(`/api/bots/${botId}/secret-cards/${messageId}/dismiss`, 'POST', body);
  }

  async signInCardDone(botId: string, messageId: string, threadId: string, done: boolean): Promise<void> {
    const action = done ? 'done' : 'cancel';
    const body: ThreadOnlyBody = { threadId: threadId };
    await this.request(`/api/bots/${botId}/sign-in-cards/${messageId}/${action}`, 'POST', body);
  }

  async forgetSelf(): Promise<void> {
    await this.request('/api/companion/self', 'DELETE');
  }

  async endpointSnapshot(): Promise<EndpointSnapshot> {
    const snapshot = new EndpointSnapshot();
    const data = await this.request('/api/companion/endpoints', 'GET') as Object;
    snapshot.serverName = textOf(data, 'serverName');
    const rows = rowsOf(data, 'endpoints');
    for (const row of rows) {
      const item = new EndpointItem();
      item.url = textOf(row, 'url');
      item.kind = textOf(row, 'kind');
      item.priority = numberOr(row, 'priority', 0);
      snapshot.endpoints.push(item);
    }
    return snapshot;
  }

  async request(path: string, method: string, body?: Object): Promise<Object> {
    const session = http.createHttp();
    const header: HttpRequestHeader = { 'Content-Type': 'application/json' };
    if (this.token.length > 0) {
      header.Authorization = `Bearer ${this.token}`;
    }
    try {
      const response = await session.request(`${this.baseUrl}${path}`, {
        method: method === 'POST' ? http.RequestMethod.POST
          : method === 'PATCH' ? http.RequestMethod.PATCH
            : method === 'DELETE' ? http.RequestMethod.DELETE
              : http.RequestMethod.GET,
        header: header,
        extraData: body !== undefined ? JSON.stringify(body) : undefined,
        connectTimeout: 8000,
        readTimeout: 20000
      });
      const code = response.responseCode;
      const raw = response.result;
      const text = typeof raw === 'string' ? raw : '{}';
      let parsed: Object = new Object();
      if (text.length > 0) {
        try {
          parsed = JSON.parse(text) as Object;
        } catch (_parseError) {
          parsed = new Object();
        }
      }
      if (code < 200 || code >= 300) {
        const message = textOf(parsed, 'error');
        throw new Error(message.length > 0 ? message : `请求失败（HTTP ${code}）`);
      }
      return parsed;
    } finally {
      session.destroy();
    }
  }
}
