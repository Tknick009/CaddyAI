from __future__ import annotations

from fastapi import APIRouter

from app.models.schemas import CoachingReport, SwingMetrics
from app.services import coach as coach_svc

router = APIRouter(prefix="/coach", tags=["coach"])


@router.post("/swing", response_model=CoachingReport)
async def analyze_swing(metrics: SwingMetrics) -> CoachingReport:
    """Take pose-derived swing metrics and return coaching advice."""
    return await coach_svc.generate_report(metrics)
