from __future__ import annotations

import pytest

from app.models.schemas import Bag, Club, ClubKind, Lie, PersonalDistance, ShotContext
from app.services import caddy


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
        Club(id="gw", kind=ClubKind.wedge, name="GW", loft_deg=50.0),
        Club(id="sw", kind=ClubKind.wedge, name="SW", loft_deg=54.0),
        Club(id="lw", kind=ClubKind.wedge, name="LW", loft_deg=58.0),
        Club(id="put", kind=ClubKind.putter, name="Putter"),
    ]
    distances = [
        PersonalDistance(club_id="7i", typical_yards=150.0, stddev_yards=4.0, sample_size=40),
        PersonalDistance(club_id="8i", typical_yards=140.0, stddev_yards=4.0, sample_size=40),
        PersonalDistance(club_id="9i", typical_yards=130.0, stddev_yards=4.0, sample_size=40),
        PersonalDistance(club_id="6i", typical_yards=160.0, stddev_yards=4.0, sample_size=40),
        PersonalDistance(club_id="pw", typical_yards=115.0, stddev_yards=3.0, sample_size=40),
    ]
    return Bag(clubs=clubs, personal_distances=distances)


def test_stock_150_yard_shot_picks_seven_iron():
    rec = caddy.recommend(ShotContext(target_distance_yards=150.0), _bag())
    assert rec.primary_club_id == "7i"


def test_headwind_clubs_up():
    # 8mph pure headwind at 150y adds 12y → plays 162y → 6 iron (160y) closer
    # than 5 iron (170y).
    rec = caddy.recommend(
        ShotContext(target_distance_yards=150.0, wind_speed_mph=8.0, wind_direction_deg=0.0),
        _bag(),
    )
    assert rec.primary_club_id == "6i"
    assert rec.wind_adjustment_yards > 0
    assert rec.effective_distance_yards > 150


def test_tailwind_clubs_down():
    rec = caddy.recommend(
        ShotContext(target_distance_yards=150.0, wind_speed_mph=10.0, wind_direction_deg=180.0),
        _bag(),
    )
    # 150 − 15 = 135 → closer to 9i (130) than 8i (140)? distance diff: 9i=5, 8i=5 → tie
    # we expect downswing is fine, just assert it clubbed down.
    personal = {pd.club_id: pd.typical_yards for pd in _bag().personal_distances}
    assert personal[rec.primary_club_id] < 150
    assert rec.wind_adjustment_yards < 0


def test_uphill_clubs_up():
    rec = caddy.recommend(
        ShotContext(target_distance_yards=150.0, elevation_change_ft=30.0),
        _bag(),
    )
    # 30ft / 3 = +10y → 160y → 6i
    assert rec.primary_club_id == "6i"


def test_bunker_lie_adds_distance():
    rec = caddy.recommend(
        ShotContext(target_distance_yards=140.0, lie=Lie.bunker),
        _bag(),
    )
    assert rec.lie_adjustment_yards > 0


def test_empty_bag_raises():
    with pytest.raises(ValueError):
        caddy.recommend(ShotContext(target_distance_yards=150), Bag(clubs=[]))
