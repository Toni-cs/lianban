import json
import time
from pathlib import Path

import httpx
import jwt

from lianban.config import settings

_token = ""
_token_exp = 0


def push_ready() -> bool:
    path = settings.huawei_sa_file
    return bool(settings.huawei_project_id and path and Path(path).is_file())


def _load_account() -> dict:
    path = Path(settings.huawei_sa_file)
    data = json.loads(path.read_text(encoding="utf-8"))
    key_id = data.get("key_id") or data.get("keyId")
    private_key = data.get("private_key") or data.get("privateKey")
    sub_account = data.get("sub_account") or data.get("subAccount")
    if not key_id or not private_key or not sub_account:
        raise ValueError("服务账号 JSON 需要 key_id、private_key、sub_account")
    return {"key_id": key_id, "private_key": private_key, "sub_account": sub_account}


def _jwt() -> str:
    global _token, _token_exp
    current = int(time.time())
    if _token and current < _token_exp - 60:
        return _token
    account = _load_account()
    payload = {
        "iss": account["sub_account"],
        "aud": "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
        "iat": current,
        "exp": current + 3600,
    }
    _token = jwt.encode(
        payload,
        account["private_key"],
        algorithm="PS256",
        headers={"kid": account["key_id"], "typ": "JWT"},
    )
    _token_exp = current + 3600
    return _token


def send_push(title: str, body: str, tokens: list[str]) -> tuple[str, str]:
    """把审批通知推到已注册的鸿蒙应用。未配置凭证时只留在应用收件箱。"""
    usable = [token for token in tokens if token]
    if not usable:
        return "skipped", "还没有带 Push Token 的华为应用，通知留在收件箱"
    if not push_ready():
        return "skipped", "未配置 HUAWEI_SA_FILE 或 HUAWEI_PROJECT_ID，未调用 Push Kit"
    url = f"https://push-api.cloud.huawei.com/v3/{settings.huawei_project_id}/messages:send"
    payload = {
        "payload": {
            "notification": {
                "category": settings.huawei_push_category or "WORK",
                "title": title[:100],
                "body": body[:200],
                "clickAction": {"actionType": 0},
            }
        },
        "target": {"token": usable[:10]},
        "pushOptions": {"testMessage": settings.huawei_push_test, "ttl": 86400},
    }
    try:
        response = httpx.post(
            url,
            headers={
                "Authorization": f"Bearer {_jwt()}",
                "push-type": "0",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=15,
        )
        data = response.json()
    except Exception as exc:
        return "failed", str(exc)[:300]
    if str(data.get("code")) == "80000000":
        return "sent", str(data.get("requestId") or "")
    return "failed", json.dumps(data, ensure_ascii=False)[:300]
