"""CaddyAI FastAPI entrypoint."""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db import create_all
from app.routers import bag, caddy, coach, garmin, launch_monitor, rounds


@asynccontextmanager
async def _lifespan(app: FastAPI):
    # Create the swing-history tables on first boot. Cheap no-op when they
    # already exist. Real production deployments should replace this with
    # an Alembic migration.
    await create_all()
    yield


app = FastAPI(
    title="CaddyAI",
    version="0.1.0",
    description=(
        "Backend for the CaddyAI iOS app. Exposes the LLM swing coach, the "
        "rule-based on-course caddy recommender, launch-monitor CSV import, "
        "bag management, and a Garmin OAuth stub."
    ),
    lifespan=_lifespan,
)

# The iOS simulator, iPhone on the same Wi-Fi, and Swagger UI all need CORS.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
    allow_credentials=False,
)

app.include_router(coach.router)
app.include_router(caddy.router)
app.include_router(bag.router)
app.include_router(launch_monitor.router)
app.include_router(rounds.router)
app.include_router(garmin.router)


@app.get("/healthz", tags=["meta"])
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/", include_in_schema=False)
def root() -> dict[str, str]:
    return {"name": "CaddyAI", "docs": "/docs"}
