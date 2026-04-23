from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.models.schemas import Round, Shot
from app.services.store import STORE

router = APIRouter(prefix="/rounds", tags=["rounds"])


@router.get("", response_model=list[Round])
def list_rounds() -> list[Round]:
    return STORE.list_rounds()


@router.put("/{round_id}", response_model=Round)
def upsert_round(round_id: str, rnd: Round) -> Round:
    if rnd.id != round_id:
        raise HTTPException(status_code=400, detail="path id does not match body id")
    return STORE.upsert_round(rnd)


@router.post("/{round_id}/shots", response_model=Round)
def add_shots(round_id: str, shots: list[Shot]) -> Round:
    try:
        return STORE.add_shots(round_id, shots)
    except KeyError:
        raise HTTPException(status_code=404, detail="round not found") from None
