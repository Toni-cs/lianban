import json
from dataclasses import dataclass

import httpx

from lianban.computer import Intent, interpret
from lianban.config import settings
from lianban.models import Bot, MemoryNote, Message


@dataclass
class Turn:
    reply: str
    approval: tuple[str, str] | None = None
    memory: str | None = None
    source: str = "local"
    kind: str = ""
    payload: dict | None = None
    immediate: str = ""
    immediate_path: str = ""


_REQUESTS = ("帮我", "请你", "请把", "麻烦", "替我", "帮忙")
_BLOCKS = ("不要", "别发", "先别", "不用")
_ACTIONS = (
    ("发邮件", "发送邮件"),
    ("发一封", "发送邮件"),
    ("发送", "发送"),
    ("删除", "删除"),
    ("支付", "支付"),
    ("付款", "付款"),
    ("转账", "转账"),
    ("下单", "下单"),
    ("发布", "发布"),
    ("提交", "提交"),
    ("每天", "创建日程"),
    ("每周", "创建日程"),
    ("提醒", "创建提醒"),
)


def _local_approval(text: str) -> str | None:
    if any(word in text for word in _BLOCKS):
        return None
    if not any(word in text for word in _REQUESTS):
        return None
    for key, action in _ACTIONS:
        if key in text:
            return action
    return None


def _local_memory(text: str) -> str | None:
    for cue in ("请记住", "帮我记住", "记住", "记下"):
        if cue in text:
            memo = text.split(cue, 1)[1].strip(" ：:，,。")
            return memo or text
    return None


def _local_reply(bot: Bot, content: str, approval: str | None, memory: str | None) -> str:
    if approval and memory:
        return f"记住了：{memory}。另外，「{approval}」要先经过华为应用，你点同意我再做。"
    if approval:
        return f"「{approval}」会发到外部。我先把确认送到华为应用，你点同意之后我才执行。"
    if memory:
        return f"记住了：{memory}"
    return f"收到。我按{bot.role}来处理这件事：{content}"


def _history_payload(history: list[Message]) -> list[dict[str, str]]:
    payload: list[dict[str, str]] = []
    for item in history[-8:]:
        role = "assistant" if item.role == "bot" else "user"
        payload.append({"role": role, "content": item.content})
    return payload


def _parse_model(text: str) -> dict:
    raw = text.strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        raw = raw.removeprefix("json").strip()
    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end < start:
        return {"reply": text.strip()}
    return json.loads(raw[start : end + 1])


def _ask_model(bot: Bot, history: list[Message], memories: list[str]) -> Turn:
    system = (
        f"你是联伴里的队友{bot.name}，职责是{bot.role}。{bot.persona}\n"
        "用中文短句回答。对外发送、删除、支付、提交、发布、下单、转账、创建日程之前，"
        "不要假装已经做完，把待确认动作写进 approval。\n"
        '只输出 JSON：{"reply":"","approval":null,"memory":null}。'
        'approval 形如 {"action":"发送邮件","detail":"具体内容"}。'
    )
    messages: list[dict[str, str]] = [{"role": "system", "content": system}]
    if memories:
        messages.append({"role": "system", "content": "已经记住：\n" + "\n".join(memories[-12:])})
    messages.extend(_history_payload(history))
    base = settings.model_base_url.rstrip("/")
    response = httpx.post(
        f"{base}/chat/completions",
        headers={"Authorization": f"Bearer {settings.model_api_key}"},
        json={"model": settings.model_name or "default", "messages": messages, "temperature": 0.4},
        timeout=30,
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"]
    data = _parse_model(content if isinstance(content, str) else str(content))
    approval = None
    raw_approval = data.get("approval")
    if isinstance(raw_approval, dict) and raw_approval.get("action"):
        approval = (str(raw_approval.get("action")), str(raw_approval.get("detail") or ""))
    memory = data.get("memory")
    memory_text = str(memory).strip() if isinstance(memory, str) and memory.strip() else None
    reply = str(data.get("reply") or "").strip() or "我先把这件事接下来。"
    return Turn(reply=reply, approval=approval, memory=memory_text, source="model")


def _from_intent(intent: Intent, memory: str | None) -> Turn:
    if intent.kind == "ask":
        reply = intent.summary
    elif intent.kind in {"list", "read"}:
        reply = "我在这台电脑上查看。"
    elif intent.kind == "write":
        reply = "写入还没发生。等华为应用点同意，电脑端才会落盘。"
    elif intent.kind == "run":
        reply = "程序还没跑。等华为应用点同意，电脑端才会运行。"
    else:
        reply = "我先把这个电脑动作停在确认前。"
    if memory:
        reply = f"记住了：{memory}。{reply}"
    turn = Turn(reply=reply, memory=memory, source="local")
    if intent.kind == "list":
        turn.immediate = "list"
    elif intent.kind == "read":
        turn.immediate = "read"
        turn.immediate_path = intent.path
    elif intent.kind == "write":
        turn.approval = ("写入电脑", f"写入 {intent.path}")
        turn.kind = "write_file"
        turn.payload = {"path": intent.path, "content": intent.content}
    elif intent.kind == "run":
        turn.approval = ("运行程序", " ".join(intent.argv))
        turn.kind = "run"
        turn.payload = {"argv": intent.argv}
    return turn


def think(bot: Bot, history: list[Message], memories: list[str], content: str) -> Turn:
    intent = interpret(content)
    local_memory = _local_memory(content)
    if intent is not None:
        return _from_intent(intent, local_memory)
    local_action = _local_approval(content)
    if settings.model_base_url and settings.model_api_key:
        try:
            turn = _ask_model(bot, history, memories)
        except Exception:
            turn = Turn(
                reply="模型暂时连不上，我先用本地队友逻辑接住。",
                source="fallback",
            )
        else:
            if local_action and not turn.approval:
                turn.approval = (local_action, content)
            if local_memory and not turn.memory:
                turn.memory = local_memory
            if turn.approval and "华为应用" not in turn.reply:
                turn.reply = f"{turn.reply} 这一步要等华为应用上点同意。"
            return turn
    else:
        turn = Turn(source="local")

    turn.approval = (local_action, content) if local_action else None
    turn.memory = local_memory
    lead = ""
    if turn.source == "fallback":
        lead = turn.reply
    turn.reply = (lead + _local_reply(bot, content, local_action, local_memory)).strip()
    return turn


def memory_lines(notes: list[MemoryNote]) -> list[str]:
    return [note.content for note in notes]
