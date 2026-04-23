from __future__ import annotations

from fastapi import APIRouter

from app.models.schemas import Bag, Club
from app.services.store import STORE

router = APIRouter(prefix="/bag", tags=["bag"])


@router.get("", response_model=Bag)
def get_bag() -> Bag:
    return STORE.get_bag()


@router.put("", response_model=Bag)
def put_bag(bag: Bag) -> Bag:
    return STORE.set_bag(bag)


@router.post("/clubs", response_model=Bag)
def add_club(club: Club) -> Bag:
    return STORE.add_club(club)


@router.delete("/clubs/{club_id}", response_model=Bag)
def remove_club(club_id: str) -> Bag:
    return STORE.remove_club(club_id)
