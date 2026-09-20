# Handoff — IS-Inventory database v2

**Branch:** `claude/brave-edison-te5508`
**Latest commit:** `3896941` — "Redesign VLAN model for multi-subnet/untagged/split DHCP; add Applications"
**Status:** Database schema is done and tested. Frontend (`app.js`) is **not** updated yet — that's the next job.

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

### Not done — `app.js`

`app.js` is the existing localStorage-based frontend (~3,800 lines) and is **not wired
to this schema at all** (`routers/records.py` has its own comment saying the API isn't
hooked into `index.html` yet). It still assumes the old model:

- VLAN field is a required integer (no Untagged option)
- One VLAN = one subnet (no Primary/Secondary levels)
- One static range + auto-computed DHCP (`wireVlanDhcpCascade()`)
- No Applications page/section anywhere

This was deliberately left alone rather than rushed — it's a separate, sizeable
frontend task, not a schema task.

## Next steps, in likely order

1. **Decide the web stack** (this was in progress and got interrupted before the VLAN
   spreadsheet came in — see the abandoned Node.js/tedious/mssql/kysely connectivity
   test in `/tmp/claude-0/stacktest` from the prior session, now stale). `app.js` today
   is client-only localStorage with no real backend talking to SQL Server; that has to
   be settled before any of the UI work below can land for real.
2. **Rebuild the VLAN form** in `app.js` (or its replacement) to match the new schema:
   Untagged toggle vs. numeric tag, add/remove secondary subnets under one VLAN,
   multiple static ranges, explicit DHCP fields with the same overlap validation the
   DB triggers enforce.
3. **Build the Applications page**, filed under Server: Server Name (lookup), Server
   Type (read-only, derived), Application Name, Port Number, Link Application,
   Incharge, Department/Section — backed by `dbo.applications` /
   `v_server_applications`.
4. **Migrate existing localStorage data** into the new schema — noted as a separate,
   not-yet-written script in `db/README.md`.
5. Before any production run: re-hash the seeded admin password
   (`10_seed.sql` ships a bcrypt hash of the placeholder `ChangeMe$2026`, plaintext in
   version control by definition).

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
