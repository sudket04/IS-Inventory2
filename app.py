"""FastAPI entry point for the IS Inventory app.

Serves the static front-end (index.html, styles.css, app.js, setup.html)
and the API routes it calls today: /api/setup (connection setup, see
setup.py) and /api/data/<key> (the key/value bridge to SQL Server, see
data.py) — the front-end still uses this KV path exclusively.

Front-end files are served by explicit routes rather than a blanket
StaticFiles mount on this directory — this directory also holds config.json,
secret.key, and the Python source itself, none of which should ever be
served over HTTP.

/api/records/<table> (see records.py) is the real per-record relational API
mounted alongside it, ready for index.html's StorageAdapter to be pointed at
once the DB integration is actually tested end-to-end — see the note at the
top of records.py.

Run with: uvicorn app:app --host 0.0.0.0 --port 8000
"""
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from routers import auth as auth_router
from routers import data as data_router
from routers import records as records_router
from routers import setup as setup_router
from routers import vlans as vlans_router

BASE_DIR = Path(__file__).resolve().parent
FRONTEND_DIST = BASE_DIR / "frontend" / "dist"

app = FastAPI(title="IS Inventory")

app.include_router(setup_router.router)
app.include_router(data_router.router)
app.include_router(records_router.router)
app.include_router(auth_router.router)
app.include_router(vlans_router.router)

# The React build (frontend/, see frontend/README.md) is optional during
# early development — mount it only once `npm run build` has produced it, so
# a fresh checkout without Node.js installed still serves the legacy
# app.js/index.html pages below.
if FRONTEND_DIST.is_dir():
    app.mount("/app", StaticFiles(directory=FRONTEND_DIST, html=True), name="frontend")


@app.get("/")
async def serve_root():
    return FileResponse(BASE_DIR / "index.html")


@app.get("/index.html")
async def serve_index():
    return FileResponse(BASE_DIR / "index.html")


@app.get("/setup.html")
async def serve_setup():
    return FileResponse(BASE_DIR / "setup.html")


@app.get("/styles.css")
async def serve_styles():
    return FileResponse(BASE_DIR / "styles.css", media_type="text/css")


@app.get("/app.js")
async def serve_app_js():
    return FileResponse(BASE_DIR / "app.js", media_type="application/javascript")
