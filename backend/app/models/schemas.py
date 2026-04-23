"""Shared wire schemas. Must stay in sync with ios/CaddyAICore/Models.swift."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class _Model(BaseModel):
    # Swift uses `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`, so
    # we deliberately keep snake_case on the wire.
    model_config = ConfigDict(populate_by_name=True)


# --- Clubs & bag -----------------------------------------------------------


class ClubKind(str, Enum):
    driver = "driver"
    wood = "wood"
    hybrid = "hybrid"
    iron = "iron"
    wedge = "wedge"
    putter = "putter"


class Club(_Model):
    id: str
    kind: ClubKind
    name: str
    loft_deg: float | None = None


class PersonalDistance(_Model):
    club_id: str
    typical_yards: float
    stddev_yards: float = 0.0
    sample_size: int = 0


class Bag(_Model):
    clubs: list[Club]
    personal_distances: list[PersonalDistance] = Field(default_factory=list)


# --- Shots & rounds --------------------------------------------------------


class ShotSource(str, Enum):
    manual = "manual"
    garmin_watch = "garmin_watch"
    launch_monitor_r10 = "launch_monitor_r10"
    launch_monitor_mevo = "launch_monitor_mevo"
    launch_monitor_skytrak = "launch_monitor_skytrak"
    launch_monitor_rapsodo = "launch_monitor_rapsodo"


class Shot(_Model):
    id: str
    club_id: str
    distance_yards: float
    carry_yards: float | None = None
    ball_speed_mph: float | None = None
    club_speed_mph: float | None = None
    launch_angle_deg: float | None = None
    spin_rpm: float | None = None
    side_yards: float | None = None  # positive = right of target
    result: Literal["fairway", "rough", "green", "bunker", "hazard", "ob", "unknown"] = (
        "unknown"
    )
    ts: datetime
    source: ShotSource = ShotSource.manual
    note: str | None = None


class Round(_Model):
    id: str
    course: str | None = None
    date: datetime
    shots: list[Shot] = Field(default_factory=list)


# --- Swing analysis --------------------------------------------------------


class SwingViewpoint(str, Enum):
    """Camera source of a `SwingMetrics`. Different viewpoints are honest
    about different measurements; the coach weights advice accordingly."""

    face_on = "face_on"
    down_the_line = "down_the_line"
    fused = "fused"          # MultiAngleSwingAnalyzer output
    pose3d = "pose3d"        # iOS 17+ VNDetectHumanBodyPose3DRequest


class SwingMetrics(_Model):
    """Output of the on-device Vision pose pipeline."""

    tempo_ratio: float = Field(
        description="backswing duration / downswing duration; ~3.0 is ideal"
    )
    backswing_sec: float
    downswing_sec: float
    peak_shoulder_turn_deg: float
    peak_hip_turn_deg: float
    x_factor_deg: float = Field(description="shoulder_turn − hip_turn at top of swing")
    lateral_sway_cm: float = Field(description="lead-hip lateral shift from address to top")
    head_movement_cm: float
    early_extension_cm: float = Field(description="pelvis forward push at impact vs address")
    swing_plane_deg: float
    weight_transfer_pct: float = Field(
        description="percent of body weight on lead foot at impact, 0-100"
    )
    confidence: float = Field(ge=0.0, le=1.0)
    handedness: Literal["right", "left"] = "right"
    club_kind: ClubKind | None = None

    # 3D-only or multi-angle-fused fields. `None` on pure face-on captures.
    viewpoint: SwingViewpoint | None = None
    attack_angle_deg: float | None = Field(
        default=None,
        description="lead-wrist descent angle at impact (°); negative = hitting down",
    )
    pelvis_slide_cm: float | None = Field(
        default=None,
        description="horizontal pelvis translation from address to top (cm)",
    )
    pelvis_tilt_deg: float | None = Field(
        default=None,
        description="hip-line tilt at impact (°); positive = trail side down",
    )
    sequencing_index: float | None = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="how close to pelvis→torso→hand kinematic sequence; 1 = ideal",
    )
    club_path_deg: float | None = Field(
        default=None,
        description="club head path at impact (°); requires club-head tracking",
    )


class Drill(_Model):
    name: str
    description: str


class CoachingReport(_Model):
    summary: str
    likely_ball_flight: str = Field(
        description="e.g. 'Weak slice' or 'Low pull-hook'"
    )
    root_causes: list[str]
    drills: list[Drill]
    # Where this report came from. "openai" = text-only GPT-4o-mini call,
    # "openai-vision" = GPT-4o with keyframe images, "mock" = deterministic
    # fallback used when OPENAI_API_KEY is unset or OpenAI returned an error.
    source: Literal["openai", "openai-vision", "mock"] = "openai"


# --- Persistence & context -------------------------------------------------


class SwingKeyframe(_Model):
    """One still frame extracted from the swing capture. Sent base64-encoded
    so clients don't need multipart upload. JPEG quality ~0.6 is enough for
    the LLM; we're not doing pixel-exact analysis server-side."""

    position: Literal["address", "top", "impact", "finish"]
    jpeg_base64: str


class CoachRequest(_Model):
    """New envelope for `POST /coach/swing` — lets the client ship
    optional keyframes for Vision-LLM analysis and a stable device id so
    the coach can retrieve the player's history for RAG context."""

    metrics: SwingMetrics
    keyframes: list[SwingKeyframe] = Field(default_factory=list)
    # Required to retrieve history; when absent the request is treated as
    # a one-shot diagnosis with no memory.
    device_id: str | None = None


class SwingHistoryEntry(_Model):
    """One previously-analyzed swing, returned by the history endpoint
    and used as RAG context. No keyframes are returned — clients that
    want them can re-fetch by swing_id (endpoint TBD)."""

    swing_id: str
    ts: datetime
    metrics: SwingMetrics
    report: CoachingReport


class SwingHistoryResponse(_Model):
    device_id: str
    entries: list[SwingHistoryEntry]


# --- On-course caddy -------------------------------------------------------


class Lie(str, Enum):
    tee = "tee"
    fairway = "fairway"
    rough = "rough"
    deep_rough = "deep_rough"
    bunker = "bunker"
    recovery = "recovery"


class ShotContext(_Model):
    target_distance_yards: float
    elevation_change_ft: float = 0.0
    wind_speed_mph: float = 0.0
    wind_direction_deg: float = 0.0  # 0 = pure headwind, 180 = pure tailwind
    lie: Lie = Lie.fairway
    pin_position: Literal["front", "middle", "back"] | None = None
    shot_shape_preference: Literal["straight", "draw", "fade"] | None = None
    avoid_left: bool = False
    avoid_right: bool = False
    must_carry_yards: float | None = None

    # --- Environment (optional; the server enriches from OpenWeather / ---
    # --- Open-Elevation when lat/lon are provided and a key is set) ------
    latitude: float | None = None
    longitude: float | None = None
    altitude_ft: float | None = Field(
        default=None,
        description="Altitude of the shot above sea level (feet). Affects air density.",
    )
    temperature_c: float | None = None
    pressure_hpa: float | None = None
    humidity_pct: float | None = None

    # --- Hazards (optional; used by the strokes-gained caddy) ---------------
    hazard_left_yards: float | None = Field(
        default=None,
        description="Lateral distance to the nearest penalty/OB on the left (yards).",
    )
    hazard_right_yards: float | None = Field(
        default=None,
        description="Lateral distance to the nearest penalty/OB on the right (yards).",
    )


class ClubChoice(_Model):
    """One candidate club, scored by expected strokes for *this* shot."""

    club_id: str
    typical_play_yards: float = Field(
        description="Club's carry distance after all environmental adjustments."
    )
    expected_strokes: float = Field(
        description="Broadie expected strokes from the predicted landing spot, "
        "marginalized over the player's dispersion."
    )
    lateral_stddev_yards: float
    long_stddev_yards: float


class CaddyRecommendation(_Model):
    primary_club_id: str
    alt_club_id: str | None = None
    effective_distance_yards: float
    wind_adjustment_yards: float
    elevation_adjustment_yards: float
    lie_adjustment_yards: float
    # v2 additions — all nullable for forward compat with v1 clients.
    air_density_adjustment_yards: float | None = None
    expected_strokes: float | None = None
    candidates: list[ClubChoice] = Field(default_factory=list)
    weather_source: Literal["none", "request", "openweather"] | None = "none"
    commentary: str
