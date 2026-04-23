"""LLM-backed swing coach with a deterministic mock fallback.

The iOS app never sees raw video — only `SwingMetrics`. We take those
metrics, build a structured prompt, and ask OpenAI for a `CoachingReport`.
If `OPENAI_API_KEY` is unset (local dev, CI, tests) we fall back to a
deterministic rule-based coach so the endpoint still behaves sensibly.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import httpx

from app.models.schemas import CoachingReport, Drill, SwingMetrics

log = logging.getLogger(__name__)

_OPENAI_URL = "https://api.openai.com/v1/chat/completions"
_MODEL = os.environ.get("CADDYAI_OPENAI_MODEL", "gpt-4o-mini")


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


async def _openai_report(metrics: SwingMetrics, api_key: str) -> CoachingReport:
    payload: dict[str, Any] = {
        "model": _MODEL,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": "Analyze this swing:\n" + metrics.model_dump_json(indent=2),
            },
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
    # Ensure drills come back as Drill objects even if the model returns plain dicts.
    drills = [Drill(**d) if isinstance(d, dict) else d for d in parsed.get("drills", [])]
    return CoachingReport(
        summary=parsed["summary"],
        likely_ball_flight=parsed["likely_ball_flight"],
        root_causes=list(parsed.get("root_causes", [])),
        drills=drills,
        source="openai",
    )


async def generate_report(metrics: SwingMetrics) -> CoachingReport:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        log.info("OPENAI_API_KEY not set; returning mock coach report")
        return _mock_report(metrics)
    try:
        return await _openai_report(metrics, api_key)
    except Exception:
        log.exception("OpenAI call failed; falling back to mock coach")
        return _mock_report(metrics)
