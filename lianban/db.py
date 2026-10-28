from collections.abc import Generator

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from lianban.config import ROOT, settings


class Base(DeclarativeBase):
    pass


def _engine():
    url = settings.database_url
    connect_args = {"check_same_thread": False} if url.startswith("sqlite") else {}
    return create_engine(url, pool_pre_ping=True, connect_args=connect_args)


engine = _engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _ensure_approval_columns() -> None:
    tables = set(inspect(engine).get_table_names())
    if "approvals" not in tables:
        return
    names = {column["name"] for column in inspect(engine).get_columns("approvals")}
    with engine.begin() as conn:
        if "kind" not in names:
            conn.execute(text("ALTER TABLE approvals ADD COLUMN kind VARCHAR(32) DEFAULT ''"))
        if "payload" not in names:
            conn.execute(text("ALTER TABLE approvals ADD COLUMN payload TEXT DEFAULT ''"))


def _ensure_companion_columns() -> None:
    tables = set(inspect(engine).get_table_names())
    if "messages" in tables:
        names = {column["name"] for column in inspect(engine).get_columns("messages")}
        with engine.begin() as conn:
            if "kind" not in names:
                conn.execute(text("ALTER TABLE messages ADD COLUMN kind VARCHAR(16) DEFAULT 'text'"))
            if "card_json" not in names:
                conn.execute(text("ALTER TABLE messages ADD COLUMN card_json TEXT DEFAULT ''"))
    if "devices" in tables:
        names = {column["name"] for column in inspect(engine).get_columns("devices")}
        with engine.begin() as conn:
            if "token_hash" not in names:
                conn.execute(text("ALTER TABLE devices ADD COLUMN token_hash VARCHAR(64) DEFAULT ''"))
    if "bots" in tables:
        names = {column["name"] for column in inspect(engine).get_columns("bots")}
        with engine.begin() as conn:
            if "always_allow" not in names:
                conn.execute(text("ALTER TABLE bots ADD COLUMN always_allow TEXT DEFAULT '[]'"))


def init_db() -> None:
    from lianban.computer import ensure_workspace
    from lianban.models import Bot

    (ROOT / "data").mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    _ensure_approval_columns()
    _ensure_companion_columns()
    ensure_workspace()
    db = SessionLocal()
    try:
        if db.query(Bot).count() > 0:
            return
        from lianban.util import new_id

        db.add_all(
            [
                Bot(
                    id=new_id(),
                    name="林知",
                    role="课程助教",
                    persona="在这台电脑的工作区里处理选课和作业。写入文件或运行脚本之前，必须等华为应用点同意。",
                ),
                Bot(
                    id=new_id(),
                    name="周衡",
                    role="实验搭档",
                    persona="在这台电脑上整理实验记录和脚本。查看可以直接做，改动电脑要等华为应用确认。",
                ),
            ]
        )
        db.commit()
    finally:
        db.close()
