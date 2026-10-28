from pydantic import BaseModel, Field


class BotIn(BaseModel):
    name: str = Field(min_length=1, max_length=32)
    role: str = Field(min_length=1, max_length=64)
    persona: str = Field(default="", max_length=500)


class BotOut(BaseModel):
    id: str
    name: str
    role: str
    persona: str
    status: str
    created_at: str


class MessageIn(BaseModel):
    content: str = Field(min_length=1, max_length=4000)


class MessageOut(BaseModel):
    id: str
    bot_id: str
    role: str
    content: str
    created_at: str


class MemoryOut(BaseModel):
    id: str
    content: str
    created_at: str


class ApprovalOut(BaseModel):
    id: str
    bot_id: str
    bot_name: str
    action: str
    detail: str
    kind: str = ""
    status: str
    created_at: str
    decided_at: str | None = None


class DecisionIn(BaseModel):
    decision: str = Field(pattern="^(approved|rejected)$")


class DeviceIn(BaseModel):
    device_id: str = ""
    name: str = Field(min_length=1, max_length=32)
    platform: str = Field(pattern="^(web|harmony)$")
    push_token: str = Field(default="", max_length=512)


class DeviceOut(BaseModel):
    id: str
    name: str
    platform: str
    has_push_token: bool
    last_seen: str


class NoticeOut(BaseModel):
    id: str
    approval_id: str
    bot_id: str
    title: str
    body: str
    push_status: str
    push_detail: str
    created_at: str
    read: bool


class ChatOut(BaseModel):
    message: MessageOut
    approval: ApprovalOut | None = None
    notice: NoticeOut | None = None
    source: str
