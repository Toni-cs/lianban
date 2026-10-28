import json

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from lianban import turns
from lianban.cache import get_cache
from lianban.computer import lan_url, list_files
from lianban.config import settings
from lianban.db import get_db
from lianban.huawei import push_ready
from lianban.models import Approval, Bot, ComputerEvent, Device, MemoryNote, Message, Notice
from lianban.schemas import (
    ApprovalOut,
    BotIn,
    BotOut,
    ChatOut,
    DecisionIn,
    DeviceIn,
    DeviceOut,
    MemoryOut,
    MessageIn,
    MessageOut,
    NoticeOut,
)
from lianban.util import iso, new_id

router = APIRouter()


def _bot_out(bot: Bot) -> BotOut:
    return BotOut(
        id=bot.id,
        name=bot.name,
        role=bot.role,
        persona=bot.persona,
        status=get_cache().get_status(bot.id),
        created_at=iso(bot.created_at) or "",
    )


def _message_out(item: Message) -> MessageOut:
    return MessageOut(
        id=item.id,
        bot_id=item.bot_id,
        role=item.role,
        content=item.content,
        created_at=iso(item.created_at) or "",
    )


def _approval_out(item: Approval, bot_name: str) -> ApprovalOut:
    return ApprovalOut(
        id=item.id,
        bot_id=item.bot_id,
        bot_name=bot_name,
        action=item.action,
        detail=item.detail,
        kind=item.kind or "",
        status=item.status,
        created_at=iso(item.created_at) or "",
        decided_at=iso(item.decided_at),
    )


def _notice_out(item: Notice) -> NoticeOut:
    return NoticeOut(
        id=item.id,
        approval_id=item.approval_id,
        bot_id=item.bot_id,
        title=item.title,
        body=item.body,
        push_status=item.push_status,
        push_detail=item.push_detail,
        created_at=iso(item.created_at) or "",
        read=item.read,
    )


def _require_bot(db: Session, bot_id: str) -> Bot:
    bot = db.get(Bot, bot_id)
    if bot is None:
        raise HTTPException(status_code=404, detail="没有这个队友")
    return bot


@router.get("/health")
def health() -> dict:
    cache = get_cache()
    database = "mysql" if settings.database_url.startswith("mysql") else "sqlite"
    try:
        cache_ok = cache.ping()
    except Exception:
        cache_ok = False
    return {
        "app": settings.app_name,
        "database": database,
        "cache": cache.name,
        "cache_ok": cache_ok,
        "model": "remote" if settings.model_base_url and settings.model_api_key else "local",
        "huawei_push": "ready" if push_ready() else "unconfigured",
        "computer": lan_url(),
    }


@router.get("/bots", response_model=list[BotOut])
def list_bots(db: Session = Depends(get_db)) -> list[BotOut]:
    bots = db.query(Bot).order_by(Bot.created_at.asc()).all()
    return [_bot_out(bot) for bot in bots]


@router.post("/bots", response_model=BotOut)
def create_bot(payload: BotIn, db: Session = Depends(get_db)) -> BotOut:
    bot = Bot(id=new_id(), name=payload.name.strip(), role=payload.role.strip(), persona=payload.persona.strip())
    db.add(bot)
    db.commit()
    db.refresh(bot)
    return _bot_out(bot)


@router.get("/bots/{bot_id}/messages", response_model=list[MessageOut])
def list_messages(bot_id: str, db: Session = Depends(get_db)) -> list[MessageOut]:
    _require_bot(db, bot_id)
    rows = db.query(Message).filter(Message.bot_id == bot_id).order_by(Message.created_at.asc()).all()
    return [_message_out(item) for item in rows]


@router.get("/bots/{bot_id}/memories", response_model=list[MemoryOut])
def list_memories(bot_id: str, db: Session = Depends(get_db)) -> list[MemoryOut]:
    _require_bot(db, bot_id)
    rows = db.query(MemoryNote).filter(MemoryNote.bot_id == bot_id).order_by(MemoryNote.created_at.asc()).all()
    return [MemoryOut(id=item.id, content=item.content, created_at=iso(item.created_at) or "") for item in rows]


@router.post("/bots/{bot_id}/messages", response_model=ChatOut)
def send_message(bot_id: str, payload: MessageIn, db: Session = Depends(get_db)) -> ChatOut:
    bot = _require_bot(db, bot_id)
    try:
        result = turns.run_turn(db, bot.id, payload.content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ChatOut(
        message=_message_out(result["message"]),
        approval=_approval_out(result["approval"], bot.name) if result["approval"] else None,
        notice=_notice_out(result["notice"]) if result["notice"] else None,
        source=result["source"],
    )


@router.get("/approvals", response_model=list[ApprovalOut])
def list_approvals(status: str = "", db: Session = Depends(get_db)) -> list[ApprovalOut]:
    query = db.query(Approval, Bot.name).join(Bot, Bot.id == Approval.bot_id)
    if status:
        query = query.filter(Approval.status == status)
    rows = query.order_by(Approval.created_at.desc()).all()
    return [_approval_out(item, name) for item, name in rows]


@router.post("/approvals/{approval_id}/decision", response_model=ChatOut)
def decide(approval_id: str, payload: DecisionIn, db: Session = Depends(get_db)) -> ChatOut:
    try:
        result = turns.decide_approval(db, approval_id, payload.decision, via="web")
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    bot = _require_bot(db, result["approval"].bot_id)
    return ChatOut(
        message=_message_out(result["message"]),
        approval=_approval_out(result["approval"], bot.name),
        notice=_notice_out(result["notice"]),
        source=result["source"],
    )


@router.post("/app/register", response_model=DeviceOut)
def register_device(payload: DeviceIn, db: Session = Depends(get_db)) -> DeviceOut:
    device = db.get(Device, payload.device_id) if payload.device_id else None
    if device is None:
        device = Device(id=payload.device_id or new_id(), name=payload.name.strip(), platform=payload.platform)
        db.add(device)
    device.name = payload.name.strip()
    device.platform = payload.platform
    device.push_token = payload.push_token.strip()
    device.last_seen = now()
    db.commit()
    db.refresh(device)
    return DeviceOut(
        id=device.id,
        name=device.name,
        platform=device.platform,
        has_push_token=bool(device.push_token),
        last_seen=iso(device.last_seen) or "",
    )


@router.get("/app/devices", response_model=list[DeviceOut])
def list_devices(db: Session = Depends(get_db)) -> list[DeviceOut]:
    rows = db.query(Device).order_by(Device.last_seen.desc()).all()
    return [
        DeviceOut(
            id=item.id,
            name=item.name,
            platform=item.platform,
            has_push_token=bool(item.push_token),
            last_seen=iso(item.last_seen) or "",
        )
        for item in rows
    ]


@router.get("/computer")
def computer(db: Session = Depends(get_db)) -> dict:
    rows = db.query(ComputerEvent).order_by(ComputerEvent.created_at.desc()).limit(60).all()
    rows.reverse()
    pending = db.query(Approval).filter(Approval.status == "pending").count()
    return {
        "lan": lan_url(),
        "files": list_files(),
        "pending": pending,
        "events": [
            {
                "id": item.id,
                "bot_id": item.bot_id,
                "kind": item.kind,
                "text": item.text,
                "created_at": iso(item.created_at) or "",
            }
            for item in rows
        ],
    }


@router.get("/computer/file")
def computer_file(path: str) -> dict:
    try:
        content = perform("read", {"path": path})
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"path": path, "content": content}


@router.get("/app/inbox", response_model=list[NoticeOut])
def inbox(db: Session = Depends(get_db)) -> list[NoticeOut]:
    rows = db.query(Notice).order_by(Notice.created_at.desc()).limit(40).all()
    return [_notice_out(item) for item in rows]
