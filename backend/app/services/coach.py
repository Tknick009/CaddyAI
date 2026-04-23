"""LLM-backed swing coach with a deterministic mock fallback.

Takes `SwingMetrics` (+ optional keyframe images and prior-swing context),
builds a structured prompt, and asks OpenAI for a `CoachingReport`. If
`OPENAI_API_KEY` is unset (local dev, CI, tests) we fall back to a
deterministic rule-based coach so the endpoint still behaves sensibly.

Two upgrade paths live here:

- **Vision mode** — when keyframes are provided and a vision-capable model
  is configured (gpt-4o), the user message becomes a multi-part content
  array: text + image_url parts with base64 data URIs. This gives the
  coach the same view a human pro would: still frames at address, top,
  impact, and finish.
- **RAG mode** — when `history` is provided, recent summaries are folded
  into the user message so advice references recurring tendencies
  instead of re-diagnosing the same fault every session.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import httpx

from app.models.schemas import (
    CoachingReport,
    Drill,
    SwingHistoryEntry,
    SwingKeyframe,
    SwingMetrics,
)

log = logging.getLogger(__name__)

_OPENAI_URL = "https://api.openai.com/v1/chat/completions"
# Text-only default. Override per-request if vision is configured below.
_MODEL = os.environ.get("CADDYAI_OPENAI_MODEL", "gpt-4o-mini")
_VISION_MODEL = os.environ.get("CADDYAI_OPENAI_VISION_MODEL", "gpt-4o")


SYSTEM_PROMPT = """You are a PGA-certified golf swing coach.

You will receive a JSON object of biomechanical metrics extracted from a
single recorded swing via on-device pose estimation. You MUST return a
JSON object with exactly these fields:

  summary             : one short paragraph (max 60 words)
  likely_ball_flight  : a short phrase, e.g. "Weak push-slice"
  root_causes         : array of 1-4 short strings
  drills              : array of 1-3 objects with {name, description}

Rules:
- Be specific. Reference the numbers you were given.
- Do not invent metrics you weren't given.
- Never speak about video or camera angle — you only have metrics.
- Tempo ratio < 2.5 means the swing is quick; > 3.3 means long/slow.
- X-factor < 25° at the top typically means loss of power.
- Lateral sway > 6 cm toward the trail side on the backswing is a fault.
- Head movement > 8 cm is excessive.
- Weight transfer < 65% on the lead foot at impact is a fault for irons.
- When an `attack_angle_deg` is provided, interpret it as club (or lead-
  wrist) descent at impact: irons should be −2° to −5°, driver +2° to +5°.
- When a `sequencing_index` is provided, values < 0.5 mean the kinematic
  sequence is out of order (torso firing before pelvis, a power leak).
- When a `viewpoint` of "pose3d" or "fused" is supplied, the metrics are
  unusually trustworthy; be more confident in your diagnosis. When
  "face_on" only, caveat plane / attack-angle claims — those are unreliable
  from a single 2D face-on camera.
- If keyframe images are attached (address / top / impact / finish), use
  them — they're the same stills a human coach would look at. Reference
  visual evidence only when the images actually show it.
- If the "Recent sessions" section is present, treat it as memory of
  THIS player's recurring tendencies. When the same fault (e.g. early
  extension) shows up again, acknowledge it and pick a progression of
  the drill rather than re-suggesting the basic one.
"""


def _mock_report(m: SwingMetrics) -> CoachingReport:
    """Deterministic heuristic used when no OPENAI_API_KEY is configured."""
    causes: list[str] = []
    drills: list[Drill] = []

    if m.tempo_ratio < 2.5:
        causes.append(
            f"Swing tempo is quick (ratio {m.tempo_ratio:.1f}:1); the downswing "
            "starts before the backswing finishes."
        )
        drills.append(
            Drill(
                name="1-2-3 tempo drill",
                description=(
                    "Count '1-2' on the backswing and '3' on the downswing. Hit "
                    "20 half-wedges on a 3:1 ratio."
                ),
            )
        )
    if m.x_factor_deg < 25:
        causes.append(
            f"X-factor at the top is only {m.x_factor_deg:.0f}°; shoulders and "
            "hips are turning together, costing you power."
        )
        drills.append(
            Drill(
                name="Chair drill",
                description=(
                    "Address the ball with a chair touching your trail hip. On "
                    "the backswing keep the hip against the chair and feel the "
                    "upper body wind up above it."
                ),
            )
        )
    if m.lateral_sway_cm > 6:
        causes.append(
            f"Hip sways {m.lateral_sway_cm:.1f} cm away from the target on the "
            "backswing instead of rotating."
        )
    if m.head_movement_cm > 8:
        causes.append(
            f"Head moves {m.head_movement_cm:.1f} cm during the swing; aim to "
            "keep it under 5 cm."
        )
    if m.weight_transfer_pct < 65:
        causes.append(
            f"Only {m.weight_transfer_pct:.0f}% of weight reaches the lead foot "
            "at impact; you're hanging back."
        )
    if (
        m.attack_angle_deg is not None
        and m.club_kind is not None
        and m.club_kind != "driver"
    ):
        aa = m.attack_angle_deg
        club_value = m.club_kind.value if hasattr(m.club_kind, "value") else str(m.club_kind)
        club_label = club_value if club_value in ("iron", "hybrid", "wood", "wedge") else "club"
        if aa > 0:
            causes.append(
                f"Attack angle is {aa:+.1f}° (hitting up on a {club_label}); expect "
                "thin contact and loss of compression."
            )
            drills.append(
                Drill(
                    name="Ball-first contact drill",
                    description=(
                        "Place a tee 1 inch in front of the ball. Swing to clip "
                        "the tee after the ball — forces a descending strike."
                    ),
                )
            )
        elif aa < -7:
            causes.append(
                f"Attack angle is {aa:.1f}° — too steep; this digs and loses distance."
            )
    if m.attack_angle_deg is not None and m.club_kind == "driver" and m.attack_angle_deg < 0:
        causes.append(
            f"Driver attack angle is {m.attack_angle_deg:.1f}° (hitting down); "
            "tee higher and feel the ball is forward in your stance to launch up."
        )
    if m.sequencing_index is not None and m.sequencing_index < 0.5:
        causes.append(
            f"Kinematic sequence score {m.sequencing_index:.2f}: upper body is "
            "firing before the lower body — a classic power leak."
        )
        drills.append(
            Drill(
                name="Step-through drill",
                description=(
                    "Start at address with feet together. Take a step toward the "
                    "target as you start down. Grooves pelvis-first sequencing."
                ),
            )
        )
    if m.pelvis_slide_cm is not None and m.pelvis_slide_cm > 8:
        causes.append(
            f"Pelvis slides {m.pelvis_slide_cm:.0f} cm laterally on the backswing "
            "instead of rotating — kills coil."
        )

    # Synthesize the most likely ball flight from the faults.
    if m.weight_transfer_pct < 60 and m.x_factor_deg < 25:
        flight = "High, weak push-slice"
    elif m.lateral_sway_cm > 6 and m.weight_transfer_pct < 60:
        flight = "Thin or fat contact, usually blocked right"
    elif m.tempo_ratio < 2.3:
        flight = "Low pull-hook"
    else:
        flight = "Inconsistent contact"

    if not causes:
        causes.append("No major faults detected — swing looks solid.")
    if not drills:
        drills.append(
            Drill(
                name="Mirror feedback",
                description=(
                    "Practice slow-motion swings in front of a mirror to "
                    "reinforce the positions you already own."
                ),
            )
        )

    summary = (
        f"Tempo {m.tempo_ratio:.1f}:1, X-factor {m.x_factor_deg:.0f}°, "
        f"weight transfer {m.weight_transfer_pct:.0f}%. "
        + (causes[0] if causes else "Keep doing what you're doing.")
    )

    return CoachingReport(
        summary=summary,
        likely_ball_flight=flight,
        root_causes=causes,
        drills=drills,
        source="mock",
    )


def _history_block(history: list[SwingHistoryEntry]) -> str:
    """Condense the player's recent sessions into a few bullet lines. Keeps
    the token budget small — we only need enough to let the model spot a
    recurring fault, not replay whole past reports."""
    if not history:
        return ""
    lines = ["\nRecent sessions (most recent first):"]
    for h in history[:5]:
        m = h.metrics
        r = h.report
        causes = "; ".join(r.root_causes[:2]) if r.root_causes else "no major faults"
        lines.append(
            f"- {h.ts:%Y-%m-%d} {m.club_kind or 'club'}: tempo {m.tempo_ratio:.1f}:1, "
            f"X-factor {m.x_factor_deg:.0f}°, flight: {r.likely_ball_flight}. {causes}"
        )
    return "\n".join(lines) + "\n"


def _user_message(
    metrics: SwingMetrics,
    keyframes: list[SwingKeyframe],
    history: list[SwingHistoryEntry],
) -> Any:
    """Build the `user` content. Text-only when there are no keyframes;
    multi-part list (text + image_url) otherwise so GPT-4o vision sees
    the stills. Returns the content suitable for the Chat Completions API.
    """
    prose = (
        "Analyze this swing:\n"
        + metrics.model_dump_json(indent=2)
        + _history_block(history)
    )
    if not keyframes:
        return prose
    content: list[dict[str, Any]] = [{"type": "text", "text": prose}]
    for kf in keyframes:
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{kf.jpeg_base64}"},
            }
        )
    return content


async def _openai_report(
    metrics: SwingMetrics,
    api_key: str,
    keyframes: list[SwingKeyframe],
    history: list[SwingHistoryEntry],
) -> CoachingReport:
    vision = bool(keyframes)
    model = _VISION_MODEL if vision else _MODEL
    payload: dict[str, Any] = {
        "model": model,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _user_message(metrics, keyframes, history)},
        ],
        "temperature": 0.4,
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            _OPENAI_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
    resp.raise_for_status()
    body = resp.json()
    content = body["choices"][0]["message"]["content"]
    parsed = json.loads(content)
    drills = [Drill(**d) if isinstance(d, dict) else d for d in parsed.get("drills", [])]
    return CoachingReport(
        summary=parsed["summary"],
        likely_ball_flight=parsed["likely_ball_flight"],
        root_causes=list(parsed.get("root_causes", [])),
        drills=drills,
        source="openai-vision" if vision else "openai",
    )


async def generate_report(
    metrics: SwingMetrics,
    keyframes: list[SwingKeyframe] | None = None,
    history: list[SwingHistoryEntry] | None = None,
) -> CoachingReport:
    keyframes = keyframes or []
    history = history or []
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        log.info("OPENAI_API_KEY not set; returning mock coach report")
        return _mock_report(metrics)
    try:
        return await _openai_report(metrics, api_key, keyframes, history)
    except Exception:
        log.exception("OpenAI call failed; falling back to mock coach")
        return _mock_report(metrics)
