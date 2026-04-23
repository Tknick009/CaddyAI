from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app
from app.services.store import STORE

client = TestClient(app)


def _bag_payload():
    return {
        "clubs": [
            {"id": "7i", "kind": "iron", "name": "7 Iron", "loft_deg": 30.0},
            {"id": "8i", "kind": "iron", "name": "8 Iron", "loft_deg": 34.0},
            {"id": "pw", "kind": "wedge", "name": "PW", "loft_deg": 46.0},
        ],
        "personal_distances": [
            {"club_id": "7i", "typical_yards": 150.0, "stddev_yards": 4.0, "sample_size": 40},
            {"club_id": "8i", "typical_yards": 140.0, "stddev_yards": 4.0, "sample_size": 40},
            {"club_id": "pw", "typical_yards": 115.0, "stddev_yards": 3.0, "sample_size": 40},
        ],
    }


def test_health():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_bag_put_get_roundtrip():
    r = client.put("/bag", json=_bag_payload())
    assert r.status_code == 200
    r = client.get("/bag")
    assert r.status_code == 200
    assert len(r.json()["clubs"]) == 3


def test_caddy_recommend_uses_stored_bag():
    client.put("/bag", json=_bag_payload())
    r = client.post("/caddy/recommend", json={"target_distance_yards": 150})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["primary_club_id"] == "7i"
    assert "commentary" in body


def test_caddy_recommend_without_bag_errors(monkeypatch):
    STORE.set_bag(STORE.get_bag().model_copy(update={"clubs": [], "personal_distances": []}))
    r = client.post("/caddy/recommend", json={"target_distance_yards": 150})
    assert r.status_code == 400


def test_coach_endpoint_mock_fallback(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    metrics = {
        "tempo_ratio": 1.9,
        "backswing_sec": 0.6,
        "downswing_sec": 0.32,
        "peak_shoulder_turn_deg": 70.0,
        "peak_hip_turn_deg": 55.0,
        "x_factor_deg": 15.0,
        "lateral_sway_cm": 7.0,
        "head_movement_cm": 9.0,
        "early_extension_cm": 4.0,
        "swing_plane_deg": 62.0,
        "weight_transfer_pct": 45.0,
        "confidence": 0.85,
        "handedness": "right",
        "club_kind": "iron",
    }
    r = client.post("/coach/swing", json=metrics)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["source"] == "mock"
    assert body["root_causes"]
    assert body["drills"]


def test_garmin_status_unconfigured(monkeypatch):
    monkeypatch.delenv("GARMIN_CLIENT_ID", raising=False)
    monkeypatch.delenv("GARMIN_CLIENT_SECRET", raising=False)
    r = client.get("/garmin/status")
    assert r.status_code == 200
    assert r.json()["configured"] is False
