"""python -m lianban.pair：在电脑上开启一次配对窗口。

打印六位配对码和 openmausbot://pair 深链，两分钟内单次有效。
手机端可以用「其他连接方式 → 手动输入地址」填地址 + 六位码。
"""

from lianban.companion import open_pairing, server_name
from lianban.computer import lan_url


def main() -> None:
    window = open_pairing()
    lan = lan_url()
    link = (
        f"openmausbot://pair?address={lan.replace('http://', '')}"
        f"&token={window['token']}&code={window['code']}&name={server_name()}"
    )
    print(f"电脑：{server_name()}")
    print(f"地址：{lan}")
    print(f"六位配对码：{window['code']}（两分钟内有效，用一次作废）")
    print(f"配对链接：{link}")
    print("在手机「联伴」里选择「其他连接方式 → 手动输入地址」，或直接扫包含上面链接的二维码。")


if __name__ == "__main__":
    main()
