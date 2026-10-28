"""把联伴配对到你本地的 OpenMausBot（10.0.2.2:8810，模拟器视角的宿主机）。

用法：python scripts/auto_pair_omb.py <六位码>
- 不清应用数据：在保留已配对电脑的基础上「添加另一台电脑」
- 动态坐标驱动，避开键盘遮挡
"""

import json
import subprocess
import sys
import time

HDC = r"D:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
LAYOUT_LOCAL = r"D:/Bot/harmony/sign/layout.json"
TARGET = "10.0.2.2:8810"


def shell(cmd: str) -> None:
    subprocess.run([HDC, "shell", cmd], capture_output=True, timeout=30)


def dump() -> dict:
    shell("uitest dumpLayout -p /data/local/tmp/layout.json")
    out = subprocess.run([HDC, "shell", "cat /data/local/tmp/layout.json"], capture_output=True, timeout=30)
    text = out.stdout.decode("utf-8", errors="ignore")
    with open(LAYOUT_LOCAL, "w", encoding="utf-8") as f:
        f.write(text)
    return json.loads(text)


def nodes(data: dict) -> list[dict]:
    found: list[dict] = []

    def walk(node: dict) -> None:
        found.append(node.get("attributes", {}))
        for child in node.get("children", []):
            walk(child)

    walk(data)
    return found


def center(bounds: str) -> tuple[int, int]:
    nums = [int(x) for x in bounds.strip("[]").replace("][", ",").split(",")]
    return (nums[0] + nums[2]) // 2, (nums[1] + nums[3]) // 2


def find(data: dict, *, text: str = "", hint: str = "", contains: bool = False) -> tuple[int, int] | None:
    for a in nodes(data):
        value = a.get("text") or ""
        placeholder = a.get("hint") or ""
        if text and (value == text or (contains and text in value)):
            return center(a["bounds"])
        if hint and (placeholder == hint or (contains and hint in placeholder)):
            return center(a["bounds"])
    return None


def click(pos: tuple[int, int]) -> None:
    print(f"  click ({pos[0]},{pos[1]})")
    shell(f"uitest uiInput click {pos[0]} {pos[1]}")


def input_text(pos: tuple[int, int], text: str) -> None:
    print(f"  input {text!r} at ({pos[0]},{pos[1]})")
    shell(f"uitest uiInput inputText {pos[0]} {pos[1]} {text}")


def hide_keyboard() -> None:
    data = dump()
    pos = next((center(a["bounds"]) for a in nodes(data) if "KeyHideKbd" in (a.get("id") or "")), None)
    if pos is not None:
        print(f"  收起键盘 ({pos[0]},{pos[1]})")
        shell(f"uitest uiInput click {pos[0]} {pos[1]}")
        time.sleep(1.2)


def wait_for(fn, timeout: float = 8.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = dump()
        result = fn(data)
        if result is not None:
            return data, result
        time.sleep(0.8)
    return None, None


def main() -> int:
    if len(sys.argv) < 2 or not (3 <= len(sys.argv[1]) <= 32):
        print("用法: python scripts/auto_pair_omb.py <配对码>")
        return 2
    code = sys.argv[1]
    print(f"配对码 = {code}，目标 = {TARGET}")

    print("1) 确保 App 在前台")
    pid = subprocess.run([HDC, "shell", "pidof com.lianban.controller"], capture_output=True, text=True, timeout=15)
    if not pid.stdout.strip():
        shell("aa start -a EntryAbility -b com.lianban.controller")
        time.sleep(5)
    else:
        shell("aa start -a EntryAbility -b com.lianban.controller")
        time.sleep(2)

    print("2) 主界面点「＋」添加电脑")
    _, plus = wait_for(lambda d: find(d, text="＋"), timeout=10)
    if plus is None:
        print("  不在主界面（可能在对话里），先返回")
        back = find(dump(), text="‹")
        if back is not None:
            click(back)
            time.sleep(1.5)
        _, plus = wait_for(lambda d: find(d, text="＋"), timeout=8)
    if plus is None:
        print("找不到「＋」入口")
        return 1
    click(plus)
    time.sleep(2)

    print("3) 进「手动输入地址」")
    _, manual = wait_for(lambda d: find(d, text="手动输入地址"), timeout=8)
    if manual is None:
        print("配对屏没出现")
        return 1
    click(manual)
    time.sleep(1.5)

    print("4) 填地址")
    data = dump()
    addr = find(data, hint="192.168", contains=True)
    if addr is None:
        addr = find(data, text=TARGET, contains=True)
    if addr is None:
        print("找不到地址输入框")
        return 1
    input_text(*addr, TARGET)

    print("5) 填配对码")
    _, code_pos = wait_for(lambda d: find(d, hint="六位配对码"), timeout=6)
    if code_pos is None:
        print("找不到配对码输入框")
        return 1
    input_text(*code_pos, code)

    print("6) 收键盘并点「连接这台电脑」")
    hide_keyboard()
    _, btn = wait_for(lambda d: find(d, text="连接这台电脑"), timeout=6)
    if btn is None:
        print("找不到连接按钮")
        return 1
    click(btn)

    print("7) 等待配对结果（轮询 25 秒）")
    deadline = time.time() + 25
    while time.time() < deadline:
        time.sleep(2)
        data = dump()
        texts = [a.get("text") or "" for a in nodes(data)]
        joined = " ".join(texts)
        if "配对失败" in joined or "不对" in joined or "重新" in joined:
            print(f"  配对失败：{[t for t in texts if t][:8]}")
            return 1
        if any("已连接" in t for t in texts) or any("工作中" in t for t in texts):
            print("  配对成功 ✔")
            break
    else:
        print("  超时未确认，需人工看屏")

    print("8) 最终状态")
    time.sleep(3)
    data = dump()
    texts = [t for t in (a.get("text") or "" for a in nodes(data)) if t]
    print("  " + " | ".join(texts[:10]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
