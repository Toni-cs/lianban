"""伴侣协议全链路自测：模拟手机端（联伴鸿蒙）的完整交互。"""

import json
import os
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.getcwd())

import httpx

BASE = "http://127.0.0.1:8810"


def main() -> int:
    failures: list[str] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        mark = "PASS" if ok else "FAIL"
        print(f"[{mark}] {name} {detail}")
        if not ok:
            failures.append(name)

    from lianban.db import SessionLocal
    from lianban.models import Bot as BotRow

    db = SessionLocal()
    for row in db.query(BotRow).all():
        row.always_allow = "[]"
    db.commit()
    db.close()

    subprocess.run([sys.executable, "-m", "lianban.pair"], check=True, capture_output=True, cwd=".")
    window = json.loads(open("data/pairing.json", encoding="utf-8").read())
    code = window["code"]

    client = httpx.Client(base_url=BASE, timeout=10)

    # 1) 配对
    r = client.post("/api/pair", json={"credential": code, "deviceName": "联伴鸿蒙"})
    check("POST /api/pair 状态", r.status_code in (200, 201), str(r.status_code))
    body = r.json()
    token = body.get("token", "")
    check("返回 token/serverName", bool(token) and bool(body.get("serverName")), body.get("serverName", ""))
    headers = {"Authorization": f"Bearer {token}"}

    # 1b) 旧码复用应被拒（单次有效）
    r2 = client.post("/api/pair", json={"credential": code, "deviceName": "联伴鸿蒙"})
    check("配对码单次有效", r2.status_code == 401, str(r2.status_code))

    # 1c) 无 token 访问应 401
    r = client.get("/api/bots")
    check("无凭证访问被拒", r.status_code == 401, str(r.status_code))

    # 2) 队友列表
    r = client.get("/api/bots", params={"messages": 20}, headers=headers)
    check("GET /api/bots", r.status_code == 200 and "bots" in r.json(), str(r.status_code))
    bots = r.json()["bots"]
    check("bots 结构（threadId/unread/busy）", all("threadId" in b and "unread" in b and "busy" in b for b in bots))
    bot = bots[0]
    bot_id = bot["id"]
    print(f"     队友示例：{bot['name']} threadId={bot['threadId']}")

    # 3) 线程消息分页
    r = client.get(f"/api/threads/{bot_id}/messages", params={"limit": 40}, headers=headers)
    check("GET /api/threads/:id/messages", r.status_code == 200 and "messages" in r.json())
    page = r.json()
    check("分页字段 hasMore/activeLeafId", "hasMore" in page and "activeLeafId" in page)

    # 4) SSE 事件流（先订阅，再发消息）
    frames: list[dict] = []
    stop = threading.Event()

    def listen() -> None:
        try:
            with client.stream("GET", "/api/events", headers=headers, timeout=20) as resp:
                buffer = ""
                for chunk in resp.iter_text():
                    buffer += chunk
                    while "\n\n" in buffer:
                        block, buffer = buffer.split("\n\n", 1)
                        for line in block.splitlines():
                            if line.startswith("data:"):
                                try:
                                    frames.append(json.loads(line[5:].strip()))
                                except json.JSONDecodeError:
                                    pass
                    if stop.is_set():
                        break
        except Exception:
            pass

    listener = threading.Thread(target=listen, daemon=True)
    listener.start()
    time.sleep(1.0)

    # 5) 发送消息（应立即 202，后台执行）
    text = "帮我把实验记录写入 report.md 内容是整理今天的测量数据"
    r = client.post(f"/api/bots/{bot_id}/messages", json={"text": text, "threadId": bot_id}, headers=headers)
    check("POST /api/bots/:id/messages → 202", r.status_code == 202, str(r.status_code))

    # 6) 等待后台回合完成 → 卡片 + 回复
    deadline = time.time() + 15
    card = None
    while time.time() < deadline:
        r = client.get(f"/api/threads/{bot_id}/messages", params={"limit": 40}, headers=headers)
        messages = r.json()["messages"]
        card = next((m for m in messages if m.get("card") and not m["card"].get("answered")), None)
        bot_rows = [b for b in client.get("/api/bots", params={"messages": 1}, headers=headers).json()["bots"] if b["id"] == bot_id]
        if card and bot_rows and not bot_rows[0]["busy"]:
            break
        time.sleep(0.6)
    check("批准卡片出现在对话里", card is not None)
    if card:
        c = card["card"]
        check("卡片字段（requestId/options/allowKey）",
              bool(c.get("requestId")) and "允许" in c.get("options", []) and bool(c.get("allowKey")))
        print(f"     卡片：{c.get('title')} / {c.get('subtitle', '')[:40]}")
        # 7) respond allow
        r = client.post(f"/api/bots/{bot_id}/respond",
                        json={"requestId": c["requestId"], "behavior": "allow", "threadId": bot_id}, headers=headers)
        check("POST respond(allow)", r.status_code == 200, r.text[:80])
        time.sleep(0.5)
        r = client.get(f"/api/threads/{bot_id}/messages", params={"limit": 40}, headers=headers)
        settled = next((m for m in r.json()["messages"] if m.get("card", {}).get("requestId") == c["requestId"]), None)
        check("卡片已标记 answered", bool(settled and settled["card"].get("answered")), settled["card"].get("answered", ""))

    # 8) SSE 收帧检查
    time.sleep(1.5)
    stop.set()
    kinds = {f.get("kind") for f in frames}
    check("SSE hello 帧", "hello" in kinds, str(kinds))
    check("SSE message 帧", "message" in kinds)
    check("SSE bot 帧", "bot" in kinds)

    # 9) always-allow：先发一条产生卡片的消息，再授权，再发同类消息应直接执行
    text2 = "帮我把实验记录写入 notes.md 内容是今天天气很好"
    client.post(f"/api/bots/{bot_id}/messages", json={"text": text2, "threadId": bot_id}, headers=headers)
    deadline = time.time() + 15
    card2 = None
    while time.time() < deadline:
        r = client.get(f"/api/threads/{bot_id}/messages", params={"limit": 40}, headers=headers)
        msgs = r.json()["messages"]
        pending = [m for m in msgs if m.get("card") and not m["card"].get("answered")]
        card2 = pending[0] if pending else None
        if card2:
            break
        time.sleep(0.6)
    check("第二张待确认卡片", card2 is not None)
    if card2:
        allow_key = card2["card"]["allowKey"]
        r = client.post(f"/api/bots/{bot_id}/always-allow", json={"allowKey": allow_key, "threadId": bot_id}, headers=headers)
        check("POST always-allow", r.status_code == 200, str(r.status_code))
        client.post(f"/api/bots/{bot_id}/respond",
                    json={"requestId": card2["card"]["requestId"], "behavior": "deny", "threadId": bot_id}, headers=headers)
        time.sleep(0.5)
        # 同类消息直接执行
        client.post(f"/api/bots/{bot_id}/messages", json={"text": text2 + "（再试一次）", "threadId": bot_id}, headers=headers)
        deadline = time.time() + 15
        direct = False
        while time.time() < deadline:
            r = client.get(f"/api/threads/{bot_id}/messages", params={"limit": 40}, headers=headers)
            direct = any("始终允许" in (m.get("text") or "") for m in r.json()["messages"])
            if direct:
                break
            time.sleep(0.6)
        check("命中始终允许后直接执行", direct)

    # 10) read / interrupt / endpoints
    r = client.post(f"/api/bots/{bot_id}/read", json={"threadId": bot_id}, headers=headers)
    check("POST read", r.status_code == 200)
    r = client.post(f"/api/bots/{bot_id}/interrupt", json={"threadId": bot_id}, headers=headers)
    check("POST interrupt", r.status_code == 200)
    r = client.get("/api/companion/endpoints", headers=headers)
    check("GET /api/companion/endpoints", r.status_code == 200 and "endpoints" in r.json(), r.text[:60])

    print()
    if failures:
        print(f"共 {len(failures)} 项失败：{failures}")
        return 1
    print("全链路自测通过 ✔")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
