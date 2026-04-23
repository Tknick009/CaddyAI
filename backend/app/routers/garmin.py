"""Garmin Connect OAuth stub.

Garmin's consumer OAuth is a 2-legged dance requiring a developer account
and an approved Connect IQ / Health API application. For v1 we expose
endpoint shapes the iOS app can target; they return 501 until the
`GARMIN_CLIENT_ID` / `GARMIN_CLIENT_SECRET` env vars are configured and the
OAuth flow is implemented.
"""

from __future__ import annotations

import os

from fastapi import APIRouter, HTTPException

router = APIRouter(prefix="/garmin", tags=["garmin"])


def _configured() -> bool:
    return bool(os.environ.get("GARMIN_CLIENT_ID") and os.environ.get("GARMIN_CLIENT_SECRET"))


@router.get("/oauth/start")
def oauth_start() -> dict[str, str]:
    if not _configured():
        raise HTTPException(
            status_code=501,
            detail=(
                "Garmin OAuth not configured. Set GARMIN_CLIENT_ID and "
                "GARMIN_CLIENT_SECRET after registering a Garmin Connect "
                "Developer Program app."
            ),
        )
    # TODO(v2): request a request-token from Garmin and redirect user.
    raise HTTPException(status_code=501, detail="not yet implemented (v2)")


@router.get("/oauth/callback")
def oauth_callback(oauth_token: str, oauth_verifier: str) -> dict[str, str]:
    # TODO(v2): exchange verifier for access_token, persist per user.
    raise HTTPException(status_code=501, detail="not yet implemented (v2)")


@router.get("/status")
def status() -> dict[str, bool | str]:
    return {
        "configured": _configured(),
        "note": (
            "Apply at https://developer.garmin.com/ for the Health API or "
            "Connect IQ program, then set GARMIN_CLIENT_ID/SECRET."
        ),
    }
