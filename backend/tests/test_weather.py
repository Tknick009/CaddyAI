from __future__ import annotations

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.schemas import Bag, Club, ClubKind, PersonalDistance
from app.services import weather as weather_svc
from app.services.store import STORE

client = TestClient(app)


def _bag() -> Bag:
    return Bag(
        clubs=[
            Club(id="drv", kind=ClubKind.driver, name="Driver", loft_deg=10.5),
            Club(id="5i", kind=ClubKind.iron, name="5 Iron", loft_deg=24),
            Club(id="7i", kind=ClubKind.iron, name="7 Iron", loft_deg=30),
            Club(id="9i", kind=ClubKind.iron, name="9 Iron", loft_deg=38),
        ],
        personal_distances=[
            PersonalDistance(club_id="5i", typical_yards=170, stddev_yards=4, sample_size=40),
            PersonalDistance(club_id="7i", typical_yards=150, stddev_yards=4, sample_size=40),
            PersonalDistance(club_id="9i", typical_yards=130, stddev_yards=4, sample_size=40),
        ],
    )


@pytest.mark.asyncio
async def test_fetch_conditions_returns_none_source_without_coords():
    e = await weather_svc.fetch_conditions(None, None)
    assert e.source == "none"
    assert e.altitude_ft is None


@pytest.mark.asyncio
async def test_fetch_conditions_is_best_effort_on_failure(monkeypatch):
    """When both providers 500, we return a populated EnrichedConditions with
    source='none' and None fields. The caddy endpoint still works."""
    monkeypatch.setenv("OPENWEATHER_API_KEY", "fake-key")

    class _FailingClient:
        async def aclose(self):
            return None

        async def get(self, *a, **kw):
            raise httpx.HTTPError("boom")

    e = await weather_svc.fetch_conditions(37.7, -122.4, client=_FailingClient())
    assert e.source == "none"
    assert e.temperature_c is None
    assert e.altitude_ft is None


@pytest.mark.asyncio
async def test_fetch_conditions_parses_openweather(monkeypatch):
    monkeypatch.setenv("OPENWEATHER_API_KEY", "fake-key")

    class _OKResp:
        def __init__(self, payload, code=200):
            self._p = payload
            self.status_code = code

        def json(self):
            return self._p

    class _FakeClient:
        async def aclose(self):
            return None

        async def get(self, url, params=None):
            if "openweather" in url:
                return _OKResp({
                    "main": {"temp": 25.0, "pressure": 1015, "humidity": 60},
                    "wind": {"speed": 5.0, "deg": 270},
                })
            if "open-elevation" in url:
                return _OKResp({"results": [{"elevation": 1600.0}]})
            raise AssertionError(f"unexpected url: {url}")

    e = await weather_svc.fetch_conditions(39.7, -104.9, client=_FakeClient())
    assert e.source == "openweather"
    assert e.temperature_c == 25.0
    assert e.pressure_hpa == 1015
    assert e.humidity_pct == 60
    assert e.wind_speed_mph is not None
    assert 10.5 < e.wind_speed_mph < 11.5   # 5 m/s ≈ 11.18 mph
    # Open-Elevation returns meters; we convert to feet.
    assert e.altitude_ft is not None
    assert 5200 < e.altitude_ft < 5300


def test_caddy_recommend_uses_stored_bag_and_reports_weather_source(monkeypatch):
    STORE.set_bag(_bag())
    monkeypatch.delenv("OPENWEATHER_API_KEY", raising=False)
    r = client.post(
        "/caddy/recommend",
        json={
            "target_distance_yards": 150.0,
            "altitude_ft": 5280.0,
            "temperature_c": 20.0,
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["weather_source"] in ("request", "openweather", "none")
    assert body["primary_club_id"] in {"5i", "7i", "9i"}
    assert "expected_strokes" in body
    assert body["air_density_adjustment_yards"] is not None


def test_caddy_v1_clients_still_get_recommendation_without_new_fields():
    STORE.set_bag(_bag())
    r = client.post(
        "/caddy/recommend",
        json={"target_distance_yards": 150.0},
    )
    assert r.status_code == 200
    body = r.json()
    # v1 fields all still there.
    for k in ("primary_club_id", "effective_distance_yards", "commentary"):
        assert k in body
