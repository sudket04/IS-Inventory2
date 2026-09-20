# Handoff — IS-Inventory database v2

**Branch:** `claude/brave-edison-te5508`
**Latest commit:** `a1f19fd` — "Add JWT auth, nested VLAN API, and React/Vite/Tailwind frontend"
**Status:** Database schema is done and tested. Backend now has real auth + a nested
VLAN API. A new React frontend (`frontend/`) is scaffolded and wired to it — VLAN
editor, Applications tab, and the Site-scoped Server list are real; most other pages
are still stubs. The legacy `app.js`/`index.html` is untouched and still serves at `/`.

## Where things stand

### Done — `db/` (SQL Server 2022+, verified on 2025 RTM-CU9)

The whole v2 schema in `db/01_functions.sql` … `db/11_applications.sql` builds clean from
scratch and passes its test suite (65/65 checks across `test_network.sql` and
`test_rbac_views.sql`). See `db/README.md` for the file-by-file breakdown and the full
rationale for every structural change from v1.

Two rounds of changes happened, in order:

1. **e63b73f** — the original v2 rebuild: RBAC as data (not a CHECK constraint), IP
   addresses unified into one `ip_allocations` registry, real FKs everywhere, system
   versioning, filtered-unique soft delete, indexes.
2. **3896941** (this round) — triggered by the user sending a real VLAN config
   spreadsheet that the first VLAN design couldn't represent. Three gaps, all fixed:
   - **One VLAN can have multiple subnets.** Split `vlans` (tag/identity) from
     `vlan_subnets` (one row per IP range, `level` = Primary/Secondary). A VLAN tag is
     no longer unique across the estate — it's unique per device.
   - **VLAN can be Untagged.** `vlan_tag` is now `INT NULL`; NULL = untagged (native
     VLAN on a trunk), not "not entered yet." Persisted `is_untagged` bit column.
   - **DHCP isn't always "whatever's left after one static block."** Added
     `vlan_static_ranges` (a subnet can have N disjoint static blocks). DHCP
     start/end on `vlan_subnets` are now explicit, trigger-validated columns instead of
     computed — the real WIFI-Data-Center /21 runs DHCP in the *middle* of the range
     with static blocks on both sides, which the old "leftover" derivation couldn't
     model at all.
   - Also added `dbo.applications` (filed under a server) + `v_server_applications`,
     per the user's request #5. `server_type` is derived via the view (from
     `servers.hosting_type/os_version`), not stored, to avoid drift.

Everything is covered by triggers/CHECK constraints for the cases that matter:
overlapping static ranges, static overlapping DHCP, ranges outside subnet bounds, more
than one Primary subnet per VLAN, duplicate tag on the same device.

Also since the DB round: `hardware.location_id` and `vlans.location_id` are now
`NOT NULL` — every data-entry form must resolve to a site. The two-site limit (1st
Site/2nd Site) stays a `10_seed.sql` convention, not a DB CHECK.

### Done — backend (`app.py`, `auth.py`, `routers/`)

The stack decision that had stalled from before the VLAN spreadsheet: **kept FastAPI +
pyodbc** (it already existed and matches this schema), did not rewrite it in Node —
Node is now only the frontend's build tool.

- `auth.py` / `routers/auth.py`: real login. bcrypt-verifies against
  `dbo.app_users`, issues an httpOnly JWT cookie carrying `role_id` and the caller's
  `user_site_scope` rows. `auth.require_permission(module, action)` does a live
  `dbo.role_permissions` lookup (revoking a permission takes effect on that user's
  very next request); `auth.require_site_access` checks a Staff account's site list
  against a record's `location_id`.
- `routers/vlans.py`: the nested API the generic single-table CRUD can't do — a
  VLAN's subnets and a subnet's static ranges are multi-table writes.
  `GET /api/vlans/{id}/full` returns a VLAN with its subnets and each subnet's static
  ranges nested. IP fields go through `dbo.fn_IpToInt` inline in SQL, never
  reimplemented in Python; the DB triggers still do the actual overlap validation,
  this only turns their errors into a readable message.
- `routers/records.py`: was previously **unauthenticated** — now every verb checks
  `require_permission` and, for `hardware`/`vlans` (the tables that carry
  `location_id` directly), site scope too.
- `table_registry.py`: registered `applications` as a flat CRUD table.

### Done — frontend (`frontend/`, React + Vite + Tailwind + TanStack Query)

New, separate from the legacy frontend — `app.js`/`index.html` are untouched at `/`,
kept as reference/rollback per the earlier decision not to rewrite over them blind.
`npm run build` writes `frontend/dist`, which `app.py` mounts at `/app` automatically
once present.

Real and wired to the endpoints above:
- Login/session (cookie-based, `RequireAuth` redirects to `/login` on 401)
- **VlanEditor** + **SubnetRow**: Untagged toggle, add/remove Primary/Secondary
  subnets, per-subnet IP Assignment (Static/DHCP/Static+DHCP), multiple static
  ranges, explicit DHCP fields — the full nested shape from `04_network.sql`
- **ApplicationsTab** under Server detail — `server_type` shown read-only, derived
  from the server, never entered as its own field
- **Servers** list: Site as a table column + filter (not a separate switcher, per
  the UX decision), disabled lock icon on rows outside the logged-in user's scope
- **SiteSelect**: the mandatory site field on the VLAN editor form

Still stubs, not yet built (see `frontend/README.md`): Dashboard, Hardware/Software
Catalogue/Users & Roles list pages (copy `Servers.jsx` as the template), and the
"+ เพิ่มใหม่" create-new flows on both Servers and VLAN.

## Next steps, in likely order

1. **Wire up create-new flows** — VlanEditor and ApplicationsTab assume the parent
   record already exists; there's no "create a brand-new VLAN/Server" screen yet.
2. **Build the remaining list pages** (Hardware, Software Catalogue, Users & Roles,
   Network Devices) using `Servers.jsx` as the template — same Site column + filter
   pattern, same permission-checked API underneath.
3. **Dashboard** — warranty/MA-expiry watch, license compliance, the actual landing
   page after login (currently a placeholder route).
4. **Migrate existing localStorage data** into the new schema — noted as a separate,
   not-yet-written script in `db/README.md`.
5. Before any production run: re-hash the seeded admin password
   (`10_seed.sql` ships a bcrypt hash of the placeholder `ChangeMe$2026`, plaintext in
   version control by definition), and generate real `jwt_secret.key`/`secret.key`
   files per environment (both are gitignored, auto-created on first run).

## How to verify the DB side yourself

```bash
sqlcmd -S <server> -U <user> -P <password> -Q "CREATE DATABASE ISInventory"

for f in db/01_functions.sql db/02_core.sql db/03_assets.sql db/04_network.sql \
         db/05_software.sql db/06_access.sql db/07_temporal.sql db/08_indexes.sql \
         db/09_views.sql db/10_seed.sql db/11_applications.sql; do
  sqlcmd -S <server> -U <user> -P <password> -d ISInventory -b -I -i "$f" || break
done

sqlcmd -S <server> -U <user> -P <password> -d ISInventory -I -i db/tests/test_network.sql
sqlcmd -S <server> -U <user> -P <password> -d ISInventory -I -i db/tests/test_rbac_views.sql
```

Both test files print PASS/FAIL per check and clean up their own fixtures.
