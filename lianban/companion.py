"""伴侣协议层：配对、设备鉴权、SSE 事件总线、wire 数据格式。

手机端（联伴鸿蒙）与上游安卓/iOS 伴侣一致：
- POST /api/pair 用一次性凭证换 Bearer token
- 之后所有请求带 Authorization: Bearer {token}
- 事件流走 GET /api/events（SSE）
"""

import asyncio
import hashlib
import json
import secrets
import socket
import threading
import time

from fastapi import HTTPException

from lianban.cache import get_cache
from lianban.computer import lan_url
from lianban.config import ROOT, settings
from lianban.models import Bot, Device, Message

PAIRING_FILE = ROOT / "data" / "pairing.json"
PAIRING_TTL_SECONDS = 120


def server_name() -> str:
    try:
        host = socket.gethostname() or "这台电脑"
    except OSError:
        host = "这台电脑"
    return f"{host} · 联伴"


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def open_pairing() -> dict:
    """开启一个配对窗口：六位码 + 高熵 token，两分钟内单次有效。"""
    code = f"{secrets.randbelow(1000000):06d}"
    token = f"omb_pair_{secrets.token_urlsafe(32)}"
    payload = {"code": code, "token": token, "expires_at": time.time() + PAIRING_TTL_SECONDS}
    PAIRING_FILE.parent.mkdir(parents=True, exist_ok=True)
    PAIRING_FILE.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return payload


def _read_pairing() -> dict | None:
    try:
        payload = json.loads(PAIRING_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict) or payload.get("expires_at", 0) < time.time():
        return None
    return payload


def _consume_pairing_file() -> None:
    try:
        PAIRING_FILE.unlink()
    except OSError:
        pass


def redeem(credential: str, device_name: str) -> dict:
    """兑换配对凭证（六位码或 token），成功后签发长期设备 token。"""
    payload = _read_pairing()
    presented = (credential or "").strip()
    if payload is None:
        raise HTTPException(status_code=401, detail="现在没有进行中的配对，请在电脑上重新开启")
    if presented not in (payload.get("code"), payload.get("token")):
        raise HTTPException(status_code=401, detail="配对码不对，请核对电脑上显示的六位数字")
    _consume_pairing_file()
    token = f"omb_{secrets.token_urlsafe(32)}"
    return {"token": token, "token_hash": _hash(token), "device_name": device_name.strip() or "联伴手机"}


def register_device(db, token_hash: str, device_name: str) -> Device:
    device = (
        db.query(Device)
        .filter(Device.token_hash == token_hash, Device.platform == "harmony")
        .first()
    )
    if device is None:
        device = Device(id=secrets.token_hex(8), name=device_name, platform="harmony", push_token="")
        db.add(device)
    device.name = device_name
    device.token_hash = token_hash
    from lianban.util import now as _now

    device.last_seen = _now()
    db.commit()
    db.refresh(device)
    return device


class Bus:
    """进程内 SSE 事件总线；后台线程发布的帧安全地送到各 asyncio 队列。"""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._subs: list[tuple[asyncio.AbstractEventLoop, asyncio.Queue]] = []

    def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue()
        loop = asyncio.get_running_loop()
        with self._lock:
            self._subs.append((loop, queue))
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        with self._lock:
            self._subs = [(q_loop, q) for q_loop, q in self._subs if q is not queue]

    def publish(self, frame: dict) -> None:
        with self._lock:
            subs = list(self._subs)
        for loop, queue in subs:
            try:
                loop.call_soon_threadsafe(queue.put_nowait, frame)
            except RuntimeError:
                pass


bus = Bus()


def emit_message(message: Message) -> None:
    bus.publish({"kind": "message", "threadId": message.bot_id, "message": wire_message(message)})


def emit_bot(bot_id: str) -> None:
    bus.publish({"kind": "bot", "botId": bot_id})


def wire_bot(bot: Bot, messages: list[Message] | None = None) -> dict:
    cache = get_cache()
    return {
        "id": bot.id,
        "name": bot.name,
        "title": bot.role,
        "description": bot.persona[:120],
        "threadId": bot.id,
        "unread": cache.get_unread(bot.id),
        "busy": cache.get_status(bot.id) == "working",
        "color": "teal",
        "createdAt": int(bot.created_at.timestamp() * 1000) if bot.created_at else 0,
        "messages": [wire_message(item) for item in (messages or [])],
    }


def wire_message(item: Message) -> dict:
    frame: dict = {
        "id": item.id,
        "role": item.role,
        "kind": item.kind or "text",
        "text": item.content,
        "at": int(item.created_at.timestamp() * 1000) if item.created_at else 0,
    }
    card = parse_card(item)
    if card is not None:
        frame["card"] = card
    return frame


def parse_card(item: Message) -> dict | None:
    if not item.card_json:
        return None
    try:
        card = json.loads(item.card_json)
    except json.JSONDecodeError:
        return None
    return card if isinstance(card, dict) else None


def companion_endpoints() -> dict:
    lan = lan_url()
    endpoints = []
    if lan:
        endpoints.append({"url": lan, "kind": "lan", "priority": 0})
    return {"serverName": server_name(), "endpoints": endpoints}


__all__ = [
    "PAIRING_TTL_SECONDS",
    "bus",
    "companion_endpoints",
    "emit_bot",
    "emit_message",
    "open_pairing",
    "redeem",
    "register_device",
    "server_name",
    "wire_bot",
    "wire_message",
]
