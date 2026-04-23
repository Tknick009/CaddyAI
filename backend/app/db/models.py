"""ORM models. Wire/DTO shapes still live in `app.models.schemas` — these
rows exist purely to give each `SwingMetrics` + `CoachingReport` a home
on disk, plus the keyframe blobs we feed to Vision-capable LLMs.

`metrics_json` and `report_json` are stored as strings (already JSON)
so we can add new optional fields to `SwingMetrics` without migrating
the DB — the ORM doesn't need to know the shape.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import ForeignKey, Integer, LargeBinary, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class SwingHistoryRow(Base):
    __tablename__ = "swing_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    swing_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    device_id: Mapped[str] = mapped_column(String(128), index=True)
    ts: Mapped[datetime] = mapped_column(index=True)
    club_kind: Mapped[str | None] = mapped_column(String(16), nullable=True)
    viewpoint: Mapped[str | None] = mapped_column(String(32), nullable=True)
    metrics_json: Mapped[str] = mapped_column(Text)
    report_json: Mapped[str] = mapped_column(Text)
    # The OpenAI call used to generate this report. "openai" | "openai-vision"
    # | "mock". Useful for later analysis of which reports came from which
    # flow (e.g. quality dashboards).
    coach_source: Mapped[str] = mapped_column(String(32))

    keyframes: Mapped[list[SwingKeyframeRow]] = relationship(
        back_populates="swing", cascade="all, delete-orphan"
    )


class SwingKeyframeRow(Base):
    """Address / top / impact / finish still images. JPEG-encoded bytes.

    Stored alongside the metrics so the coach can re-run with vision
    later without needing the iOS app to re-upload anything.
    """

    __tablename__ = "swing_keyframes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    swing_id: Mapped[str] = mapped_column(
        ForeignKey("swing_history.swing_id", ondelete="CASCADE"),
        index=True,
    )
    position: Mapped[str] = mapped_column(String(16))   # "address" | "top" | "impact" | "finish"
    jpeg: Mapped[bytes] = mapped_column(LargeBinary)

    swing: Mapped[SwingHistoryRow] = relationship(back_populates="keyframes")
