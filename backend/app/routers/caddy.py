from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.models.schemas import Bag, CaddyRecommendation, ShotContext
from app.services import caddy as caddy_svc
from app.services import weather as weather_svc
from app.services.store import STORE

router = APIRouter(prefix="/caddy", tags=["caddy"])


class RecommendRequest(ShotContext):
    """`ShotContext` plus an optional inline `bag`.

    When `bag` is omitted the server uses whatever bag is currently stored
    via `PUT /bag`. Keeping the fields flat (instead of nesting `ctx` and
    `bag`) keeps the iOS client simple and the Swagger UI readable.
    """

    bag: Bag | None = None


def _merge_enriched(ctx: ShotContext, e: weather_svc.EnrichedConditions) -> ShotContext:
    """Backfill environment fields only where the client didn't already provide them."""
    data = ctx.model_dump()
    if ctx.temperature_c is None and e.temperature_c is not None:
        data["temperature_c"] = e.temperature_c
    if ctx.pressure_hpa is None and e.pressure_hpa is not None:
        data["pressure_hpa"] = e.pressure_hpa
    if ctx.humidity_pct is None and e.humidity_pct is not None:
        data["humidity_pct"] = e.humidity_pct
    if ctx.altitude_ft is None and e.altitude_ft is not None:
        data["altitude_ft"] = e.altitude_ft
    # Only override wind if the client sent zeros (i.e. didn't know).
    if ctx.wind_speed_mph == 0.0 and e.wind_speed_mph is not None:
        data["wind_speed_mph"] = e.wind_speed_mph
        if e.wind_direction_deg_from is not None:
            # Meteo "from" → our shot-frame direction is player-heading dependent
            # and the client is responsible for translating; leave as-is when
            # the user already set wind_direction_deg.
            data["wind_direction_deg"] = e.wind_direction_deg_from
    return ShotContext(**data)


@router.post("/recommend", response_model=CaddyRecommendation)
async def recommend(req: RecommendRequest) -> CaddyRecommendation:
    effective_bag = req.bag or STORE.get_bag()
    if not effective_bag.clubs:
        raise HTTPException(
            status_code=400,
            detail="No clubs available; configure your bag first via PUT /bag.",
        )
    ctx = ShotContext(**req.model_dump(exclude={"bag"}))

    enriched = await weather_svc.fetch_conditions(ctx.latitude, ctx.longitude)
    ctx = _merge_enriched(ctx, enriched)

    rec = caddy_svc.recommend(ctx, effective_bag)
    rec = rec.model_copy(update={
        "weather_source": "openweather" if enriched.source == "openweather" else (
            "request" if (ctx.temperature_c is not None or ctx.pressure_hpa is not None)
            else "none"
        )
    })
    return rec
