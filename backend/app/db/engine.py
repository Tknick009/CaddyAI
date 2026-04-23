"""Async SQLAlchemy engine + session factory.

Minimal surface area: one engine, one sessionmaker, one `create_all`
helper called at startup. Tests override `DATABASE_URL` to point at a
tempfile so every test run starts from a blank slate.
"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

_DEFAULT_URL = "sqlite+aiosqlite:///./caddyai.db"


def _build_engine() -> AsyncEngine:
    url = os.environ.get("DATABASE_URL", _DEFAULT_URL)
    return create_async_engine(url, future=True)


ENGINE: AsyncEngine = _build_engine()
_SESSION_FACTORY: async_sessionmaker[AsyncSession] = async_sessionmaker(
    ENGINE, expire_on_commit=False, class_=AsyncSession
)


async def create_all() -> None:
    """Create tables if they don't exist yet. Cheap — safe to call on
    every startup. Real production use should replace this with Alembic."""
    from app.db.models import Base  # local import to avoid circular imports

    async with ENGINE.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def reset() -> None:
    """Drop and recreate all tables. Used by tests; never called from
    application code."""
    from app.db.models import Base

    async with ENGINE.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency that yields an `AsyncSession` per-request."""
    async with _SESSION_FACTORY() as session:
        yield session


def _rebuild_for_tests() -> None:
    """Rebind the module-level engine after tests monkey-patch
    `DATABASE_URL`. Only call this from test fixtures."""
    global ENGINE, _SESSION_FACTORY
    ENGINE = _build_engine()
    _SESSION_FACTORY = async_sessionmaker(
        ENGINE, expire_on_commit=False, class_=AsyncSession
    )
