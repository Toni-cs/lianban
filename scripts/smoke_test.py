import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
database = Path(tempfile.mkstemp(suffix=".db")[1])
computer = Path(tempfile.mkdtemp())
os.environ["DATABASE_URL"] = "sqlite:///" + database.as_posix()
os.environ["COMPUTER_DIR"] = str(computer)
os.environ["REDIS_URL"] = ""
os.environ["MODEL_BASE_URL"] = ""
os.environ["MODEL_API_KEY"] = ""
os.environ["HUAWEI_SA_FILE"] = ""

from fastapi.testclient import TestClient
from lianban.computer import write_file
from lianban.main import app


def main() -> None:
    with TestClient(app) as client:
        health = client.get("/api/health")
        assert health.status_code == 200, health.text
        assert health.json()["app"] == "联伴"

        bots = client.get("/api/bots").json()
        bot_id = bots[0]["id"]
        listed = client.post(f"/api/bots/{bot_id}/messages", json={"content": "看看文件"})
        assert listed.status_code == 200, listed.text
        assert "实验记录.txt" in listed.json()["message"]["content"]
        assert listed.json()["approval"] is None

        asked = client.post(
            f"/api/bots/{bot_id}/messages",
            json={"content": "请把内容写到 报告.txt：电路实验完成"},
        )
        assert asked.status_code == 200, asked.text
        approval = asked.json()["approval"]
        assert approval["kind"] == "write_file"
        assert not (computer / "报告.txt").exists()

        denied = client.post(
            f"/api/approvals/{approval['id']}/decision",
            json={"decision": "rejected"},
        )
        assert denied.status_code == 200, denied.text
        assert not (computer / "报告.txt").exists()

        again = client.post(
            f"/api/bots/{bot_id}/messages",
            json={"content": "请把内容写到 报告.txt：电路实验完成"},
        )
        approval_id = again.json()["approval"]["id"]
        allowed = client.post(f"/api/approvals/{approval_id}/decision", json={"decision": "approved"})
        assert allowed.status_code == 200, allowed.text
        assert (computer / "报告.txt").read_text(encoding="utf-8") == "电路实验完成"
        assert "已写入" in allowed.json()["message"]["content"]

        run = client.post(f"/api/bots/{bot_id}/messages", json={"content": "请运行 python hello.py"})
        run_id = run.json()["approval"]["id"]
        ran = client.post(f"/api/approvals/{run_id}/decision", json={"decision": "approved"})
        assert ran.status_code == 200, ran.text
        assert "电脑端脚本已运行" in ran.json()["message"]["content"]

        files = client.get("/api/computer").json()["files"]
        assert any(item["path"] == "报告.txt" for item in files)
        page = client.get("/")
        assert page.status_code == 200 and "电脑端" in page.text
        control = client.get("/control")
        assert control.status_code == 200 and "华为应用" in control.text

    try:
        write_file("../outside.txt", "no")
        raise SystemExit("路径逃逸没有被拦住")
    except ValueError:
        pass
    print("smoke ok")


if __name__ == "__main__":
    main()
