"""Shared pytest fixtures.

Give every test run its own on-disk SQLite database so history state
doesn't leak across tests — and so the default `caddyai.db` sitting
next to a developer's checkout never gets touched by CI.
"""

from __future__ import annotations

import asyncio
import os
import tempfile
from collections.abc import Iterator

import pytest


def _run(coro):
    """Run a coroutine to completion on a fresh event loop.

    Using `asyncio.run` directly would conflict with pytest-asyncio's
    own loop; we want *sync* fixtures so every test (async or not) sees
    a fresh schema before it runs.
    """
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@pytest.fixture(autouse=True, scope="session")
def _isolated_database_url() -> Iterator[None]:
    tmp = tempfile.NamedTemporaryFile(prefix="caddyai-test-", suffix=".db", delete=False)
    tmp.close()
    os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{tmp.name}"

    # Rebuild the module-level engine now that the env var is set.
    from app.db import engine as _engine

    _engine._rebuild_for_tests()
    _run(_engine.create_all())
    try:
        yield
    finally:
        os.unlink(tmp.name)


@pytest.fixture(autouse=True)
def _reset_db_between_tests() -> Iterator[None]:
    from app.db import engine as _engine

    _run(_engine.reset())
    yield
