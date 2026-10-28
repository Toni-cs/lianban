"""伴侣路由：手机端（联伴鸿蒙）专用的 API 面。

与上游安卓/iOS 伴侣的协议一致；旧 web 端点保持不动、不带鉴权。
"""

import asyncio
import hashlib
import json
import threading

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from lianban import turns
from lianban.cache import get_cache
from lianban.companion import (
    bus,
    companion_endpoints,
    open_pairing,
    redeem,
    register_device,
    server_name,
    wire_bot,
    wire_message,
)
from lianban.computer import lan_url
from lianban.db import SessionLocal, get_db
from lianban.models import Bot, Device, Message

router = APIRouter()


class PairIn(BaseModel):
    credential: str = Field(min_length=1, max_length=128)
    deviceName: str = Field(default="", max_length=60)


class SendIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    threadId: str = Field(default="", max_length=64)


class RespondIn(BaseModel):
    requestId: str = Field(min_length=1, max_length=64)
    behavior: str = Field(pattern="^(allow|deny|answer)$")
    message: str = Field(default="", max_length=2000)
    threadId: str = Field(default="", max_length=64)


class AlwaysAllowIn(BaseModel):
    allowKey: str = Field(min_length=1, max_length=128)
    threadId: str = Field(default="", max_length=64)


class ThreadIn(BaseModel):
    threadId: str = Field(default="", max_length=64)


def _current_device(
    request: Request,
    db: Session = Depends(get_db),
) -> Device:
    auth = request.headers.get("authorization") or ""
    scheme, _, token = auth.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="请先从电脑的「远程访问」配对这台手机")
    token_hash = hashlib.sha256(token.strip().encode("utf-8")).hexdigest()
    device = (
        db.query(Device)
        .filter(Device.token_hash == token_hash, Device.platform == "harmony")
        .first()
    )
    if device is None:
        raise HTTPException(status_code=401, detail="配对已失效，请重新配对")
    return device


def _require_bot(db: Session, bot_id: str) -> Bot:
    bot = db.get(Bot, bot_id)
    if bot is None:
        raise HTTPException(status_code=404, detail="没有这个队友")
    return bot


def _page(messages: list[Message], limit: int) -> list[Message]:
    if limit <= 0:
        return []
    tail = messages[-limit:]
    return list(reversed(tail))  # 最新的在前，与上游分页方向一致


@router.post("/pair")
def pair(payload: PairIn, db: Session = Depends(get_db)) -> dict:
    issued = redeem(payload.credential, payload.deviceName)
    device = register_device(db, issued["token_hash"], issued["device_name"])
    return {
        "token": issued["token"],
        "serverName": server_name(),
        "device": {"id": device.id, "name": device.name},
    }


@router.get("/pair/open")
def pair_open(request: Request) -> dict:
    host = request.client.host if request.client else ""
    if host not in {"127.0.0.1", "::1", "localhost"}:
        raise HTTPException(status_code=403, detail="只能在电脑本机开启配对")
    window = open_pairing()
    lan = lan_url()
    link = f"openmausbot://pair?address={lan.replace('http://', '')}&token={window['token']}&code={window['code']}&name={server_name()}"
    return {"code": window["code"], "link": link, "expiresIn": 120, "serverName": server_name(), "lan": lan}


@router.get("/companion/endpoints")
def endpoints(device: Device = Depends(_current_device)) -> dict:
    return companion_endpoints()


@router.get("/bots")
def list_bots(
    messages: int = 20,
    device: Device = Depends(_current_device),
    db: Session = Depends(get_db),
) -> dict:
    limit = max(0, min(messages, 200))
    bots = db.query(Bot).order_by(Bot.created_at.asc()).all()
    rows = []
    for bot in bots:
        history = (
            db.query(Message)
            .filter(Message.bot_id == bot.id)
            .order_by(Message.created_at.asc())
            .all()
        )
        rows.append(wire_bot(bot, _page(history, limit)))
    return {"bots": rows}


@router.get("/threads/{thread_id}/messages")
def thread_messages(
    thread_id: str,
    limit: int = 40,
    before: str = "",
    device: Device = Depends(_current_device),
    db: Session = Depends(get_db),
) -> dict:
    bot = db.get(Bot, thread_id)
    if bot is None:
        raise HTTPException(status_code=404, detail="没有这个对话")
    history = (
        db.query(Message)
        .filter(Message.bot_id == bot.id)
        .order_by(Message.created_at.asc())
        .all()
    )
    if before:
        ids = [item.id for item in history]
        if before not in ids:
            raise HTTPException(status_code=404, detail="没有这条消息")
        history = history[: ids.index(before)]
    size = max(0, min(limit, 200))
    page = _page(history, size)
    return {
        "messages": [wire_message(item) for item in page],
        "hasMore": len(history) > size,
        "activeLeafId": page[0].id if page else None,
    }


@router.post("/bots/{bot_id}/messages", status_code=202)
def send_message(
    bot_id: str,
    payload: SendIn,
    device: Device = Depends(_current_device),
) -> dict:
    if payload.threadId and payload.threadId != bot_id:
        raise HTTPException(status_code=400, detail="threadId 必须是这个队友的对话")
    db_probe = SessionLocal()
    try:
        _require_bot(db_probe, bot_id)
    finally:
        db_probe.close()
    threading.Thread(target=_background_turn, args=(bot_id, payload.text), daemon=True).start()
    return {"ok": True, "threadId": bot_id}


def _background_turn(bot_id: str, text: str) -> None:
    db = SessionLocal()
    try:
        turns.run_turn(db, bot_id, text)
    except Exception:
        get_cache().set_status(bot_id, "idle")
    finally:
        db.close()


@router.post("/bots/{bot_id}/respond")
def respond(
    bot_id: str,
    payload: RespondIn,
    device: Device = Depends(_current_device),
    db: Session = Depends(get_db),
) -> dict:
    _require_bot(db, bot_id)
    behavior = payload.behavior
    if behavior == "answer":
        if not payload.message.strip():
            raise HTTPException(status_code=400, detail="回答内容不能为空")
        turns.answer_card(db, bot_id, payload.requestId, payload.message.strip())
        return {"ok": True, "outcome": "answered"}
    decision = "approved" if behavior == "allow" else "rejected"
    try:
        turns.decide_approval(db, payload.requestId, decision, via="harmony")
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "outcome": decision}


@router.post("/bots/{bot_id}/always-allow")
def always_allow(
    bot_id: str,
    payload: AlwaysAllowIn,
    device: Device = Depends(_current_device),
    db: Session = Depends(get_db),
) -> dict:
    bot = _require_bot(db, bot_id)
    try:
        turns.always_allow(db, bot_id, payload.allowKey)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    db.refresh(bot)
    history = (
        db.query(Message)
        .filter(Message.bot_id == bot.id)
        .order_by(Message.created_at.asc())
        .all()
    )
    return {"bot": wire_bot(bot, _page(history, 20))}


@router.post("/bots/{bot_id}/read")
def mark_read(
    bot_id: str,
    payload: ThreadIn,
    device: Device = Depends(_current_device),
    db: Session = Depends(get_db),
) -> dict:
    bot = _require_bot(db, bot_id)
    turns.mark_read(db, bot_id)
    history = (
        db.query(Message)
        .filter(Message.bot_id == bot.id)
        .order_by(Message.created_at.asc())
        .all()
    )
    return {"bot": wire_bot(bot, _page(history, 20))}


@router.post("/bots/{bot_id}/interrupt")
def interrupt(
    bot_id: str,
    payload: ThreadIn,
    device: Device = Depends(_current_device),
    db: Session = Depends(get_db),
) -> dict:
    _require_bot(db, bot_id)
    turns.request_interrupt(db, bot_id)
    return {"ok": True}


@router.get("/events")
async def events(request: Request, device: Device = Depends(_current_device)) -> StreamingResponse:
    queue = bus.subscribe()

    async def stream():
        hello = json.dumps({"kind": "hello", "cursor": f"lianban:{id(queue):x}", "resumed": False}, ensure_ascii=False)
        yield f"data: {hello}\n\n"
        try:
            while True:
                if await request.is_disconnected():
                    break
                try:
                    frame = await asyncio.wait_for(queue.get(), timeout=15.0)
                    yield f"data: {json.dumps(frame, ensure_ascii=False)}\n\n"
                except asyncio.TimeoutError:
                    yield ": ping\n\n"
        finally:
            bus.unsubscribe(queue)

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
