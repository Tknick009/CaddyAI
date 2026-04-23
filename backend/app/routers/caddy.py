from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.models.schemas import Bag, CaddyRecommendation, ShotContext
from app.services import caddy as caddy_svc
from app.services.store import STORE

router = APIRouter(prefix="/caddy", tags=["caddy"])


class RecommendRequest(ShotContext):
    """`ShotContext` plus an optional inline `bag`.

    When `bag` is omitted the server uses whatever bag is currently stored
    via `PUT /bag`. Keeping the fields flat (instead of nesting `ctx` and
    `bag`) keeps the iOS client simple and the Swagger UI readable.
    """

    bag: Bag | None = None


@router.post("/recommend", response_model=CaddyRecommendation)
def recommend(req: RecommendRequest) -> CaddyRecommendation:
    effective_bag = req.bag or STORE.get_bag()
    if not effective_bag.clubs:
        raise HTTPException(
            status_code=400,
            detail="No clubs available; configure your bag first via PUT /bag.",
        )
    ctx = ShotContext(**req.model_dump(exclude={"bag"}))
    return caddy_svc.recommend(ctx, effective_bag)
