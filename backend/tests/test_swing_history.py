from __future__ import annotations

import base64

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.schemas import (
    ClubKind,
    CoachingReport,
    Drill,
    SwingKeyframe,
    SwingMetrics,
)
from app.services import coach as coach_svc

client = TestClient(app)


def _metrics(**over):
    base = dict(
        tempo_ratio=3.0,
        backswing_sec=0.9,
        downswing_sec=0.3,
        peak_shoulder_turn_deg=90.0,
        peak_hip_turn_deg=50.0,
        x_factor_deg=40.0,
        lateral_sway_cm=3.0,
        head_movement_cm=4.0,
        early_extension_cm=1.0,
        swing_plane_deg=58.0,
        weight_transfer_pct=80.0,
        confidence=0.9,
        handedness="right",
        club_kind=ClubKind.iron,
    )
    base.update(over)
    return SwingMetrics(**base).model_dump(by_alias=True)


def test_history_block_formats_five_most_recent():
    from datetime import datetime

    from app.models.schemas import CoachingReport as CR
    from app.models.schemas import SwingHistoryEntry

    entries = [
        SwingHistoryEntry(
            swing_id=f"s{i}",
            ts=datetime(2025, 1, i + 1),
            metrics=SwingMetrics(**{
                "tempo_ratio": 3.0,
                "backswing_sec": 0.9,
                "downswing_sec": 0.3,
                "peak_shoulder_turn_deg": 90.0,
                "peak_hip_turn_deg": 50.0,
                "x_factor_deg": 40.0,
                "lateral_sway_cm": 3.0,
                "head_movement_cm": 4.0,
                "early_extension_cm": 1.0,
                "swing_plane_deg": 58.0,
                "weight_transfer_pct": 80.0,
                "confidence": 0.9,
                "handedness": "right",
                "club_kind": ClubKind.iron,
            }),
            report=CR(
                summary=f"s{i}",
                likely_ball_flight="Push-slice",
                root_causes=[f"cause-{i}"],
                drills=[Drill(name="d", description="x")],
                source="mock",
            ),
        )
        for i in range(7)
    ]
    block = coach_svc._history_block(entries)
    assert "Recent sessions" in block
    # Only 5 rendered, not 7.
    assert block.count("\n- ") == 5
    assert "Push-slice" in block


@pytest.mark.asyncio
async def test_user_message_adds_vision_parts_when_keyframes_present():
    jpeg = base64.b64encode(b"\xff\xd8\xff\xd9").decode()
    m = SwingMetrics(**{
        "tempo_ratio": 3.0,
        "backswing_sec": 0.9,
        "downswing_sec": 0.3,
        "peak_shoulder_turn_deg": 90.0,
        "peak_hip_turn_deg": 50.0,
        "x_factor_deg": 40.0,
        "lateral_sway_cm": 3.0,
        "head_movement_cm": 4.0,
        "early_extension_cm": 1.0,
        "swing_plane_deg": 58.0,
        "weight_transfer_pct": 80.0,
        "confidence": 0.9,
        "handedness": "right",
        "club_kind": ClubKind.iron,
    })
    content = coach_svc._user_message(
        m,
        keyframes=[SwingKeyframe(position="top", jpeg_base64=jpeg)],
        history=[],
    )
    assert isinstance(content, list)
    types = [p.get("type") for p in content]
    assert types == ["text", "image_url"]
    assert content[1]["image_url"]["url"].startswith("data:image/jpeg;base64,")


@pytest.mark.asyncio
async def test_user_message_is_plain_text_without_keyframes():
    m = SwingMetrics(**{
        "tempo_ratio": 3.0,
        "backswing_sec": 0.9,
        "downswing_sec": 0.3,
        "peak_shoulder_turn_deg": 90.0,
        "peak_hip_turn_deg": 50.0,
        "x_factor_deg": 40.0,
        "lateral_sway_cm": 3.0,
        "head_movement_cm": 4.0,
        "early_extension_cm": 1.0,
        "swing_plane_deg": 58.0,
        "weight_transfer_pct": 80.0,
        "confidence": 0.9,
        "handedness": "right",
        "club_kind": ClubKind.iron,
    })
    content = coach_svc._user_message(m, keyframes=[], history=[])
    assert isinstance(content, str)
    assert "Analyze this swing" in content


def test_coach_endpoint_persists_and_returns_history(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    device = "device-abc"

    # First swing: heavy-handed bad-X-factor payload.
    r = client.post(
        "/coach/swing",
        json={"metrics": _metrics(x_factor_deg=10.0), "keyframes": [], "device_id": device},
    )
    assert r.status_code == 200, r.text
    assert r.json()["source"] == "mock"

    # Second swing on same device.
    r = client.post(
        "/coach/swing",
        json={"metrics": _metrics(tempo_ratio=1.8), "keyframes": [], "device_id": device},
    )
    assert r.status_code == 200

    # History should list both, newest first.
    r = client.get("/coach/swing/history", headers={"X-Device-Id": device})
    assert r.status_code == 200
    body = r.json()
    assert body["device_id"] == device
    assert len(body["entries"]) == 2
    ts = [e["ts"] for e in body["entries"]]
    assert ts == sorted(ts, reverse=True)


def test_coach_endpoint_is_backward_compatible_with_bare_metrics(monkeypatch):
    """v1 clients sending SwingMetrics directly must still work."""
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    r = client.post("/coach/swing", json=_metrics())
    assert r.status_code == 200, r.text
    assert "summary" in r.json()


def test_coach_endpoint_without_device_does_not_persist(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    r = client.post("/coach/swing", json={"metrics": _metrics(), "keyframes": []})
    assert r.status_code == 200

    r = client.get("/coach/swing/history", headers={"X-Device-Id": "nobody"})
    assert r.status_code == 200
    assert r.json()["entries"] == []


def test_coach_endpoint_uses_header_device_id_when_body_lacks_one(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    device = "header-device"
    r = client.post(
        "/coach/swing",
        json=_metrics(),
        headers={"X-Device-Id": device},
    )
    assert r.status_code == 200

    r = client.get("/coach/swing/history", headers={"X-Device-Id": device})
    assert r.status_code == 200
    assert len(r.json()["entries"]) == 1


def test_coach_history_requires_device_header():
    r = client.get("/coach/swing/history")
    assert r.status_code == 422  # missing required header


@pytest.mark.asyncio
async def test_generate_report_with_history_injects_block_into_prompt(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "fake-key")
    captured: dict = {}

    class _Resp:
        status_code = 200

        def raise_for_status(self):
            pass

        def json(self):
            return {
                "choices": [{
                    "message": {
                        "content": (
                            '{"summary": "ok", "likely_ball_flight": "Straight", '
                            '"root_causes": [], "drills": []}'
                        )
                    }
                }]
            }

    class _Client:
        def __init__(self, *a, **kw):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

        async def post(self, url, headers, json):
            captured["payload"] = json
            return _Resp()

    monkeypatch.setattr(coach_svc.httpx, "AsyncClient", _Client)

    from datetime import datetime

    from app.models.schemas import SwingHistoryEntry

    m = SwingMetrics(**{
        "tempo_ratio": 3.0,
        "backswing_sec": 0.9,
        "downswing_sec": 0.3,
        "peak_shoulder_turn_deg": 90.0,
        "peak_hip_turn_deg": 50.0,
        "x_factor_deg": 40.0,
        "lateral_sway_cm": 3.0,
        "head_movement_cm": 4.0,
        "early_extension_cm": 1.0,
        "swing_plane_deg": 58.0,
        "weight_transfer_pct": 80.0,
        "confidence": 0.9,
        "handedness": "right",
        "club_kind": ClubKind.iron,
    })
    history = [
        SwingHistoryEntry(
            swing_id="prev",
            ts=datetime(2025, 1, 1),
            metrics=m,
            report=CoachingReport(
                summary="prev",
                likely_ball_flight="Pull-hook",
                root_causes=["early extension was 7 cm"],
                drills=[Drill(name="d", description="x")],
                source="mock",
            ),
        )
    ]

    report = await coach_svc.generate_report(m, history=history)
    assert report.source == "openai"
    prose = captured["payload"]["messages"][1]["content"]
    assert "Recent sessions" in prose
    assert "Pull-hook" in prose
