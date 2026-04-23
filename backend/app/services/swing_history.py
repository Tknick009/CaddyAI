"""Persistent swing-history repository.

Two responsibilities:
- **Write**: store a new `(metrics, report, optional keyframes)` tuple
  for a given device.
- **Read**: retrieve the last N reports for a device, used by the coach
  to build RAG context so advice references recurring tendencies instead
  of re-diagnosing the same fault every session.
"""

from __future__ import annotations

import base64
from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import SwingHistoryRow, SwingKeyframeRow
from app.models.schemas import (
    CoachingReport,
    SwingHistoryEntry,
    SwingKeyframe,
    SwingMetrics,
)


async def record_swing(
    session: AsyncSession,
    device_id: str,
    metrics: SwingMetrics,
    report: CoachingReport,
    keyframes: list[SwingKeyframe] | None,
    coach_source: str,
) -> SwingHistoryEntry:
    swing_id = uuid4().hex
    now = datetime.now(tz=UTC)
    row = SwingHistoryRow(
        swing_id=swing_id,
        device_id=device_id,
        ts=now,
        club_kind=metrics.club_kind.value if metrics.club_kind else None,
        viewpoint=metrics.viewpoint.value if metrics.viewpoint else None,
        metrics_json=metrics.model_dump_json(by_alias=True),
        report_json=report.model_dump_json(by_alias=True),
        coach_source=coach_source,
    )
    for kf in keyframes or []:
        raw = base64.b64decode(kf.jpeg_base64)
        row.keyframes.append(SwingKeyframeRow(swing_id=swing_id, position=kf.position, jpeg=raw))
    session.add(row)
    await session.commit()
    return SwingHistoryEntry(
        swing_id=swing_id,
        ts=now,
        metrics=metrics,
        report=report,
    )


async def recent_for_device(
    session: AsyncSession,
    device_id: str,
    limit: int = 20,
) -> list[SwingHistoryEntry]:
    stmt = (
        select(SwingHistoryRow)
        .where(SwingHistoryRow.device_id == device_id)
        .order_by(SwingHistoryRow.ts.desc())
        .limit(limit)
    )
    result = await session.execute(stmt)
    rows = list(result.scalars().all())
    return [_row_to_entry(r) for r in rows]


def _row_to_entry(row: SwingHistoryRow) -> SwingHistoryEntry:
    return SwingHistoryEntry(
        swing_id=row.swing_id,
        ts=row.ts,
        metrics=SwingMetrics.model_validate_json(row.metrics_json),
        report=CoachingReport.model_validate_json(row.report_json),
    )
