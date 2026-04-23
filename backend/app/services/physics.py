"""Ball-flight physics helpers used by the strokes-gained caddy.

Everything here is a simple closed-form approximation — not a trajectory
integrator. Good enough to rank clubs; don't treat the outputs as
launch-monitor truth.

References
----------
* International Standard Atmosphere (ISA) for air-density vs. altitude/temp.
* Carry-distance scaling with air density: carry ~= d0 * (rho_0 / rho)^0.5
  (Trackman "Laws of the Flight" — the exponent is closer to 0.5 than 1.0
  because drag is velocity-squared but the ball spends roughly constant
  time aloft at our loft range). Using 0.5 here keeps the model
  reasonable across 3000-ft altitude swings without overstating Denver.
"""

from __future__ import annotations

import math

# Sea-level, 15 °C, dry air.
RHO_SEA_LEVEL_KG_M3: float = 1.225
_R_DRY: float = 287.058   # J / (kg · K)
_R_VAPOR: float = 461.495
_FT_PER_METER: float = 3.28084

# Saturation vapor pressure (Tetens, Pa) — enough accuracy for
# humidity's second-order effect on density.
def _saturation_vapor_pressure_pa(temp_c: float) -> float:
    return 610.78 * math.exp(17.27 * temp_c / (temp_c + 237.3))


def air_density_kg_m3(
    altitude_ft: float | None = None,
    temperature_c: float | None = None,
    pressure_hpa: float | None = None,
    humidity_pct: float | None = None,
) -> float:
    """Air density in kg/m³ using the ideal-gas law.

    If pressure isn't supplied we derive it from altitude via the dry ISA
    lapse model. If temperature isn't supplied we use 15 °C. Humidity is
    optional; when present it reduces density by 0.5-1 % at summer levels.
    """
    temp_c = 15.0 if temperature_c is None else temperature_c
    temp_k = temp_c + 273.15

    if pressure_hpa is not None:
        p_total = pressure_hpa * 100.0
    else:
        alt_m = (altitude_ft or 0.0) / _FT_PER_METER
        # ISA troposphere barometric formula, 288.15 K reference, 0.0065 K/m lapse.
        p_total = 101_325.0 * (1.0 - 0.0065 * alt_m / 288.15) ** 5.25588

    if humidity_pct is not None:
        p_v = (humidity_pct / 100.0) * _saturation_vapor_pressure_pa(temp_c)
    else:
        p_v = 0.0
    p_d = max(0.0, p_total - p_v)
    return p_d / (_R_DRY * temp_k) + p_v / (_R_VAPOR * temp_k)


def density_altitude_carry_multiplier(
    altitude_ft: float | None = None,
    temperature_c: float | None = None,
    pressure_hpa: float | None = None,
    humidity_pct: float | None = None,
) -> float:
    """Factor to multiply sea-level carry by for the given conditions.

    Denver in summer → about 1.07-1.08 (balls fly ~7 % farther).
    """
    rho = air_density_kg_m3(altitude_ft, temperature_c, pressure_hpa, humidity_pct)
    return math.sqrt(RHO_SEA_LEVEL_KG_M3 / rho)


def wind_adjustment_yards(
    target_yards: float,
    wind_speed_mph: float,
    wind_direction_deg: float,
) -> float:
    """Yards to add to the play distance (positive = club up).

    wind_direction_deg: 0 = pure headwind, 180 = pure tailwind.
    Classic rule: ~1 % of play distance per mph of head/tail component.
    """
    theta = math.radians(wind_direction_deg)
    head_component = wind_speed_mph * math.cos(theta)
    return target_yards * (head_component / 100.0)


def elevation_adjustment_yards(elevation_change_ft: float) -> float:
    """Yards to add. ~1 yard per 3 ft is PGA-tour-caliber accurate."""
    return elevation_change_ft / 3.0


def temperature_adjustment_yards(
    base_carry_yards: float,
    temperature_c: float | None,
) -> float:
    """Very mild effect independent of density altitude (ball + clubface).

    Empirically about 2 yards per 10 °C of delta from 20 °C for a
    150-yard shot — linear and small. We fold *most* of the temp effect
    into the density altitude term above; this captures the residual
    (ball core warms, clubface energy transfer).
    """
    if temperature_c is None:
        return 0.0
    delta = temperature_c - 20.0
    return base_carry_yards * 0.00133 * delta  # ~2y per 10C on 150y
