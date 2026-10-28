const filesEl = document.querySelector("#files");
const screenEl = document.querySelector("#screen");
const previewEl = document.querySelector("#preview");
const botsEl = document.querySelector("#bots");
const transcriptEl = document.querySelector("#transcript");
const linkState = document.querySelector("#link-state");
let currentBot = "";
let stick = true;
let fileKey = "";
let botKey = "";
let messageKey = "";

async function refresh() {
  const [computer, bots, devices] = await Promise.all([
    api("/api/computer"),
    api("/api/bots"),
    api("/api/app/devices"),
  ]);
  const controlled = devices.some((item) => {
    return item.platform === "harmony" && Date.now() - Date.parse(item.last_seen) < 60000;
  });
  linkState.textContent = controlled
    ? `华为应用正在控制 · ${computer.pending} 条待确认 · ${computer.lan}`
    : `等待华为应用连接 · ${computer.pending} 条待确认 · ${computer.lan}/control`;

  const nextFileKey = computer.files.map((file) => `${file.path}:${file.size}`).join("|");
  if (nextFileKey !== fileKey) {
    fileKey = nextFileKey;
    filesEl.replaceChildren();
    if (computer.files.length === 0) {
      filesEl.append(node("li", "muted", "工作区是空的"));
    }
    computer.files.forEach((file) => {
      const item = node("li");
      const button = node("button", "file", file.path);
      button.addEventListener("click", () => openFile(file.path));
      item.append(button, node("span", "size", `${file.size} 字节`));
      filesEl.append(item);
    });
  }

  const lines = computer.events.map((item) => `[${item.kind}] ${item.text}`);
  screenEl.textContent = lines.join("\n\n") || "工作区已就绪。写入和运行会等华为应用点同意。";

  if (!currentBot && bots[0]) currentBot = bots[0].id;
  const nextBotKey = bots.map((bot) => `${bot.id}:${bot.id === currentBot ? 1 : 0}`).join("|");
  if (nextBotKey !== botKey) {
    botKey = nextBotKey;
    botsEl.replaceChildren();
    bots.forEach((bot) => {
      const button = node("button", bot.id === currentBot ? "bot on" : "bot", `${bot.name} · ${bot.role}`);
      button.addEventListener("click", () => {
        currentBot = bot.id;
        botKey = "";
        messageKey = "";
        loadTranscript();
      });
      botsEl.append(button);
    });
  }
  if (currentBot) await loadTranscript();
}

async function loadTranscript() {
  const messages = await api(`/api/bots/${currentBot}/messages`);
  const nextMessageKey = messages.map((item) => item.id).join("|");
  if (nextMessageKey === messageKey) return;
  messageKey = nextMessageKey;
  const nearBottom = transcriptEl.scrollHeight - transcriptEl.scrollTop - transcriptEl.clientHeight < 40;
  transcriptEl.replaceChildren();
  if (messages.length === 0) {
    transcriptEl.append(node("p", "muted", "还没有指令。请在华为应用里把任务发给这位队友。"));
    return;
  }
  messages.forEach((item) => {
    transcriptEl.append(node("p", item.role === "user" ? "from-app" : "from-bot", item.content));
  });
  if (stick || nearBottom) transcriptEl.scrollTop = transcriptEl.scrollHeight;
}

async function openFile(path) {
  const file = await api(`/api/computer/file?path=${encodeURIComponent(path)}`);
  previewEl.textContent = `${file.path}\n\n${file.content}`;
}

refresh().catch((error) => {
  linkState.textContent = error.message;
});
setInterval(() => {
  refresh().catch((error) => {
    linkState.textContent = error.message;
  });
}, 2000);
