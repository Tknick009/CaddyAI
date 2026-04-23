"""Optional weather + elevation enrichment.

We never *require* live weather — the client can (and does) still push
wind/temperature in the shot context. But when `lat`/`lon` are present
and an API key is configured, we enrich the context so the player
doesn't have to type conditions they're standing in the middle of.

Providers
---------
* **Weather**: OpenWeatherMap Current Weather Data (needs
  `OPENWEATHER_API_KEY`). Free tier is 60 calls/min, plenty for a golf
  round.
* **Elevation**: Open-Elevation — free, no key required. We only use
  this when the client didn't provide `altitude_ft`.

Both calls are best-effort: any failure (timeout, non-2xx, bad JSON)
returns `None` for that field and the caddy engine falls back to
whatever the client already supplied.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Literal

import httpx

_OPENWEATHER_URL = "https://api.openweathermap.org/data/2.5/weather"
_OPEN_ELEVATION_URL = "https://api.open-elevation.com/api/v1/lookup"


@dataclass(frozen=True)
class EnrichedConditions:
    source: Literal["none", "request", "openweather"]
    temperature_c: float | None
    pressure_hpa: float | None
    humidity_pct: float | None
    wind_speed_mph: float | None
    wind_direction_deg_from: float | None   # meteorological "from" direction
    altitude_ft: float | None


def _api_key() -> str | None:
    k = os.environ.get("OPENWEATHER_API_KEY")
    return k if k else None


async def fetch_conditions(
    lat: float | None,
    lon: float | None,
    client: httpx.AsyncClient | None = None,
) -> EnrichedConditions:
    """Best-effort pull of local weather + elevation."""
    if lat is None or lon is None:
        return EnrichedConditions("none", None, None, None, None, None, None)

    owned_client = client is None
    c = client or httpx.AsyncClient(timeout=4.0)
    try:
        weather_source: Literal["none", "openweather"] = "none"
        temp_c = pressure = humidity = wind_mph = wind_from = altitude = None

        key = _api_key()
        if key:
            try:
                r = await c.get(
                    _OPENWEATHER_URL,
                    params={"lat": lat, "lon": lon, "units": "metric", "appid": key},
                )
                if r.status_code == 200:
                    j = r.json()
                    main = j.get("main", {})
                    wind = j.get("wind", {})
                    temp_c = main.get("temp")
                    pressure = main.get("pressure")
                    humidity = main.get("humidity")
                    if (w := wind.get("speed")) is not None:
                        wind_mph = w * 2.23694
                    wind_from = wind.get("deg")
                    weather_source = "openweather"
            except (httpx.HTTPError, ValueError):
                pass

        try:
            r = await c.get(
                _OPEN_ELEVATION_URL,
                params={"locations": f"{lat},{lon}"},
            )
            if r.status_code == 200:
                results = r.json().get("results") or []
                if results:
                    elev_m = results[0].get("elevation")
                    if elev_m is not None:
                        altitude = elev_m * 3.28084
        except (httpx.HTTPError, ValueError):
            pass

        return EnrichedConditions(
            source=weather_source,
            temperature_c=temp_c,
            pressure_hpa=pressure,
            humidity_pct=humidity,
            wind_speed_mph=wind_mph,
            wind_direction_deg_from=wind_from,
            altitude_ft=altitude,
        )
    finally:
        if owned_client:
            await c.aclose()
