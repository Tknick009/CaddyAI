from __future__ import annotations

import json

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app.models.schemas import Shot
from app.services.launch_monitor import Vendor, parse_csv

router = APIRouter(prefix="/launch-monitor", tags=["launch-monitor"])


@router.post("/import", response_model=list[Shot])
async def import_csv(
    file: UploadFile = File(..., description="CSV exported from the launch monitor"),
    vendor: Vendor = Form(
        "auto",
        description="r10 | rapsodo | skytrak | mevo | auto (default)",
    ),
    club_id_map_json: str | None = Form(
        None,
        description="Optional JSON object mapping vendor club names to Club.id",
    ),
) -> list[Shot]:
    content_bytes = await file.read()
    try:
        content = content_bytes.decode("utf-8-sig")
    except UnicodeDecodeError:
        content = content_bytes.decode("latin-1")
    mapping: dict[str, str] | None = None
    if club_id_map_json:
        try:
            mapping = json.loads(club_id_map_json)
        except json.JSONDecodeError as e:
            raise HTTPException(
                status_code=400, detail=f"invalid club_id_map_json: {e}"
            ) from e
    try:
        return parse_csv(content, vendor=vendor, club_id_map=mapping)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
