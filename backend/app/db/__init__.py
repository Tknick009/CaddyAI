"""Persistent storage layer (SQLAlchemy 2.0 async).

v1 used in-memory dicts for bag + rounds; v2 replaces those with a
SQLite-backed async store that persists swing reports and the clubs/
rounds data across restarts. `DATABASE_URL` (env var) selects the
backend — default is `sqlite+aiosqlite:///./caddyai.db`, which means
the file lives next to wherever `uvicorn` is launched.

Point `DATABASE_URL` at Postgres (`postgresql+asyncpg://...`) in
production; the ORM models are engine-agnostic.
"""

from app.db.engine import ENGINE, create_all, get_session, reset
from app.db.models import Base, SwingHistoryRow

__all__ = [
    "Base",
    "ENGINE",
    "SwingHistoryRow",
    "create_all",
    "get_session",
    "reset",
]
