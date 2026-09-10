"""Async ARQ Redis pool. POST /documents enqueues here instead of ingesting inline."""

import asyncio

from arq import create_pool
from arq.connections import ArqRedis, RedisSettings

from app.core.config import get_settings

_pool: ArqRedis | None = None
_pool_lock = asyncio.Lock()


async def get_queue_pool() -> ArqRedis:
    global _pool
    async with _pool_lock:
        if _pool is None:
            _pool = await create_pool(
                RedisSettings.from_dsn(get_settings().redis_url)
            )
    return _pool


async def close_queue_pool() -> None:
    global _pool
    async with _pool_lock:
        if _pool is not None:
            await _pool.close()
            _pool = None
