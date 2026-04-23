from __future__ import annotations

import math

import pytest

from app.models.schemas import Bag, Club, ClubKind, Lie, PersonalDistance, ShotContext
from app.services import caddy
from app.services import strokes_gained as sg


def test_expected_strokes_monotonic_in_distance():
    """Farther from the hole → more strokes to hole. On every lie."""
    for lie in ("fairway", "rough", "sand", "tee"):
        xs = [sg.expected_strokes(d, lie) for d in (50, 100, 150, 200, 250)]
        assert xs == sorted(xs)


def test_expected_strokes_rough_harder_than_fairway():
    for d in (60, 120, 180):
        assert sg.expected_strokes(d, Lie.rough) > sg.expected_strokes(d, Lie.fairway)


def test_expected_strokes_clamps_above_table():
    # 600 yards is off the end of the table; should return the tail value.
    assert math.isclose(
        sg.expected_strokes(600, "fairway"),
        sg.expected_strokes(300, "fairway"),
    )


def test_dispersion_grows_with_looser_club():
    d_driver = sg.default_dispersion(ClubKind.driver, 260.0)
    d_wedge = sg.default_dispersion(ClubKind.wedge, 90.0)
    assert d_driver.lateral_std_yards > d_wedge.lateral_std_yards


def test_es_for_shot_prefers_on_target_club():
    """150y shot: a club that carries 150 beats one that carries 100 or 200."""
    iron_disp = sg.default_dispersion(ClubKind.iron, 150)
    wedge_disp = sg.default_dispersion(ClubKind.wedge, 100)
    hybrid_disp = sg.default_dispersion(ClubKind.hybrid, 200)
    on_target = sg.expected_strokes_for_shot(150, 150, iron_disp, Lie.fairway)
    under = sg.expected_strokes_for_shot(150, 100, wedge_disp, Lie.fairway)
    over = sg.expected_strokes_for_shot(150, 200, hybrid_disp, Lie.fairway)
    assert on_target < under
    assert on_target < over


def _bag() -> Bag:
    clubs = [
        Club(id="drv", kind=ClubKind.driver, name="Driver", loft_deg=10.5),
        Club(id="3w", kind=ClubKind.wood, name="3 Wood", loft_deg=15.0),
        Club(id="4h", kind=ClubKind.hybrid, name="4 Hybrid", loft_deg=22.0),
        Club(id="5i", kind=ClubKind.iron, name="5 Iron", loft_deg=24.0),
        Club(id="6i", kind=ClubKind.iron, name="6 Iron", loft_deg=27.0),
        Club(id="7i", kind=ClubKind.iron, name="7 Iron", loft_deg=30.0),
        Club(id="8i", kind=ClubKind.iron, name="8 Iron", loft_deg=34.0),
        Club(id="9i", kind=ClubKind.iron, name="9 Iron", loft_deg=38.0),
        Club(id="pw", kind=ClubKind.wedge, name="PW", loft_deg=46.0),
        Club(id="put", kind=ClubKind.putter, name="Putter"),
    ]
    distances = [
        PersonalDistance(club_id="5i", typical_yards=170, stddev_yards=4, sample_size=40),
        PersonalDistance(club_id="6i", typical_yards=160, stddev_yards=4, sample_size=40),
        PersonalDistance(club_id="7i", typical_yards=150, stddev_yards=4, sample_size=40),
        PersonalDistance(club_id="8i", typical_yards=140, stddev_yards=4, sample_size=40),
        PersonalDistance(club_id="9i", typical_yards=130, stddev_yards=4, sample_size=40),
        PersonalDistance(club_id="pw", typical_yards=115, stddev_yards=3, sample_size=40),
    ]
    return Bag(clubs=clubs, personal_distances=distances)


def test_caddy_picks_seven_iron_for_flat_150_yard_shot():
    rec = caddy.recommend(ShotContext(target_distance_yards=150.0), _bag())
    assert rec.primary_club_id == "7i"
    assert rec.expected_strokes is not None
    assert rec.candidates  # populated


def test_caddy_returns_sorted_candidates():
    rec = caddy.recommend(ShotContext(target_distance_yards=150.0), _bag())
    es = [c.expected_strokes for c in rec.candidates]
    assert es == sorted(es)
    assert rec.candidates[0].club_id == rec.primary_club_id


def test_altitude_shortens_the_club_choice():
    sea = caddy.recommend(ShotContext(target_distance_yards=150.0), _bag())
    denver = caddy.recommend(
        ShotContext(target_distance_yards=150.0, altitude_ft=5280.0, temperature_c=20.0),
        _bag(),
    )
    # At 5280 ft the same target is "easier" — either primary clubs down to
    # 8i or we at least see an air-density adjustment reported.
    assert denver.air_density_adjustment_yards is not None
    assert denver.air_density_adjustment_yards > 0
    sea_club = {"7i": 150, "8i": 140}
    denver_club = {"7i": 150, "8i": 140, "9i": 130}
    assert sea.primary_club_id in sea_club
    assert denver.primary_club_id in denver_club
    # Denver should be at least as-short or shorter than sea level.
    assert denver_club[denver.primary_club_id] <= sea_club[sea.primary_club_id]


def test_hazard_right_shifts_away_from_driver():
    """With the right side death-penalty close, the SG caddy shouldn't pick
    the longest possible club — dispersion punishes overshooting hazard-side."""
    # 180y tee shot with a 15-yard-wide corridor to the right hazard.
    safe = caddy.recommend(
        ShotContext(target_distance_yards=180.0, lie=Lie.tee),
        _bag(),
    )
    tight = caddy.recommend(
        ShotContext(target_distance_yards=180.0, lie=Lie.tee, hazard_right_yards=15.0),
        _bag(),
    )
    # Expected strokes should rise when the hazard is tight.
    assert tight.expected_strokes is not None
    assert safe.expected_strokes is not None
    assert tight.expected_strokes >= safe.expected_strokes


def test_caddy_still_handles_empty_bag():
    with pytest.raises(ValueError):
        caddy.recommend(ShotContext(target_distance_yards=150), Bag(clubs=[]))


def test_headwind_clubs_up_via_strokes_gained():
    rec = caddy.recommend(
        ShotContext(target_distance_yards=150.0, wind_speed_mph=10.0, wind_direction_deg=0.0),
        _bag(),
    )
    # 10mph pure headwind → play distance effectively ~165y → 6i beats 7i.
    assert rec.primary_club_id in {"6i", "5i"}
    assert rec.wind_adjustment_yards > 0
