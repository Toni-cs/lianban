"""模拟器联伴自动配对：每次输入前 dump 实际坐标，避开键盘偏移。"""

import json
import subprocess
import time

HDC = r"D:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
LAYOUT_LOCAL = r"D:/Bot/harmony/sign/layout.json"


def shell(cmd: str) -> str:
    out = subprocess.run([HDC, "shell", cmd], capture_output=True, text=True, timeout=30)
    return (out.stdout or "") + (out.stderr or "")


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


def find_text(data: dict, keyword: str) -> tuple[int, int] | None:
    for a in nodes(data):
        if keyword in (a.get("text") or ""):
            return center(a["bounds"])
    return None


def find_hint(data: dict, keyword: str) -> tuple[int, int] | None:
    for a in nodes(data):
        if keyword in (a.get("hint") or ""):
            return center(a["bounds"])
    return None


def click(x: int, y: int) -> None:
    print(f"  click ({x},{y})")
    shell(f"uitest uiInput click {x} {y}")


def input_text(x: int, y: int, text: str) -> None:
    print(f"  input {text!r} at ({x},{y})")
    shell(f"uitest uiInput inputText {x} {y} {text}")


def wait_for(data_fn, timeout: float = 8.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = dump()
        result = data_fn(data)
        if result is not None:
            return data, result
        time.sleep(0.8)
    return None, None


def hide_keyboard() -> None:
    data = dump()

    def find_hide(d: dict) -> tuple[int, int] | None:
        for a in nodes(d):
            if "KeyHideKbd" in (a.get("id") or ""):
                return center(a["bounds"])
        return None

    pos = find_hide(data)
    if pos is not None:
        print(f"  收起键盘 ({pos[0]},{pos[1]})")
        shell(f"uitest uiInput click {pos[0]} {pos[1]}")
        time.sleep(1.2)


def main() -> None:
    print("1) 清数据重启")
    shell("bm clean -n com.lianban.controller -d")
    shell("aa force-stop com.lianban.controller")
    time.sleep(1)
    shell("aa start -a EntryAbility -b com.lianban.controller")
    time.sleep(4)

    print("2) 进入手动输入地址")
    _, pos = wait_for(lambda d: find_text(d, "手动输入地址"))
    if pos is None:
        raise SystemExit("找不到「手动输入地址」")
    click(*pos)
    time.sleep(1.5)

    print("3) 生成配对码")
    code_proc = subprocess.run(
        ["python", "-c", "from lianban.companion import open_pairing; print(open_pairing()['code'])"],
        capture_output=True, text=True, cwd="D:/Bot", timeout=15,
    )
    code = code_proc.stdout.strip()
    print(f"  配对码 = {code}")
    if not code.isdigit() or len(code) != 6:
        raise SystemExit(f"配对码异常: {code!r}")

    print("4) 输入地址（键盘未弹出坐标）")
    data = dump()
    addr = find_hint(data, "192.168")
    if addr is None:
        raise SystemExit("找不到地址输入框")
    input_text(*addr, "10.0.2.2:8814")

    print("5) 动态定位配对码框并输入")
    _, code_pos = wait_for(lambda d: find_hint(d, "六位配对码"))
    if code_pos is None:
        raise SystemExit("找不到配对码输入框")
    input_text(*code_pos, code)

    print("6) 收起键盘并点击「连接这台电脑」")
    hide_keyboard()
    _, btn = wait_for(lambda d: find_text(d, "连接这台电脑"))
    if btn is None:
        raise SystemExit("找不到连接按钮")
    click(*btn)

    print("7) 确认屏点「信任并连接」")
    _, trust = wait_for(lambda d: find_text(d, "信任并连接"), timeout=10)
    if trust is None:
        raise SystemExit("确认屏未出现")
    click(*trust)

    print("8) 验证主界面")
    time.sleep(4)
    data = dump()
    texts = [a.get("text") or "" for a in nodes(data)]
    marks = [t for t in texts if t and ("林知" in t or "周衡" in t or "已连接" in t or "工作中" in t)]
    print(f"  主界面关键文本: {marks[:6]}")
    if marks:
        print("配对成功，联伴已连上电脑 ✔")
    else:
        all_text = [t for t in texts if t][:12]
        print(f"  当前界面文本: {all_text}")


if __name__ == "__main__":
    main()
