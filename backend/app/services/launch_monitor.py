"""Launch-monitor CSV ingestion.

Different devices export slightly different columns. We normalize to
`Shot`. Supported vendors:

- Garmin Approach R10
- Rapsodo MLM2PRO
- SkyTrak
- FlightScope Mevo / Mevo+

Heuristic detection looks for the union of column names in the header.
If the user already knows the vendor they can pass it explicitly.
"""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, datetime
from typing import Literal

from app.models.schemas import Shot, ShotSource

Vendor = Literal["r10", "rapsodo", "skytrak", "mevo", "auto"]

# Column aliases per vendor.
VENDOR_COLUMNS: dict[str, dict[str, tuple[str, ...]]] = {
    "r10": {
        "club": ("Club Type", "Club"),
        "total": ("Total Distance", "Total"),
        "carry": ("Carry Distance", "Carry"),
        "ball_speed": ("Ball Speed",),
        "club_speed": ("Club Head Speed", "Club Speed"),
        "launch": ("Launch Angle",),
        "spin": ("Spin Rate", "Back Spin"),
        "side": ("Side", "Offline"),
        "ts": ("Date", "Shot Created Date"),
    },
    "rapsodo": {
        "club": ("Club",),
        "total": ("Total Distance (Yards)",),
        "carry": ("Carry Distance (Yards)",),
        "ball_speed": ("Ball Speed (mph)",),
        "club_speed": ("Club Head Speed (mph)",),
        "launch": ("Launch Angle (deg)",),
        "spin": ("Total Spin (rpm)",),
        "side": ("Side Carry (Yards)",),
        "ts": ("Shot Time",),
    },
    "skytrak": {
        "club": ("Club",),
        "total": ("Total Distance",),
        "carry": ("Carry",),
        "ball_speed": ("Ball Speed",),
        "club_speed": ("Club Speed",),
        "launch": ("Launch Angle",),
        "spin": ("Back Spin",),
        "side": ("Side Total",),
        "ts": ("Date/Time", "Timestamp"),
    },
    "mevo": {
        "club": ("Club Type",),
        "total": ("Total",),
        "carry": ("Carry",),
        "ball_speed": ("Ball Speed",),
        "club_speed": ("Club Head Speed",),
        "launch": ("Launch Angle",),
        "spin": ("Spin Rate",),
        "side": ("Smash",),  # Mevo base doesn't report side — we leave it blank
        "ts": ("Time", "Timestamp"),
    },
}

_VENDOR_SOURCE: dict[str, ShotSource] = {
    "r10": ShotSource.launch_monitor_r10,
    "rapsodo": ShotSource.launch_monitor_rapsodo,
    "skytrak": ShotSource.launch_monitor_skytrak,
    "mevo": ShotSource.launch_monitor_mevo,
}


def detect_vendor(header: list[str]) -> str:
    header_l = {h.strip().lower() for h in header}
    scores: dict[str, int] = {}
    for vendor, cols in VENDOR_COLUMNS.items():
        score = 0
        for aliases in cols.values():
            if any(a.lower() in header_l for a in aliases):
                score += 1
        scores[vendor] = score
    best = max(scores, key=lambda k: scores[k])
    if scores[best] < 3:
        raise ValueError(
            f"Could not detect launch monitor vendor from header: {header}"
        )
    return best


def _get(row: dict[str, str], aliases: tuple[str, ...]) -> str | None:
    for a in aliases:
        for key in row:
            if key.strip().lower() == a.lower():
                v = row[key].strip()
                return v or None
    return None


def _parse_float(s: str | None) -> float | None:
    if s is None or s == "":
        return None
    try:
        return float(s.replace(",", ""))
    except ValueError:
        return None


def _parse_ts(s: str | None) -> datetime:
    if s is None or s == "":
        return datetime.now(UTC)
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%m/%d/%Y %H:%M:%S",
        "%m/%d/%Y %I:%M:%S %p",
        "%Y-%m-%d %H:%M",
    ):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=UTC)
        except ValueError:
            continue
    return datetime.now(UTC)


def parse_csv(
    content: str,
    vendor: Vendor = "auto",
    club_id_map: dict[str, str] | None = None,
) -> list[Shot]:
    """Parse a launch-monitor CSV export into a list of `Shot`s.

    `club_id_map` maps the vendor's club name (e.g. "7i", "7 Iron", "PW")
    to one of the player's `Club.id`s. Unknown clubs become an empty string —
    the caller can prompt the user to map them.
    """
    reader = csv.reader(io.StringIO(content))
    try:
        header = next(reader)
    except StopIteration:
        return []

    if vendor == "auto":
        vendor = detect_vendor(header)  # type: ignore[assignment]
    cols = VENDOR_COLUMNS[vendor]
    source = _VENDOR_SOURCE[vendor]
    mapping = {k.lower(): v for k, v in (club_id_map or {}).items()}

    shots: list[Shot] = []
    dict_reader = csv.DictReader(io.StringIO(content))
    for row in dict_reader:
        club_name = _get(row, cols["club"]) or ""
        club_id = mapping.get(club_name.lower(), "")
        total = _parse_float(_get(row, cols["total"]))
        carry = _parse_float(_get(row, cols["carry"]))
        if total is None and carry is None:
            continue
        shots.append(
            Shot(
                id=str(uuid.uuid4()),
                club_id=club_id,
                distance_yards=total if total is not None else (carry or 0.0),
                carry_yards=carry,
                ball_speed_mph=_parse_float(_get(row, cols["ball_speed"])),
                club_speed_mph=_parse_float(_get(row, cols["club_speed"])),
                launch_angle_deg=_parse_float(_get(row, cols["launch"])),
                spin_rpm=_parse_float(_get(row, cols["spin"])),
                side_yards=_parse_float(_get(row, cols["side"])),
                result="unknown",
                ts=_parse_ts(_get(row, cols["ts"])),
                source=source,
                note=f"imported from {vendor}",
            )
        )
    return shots
