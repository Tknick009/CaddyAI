"""In-memory stores. v2 will replace with SQLite/Postgres + Alembic."""

from __future__ import annotations

import threading
from collections.abc import Iterable

from app.models.schemas import Bag, Club, PersonalDistance, Round, Shot


class _InMemoryStore:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._bag = Bag(clubs=[], personal_distances=[])
        self._rounds: dict[str, Round] = {}

    # --- bag ---------------------------------------------------------------

    def get_bag(self) -> Bag:
        with self._lock:
            return self._bag.model_copy(deep=True)

    def set_bag(self, bag: Bag) -> Bag:
        with self._lock:
            self._bag = bag.model_copy(deep=True)
            return self._bag.model_copy(deep=True)

    def add_club(self, club: Club) -> Bag:
        with self._lock:
            clubs = [c for c in self._bag.clubs if c.id != club.id]
            clubs.append(club)
            self._bag = self._bag.model_copy(update={"clubs": clubs})
            return self._bag.model_copy(deep=True)

    def remove_club(self, club_id: str) -> Bag:
        with self._lock:
            clubs = [c for c in self._bag.clubs if c.id != club_id]
            distances = [d for d in self._bag.personal_distances if d.club_id != club_id]
            self._bag = self._bag.model_copy(
                update={"clubs": clubs, "personal_distances": distances}
            )
            return self._bag.model_copy(deep=True)

    # --- rounds / shots ----------------------------------------------------

    def upsert_round(self, rnd: Round) -> Round:
        with self._lock:
            self._rounds[rnd.id] = rnd.model_copy(deep=True)
            return self._rounds[rnd.id].model_copy(deep=True)

    def list_rounds(self) -> list[Round]:
        with self._lock:
            return [r.model_copy(deep=True) for r in self._rounds.values()]

    def add_shots(self, round_id: str, shots: Iterable[Shot]) -> Round:
        with self._lock:
            rnd = self._rounds.get(round_id)
            if rnd is None:
                raise KeyError(round_id)
            rnd.shots.extend(shots)
            self._rounds[round_id] = rnd
            self._recompute_personal_distances()
            return rnd.model_copy(deep=True)

    # --- personal distance learning ---------------------------------------

    def _recompute_personal_distances(self) -> None:
        # Running average of carry yards per club across all rounds.
        buckets: dict[str, list[float]] = {}
        for rnd in self._rounds.values():
            for shot in rnd.shots:
                if not shot.club_id:
                    continue
                # Prefer carry when available, else total.
                y = shot.carry_yards if shot.carry_yards is not None else shot.distance_yards
                buckets.setdefault(shot.club_id, []).append(y)
        distances: list[PersonalDistance] = []
        for club_id, samples in buckets.items():
            if not samples:
                continue
            mean = sum(samples) / len(samples)
            variance = sum((s - mean) ** 2 for s in samples) / max(1, len(samples) - 1)
            stddev = variance**0.5
            distances.append(
                PersonalDistance(
                    club_id=club_id,
                    typical_yards=round(mean, 1),
                    stddev_yards=round(stddev, 1),
                    sample_size=len(samples),
                )
            )
        self._bag = self._bag.model_copy(update={"personal_distances": distances})


STORE = _InMemoryStore()
