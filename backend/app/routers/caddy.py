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
    # Only override wind speed if the client sent zero (i.e. didn't know).
    #
    # We deliberately do NOT backfill `wind_direction_deg` from weather:
    #   * OpenWeather's `wind.deg` is a meteorological compass bearing
    #     (0° = wind coming from north, 90° = from east, ...).
    #   * `ShotContext.wind_direction_deg` is a *shot-relative* angle
    #     (0° = pure headwind, 180° = pure tailwind).
    # Converting between those requires the player's heading toward the
    # pin, which the server doesn't know. Blindly copying the compass
    # bearing into the shot-relative field would make the downstream
    # cos(theta) head/tail component effectively random.
    #
    # The client is responsible for the conversion and should send the
    # computed `wind_direction_deg` directly. Until it does, we leave
    # the field at the client's default (0 → conservative headwind
    # assumption) and just pass through the speed.
    if ctx.wind_speed_mph == 0.0 and e.wind_speed_mph is not None:
        data["wind_speed_mph"] = e.wind_speed_mph
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
