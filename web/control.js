const botList = document.querySelector("#bot-list");
const inbox = document.querySelector("#inbox");
const form = document.querySelector("#task-form");
const task = document.querySelector("#task");
const phoneState = document.querySelector("#phone-state");
let currentBot = "";
let deviceId = localStorage.getItem("lianban.controller") || "";
let inboxKey = "";
let botKey = "";

async function heartbeat() {
  const device = await api("/api/app/register", {
    method: "POST",
    body: JSON.stringify({
      device_id: deviceId,
      name: "华为应用控制端",
      platform: "harmony",
      push_token: "",
    }),
  });
  deviceId = device.id;
  localStorage.setItem("lianban.controller", deviceId);
}

async function refresh() {
  await heartbeat();
  const [health, bots, notices, pending] = await Promise.all([
    api("/api/health"),
    api("/api/bots"),
    api("/api/app/inbox"),
    api("/api/approvals?status=pending"),
  ]);
  phoneState.textContent = `已连上电脑端 ${health.computer}`;
  const pendingIds = new Set(pending.map((item) => item.id));
  if (!currentBot && bots[0]) currentBot = bots[0].id;
  const nextBotKey = bots.map((bot) => `${bot.id}:${bot.id === currentBot ? 1 : 0}`).join("|");
  if (nextBotKey !== botKey) {
    botKey = nextBotKey;
    botList.replaceChildren();
    bots.forEach((bot) => {
      const button = node("button", bot.id === currentBot ? "choice on" : "choice", `${bot.name} · ${bot.role}`);
      button.addEventListener("click", () => {
        currentBot = bot.id;
        botKey = "";
        refresh().catch(showError);
      });
      botList.append(button);
    });
  }

  const visible = notices.filter((item) => item.approval_id && pendingIds.has(item.approval_id));
  const nextInboxKey = visible.map((item) => item.approval_id).join("|");
  if (nextInboxKey !== inboxKey) {
    inboxKey = nextInboxKey;
    inbox.replaceChildren();
    if (visible.length === 0) {
      inbox.append(node("p", "muted", "没有待确认的电脑动作。"));
      return;
    }
    visible.forEach((item) => {
      const card = node("article", "card");
      card.append(node("strong", "", item.title), node("p", "", item.body));
      const row = node("div", "row");
      const allow = node("button", "yes", "同意");
      const deny = node("button", "no", "拒绝");
      allow.addEventListener("click", () => decide(item.approval_id, "approved"));
      deny.addEventListener("click", () => decide(item.approval_id, "rejected"));
      row.append(allow, deny);
      card.append(row);
      inbox.append(card);
    });
  }
}

async function decide(id, decision) {
  await api(`/api/approvals/${id}/decision`, {
    method: "POST",
    body: JSON.stringify({ decision }),
  });
  await refresh();
}

function showError(error) {
  phoneState.textContent = error.message;
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const content = task.value.trim();
  if (!currentBot || !content) return;
  form.querySelector("button").disabled = true;
  try {
    await api(`/api/bots/${currentBot}/messages`, {
      method: "POST",
      body: JSON.stringify({ content }),
    });
    task.value = "";
    await refresh();
  } catch (error) {
    showError(error);
  } finally {
    form.querySelector("button").disabled = false;
  }
});

refresh().catch(showError);
setInterval(() => refresh().catch(showError), 3000);
