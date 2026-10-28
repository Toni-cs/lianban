import time

import redis

from lianban.config import settings


class Cache:
    name = "memory"

    def ping(self) -> bool:
        return True

    def set_status(self, bot_id: str, status: str, ttl: int = 120) -> None:
        raise NotImplementedError

    def get_status(self, bot_id: str) -> str:
        raise NotImplementedError

    def set_unread(self, bot_id: str, unread: bool) -> None:
        raise NotImplementedError

    def get_unread(self, bot_id: str) -> bool:
        raise NotImplementedError


class MemoryCache(Cache):
    def __init__(self, name: str = "memory") -> None:
        self.name = name
        self._values: dict[str, tuple[str, float]] = {}
        self._unread: dict[str, bool] = {}

    def set_status(self, bot_id: str, status: str, ttl: int = 120) -> None:
        self._values[bot_id] = (status, time.time() + ttl)

    def get_status(self, bot_id: str) -> str:
        item = self._values.get(bot_id)
        if not item or item[1] < time.time():
            return "idle"
        return item[0]

    def set_unread(self, bot_id: str, unread: bool) -> None:
        self._unread[bot_id] = unread

    def get_unread(self, bot_id: str) -> bool:
        return bool(self._unread.get(bot_id))


class RedisCache(Cache):
    name = "redis"

    def __init__(self, client: redis.Redis) -> None:
        self.client = client

    def ping(self) -> bool:
        return bool(self.client.ping())

    def set_status(self, bot_id: str, status: str, ttl: int = 120) -> None:
        self.client.set(f"lianban:bot:{bot_id}:status", status, ex=ttl)

    def get_status(self, bot_id: str) -> str:
        value = self.client.get(f"lianban:bot:{bot_id}:status")
        if value is None:
            return "idle"
        if isinstance(value, bytes):
            return value.decode("utf-8")
        return str(value)

    def set_unread(self, bot_id: str, unread: bool) -> None:
        if unread:
            self.client.set(f"lianban:bot:{bot_id}:unread", "1", ex=86400)
        else:
            self.client.delete(f"lianban:bot:{bot_id}:unread")

    def get_unread(self, bot_id: str) -> bool:
        return self.client.exists(f"lianban:bot:{bot_id}:unread") > 0


_cache: Cache | None = None


def build_cache() -> Cache:
    if not settings.redis_url:
        return MemoryCache()
    try:
        client = redis.Redis.from_url(
            settings.redis_url,
            socket_connect_timeout=1,
            socket_timeout=1,
            decode_responses=False,
        )
        client.ping()
        return RedisCache(client)
    except Exception:
        return MemoryCache("redis-unavailable")


def init_cache() -> Cache:
    global _cache
    _cache = build_cache()
    return _cache


def get_cache() -> Cache:
    global _cache
    if _cache is None:
        _cache = build_cache()
    return _cache
