"""回合执行核心：写用户消息 → 思考 → 回复 / 批准卡片 / 记忆。

旧 web 端点同步调用，伴侣端点放后台线程调用；
两种入口共享同一份逻辑，所以手机和电脑看到的是同一条对话。
"""

import json

from sqlalchemy.orm import Session

from lianban.cache import get_cache
from lianban.companion import emit_bot, emit_message
from lianban.computer import perform
from lianban.engine import memory_lines, think
from lianban.huawei import push_ready, send_push
from lianban.models import Approval, Bot, ComputerEvent, Device, MemoryNote, Message, Notice
from lianban.util import new_id, now


def _log(db: Session, bot_id: str, kind: str, text: str) -> None:
    db.add(ComputerEvent(id=new_id(), bot_id=bot_id, kind=kind, text=text[:2000]))


def _publish(db: Session, title: str, body: str, bot_id: str = "", approval_id: str = "") -> Notice:
    tokens = [item.push_token for item in db.query(Device).all() if item.push_token]
    status, detail = send_push(title, body, tokens)
    notice = Notice(
        id=new_id(),
        approval_id=approval_id,
        bot_id=bot_id,
        title=title,
        body=body,
        push_status=status,
        push_detail=detail,
        read=False,
    )
    db.add(notice)
    return notice


def _bot_always_allow(bot: Bot) -> set[str]:
    try:
        data = json.loads(bot.always_allow or "[]")
    except json.JSONDecodeError:
        return set()
    return {item for item in data if isinstance(item, str)} if isinstance(data, list) else set()


def _payload_dict(payload: object) -> dict:
    """payload 可能是 dict、JSON 字符串或 None；统一成 dict。"""
    if isinstance(payload, dict):
        return payload
    if isinstance(payload, str) and payload.strip():
        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            return {}
        return data if isinstance(data, dict) else {}
    return {}


def _save_always_allow(db: Session, bot: Bot, keys: set[str]) -> None:
    bot.always_allow = json.dumps(sorted(keys), ensure_ascii=False)
    db.commit()


def _add_message(db: Session, bot_id: str, role: str, content: str, kind: str = "text", card_json: str = "") -> Message:
    message = Message(
        id=new_id(),
        bot_id=bot_id,
        role=role,
        content=content,
        kind=kind,
        card_json=card_json,
    )
    db.add(message)
    return message


def _card_json_for(approval: Approval, allow_key: str) -> str:
    card = {
        "title": approval.action,
        "subtitle": approval.detail,
        "options": ["允许", "拒绝"],
        "requestType": "permission",
        "requestId": approval.id,
        "allowKey": allow_key,
    }
    return json.dumps(card, ensure_ascii=False)


def run_turn(db: Session, bot_id: str, text: str) -> dict:
    """执行一轮对话；返回旧 web 端点需要的摘要字段。"""
    bot = db.get(Bot, bot_id)
    if bot is None:
        raise ValueError("没有这个队友")
    content = text.strip()
    if not content:
        raise ValueError("消息不能为空")

    user_message = _add_message(db, bot.id, "user", content)
    db.commit()
    emit_message(user_message)
    emit_bot(bot.id)

    cache = get_cache()
    cache.set_status(bot.id, "working")
    cache.set_unread(bot.id, True)
    emit_bot(bot.id)
    approval_out = None
    notice_out = None
    card_message: Message | None = None
    try:
        history = db.query(Message).filter(Message.bot_id == bot.id).order_by(Message.created_at.asc()).all()
        notes = db.query(MemoryNote).filter(MemoryNote.bot_id == bot.id).order_by(MemoryNote.created_at.asc()).all()
        turn = think(bot, history, memory_lines(notes), content)

        if get_cache().get_status(bot.id) == "canceling":
            stopped = _add_message(db, bot.id, "bot", "已按你的要求停止，这一轮不再继续。")
            db.commit()
            emit_message(stopped)
            return {
                "message": stopped,
                "approval": None,
                "notice": None,
                "source": "interrupted",
            }

        reply_text = turn.reply
        if turn.immediate:
            try:
                result = perform(turn.immediate, {"path": turn.immediate_path})
            except ValueError as exc:
                result = str(exc)
            _log(db, bot.id, turn.immediate, result)
            reply_text = f"{reply_text}\n{result}"

        allow_keys = _bot_always_allow(bot)
        if turn.approval:
            action, detail = turn.approval
            allow_key = turn.kind or f"action:{action}"
            if allow_key in allow_keys:
                if turn.kind:
                    data = _payload_dict(turn.payload)
                    try:
                        result = perform(turn.kind, data)
                    except ValueError as exc:
                        result = str(exc)
                    _log(db, bot.id, turn.kind, result)
                    reply_text = f"{reply_text}\n已按「始终允许」直接执行：{result}"
                else:
                    reply_text = f"{reply_text}\n这一步在「始终允许」名单里，不再单独确认。"
            else:
                approval = Approval(
                    id=new_id(),
                    bot_id=bot.id,
                    action=action,
                    detail=detail,
                    kind=turn.kind,
                    payload=json.dumps(turn.payload or {}, ensure_ascii=False),
                    status="pending",
                )
                db.add(approval)
                db.flush()
                card_message = _add_message(
                    db, bot.id, "bot", f"等你确认：{action}", kind="options",
                    card_json=_card_json_for(approval, allow_key),
                )
                notice = _publish(
                    db,
                    title=f"{bot.name}请求确认",
                    body=f"{action}：{detail[:80]}",
                    bot_id=bot.id,
                    approval_id=approval.id,
                )
                approval_out = approval
                notice_out = notice

        if turn.memory:
            db.add(MemoryNote(id=new_id(), bot_id=bot.id, content=turn.memory))
        reply = _add_message(db, bot.id, "bot", reply_text)
        db.commit()
        db.refresh(reply)
        if card_message is not None:
            db.refresh(card_message)
            emit_message(card_message)
        emit_message(reply)
        emit_bot(bot.id)
        return {
            "message": reply,
            "approval": approval_out,
            "notice": notice_out,
            "source": turn.source,
        }
    finally:
        cache.set_status(bot.id, "idle")
        cache.set_unread(bot.id, True)
        emit_bot(bot.id)


def decide_approval(db: Session, approval_id: str, decision: str, via: str = "web") -> dict:
    """处理一张批准卡片：allow → 执行，deny → 拒绝。"""
    approval = db.get(Approval, approval_id)
    if approval is None:
        raise ValueError("没有这条确认")
    if approval.status != "pending":
        raise ValueError("这条确认已经处理过")
    bot = db.get(Bot, approval.bot_id)
    if bot is None:
        raise ValueError("没有这个队友")
    approval.status = "approved" if decision == "approved" else "rejected"
    approval.decided_at = now()
    if decision == "approved":
        title = f"{bot.name}已开始执行"
        if approval.kind:
            data = _payload_dict(approval.payload)
            try:
                result = perform(approval.kind, data)
            except ValueError as exc:
                result = str(exc)
            _log(db, bot.id, approval.kind, result)
            reply_text = f"华为应用已同意「{approval.action}」。电脑端结果：{result}"
        else:
            reply_text = f"华为应用已同意「{approval.action}」。我开始执行：{approval.detail}"
    else:
        reply_text = f"华为应用已拒绝「{approval.action}」。电脑端不会执行。"
        title = f"{bot.name}已取消"
        _log(db, bot.id, "rejected", reply_text)
    reply = _add_message(db, bot.id, "bot", reply_text)
    notice = _publish(db, title=title, body=reply_text[:80], bot_id=bot.id)
    _settle_card(db, approval.id, "允许" if decision == "approved" else "拒绝")
    db.commit()
    db.refresh(reply)
    emit_message(reply)
    emit_bot(bot.id)
    return {"message": reply, "approval": approval, "notice": notice, "source": via}


def answer_card(db: Session, bot_id: str, request_id: str, answer: str) -> Message:
    """把一句话答案写进对话（提问卡的回答路径）。"""
    bot = db.get(Bot, bot_id)
    if bot is None:
        raise ValueError("没有这个队友")
    _settle_card(db, request_id, answer)
    user_reply = _add_message(db, bot.id, "user", answer)
    db.commit()
    db.refresh(user_reply)
    emit_message(user_reply)
    return user_reply


def _settle_card(db: Session, request_id: str, answered: str) -> None:
    """把卡片消息标记为已回答（answered 字段与上游 wire 卡片一致）。"""
    rows = db.query(Message).filter(Message.kind == "options").all()
    for row in rows:
        if not row.card_json:
            continue
        try:
            card = json.loads(row.card_json)
        except json.JSONDecodeError:
            continue
        if isinstance(card, dict) and card.get("requestId") == request_id:
            card["answered"] = answered
            card["answeredText"] = answered
            row.card_json = json.dumps(card, ensure_ascii=False)
            db.add(row)
            emit_message(row)


def always_allow(db: Session, bot_id: str, allow_key: str) -> Bot:
    """把 allowKey 加入队友的始终允许名单。"""
    bot = db.get(Bot, bot_id)
    if bot is None:
        raise ValueError("没有这个队友")
    if not allow_key:
        raise ValueError("allowKey 不能为空")
    pending = (
        db.query(Approval)
        .filter(Approval.bot_id == bot_id, Approval.status == "pending")
        .all()
    )
    card_match = False
    for row in db.query(Message).filter(Message.kind == "options").all():
        if not row.card_json:
            continue
        try:
            card = json.loads(row.card_json)
        except json.JSONDecodeError:
            continue
        if isinstance(card, dict) and card.get("allowKey") == allow_key and not card.get("answered"):
            card_match = True
    if not card_match and not any(p.kind == allow_key or p.action == allow_key for p in pending):
        raise ValueError("这个授权不在待确认的批准里")
    keys = _bot_always_allow(bot)
    keys.add(allow_key)
    _save_always_allow(db, bot, keys)
    emit_bot(bot.id)
    return bot


def mark_read(db: Session, bot_id: str) -> None:
    get_cache().set_unread(bot_id, False)
    emit_bot(bot_id)


def request_interrupt(db: Session, bot_id: str) -> bool:
    """请求中断：回合线程在思考返回后检查该标志。"""
    if get_cache().get_status(bot_id) != "working":
        return False
    get_cache().set_status(bot_id, "canceling")
    emit_bot(bot_id)
    return True
