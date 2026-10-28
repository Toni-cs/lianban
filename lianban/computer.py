import re
import socket
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from lianban.config import ROOT, settings

_NAME = r"([\w\u4e00-\u9fff][\w\u4e00-\u9fff.\-]{0,48}\.(?:txt|md|py|json|csv))"
_LIST_WORDS = ("有哪些文件", "文件列表", "列出文件", "看看文件", "电脑上有什么", "电脑里有什么", "工作区")
_ALLOWED_SUFFIX = {".txt", ".md", ".py", ".json", ".csv"}


@dataclass
class Intent:
    kind: str
    path: str = ""
    content: str = ""
    argv: list[str] = field(default_factory=list)
    summary: str = ""


def workspace():
    raw = settings.computer_dir or str(ROOT / "data" / "computer")
    path = Path(raw)
    path.mkdir(parents=True, exist_ok=True)
    return path


def ensure_workspace() -> None:
    root = workspace()
    note = root / "实验记录.txt"
    if not note.exists():
        note.write_text(
            "这是联伴电脑端的工作区。\n队友只能在这个文件夹里读写。\n写入和运行要等华为应用点同意。\n",
            encoding="utf-8",
        )
    script = root / "hello.py"
    if not script.exists():
        script.write_text('print("电脑端脚本已运行")\n', encoding="utf-8")


def resolve(rel: str):
    raw = rel.strip().replace("\\", "/")
    if not raw or raw.startswith(("/", ".")) or ":" in raw or ".." in raw.split("/"):
        raise ValueError("只能使用电脑工作区里的相对路径")
    root = workspace().resolve()
    path = (root / raw).resolve()
    if path != root and root not in path.parents:
        raise ValueError("不能超出电脑工作区")
    return path


def list_files() -> list[dict]:
    root = workspace().resolve()
    items = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        items.append({"path": path.relative_to(root).as_posix(), "size": path.stat().st_size})
    items.sort(key=lambda item: item["path"])
    return items[:200]


def read_file(rel: str) -> str:
    path = resolve(rel)
    if not path.is_file():
        raise ValueError("电脑上没有这个文件")
    return path.read_text(encoding="utf-8", errors="replace")[:8000]


def write_file(rel: str, content: str) -> None:
    if len(content) > 20000:
        raise ValueError("内容超过 20000 字")
    path = resolve(rel)
    if path.suffix.lower() not in _ALLOWED_SUFFIX:
        raise ValueError("只能写入 txt、md、py、json、csv")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def run_python(argv: list[str]) -> str:
    if len(argv) != 2 or argv[0].lower() not in {"python", "py"}:
        raise ValueError("只允许 python --version，或 python 工作区里的某个.py 脚本")
    if any(token in arg for arg in argv for token in ("|", "&", ";", ">", "<", "`", "$", "\n")):
        raise ValueError("命令里不能带管道或重定向")
    arg = argv[1]
    if arg == "--version":
        command = [sys.executable, "--version"]
    elif arg.endswith(".py") and "/" not in arg and "\\" not in arg:
        script = resolve(arg)
        if not script.is_file():
            raise ValueError("工作区里没有这个脚本")
        command = [sys.executable, str(script)]
    else:
        raise ValueError("只允许 python --version，或 python 工作区里的某个.py 脚本")
    try:
        completed = subprocess.run(
            command,
            cwd=str(workspace()),
            capture_output=True,
            text=True,
            timeout=8,
            shell=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise ValueError("脚本运行超过 8 秒，已停掉") from exc
    output = (completed.stdout + completed.stderr).strip()
    return (output or f"退出码 {completed.returncode}")[:4000]


def perform(kind: str, payload: dict) -> str:
    if kind == "list":
        names = [item["path"] for item in list_files()]
        return "、".join(names) or "工作区是空的"
    if kind == "read":
        return read_file(str(payload.get("path") or ""))
    if kind == "write_file":
        path = str(payload.get("path") or "")
        write_file(path, str(payload.get("content") or ""))
        return f"已写入 {path}"
    if kind == "run":
        argv = payload.get("argv") or []
        if not isinstance(argv, list):
            raise ValueError("运行参数不正确")
        return run_python([str(item) for item in argv])
    raise ValueError("没有可在电脑上执行的动作")


def interpret(text: str) -> Intent | None:
    write = re.search(rf"(?:写入|写到|保存到|保存成|新建)\s*{_NAME}", text)
    if write:
        name = write.group(1)
        after = text.split(name, 1)[1]
        found = re.search(r"(?:内容是|内容为)\s*(.+)$", after)
        content = found.group(1).strip() if found else after.strip(" ：:，,。")
        if not content:
            return Intent(kind="ask", path=name, summary=f"要写入《{name}》的话，请补上内容。")
        return Intent(kind="write", path=name, content=content)
    run = re.search(r"(?:运行|执行)\s+(?:python|py)\s+(\S+)", text, re.I)
    if run:
        arg = run.group(1).strip("。")
        if arg == "--version" or (arg.endswith(".py") and "/" not in arg and "\\" not in arg):
            return Intent(kind="run", argv=["python", arg])
        return Intent(kind="ask", summary="这台电脑只接受 python --version，或 python 某个.py 脚本。")
    read = re.search(rf"(?:读取|打开|查看|看一下)\s*{_NAME}", text)
    if read:
        return Intent(kind="read", path=read.group(1))
    if any(word in text for word in _LIST_WORDS):
        return Intent(kind="list")
    return None


def lan_url() -> str:
    ip = "127.0.0.1"
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.2)
    try:
        sock.connect(("192.168.1.1", 80))
        ip = sock.getsockname()[0]
    except OSError:
        pass
    finally:
        sock.close()
    return f"http://{ip}:{settings.port}"
