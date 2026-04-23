"""On-course caddy.

v1 picked the club whose stock distance was closest to the play
distance. v2 (this file) picks the club that *minimizes expected
strokes to hole* under the player's dispersion — Broadie-style. The
difference shows up most on partial-club shots and shots flirting with
a hazard; the old engine cheerfully recommended 8-iron straight at a
water carry you only clear 60 % of the time.

Inputs that feed the selection:
  * Play distance = target + elevation
  * Each club's effective *carry* after wind + air-density + temperature
  * Dispersion ellipse — learned per club if we have enough shots,
    otherwise kind-based default.

The v1 "stock" adjustments (wind, elevation, lie) are still reported in
the response so clients that render them keep working.
"""

from __future__ import annotations

import math

from app.models.schemas import (
    Bag,
    CaddyRecommendation,
    Club,
    ClubChoice,
    ClubKind,
    Lie,
    PersonalDistance,
    ShotContext,
)
from app.services import physics
from app.services import strokes_gained as sg

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


def _default_carry_yards(club: Club) -> float:
    table = DEFAULT_DISTANCES.get(club.kind, {})
    if not table:
        return 100.0
    if club.loft_deg is not None:
        closest = min(table.keys(), key=lambda k: abs(k - (club.loft_deg or 0.0)))
        return table[closest]
    return sum(table.values()) / len(table)


def _personal_or_default(club: Club, personal: dict[str, PersonalDistance]) -> float:
    pd = personal.get(club.id)
    if pd is not None:
        return pd.typical_yards
    return _default_carry_yards(club)


def _lie_adjustment(lie: Lie, target: float) -> float:
    """How many extra yards of club it takes to escape the lie."""
    if lie in (Lie.tee, Lie.fairway):
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


def _env_multiplier(ctx: ShotContext) -> float:
    """Density-altitude multiplier on carry. 1.0 at sea level, ~1.07 in Denver."""
    return physics.density_altitude_carry_multiplier(
        altitude_ft=ctx.altitude_ft,
        temperature_c=ctx.temperature_c,
        pressure_hpa=ctx.pressure_hpa,
        humidity_pct=ctx.humidity_pct,
    )


def _adjusted_carry(club_carry_yards: float, ctx: ShotContext, env_mult: float) -> float:
    """Turn a stock carry into 'what this shot will actually carry.'

    Wind and temperature are applied against the *carry*, not the target
    distance — a 10-mph headwind takes a fixed ~percentage off every
    club's flight.
    """
    carry = club_carry_yards * env_mult
    carry += physics.temperature_adjustment_yards(carry, ctx.temperature_c)
    theta = math.radians(ctx.wind_direction_deg)
    head_component = ctx.wind_speed_mph * math.cos(theta)
    carry -= carry * (head_component / 100.0)
    return carry


def recommend(ctx: ShotContext, bag: Bag) -> CaddyRecommendation:
    if not bag.clubs:
        raise ValueError("bag has no clubs")

    lie_adj = _lie_adjustment(ctx.lie, ctx.target_distance_yards)
    elev_adj = physics.elevation_adjustment_yards(ctx.elevation_change_ft)
    env_mult = _env_multiplier(ctx)
    play_distance = ctx.target_distance_yards + lie_adj + elev_adj
    if ctx.must_carry_yards is not None:
        play_distance = max(play_distance, ctx.must_carry_yards + 5.0)

    personal = {pd.club_id: pd for pd in bag.personal_distances}
    candidates: list[ClubChoice] = []
    club_by_id: dict[str, Club] = {c.id: c for c in bag.clubs}

    for club in bag.clubs:
        if club.kind is ClubKind.putter:
            continue
        stock = _personal_or_default(club, personal)
        adj_carry = _adjusted_carry(stock, ctx, env_mult)
        disp = sg.default_dispersion(club.kind, adj_carry)
        es = sg.expected_strokes_for_shot(
            play_distance_yards=play_distance,
            carry_yards=adj_carry,
            dispersion=disp,
            base_lie=ctx.lie,
            hazard_left_yards=ctx.hazard_left_yards,
            hazard_right_yards=ctx.hazard_right_yards,
        )
        candidates.append(
            ClubChoice(
                club_id=club.id,
                typical_play_yards=round(adj_carry, 1),
                expected_strokes=round(es, 3),
                lateral_stddev_yards=round(disp.lateral_std_yards, 1),
                long_stddev_yards=round(disp.long_std_yards, 1),
            )
        )

    if not candidates:
        raise ValueError("bag has only a putter")

    candidates.sort(key=lambda c: c.expected_strokes)
    primary_choice = candidates[0]
    primary = club_by_id[primary_choice.club_id]

    # Pick an alternate that's on the *opposite* side of the target so the
    # "smooth X / hard Y" framing keeps working.
    alt: Club | None = None
    alt_choice: ClubChoice | None = None
    primary_delta = primary_choice.typical_play_yards - play_distance
    for choice in candidates[1:]:
        if (choice.typical_play_yards - play_distance) * primary_delta <= 0:
            alt = club_by_id[choice.club_id]
            alt_choice = choice
            break
    if alt is None and len(candidates) > 1:
        alt_choice = candidates[1]
        alt = club_by_id[alt_choice.club_id]

    stock_primary = _personal_or_default(primary, personal)
    wind_adj = physics.wind_adjustment_yards(
        ctx.target_distance_yards, ctx.wind_speed_mph, ctx.wind_direction_deg
    )
    density_adj = stock_primary * (env_mult - 1.0)
    # Keep v1's "effective_distance" semantic: how far the shot plays,
    # with wind folded in. The SG engine uses a carry-adjusted model
    # internally; this is purely what we surface to clients for display.
    effective_display = play_distance + wind_adj - density_adj

    parts: list[str] = [
        f"Plays {play_distance:.0f}y from the tee box "
        f"({ctx.target_distance_yards:.0f}y target"
    ]
    if wind_adj:
        parts.append(f"{wind_adj:+.0f}y wind")
    if elev_adj:
        parts.append(f"{elev_adj:+.0f}y elevation")
    if lie_adj:
        parts.append(f"{lie_adj:+.0f}y lie")
    if abs(density_adj) >= 2.0:
        parts.append(f"{density_adj:+.0f}y air")
    header = ", ".join(parts) + ")."

    delta = primary_choice.typical_play_yards - play_distance
    if abs(delta) < 3:
        swing_note = f"Stock {primary.name}."
    elif delta > 0:
        swing_note = f"Smooth {primary.name} — a touch too much, ease off."
    else:
        swing_note = f"Full {primary.name} — you'll need every bit of it."

    if alt and alt_choice and alt.id != primary.id:
        swing_note += f" Alt: {alt.name} ({alt_choice.expected_strokes:.2f} ES)."
    swing_note += f" Expected {primary_choice.expected_strokes:.2f} strokes to hole."

    return CaddyRecommendation(
        primary_club_id=primary.id,
        alt_club_id=alt.id if alt and alt.id != primary.id else None,
        effective_distance_yards=round(effective_display, 1),
        wind_adjustment_yards=round(wind_adj, 1),
        elevation_adjustment_yards=round(elev_adj, 1),
        lie_adjustment_yards=round(lie_adj, 1),
        air_density_adjustment_yards=round(density_adj, 1) if env_mult != 1.0 else None,
        expected_strokes=primary_choice.expected_strokes,
        candidates=candidates,
        commentary=f"{header} {swing_note}",
    )
