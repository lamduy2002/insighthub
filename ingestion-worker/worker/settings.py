"""ARQ WorkerSettings. Shares REDIS_URL with api so enqueued jobs are picked up here."""

import asyncio

from arq import func
from arq.connections import RedisSettings

from app.core.config import get_settings
from app.core.db import close_pool, initialize_database
from worker.tasks import ingest_document


async def startup(ctx: dict) -> None:
    await asyncio.to_thread(initialize_database)


async def shutdown(ctx: dict) -> None:
    await asyncio.to_thread(close_pool)


class WorkerSettings:
    functions = [func(ingest_document, name="ingest_document", max_tries=3)]
    redis_settings = RedisSettings.from_dsn(get_settings().redis_url)
    on_startup = startup
    on_shutdown = shutdown
    max_jobs = 10
    # < MH7's 30s ready/failed SLA, with headroom for queue wait + DB commit, so a
    # single attempt can never "succeed" after silently blowing past the SLA.
    job_timeout = 25
