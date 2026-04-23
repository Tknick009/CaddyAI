from __future__ import annotations

from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models.schemas import (
    CoachingReport,
    CoachRequest,
    SwingHistoryResponse,
    SwingMetrics,
)
from app.services import coach as coach_svc
from app.services import swing_history as history_svc

router = APIRouter(prefix="/coach", tags=["coach"])


@router.post("/swing", response_model=CoachingReport)
async def analyze_swing(
    payload: CoachRequest | SwingMetrics,
    session: AsyncSession = Depends(get_session),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
) -> CoachingReport:
    """Take pose-derived swing metrics and return coaching advice.

    Accepts two envelope shapes for backward compat with v1 clients:

    - `SwingMetrics` — legacy v1 bare payload, no keyframes, no history.
    - `CoachRequest` — v2 envelope carrying metrics + optional keyframes
      + optional device_id for RAG retrieval.

    When a device_id is available (either via the request body or the
    `X-Device-Id` header), we retrieve the player's recent history and
    fold it into the coach prompt, then persist this new session so
    tomorrow's request can see it too.
    """
    if isinstance(payload, CoachRequest):
        metrics = payload.metrics
        keyframes = payload.keyframes
        device_id = payload.device_id or x_device_id
    else:
        metrics = payload
        keyframes = []
        device_id = x_device_id

    history = (
        await history_svc.recent_for_device(session, device_id, limit=10)
        if device_id
        else []
    )
    report = await coach_svc.generate_report(
        metrics, keyframes=keyframes, history=history
    )
    if device_id:
        await history_svc.record_swing(
            session,
            device_id=device_id,
            metrics=metrics,
            report=report,
            keyframes=keyframes,
            coach_source=report.source,
        )
    return report


@router.get("/swing/history", response_model=SwingHistoryResponse)
async def swing_history(
    session: AsyncSession = Depends(get_session),
    x_device_id: str = Header(alias="X-Device-Id"),
    limit: int = 20,
) -> SwingHistoryResponse:
    """Return the device's most recent analyzed swings (newest first)."""
    entries = await history_svc.recent_for_device(session, x_device_id, limit=limit)
    return SwingHistoryResponse(device_id=x_device_id, entries=entries)
