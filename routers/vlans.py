"""Nested read/write for the VLAN model from db/04_network.sql.

routers/records.py's generic CRUD only ever touches ONE table by name, which
is enough for dbo.vlans itself (tag, name, zone, location_id — plain
columns) but not for what hangs off it: a VLAN carries N subnets
(Primary/Secondary — "VLAN Level" in the UI), and each subnet carries N
disjoint static ranges plus its own DHCP pool. Saving one of those is a
multi-table write, so it gets its own endpoints here rather than being
forced into the one-table-at-a-time shape.

IP address fields arrive from the browser as plain dotted strings; the
conversion to the BIGINT the database actually stores lives in
dbo.fn_IpToInt, called inline in the SQL below, so the "IP address is a
number" rule from 04_network.sql's design never gets re-implemented (and
never drifts) in Python.

Every write here still goes through the triggers in 04_network.sql
(trg_vlan_static_ranges_valid, trg_vlan_subnets_dhcp_no_overlap) — this
router does not re-validate range overlap itself, it just gives the
resulting pyodbc error a readable message instead of a raw SQL exception.
"""
from typing import Any, Dict, List, Optional

import pyodbc
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

import auth
import db
from config import load_config

router = APIRouter(prefix="/api/vlans")


def _require_config():
    cfg = load_config()
    if cfg is None:
        raise HTTPException(status_code=503, detail="Database not configured yet. Visit /setup.html.")
    return cfg


def _vlan_location(conn, vlan_id: str) -> str:
    cursor = conn.cursor()
    cursor.execute("SELECT location_id FROM dbo.vlans WHERE vlan_id_pk = ? AND is_deleted = 0", vlan_id)
    row = cursor.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="VLAN not found")
    return row[0]


def _subnet_vlan_and_location(conn, subnet_id: str):
    cursor = conn.cursor()
    cursor.execute(
        "SELECT s.vlan_id_pk, v.location_id FROM dbo.vlan_subnets s "
        "JOIN dbo.vlans v ON v.vlan_id_pk = s.vlan_id_pk "
        "WHERE s.subnet_id = ? AND s.is_deleted = 0",
        subnet_id,
    )
    row = cursor.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Subnet not found")
    return row[0], row[1]


def _friendly_integrity_error(exc: pyodbc.IntegrityError) -> str:
    text = str(exc)
    if "50002" in text:
        return "That range falls outside the usable range of its subnet."
    if "50003" in text:
        return "That static range overlaps this subnet's DHCP pool."
    if "50004" in text:
        return "Two static ranges on this subnet overlap."
    if "50005" in text:
        return "This subnet's DHCP pool overlaps one of its static ranges."
    if "UQ_subnets_one_primary" in text:
        return "This VLAN already has a Primary subnet — only one is allowed."
    return f"Rejected by the database: {text}"


class SubnetIn(BaseModel):
    level: str = "Primary"                 # 'Primary' | 'Secondary'
    network_address: str                   # e.g. '192.168.56.0'
    prefix_len: int
    gateway: Optional[str] = None
    ip_assignment: str = "Static"           # 'Static' | 'DHCP' | 'Static+DHCP'
    dhcp_server: Optional[str] = None
    dhcp_start: Optional[str] = None
    dhcp_end: Optional[str] = None
    remarks: Optional[str] = None


class StaticRangeIn(BaseModel):
    start_ip: str
    end_ip: str
    remarks: Optional[str] = None


@router.get("/{vlan_id}/full")
async def get_vlan_full(vlan_id: str, user: Dict[str, Any] = Depends(auth.require_permission("vlans", "view"))):
    cfg = _require_config()
    conn = db.get_connection(cfg)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM dbo.vlans WHERE vlan_id_pk = ? AND is_deleted = 0", vlan_id)
        vlan_row = cursor.fetchone()
        if vlan_row is None:
            raise HTTPException(status_code=404, detail="VLAN not found")
        columns = [c[0] for c in cursor.description]
        vlan = dict(zip(columns, vlan_row))

        cursor.execute(
            "SELECT * FROM dbo.vlan_subnets WHERE vlan_id_pk = ? AND is_deleted = 0 ORDER BY level, subnet_id",
            vlan_id,
        )
        sub_columns = [c[0] for c in cursor.description]
        subnets: List[Dict[str, Any]] = [dict(zip(sub_columns, row)) for row in cursor.fetchall()]

        for subnet in subnets:
            cursor.execute(
                "SELECT * FROM dbo.vlan_static_ranges WHERE subnet_id = ? ORDER BY seq_no",
                subnet["subnet_id"],
            )
            range_columns = [c[0] for c in cursor.description]
            subnet["static_ranges"] = [dict(zip(range_columns, row)) for row in cursor.fetchall()]

        vlan["subnets"] = subnets
        return vlan
    finally:
        conn.close()


@router.post("/{vlan_id}/subnets")
async def add_subnet(vlan_id: str, body: SubnetIn,
                      user: Dict[str, Any] = Depends(auth.require_permission("vlans", "edit"))):
    cfg = _require_config()
    conn = db.get_connection(cfg)
    try:
        auth.require_site_access(user, _vlan_location(conn, vlan_id))
        subnet_id = db.next_id(cfg, "SUB")
        conn.autocommit = True
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                INSERT INTO dbo.vlan_subnets
                    (subnet_id, vlan_id_pk, level, network_num, prefix_len, gateway_num,
                     ip_assignment, dhcp_server_num, dhcp_start_num, dhcp_end_num, remarks)
                VALUES
                    (?, ?, ?, dbo.fn_IpToInt(?), ?,
                     CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                     ?,
                     CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                     CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                     CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                     ?)
                """,
                subnet_id, vlan_id, body.level, body.network_address, body.prefix_len,
                body.gateway, body.gateway,
                body.ip_assignment,
                body.dhcp_server, body.dhcp_server,
                body.dhcp_start, body.dhcp_start,
                body.dhcp_end, body.dhcp_end,
                body.remarks,
            )
        except pyodbc.IntegrityError as exc:
            return JSONResponse({"ok": False, "error": _friendly_integrity_error(exc)}, status_code=409)
        cursor.execute("SELECT * FROM dbo.vlan_subnets WHERE subnet_id = ?", subnet_id)
        columns = [c[0] for c in cursor.description]
        return dict(zip(columns, cursor.fetchone()))
    finally:
        conn.close()


@router.put("/subnets/{subnet_id}")
async def update_subnet(subnet_id: str, body: SubnetIn,
                         user: Dict[str, Any] = Depends(auth.require_permission("vlans", "edit"))):
    cfg = _require_config()
    conn = db.get_connection(cfg)
    try:
        _, location_id = _subnet_vlan_and_location(conn, subnet_id)
        auth.require_site_access(user, location_id)
        conn.autocommit = True
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                UPDATE dbo.vlan_subnets SET
                    level = ?, network_num = dbo.fn_IpToInt(?), prefix_len = ?,
                    gateway_num = CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                    ip_assignment = ?,
                    dhcp_server_num = CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                    dhcp_start_num  = CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                    dhcp_end_num    = CASE WHEN ? IS NULL THEN NULL ELSE dbo.fn_IpToInt(?) END,
                    remarks = ?, updated_at = SYSUTCDATETIME()
                WHERE subnet_id = ?
                """,
                body.level, body.network_address, body.prefix_len,
                body.gateway, body.gateway,
                body.ip_assignment,
                body.dhcp_server, body.dhcp_server,
                body.dhcp_start, body.dhcp_start,
                body.dhcp_end, body.dhcp_end,
                body.remarks, subnet_id,
            )
        except pyodbc.IntegrityError as exc:
            return JSONResponse({"ok": False, "error": _friendly_integrity_error(exc)}, status_code=409)
        cursor.execute("SELECT * FROM dbo.vlan_subnets WHERE subnet_id = ?", subnet_id)
        columns = [c[0] for c in cursor.description]
        return dict(zip(columns, cursor.fetchone()))
    finally:
        conn.close()


@router.delete("/subnets/{subnet_id}")
async def delete_subnet(subnet_id: str, user: Dict[str, Any] = Depends(auth.require_permission("vlans", "delete"))):
    cfg = _require_config()
    conn = db.get_connection(cfg)
    try:
        _, location_id = _subnet_vlan_and_location(conn, subnet_id)
        auth.require_site_access(user, location_id)
        conn.autocommit = True
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE dbo.vlan_subnets SET is_deleted = 1, deleted_at = SYSUTCDATETIME(), deleted_by = ? "
            "WHERE subnet_id = ?",
            user["sub"], subnet_id,
        )
        return {"ok": True}
    finally:
        conn.close()


@router.post("/subnets/{subnet_id}/static-ranges")
async def add_static_range(subnet_id: str, body: StaticRangeIn,
                            user: Dict[str, Any] = Depends(auth.require_permission("vlans", "edit"))):
    cfg = _require_config()
    conn = db.get_connection(cfg)
    try:
        _, location_id = _subnet_vlan_and_location(conn, subnet_id)
        auth.require_site_access(user, location_id)
        range_id = db.next_id(cfg, "STR")
        conn.autocommit = True
        cursor = conn.cursor()
        cursor.execute("SELECT ISNULL(MAX(seq_no), 0) + 1 FROM dbo.vlan_static_ranges WHERE subnet_id = ?", subnet_id)
        seq_no = cursor.fetchone()[0]
        try:
            cursor.execute(
                "INSERT INTO dbo.vlan_static_ranges (range_id, subnet_id, seq_no, start_num, end_num, remarks) "
                "VALUES (?, ?, ?, dbo.fn_IpToInt(?), dbo.fn_IpToInt(?), ?)",
                range_id, subnet_id, seq_no, body.start_ip, body.end_ip, body.remarks,
            )
        except pyodbc.IntegrityError as exc:
            return JSONResponse({"ok": False, "error": _friendly_integrity_error(exc)}, status_code=409)
        cursor.execute("SELECT * FROM dbo.vlan_static_ranges WHERE range_id = ?", range_id)
        columns = [c[0] for c in cursor.description]
        return dict(zip(columns, cursor.fetchone()))
    finally:
        conn.close()


@router.delete("/static-ranges/{range_id}")
async def delete_static_range(range_id: str,
                               user: Dict[str, Any] = Depends(auth.require_permission("vlans", "delete"))):
    cfg = _require_config()
    conn = db.get_connection(cfg)
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT r.subnet_id, v.location_id FROM dbo.vlan_static_ranges r "
            "JOIN dbo.vlan_subnets s ON s.subnet_id = r.subnet_id "
            "JOIN dbo.vlans v ON v.vlan_id_pk = s.vlan_id_pk "
            "WHERE r.range_id = ?",
            range_id,
        )
        row = cursor.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Static range not found")
        auth.require_site_access(user, row[1])
        conn.autocommit = True
        cursor.execute("DELETE FROM dbo.vlan_static_ranges WHERE range_id = ?", range_id)
        return {"ok": True}
    finally:
        conn.close()
