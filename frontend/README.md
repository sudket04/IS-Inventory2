# IS-Inventory frontend

React + Vite + Tailwind. Replaces `app.js`/`index.html` (kept in the repo
root as reference/rollback, not deleted) once this is feature-complete.

## Dev

```bash
cd frontend
npm install
npm run dev        # http://localhost:5173, proxies /api to :8000
```

Run the FastAPI backend separately (`uvicorn app:app --reload --port 8000`)
— the dev server's Vite proxy (see `vite.config.js`) forwards `/api/*` to it.

## Production build

```bash
npm run build       # writes frontend/dist
```

`app.py` mounts `frontend/dist` at `/app` automatically once it exists — one
FastAPI process serves both the API and the built frontend, no second server
in production. Until `dist/` is built, `/app` 404s and the legacy
`app.js`/`index.html` at `/` keep working exactly as before.

## What's scaffolded vs. what's still a stub

Built for real, talking to the actual FastAPI endpoints:
- Login / session (`/api/auth/*`, httpOnly cookie)
- Server list with the Site column + filter (`v_asset_360` via `/api/records/servers`)
- VLAN editor: Untagged toggle, add/remove Primary/Secondary subnets, per-subnet
  IP Assignment (Static/DHCP/Static+DHCP), multiple static ranges, explicit DHCP
  fields — the whole nested shape from `db/04_network.sql` (`/api/vlans/*`)
- Applications tab under Server detail (`/api/records/applications`)

Still placeholders, deliberately not built out yet:
- Dashboard (routed, renders a stub)
- Hardware / Software / Users & Roles pages (same list-page pattern as
  Servers/VLAN, not yet written — copy `Servers.jsx` as the template)
- Create-new-Server / create-new-VLAN flows (the editors above assume the
  record already exists; "+ เพิ่มใหม่" buttons don't wire up yet)
