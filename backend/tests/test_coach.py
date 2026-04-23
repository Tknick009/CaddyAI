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


def test_mock_coach_flags_positive_iron_attack_angle():
    report = coach_svc._mock_report(_metrics(attack_angle_deg=2.5, club_kind=ClubKind.iron))
    assert any("attack angle" in c.lower() for c in report.root_causes)
    assert any("ball-first" in d.name.lower() for d in report.drills)


def test_mock_coach_flags_steep_iron_attack_angle():
    report = coach_svc._mock_report(_metrics(attack_angle_deg=-9.0, club_kind=ClubKind.iron))
    assert any("too steep" in c.lower() for c in report.root_causes)


def test_mock_coach_flags_driver_hitting_down():
    report = coach_svc._mock_report(_metrics(attack_angle_deg=-2.5, club_kind=ClubKind.driver))
    assert any("hitting down" in c.lower() for c in report.root_causes)


def test_mock_coach_does_not_diagnose_attack_angle_when_club_kind_is_unknown():
    # Regression: None != "driver" is True in Python, so the non-driver
    # branch used to fire on unknown clubs and incorrectly shout
    # "hitting up on an iron" at, e.g., a driver swing the client didn't
    # tag with a club_kind. Unknown club → no attack-angle verdict.
    report = coach_svc._mock_report(_metrics(attack_angle_deg=3.0, club_kind=None))
    assert not any("hitting up" in c.lower() for c in report.root_causes)
    assert not any("too steep" in c.lower() for c in report.root_causes)


def test_mock_coach_labels_wedge_and_hybrid_correctly():
    wedge = coach_svc._mock_report(_metrics(attack_angle_deg=3.0, club_kind=ClubKind.wedge))
    assert any("hitting up on a wedge" in c.lower() for c in wedge.root_causes)
    hybrid = coach_svc._mock_report(_metrics(attack_angle_deg=3.0, club_kind=ClubKind.hybrid))
    assert any("hitting up on a hybrid" in c.lower() for c in hybrid.root_causes)


def test_mock_coach_flags_bad_sequencing():
    report = coach_svc._mock_report(_metrics(sequencing_index=0.3))
    assert any("sequence" in c.lower() for c in report.root_causes)
    assert any("step-through" in d.name.lower() for d in report.drills)


def test_mock_coach_flags_excessive_pelvis_slide():
    report = coach_svc._mock_report(_metrics(pelvis_slide_cm=12.0))
    assert any("slide" in c.lower() for c in report.root_causes)


def test_3d_viewpoint_metrics_round_trip():
    m = _metrics(
        viewpoint="pose3d",
        attack_angle_deg=-4.2,
        pelvis_slide_cm=3.0,
        pelvis_tilt_deg=7.0,
        sequencing_index=0.85,
    )
    dumped = m.model_dump(by_alias=True, exclude_none=True)
    assert dumped["viewpoint"] == "pose3d"
    assert dumped["attack_angle_deg"] == -4.2
    assert "pelvis_slide_cm" in dumped
    assert dumped["sequencing_index"] == 0.85
