"""Server-side password hashing and session tokens for dbo.app_users.

index.html currently hashes passwords with SHA-256 in the browser before
they're ever sent anywhere — fine as a "don't keep plaintext lying around in
this client-only prototype" gesture, but not a real password hash (no salt,
fast to brute-force). Once the backend owns the users table, hashing moves
here: bcrypt, salted, done server-side, and the plaintext password never
needs to touch storage at all.

The JWT half is the session layer for the React frontend: login exchanges a
username/password for a short-lived signed token, carried in an httpOnly
cookie so page JS never sees it (defends against XSS reading the token, not
just CSRF — SameSite=lax covers CSRF for this same-origin app).
"""
import os
import time
from pathlib import Path
from typing import Any, Dict, Optional

import bcrypt
import jwt
from fastapi import Cookie, Depends, HTTPException, status

BASE_DIR = Path(__file__).resolve().parent
JWT_KEY_PATH = BASE_DIR / "jwt_secret.key"
TOKEN_TTL_SECONDS = 8 * 60 * 60  # 8h — a work day; re-login after that, no silent refresh yet


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except ValueError:
        return False  # hashed isn't a valid bcrypt hash (e.g. still the old client-side sha256 value)


def _jwt_secret() -> bytes:
    if JWT_KEY_PATH.exists():
        return JWT_KEY_PATH.read_bytes()
    key = os.urandom(32)
    JWT_KEY_PATH.write_bytes(key)
    try:
        os.chmod(JWT_KEY_PATH, 0o600)
    except OSError:
        pass
    return key


def create_access_token(user_id: str, role_id: str, site_ids: list) -> str:
    payload = {
        "sub": user_id,
        "role_id": role_id,
        "site_ids": site_ids,   # locations this user may EDIT; empty/absent = Admin (all sites)
        "iat": int(time.time()),
        "exp": int(time.time()) + TOKEN_TTL_SECONDS,
    }
    return jwt.encode(payload, _jwt_secret(), algorithm="HS256")


def decode_access_token(token: str) -> Optional[Dict[str, Any]]:
    try:
        return jwt.decode(token, _jwt_secret(), algorithms=["HS256"])
    except jwt.PyJWTError:
        return None


async def get_current_user(access_token: Optional[str] = Cookie(default=None)) -> Dict[str, Any]:
    """FastAPI dependency: every protected route takes `user: dict =
    Depends(get_current_user)` and gets back the decoded token claims, or a
    401 before the route body runs at all.
    """
    if not access_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not logged in")
    claims = decode_access_token(access_token)
    if claims is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired or invalid")
    return claims


def require_site_access(user: Dict[str, Any], location_id: str) -> None:
    """Raise 403 unless `user` may edit records filed under `location_id`.
    Admin (role_id == 'ROL-001') edits every site; everyone else — including
    a misconfigured account with an empty scope — is restricted to the sites
    listed in their token, never treated as unrestricted by default.
    Viewer/Auditor tokens carry no write permission at all — that is checked
    separately by require_permission, this only narrows *which* site once a
    write permission is already confirmed.
    """
    if user.get("role_id") == "ROL-001":
        return
    site_ids = user.get("site_ids") or []
    if location_id not in site_ids:
        raise HTTPException(status_code=403, detail="This record belongs to a site outside your scope.")


def require_permission(module_key: str, action: str):
    """Dependency factory: `Depends(require_permission("vlans", "edit"))`.
    Looks up dbo.role_permissions live on every call rather than baking the
    grant into the JWT — revoking a permission in the Roles admin page takes
    effect on the token's very next request, not at its next login.
    """
    permission_id = f"{module_key}.{action}"

    async def _check(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        import db
        from config import load_config

        cfg = load_config()
        if cfg is None:
            raise HTTPException(status_code=503, detail="Database not configured yet.")
        conn = db.get_connection(cfg)
        try:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT 1 FROM dbo.role_permissions WHERE role_id = ? AND permission_id = ?",
                user["role_id"], permission_id,
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=403, detail=f"Your role cannot {action} {module_key}.")
        finally:
            conn.close()
        return user

    return _check
