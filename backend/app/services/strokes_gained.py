"""Broadie-style strokes-gained caddy.

Picks the club that minimizes *expected strokes to hole* instead of the
one whose stock distance is closest to the play distance. This is what
tour players' caddies actually do — and it swings the answer a lot on
partial-club or hazard-adjacent shots.

Model
-----
* Baseline "expected strokes from distance, given lie" from Mark
  Broadie's 2011 / 2014 papers. Values are piecewise linear between the
  anchor distances in `_BASELINES`.
* Each club in the bag has a player-specific stock carry and a
  dispersion ellipse (lateral + long-direction σ). If we've learned the
  player's dispersion from launch-monitor history, use it; otherwise
  fall back to an amateur-grade default that scales with club kind.
* We marginalize over that 2-D Gaussian with a 9-point Gauss-Hermite
  grid — plenty for ranking, and closed-form. Landing-lie is decided by
  lateral miss vs hazard offsets (in-hazard → `recovery` baseline + 1
  stroke penalty; rough-width → `rough` baseline; else `fairway`).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from app.models.schemas import Club, ClubKind, Lie

# -----------------------------------------------------------------------------
# Broadie baselines. Yards → expected strokes from that lie to hole.
# Rounded to two places; tour-scratch numbers. Putting is handled separately.
# Source: Broadie, "Every Shot Counts" (2014), table A1.
# -----------------------------------------------------------------------------
_BASELINES: dict[str, list[tuple[float, float]]] = {
    "tee": [
        (100, 2.92), (150, 3.00), (200, 3.09), (250, 3.21),
        (300, 3.38), (350, 3.61), (400, 3.84), (450, 4.13), (500, 4.40),
    ],
    "fairway": [
        (20, 2.40), (40, 2.60), (60, 2.70), (80, 2.75), (100, 2.80),
        (120, 2.85), (140, 2.91), (160, 2.98), (180, 3.08),
        (200, 3.19), (250, 3.45), (300, 3.74),
    ],
    "rough": [
        (20, 2.59), (40, 2.78), (60, 2.91), (80, 2.96), (100, 3.02),
        (120, 3.08), (140, 3.15), (160, 3.23), (180, 3.31),
        (200, 3.42), (250, 3.87), (300, 4.29),
    ],
    "sand": [
        (20, 2.53), (40, 2.82), (60, 3.15), (80, 3.24), (100, 3.23),
        (120, 3.21), (140, 3.22), (160, 3.28), (180, 3.40),
        (200, 3.56), (250, 3.97),
    ],
    "recovery": [
        (100, 3.80), (150, 3.78), (200, 3.80), (250, 3.93), (300, 4.16),
    ],
}

_LIE_TABLE_KEY = {
    Lie.tee: "tee",
    Lie.fairway: "fairway",
    Lie.rough: "rough",
    Lie.deep_rough: "rough",
    Lie.bunker: "sand",
    Lie.recovery: "recovery",
}


def expected_strokes(distance_yards: float, lie: Lie | str) -> float:
    """Interpolate Broadie's expected-strokes surface.

    Inputs clamped to the table range; the tails are conservative.
    """
    key = _LIE_TABLE_KEY[lie] if isinstance(lie, Lie) else lie
    table = _BASELINES[key]

    # On or inside the green: ~2 strokes from 10y, 1.8 from the edge.
    if distance_yards <= table[0][0]:
        if distance_yards <= 0:
            return 1.0
        first = table[0]
        return max(1.0, first[1] - (first[0] - distance_yards) * 0.015)
    if distance_yards >= table[-1][0]:
        return table[-1][1]

    for (x0, y0), (x1, y1) in zip(table, table[1:], strict=False):
        if x0 <= distance_yards <= x1:
            t = (distance_yards - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
    return table[-1][1]


# -----------------------------------------------------------------------------
# Dispersion defaults (tour-amateur). Used if the player hasn't logged enough
# shots for us to learn theirs. Roughly consistent with Arccos-scraped data.
# -----------------------------------------------------------------------------
@dataclass(frozen=True)
class Dispersion:
    lateral_std_yards: float   # L/R
    long_std_yards: float      # short/long of target


def default_dispersion(kind: ClubKind, carry_yards: float) -> Dispersion:
    # Driver: ~6 % lateral, ~5 % long. Scales inversely with club loft.
    if kind is ClubKind.driver:
        return Dispersion(carry_yards * 0.06, carry_yards * 0.05)
    if kind is ClubKind.wood:
        return Dispersion(carry_yards * 0.055, carry_yards * 0.045)
    if kind is ClubKind.hybrid:
        return Dispersion(carry_yards * 0.05, carry_yards * 0.04)
    if kind is ClubKind.iron:
        return Dispersion(carry_yards * 0.04, carry_yards * 0.035)
    if kind is ClubKind.wedge:
        return Dispersion(carry_yards * 0.035, carry_yards * 0.045)
    return Dispersion(5.0, 5.0)


# -----------------------------------------------------------------------------
# Gauss-Hermite quadrature — 3 pts per axis, exact for polynomials ≤ deg 5.
# Enough resolution to rank clubs; a full 9×9 tensor is overkill for this.
# Nodes/weights for the probabilists' Hermite measure (mean 0, variance 1).
# -----------------------------------------------------------------------------
_GH_NODES: list[float] = [-math.sqrt(3.0), 0.0, math.sqrt(3.0)]
_GH_WEIGHTS: list[float] = [1.0 / 6.0, 2.0 / 3.0, 1.0 / 6.0]


def _landing_lie(
    lateral_miss_yards: float,
    long_miss_yards: float,
    distance_to_hole_yards: float,
    hazard_left_yards: float | None,
    hazard_right_yards: float | None,
) -> tuple[Lie, float]:
    """Decide what we're playing the *next* shot from.

    Returns (lie, penalty_strokes). Penalty is 1 for a hazard/OB miss
    (lost ball, drop) and 0 otherwise.
    """
    if lateral_miss_yards < 0 and hazard_left_yards is not None:
        if abs(lateral_miss_yards) >= hazard_left_yards:
            return Lie.recovery, 1.0
    if lateral_miss_yards > 0 and hazard_right_yards is not None:
        if lateral_miss_yards >= hazard_right_yards:
            return Lie.recovery, 1.0

    if distance_to_hole_yards <= 10.0:
        # Near/on the green — use fairway (≈putting/fringe) baseline.
        return Lie.fairway, 0.0
    if abs(lateral_miss_yards) > 15.0 or abs(long_miss_yards) > 15.0:
        return Lie.rough, 0.0
    return Lie.fairway, 0.0


def expected_strokes_for_shot(
    play_distance_yards: float,
    carry_yards: float,
    dispersion: Dispersion,
    base_lie: Lie,
    hazard_left_yards: float | None = None,
    hazard_right_yards: float | None = None,
) -> float:
    """Expected strokes to hole after this shot, under the dispersion model."""
    del base_lie  # base lie affects carry elsewhere; post-shot lie is decided here
    total = 0.0
    total_w = 0.0
    for i, ni in enumerate(_GH_NODES):
        lateral_miss = ni * dispersion.lateral_std_yards
        for j, nj in enumerate(_GH_NODES):
            long_miss = nj * dispersion.long_std_yards
            actual_carry = carry_yards + long_miss
            distance_to_hole = abs(play_distance_yards - actual_carry)
            lie_after, penalty = _landing_lie(
                lateral_miss,
                play_distance_yards - actual_carry,
                distance_to_hole,
                hazard_left_yards,
                hazard_right_yards,
            )
            es = expected_strokes(distance_to_hole, lie_after) + penalty
            # Shot we just played counts too.
            total += (_GH_WEIGHTS[i] * _GH_WEIGHTS[j]) * (1.0 + es)
            total_w += _GH_WEIGHTS[i] * _GH_WEIGHTS[j]
    return total / total_w


def carry_from_personal(
    club: Club,
    personal_yards: float | None,
    default: float,
) -> float:
    return personal_yards if personal_yards is not None else default
