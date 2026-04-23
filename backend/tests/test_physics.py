from __future__ import annotations

import math

from app.services import physics


def test_sea_level_standard_conditions_multiplier_is_one():
    # At ISA sea level (15 C, 1013.25 hPa, dry) rho == 1.225, so factor == 1.
    f = physics.density_altitude_carry_multiplier(
        altitude_ft=0.0, temperature_c=15.0, pressure_hpa=1013.25, humidity_pct=0.0
    )
    assert math.isclose(f, 1.0, abs_tol=1e-3)


def test_denver_adds_about_seven_percent_of_carry():
    # Denver ~5280 ft, 20 C → ball flies meaningfully farther.
    f = physics.density_altitude_carry_multiplier(altitude_ft=5280.0, temperature_c=20.0)
    assert 1.05 < f < 1.15


def test_hot_air_adds_more_carry_than_cold_air():
    hot = physics.density_altitude_carry_multiplier(altitude_ft=0, temperature_c=35.0)
    cold = physics.density_altitude_carry_multiplier(altitude_ft=0, temperature_c=-5.0)
    assert hot > cold
    # Effect at sea level is a few percent; cold < 1 < hot.
    assert cold < 1.0 < hot


def test_humid_air_is_less_dense_than_dry_air():
    dry = physics.air_density_kg_m3(altitude_ft=0, temperature_c=25.0, humidity_pct=0.0)
    humid = physics.air_density_kg_m3(altitude_ft=0, temperature_c=25.0, humidity_pct=80.0)
    assert humid < dry


def test_wind_adjustment_sign_convention():
    # 0° = headwind → positive (need more club).
    assert physics.wind_adjustment_yards(150, 10, 0.0) > 0
    # 180° = tailwind → negative (need less club).
    assert physics.wind_adjustment_yards(150, 10, 180.0) < 0
    # 90° = crosswind → no *play-distance* change (our model is headwind/tailwind only).
    assert math.isclose(physics.wind_adjustment_yards(150, 10, 90.0), 0.0, abs_tol=1e-9)


def test_elevation_one_yard_per_three_feet():
    assert math.isclose(physics.elevation_adjustment_yards(30.0), 10.0)
    assert math.isclose(physics.elevation_adjustment_yards(-15.0), -5.0)


def test_temperature_adjustment_small_and_zero_at_reference():
    assert physics.temperature_adjustment_yards(150, temperature_c=20.0) == 0.0
    assert physics.temperature_adjustment_yards(150, temperature_c=None) == 0.0
    # Warmer → carries farther (small).
    delta = physics.temperature_adjustment_yards(150, temperature_c=30.0)
    assert 0 < delta < 4.0
