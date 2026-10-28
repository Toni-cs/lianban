from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from lianban.db import Base
from lianban.util import now


class Bot(Base):
    __tablename__ = "bots"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    role: Mapped[str] = mapped_column(String(128), nullable=False)
    persona: Mapped[str] = mapped_column(Text, default="")
    always_allow: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[DateTime] = mapped_column(DateTime, default=now)


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    bot_id: Mapped[str] = mapped_column(String(32), ForeignKey("bots.id"), index=True)
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(String(16), default="text")
    card_json: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[DateTime] = mapped_column(DateTime, default=now)


class MemoryNote(Base):
    __tablename__ = "memories"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    bot_id: Mapped[str] = mapped_column(String(32), ForeignKey("bots.id"), index=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(DateTime, default=now)


class Approval(Base):
    __tablename__ = "approvals"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    bot_id: Mapped[str] = mapped_column(String(32), ForeignKey("bots.id"), index=True)
    action: Mapped[str] = mapped_column(String(128), nullable=False)
    detail: Mapped[str] = mapped_column(Text, default="")
    kind: Mapped[str] = mapped_column(String(32), default="")
    payload: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime, default=now)
    decided_at: Mapped[DateTime | None] = mapped_column(DateTime, nullable=True)


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    platform: Mapped[str] = mapped_column(String(32), nullable=False)
    push_token: Mapped[str] = mapped_column(String(512), default="")
    token_hash: Mapped[str] = mapped_column(String(64), default="", index=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime, default=now)
    last_seen: Mapped[DateTime] = mapped_column(DateTime, default=now)


class Notice(Base):
    __tablename__ = "notices"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    approval_id: Mapped[str] = mapped_column(String(32), default="")
    bot_id: Mapped[str] = mapped_column(String(32), default="")
    title: Mapped[str] = mapped_column(String(128), nullable=False)
    body: Mapped[str] = mapped_column(Text, default="")
    push_status: Mapped[str] = mapped_column(String(32), default="skipped")
    push_detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[DateTime] = mapped_column(DateTime, default=now)
    read: Mapped[bool] = mapped_column(Boolean, default=False)


class ComputerEvent(Base):
    __tablename__ = "computer_events"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    bot_id: Mapped[str] = mapped_column(String(32), default="", index=True)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    text: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[DateTime] = mapped_column(DateTime, default=now)
