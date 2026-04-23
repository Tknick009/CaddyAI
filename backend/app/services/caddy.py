"""Rule-based on-course caddy.

Given a `ShotContext` (yardage, wind, lie, elevation) and the player's
`Bag` with `PersonalDistance`, pick the club that best matches the play
distance with a conservative bias when there's trouble.

References for the adjustment heuristics:
  - 1% of target distance per mph of headwind/tailwind component
  - ~1 yard of play distance per 1 ft of elevation
  - Lie penalties derived from general teaching-pro consensus
"""

from __future__ import annotations

import math

from app.models.schemas import (
    Bag,
    CaddyRecommendation,
    Club,
    ClubKind,
    Lie,
    PersonalDistance,
    ShotContext,
)

# Fallback distances used when we haven't learned one yet for the player.
# Loose amateur averages, yards carry.
DEFAULT_DISTANCES: dict[ClubKind, dict[float, float]] = {
    ClubKind.driver: {10.5: 230.0},
    ClubKind.wood: {15.0: 210.0, 18.0: 200.0, 21.0: 190.0},
    ClubKind.hybrid: {19.0: 195.0, 22.0: 180.0, 25.0: 170.0},
    ClubKind.iron: {
        18.0: 190.0, 21.0: 180.0, 24.0: 170.0,
        27.0: 160.0, 30.0: 150.0, 34.0: 140.0,
        38.0: 130.0, 42.0: 120.0, 46.0: 110.0,
    },
    ClubKind.wedge: {50.0: 100.0, 54.0: 85.0, 58.0: 65.0, 60.0: 55.0},
    ClubKind.putter: {3.0: 0.0},
}


def _distance_for(club: Club, personal: dict[str, PersonalDistance]) -> float:
    pd = personal.get(club.id)
    if pd is not None:
        return pd.typical_yards
    table = DEFAULT_DISTANCES.get(club.kind, {})
    if not table:
        return 100.0
    if club.loft_deg is not None:
        # nearest loft match
        closest = min(table.keys(), key=lambda k: abs(k - (club.loft_deg or 0.0)))
        return table[closest]
    # average
    return sum(table.values()) / len(table)


def _lie_adjustment(lie: Lie, target: float) -> float:
    # Returns yards to ADD to the play distance (positive -> needs more club).
    if lie is Lie.tee:
        return 0.0
    if lie is Lie.fairway:
        return 0.0
    if lie is Lie.rough:
        return target * 0.03
    if lie is Lie.deep_rough:
        return target * 0.07
    if lie is Lie.bunker:
        return target * 0.08
    if lie is Lie.recovery:
        return target * 0.10
    return 0.0


def _wind_adjustment(ctx: ShotContext) -> float:
    # direction_deg: 0 = pure headwind, 180 = pure tailwind.
    # Effective headwind component is wind_speed * cos(direction).
    theta = math.radians(ctx.wind_direction_deg)
    head_component = ctx.wind_speed_mph * math.cos(theta)
    # Classic rule of thumb: 1% of target distance per mph of head/tailwind.
    return ctx.target_distance_yards * (head_component / 100.0)


def _elevation_adjustment(ctx: ShotContext) -> float:
    # Uphill (positive elevation) means more club needed.
    # ~1 yard per 3 ft is more accurate near sea level, ~1 yard per 1 ft is
    # the old caddy-ism. We use 1 yard per 3 ft as a sane default.
    return ctx.elevation_change_ft / 3.0


def recommend(ctx: ShotContext, bag: Bag) -> CaddyRecommendation:
    if not bag.clubs:
        raise ValueError("bag has no clubs")

    wind_adj = _wind_adjustment(ctx)
    elev_adj = _elevation_adjustment(ctx)
    lie_adj = _lie_adjustment(ctx.lie, ctx.target_distance_yards)

    effective = ctx.target_distance_yards + wind_adj + elev_adj + lie_adj
    if ctx.must_carry_yards is not None:
        # never club-down below the carry requirement
        effective = max(effective, ctx.must_carry_yards + 5.0)

    personal = {pd.club_id: pd for pd in bag.personal_distances}
    scored: list[tuple[Club, float, float]] = []  # (club, dist, |residual|)
    for club in bag.clubs:
        if club.kind is ClubKind.putter:
            continue
        dist = _distance_for(club, personal)
        scored.append((club, dist, abs(dist - effective)))

    scored.sort(key=lambda t: t[2])
    if not scored:
        raise ValueError("bag has only a putter")

    primary, primary_dist, _ = scored[0]

    # Pick an alternate: the next-best club that is on the OPPOSITE side of
    # the residual — gives the user a "smooth X / hard Y" choice.
    alt = None
    for club, dist, _ in scored[1:]:
        if (dist - effective) * (primary_dist - effective) <= 0:
            alt = club
            break
    if alt is None and len(scored) > 1:
        alt = scored[1][0]

    commentary_parts: list[str] = [
        f"Plays {effective:+.0f}y effective ({ctx.target_distance_yards:.0f}y target"
    ]
    if wind_adj:
        commentary_parts.append(f"{wind_adj:+.0f}y wind")
    if elev_adj:
        commentary_parts.append(f"{elev_adj:+.0f}y elevation")
    if lie_adj:
        commentary_parts.append(f"{lie_adj:+.0f}y lie")
    header = ", ".join(commentary_parts) + ")."

    swing_note: str
    delta = primary_dist - effective
    if abs(delta) < 3:
        swing_note = f"Stock {primary.name}."
    elif delta > 0:
        swing_note = f"Smooth {primary.name} — a touch too much, ease off."
    else:
        swing_note = f"Full {primary.name} — you'll need every bit of it."

    if alt and alt is not primary:
        swing_note += f" Alt: {alt.name}."

    return CaddyRecommendation(
        primary_club_id=primary.id,
        alt_club_id=alt.id if alt else None,
        effective_distance_yards=round(effective, 1),
        wind_adjustment_yards=round(wind_adj, 1),
        elevation_adjustment_yards=round(elev_adj, 1),
        lie_adjustment_yards=round(lie_adj, 1),
        commentary=f"{header} {swing_note}",
    )
