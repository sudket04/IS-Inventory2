"""Login/logout/me for the React frontend.

Issues an httpOnly, SameSite=lax JWT cookie on success — page JS never
touches the token directly, only /api/auth/me tells it who is logged in.
"""
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel

import auth
import db
from config import load_config

router = APIRouter(prefix="/api/auth")

COOKIE_NAME = "access_token"


class LoginRequest(BaseModel):
    username: str
    password: str


def _require_config():
    cfg = load_config()
    if cfg is None:
        raise HTTPException(status_code=503, detail="Database not configured yet. Visit /setup.html.")
    return cfg


@router.post("/login")
async def login(body: LoginRequest, response: Response):
    cfg = _require_config()
    conn = db.get_connection(cfg)
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT user_id, password_hash, role_id, status, must_change_password "
            "FROM dbo.app_users WHERE username = ? AND is_deleted = 0",
            body.username,
        )
        row = cursor.fetchone()
        if row is None or not auth.verify_password(body.password, row.password_hash):
            raise HTTPException(status_code=401, detail="Invalid username or password")
        if row.status != "Active":
            raise HTTPException(status_code=403, detail="This account is disabled")

        cursor.execute("SELECT location_id FROM dbo.user_site_scope WHERE user_id = ?", row.user_id)
        site_ids = [r[0] for r in cursor.fetchall()]
    finally:
        conn.close()

    token = auth.create_access_token(row.user_id, row.role_id, site_ids)
    response.set_cookie(
        COOKIE_NAME,
        token,
        httponly=True,
        samesite="lax",
        max_age=auth.TOKEN_TTL_SECONDS,
    )
    return {
        "ok": True,
        "user_id": row.user_id,
        "role_id": row.role_id,
        "must_change_password": bool(row.must_change_password),
    }


@router.post("/logout")
async def logout(response: Response):
    response.delete_cookie(COOKIE_NAME)
    return {"ok": True}


@router.get("/me")
async def me(user: dict = Depends(auth.get_current_user)):
    return user
