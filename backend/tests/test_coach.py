from __future__ import annotations

import pytest

from app.models.schemas import ClubKind, SwingMetrics
from app.services import coach as coach_svc


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
    return SwingMetrics(**base)


def test_mock_coach_good_swing_has_no_major_faults():
    report = coach_svc._mock_report(_metrics())
    assert report.source == "mock"
    assert report.root_causes
    assert any("solid" in c.lower() or "no major" in c.lower() for c in report.root_causes)


def test_mock_coach_flags_quick_tempo():
    report = coach_svc._mock_report(_metrics(tempo_ratio=1.8))
    assert any("tempo" in c.lower() or "quick" in c.lower() for c in report.root_causes)
    assert report.drills


def test_mock_coach_flags_low_x_factor():
    report = coach_svc._mock_report(_metrics(x_factor_deg=15.0))
    assert any("x-factor" in c.lower() for c in report.root_causes)


def test_mock_coach_flags_hanging_back():
    report = coach_svc._mock_report(_metrics(weight_transfer_pct=45.0, x_factor_deg=20.0))
    flight = report.likely_ball_flight.lower()
    assert "slice" in flight or "push" in flight


@pytest.mark.asyncio
async def test_generate_report_without_openai_key_falls_back(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    report = await coach_svc.generate_report(_metrics())
    assert report.source == "mock"
