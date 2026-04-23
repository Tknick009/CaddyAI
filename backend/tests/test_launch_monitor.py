from __future__ import annotations

from app.services.launch_monitor import parse_csv

R10_CSV = """Date,Club Type,Ball Speed,Club Head Speed,Launch Angle,Spin Rate,Carry Distance,Total Distance,Side
2025-10-15 14:22:05,7 Iron,118.3,80.2,18.5,6500,148.2,155.3,1.2
2025-10-15 14:22:42,7 Iron,119.8,81.0,17.9,6400,150.9,158.1,-0.8
2025-10-15 14:23:18,7 Iron,117.1,79.8,18.8,6600,146.5,153.2,0.4
"""


RAPSODO_CSV = """Shot Time,Club,Ball Speed (mph),Club Head Speed (mph),Launch Angle (deg),Total Spin (rpm),Carry Distance (Yards),Total Distance (Yards),Side Carry (Yards)
2025-10-15 14:22:05,7i,118.3,80.2,18.5,6500,148.2,155.3,1.2
2025-10-15 14:22:42,7i,119.8,81.0,17.9,6400,150.9,158.1,-0.8
"""


def test_parse_r10_csv():
    shots = parse_csv(R10_CSV, vendor="r10", club_id_map={"7 Iron": "7i"})
    assert len(shots) == 3
    assert shots[0].club_id == "7i"
    assert abs(shots[0].distance_yards - 155.3) < 0.01
    assert abs((shots[0].carry_yards or 0) - 148.2) < 0.01
    assert shots[0].ball_speed_mph == 118.3
    assert shots[0].source.value == "launch_monitor_r10"


def test_parse_rapsodo_csv_auto_detect():
    shots = parse_csv(RAPSODO_CSV, vendor="auto", club_id_map={"7i": "7i"})
    assert len(shots) == 2
    assert shots[0].source.value == "launch_monitor_rapsodo"
    assert shots[0].club_id == "7i"


def test_unknown_club_maps_to_empty_string():
    shots = parse_csv(R10_CSV, vendor="r10")  # no mapping supplied
    assert all(s.club_id == "" for s in shots)
