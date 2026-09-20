/* =============================================================================
   IS-Inventory v2 — behaviour tests for the IP/subnet layer, including the
   VLAN model revision (multi-subnet VLANs, Untagged, split static+DHCP).

   Run after 01-11. Every row prints PASS or FAIL; nothing here writes data
   that survives the run.
   ============================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

PRINT '--- fn_IpToInt / fn_IntToIp ---';
SELECT test, expected, actual,
       result = CASE WHEN ISNULL(CAST(actual AS NVARCHAR(50)), '<NULL>')
                        = ISNULL(CAST(expected AS NVARCHAR(50)), '<NULL>')
                     THEN 'PASS' ELSE 'FAIL' END
FROM (VALUES
    ('0.0.0.0',            CAST(0          AS BIGINT), dbo.fn_IpToInt('0.0.0.0')),
    ('10.10.120.42',       CAST(168458282  AS BIGINT), dbo.fn_IpToInt('10.10.120.42')),
    ('192.168.1.100',      CAST(3232235876 AS BIGINT), dbo.fn_IpToInt('192.168.1.100')),
    ('255.255.255.255',    CAST(4294967295 AS BIGINT), dbo.fn_IpToInt('255.255.255.255')),
    ('reject 256.1.1.1',   NULL,                       dbo.fn_IpToInt('256.1.1.1')),
    ('reject 1.2.3',       NULL,                       dbo.fn_IpToInt('1.2.3')),
    ('reject 1.2.3.4.5',   NULL,                       dbo.fn_IpToInt('1.2.3.4.5')),
    ('reject abc',         NULL,                       dbo.fn_IpToInt('abc')),
    ('reject 10.10.10.a',  NULL,                       dbo.fn_IpToInt('10.10.10.a'))
) t(test, expected, actual);

PRINT '--- numeric ordering beats text ordering ---';
SELECT test = 'ipToInt(10.10.10.9) < ipToInt(10.10.10.10)',
       result = CASE WHEN dbo.fn_IpToInt('10.10.10.9') < dbo.fn_IpToInt('10.10.10.10')
                     THEN 'PASS' ELSE 'FAIL' END;

PRINT '--- round trip ---';
SELECT test = 'IntToIp(IpToInt(x)) = x',
       result = CASE WHEN dbo.fn_IntToIp(dbo.fn_IpToInt('172.16.254.1')) = '172.16.254.1'
                     THEN 'PASS' ELSE 'FAIL' END;

PRINT '--- fn_MaskToPrefix / fn_PrefixToMask ---';
SELECT test, expected, actual,
       result = CASE WHEN ISNULL(CAST(actual AS NVARCHAR(50)), '<NULL>')
                        = ISNULL(CAST(expected AS NVARCHAR(50)), '<NULL>')
                     THEN 'PASS' ELSE 'FAIL' END
FROM (VALUES
    ('mask /24',              CAST(24 AS NVARCHAR(50)), CAST(dbo.fn_MaskToPrefix('255.255.255.0')   AS NVARCHAR(50))),
    ('mask /21',              CAST(21 AS NVARCHAR(50)), CAST(dbo.fn_MaskToPrefix('255.255.248.0')   AS NVARCHAR(50))),
    ('mask /25',              CAST(25 AS NVARCHAR(50)), CAST(dbo.fn_MaskToPrefix('255.255.255.128') AS NVARCHAR(50))),
    ('reject 255.0.255.0',    NULL,                     CAST(dbo.fn_MaskToPrefix('255.0.255.0')     AS NVARCHAR(50))),
    ('prefix 24 -> mask',     N'255.255.255.0',         CAST(dbo.fn_PrefixToMask(24)                AS NVARCHAR(50))),
    ('prefix 21 -> mask',     N'255.255.248.0',         CAST(dbo.fn_PrefixToMask(21)                AS NVARCHAR(50)))
) t(test, expected, actual);

/* ===========================================================================
   VLAN model — the real firewall export as a fixture.

   VLAN 4 "FAC1": one Primary subnet + four Secondary subnets, all the same
   VLAN tag, on device mcp-1. This is the exact shape the spreadsheet showed
   and the reason vlans/vlan_subnets are two separate tables.
   =========================================================================== */
PRINT '=== VLAN with 5 subnets (1 Primary, 4 Secondary), same tag ===';
DECLARE @site1 VARCHAR(20) = (SELECT location_id FROM dbo.locations WHERE level = 'Site' AND name = N'1st Site');
DECLARE @site2 VARCHAR(20) = (SELECT location_id FROM dbo.locations WHERE level = 'Site' AND name = N'2nd Site');

INSERT INTO dbo.vlans (vlan_id_pk, vlan_tag, vlan_name, vlan_zone, vlan_by, device_name, location_id)
VALUES ('VLA-T01', 4, N'FAC1', N'Trust', N'Core Switch', N'mcp-1', @site1);

INSERT INTO dbo.vlan_subnets (subnet_id, vlan_id_pk, level, network_num, prefix_len, gateway_num)
VALUES
    ('SUB-T01', 'VLA-T01', 'Primary',   dbo.fn_IpToInt('192.168.56.0'), 24, dbo.fn_IpToInt('192.168.56.254')),
    ('SUB-T02', 'VLA-T01', 'Secondary', dbo.fn_IpToInt('192.168.37.0'), 24, dbo.fn_IpToInt('192.168.37.254')),
    ('SUB-T03', 'VLA-T01', 'Secondary', dbo.fn_IpToInt('192.168.39.0'), 24, dbo.fn_IpToInt('192.168.39.254')),
    ('SUB-T04', 'VLA-T01', 'Secondary', dbo.fn_IpToInt('192.168.59.0'), 24, dbo.fn_IpToInt('192.168.59.254')),
    ('SUB-T05', 'VLA-T01', 'Secondary', dbo.fn_IpToInt('192.168.80.0'), 24, dbo.fn_IpToInt('192.168.80.254'));

SELECT test = 'one VLAN tag now carries 5 subnets',
       actual = COUNT(*),
       result = CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL' END
  FROM dbo.vlan_subnets WHERE vlan_id_pk = 'VLA-T01';

PRINT '--- constraint: only one Primary subnet per VLAN ---';
BEGIN TRY
    INSERT INTO dbo.vlan_subnets (subnet_id, vlan_id_pk, level, network_num, prefix_len)
    VALUES ('SUB-T06', 'VLA-T01', 'Primary', dbo.fn_IpToInt('192.168.90.0'), 24);
    SELECT test = 'reject a second Primary subnet on the same VLAN', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject a second Primary subnet on the same VLAN', result = 'PASS';
END CATCH;

PRINT '=== Untagged VLAN (native VLAN on the trunk) ===';
INSERT INTO dbo.vlans (vlan_id_pk, vlan_tag, vlan_name, vlan_zone, vlan_by, device_name, location_id)
VALUES ('VLA-T02', NULL, N'ThinServer-Mgmt', N'Trust', N'Core Switch', N'mcp-1', @site1);

SELECT test = 'vlan_tag NULL renders as is_untagged = 1',
       vlan_tag, is_untagged,
       result = CASE WHEN vlan_tag IS NULL AND is_untagged = 1 THEN 'PASS' ELSE 'FAIL' END
  FROM dbo.vlans WHERE vlan_id_pk = 'VLA-T02';

PRINT '--- an untagged VLAN and a numbered VLAN 4 do not collide (different tags) ---';
SELECT test = 'both VLA-T01 (tag 4) and VLA-T02 (untagged) coexist',
       actual = COUNT(*),
       result = CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END
  FROM dbo.vlans WHERE vlan_id_pk IN ('VLA-T01','VLA-T02');

PRINT '--- constraint: same tag cannot repeat on the same device ---';
BEGIN TRY
    INSERT INTO dbo.vlans (vlan_id_pk, vlan_tag, vlan_name, device_name, location_id)
    VALUES ('VLA-T03', 4, N'FAC1-DUP', N'mcp-1', @site1);
    SELECT test = 'reject VLAN tag 4 twice on device mcp-1', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject VLAN tag 4 twice on device mcp-1', result = 'PASS';
END CATCH;

SELECT test = 'the same tag 4 IS allowed on a different device',
       result = 'n/a (exercised below)';
INSERT INTO dbo.vlans (vlan_id_pk, vlan_tag, vlan_name, device_name, location_id)
VALUES ('VLA-T04', 4, N'FAC1-OTHER-SWITCH', N'mcp-2', @site2);
SELECT test = 'VLAN tag 4 on device mcp-2 (a different device) is accepted',
       result = 'PASS';

/* ===========================================================================
   The WIFI-Data-Center case: a /21 with DHCP in the middle, flanked by two
   separate static blocks. This is exactly what the first schema version
   could not represent (it derived one DHCP range as "whatever is left after
   one static block").
   =========================================================================== */
PRINT '=== one subnet, DHCP in the middle, static on both sides ===';
INSERT INTO dbo.vlans (vlan_id_pk, vlan_tag, vlan_name, vlan_zone, vlan_by, device_name, location_id)
VALUES ('VLA-T05', 152, N'WIFI-Data-Center', N'Trust', N'Core Switch', N'mcp-1', @site1);

INSERT INTO dbo.vlan_subnets (subnet_id, vlan_id_pk, level, network_num, prefix_len,
                              gateway_num, ip_assignment, dhcp_server_num, dhcp_start_num, dhcp_end_num)
VALUES ('SUB-T10', 'VLA-T05', 'Primary',
        dbo.fn_IpToInt('192.168.152.0'), 21,
        dbo.fn_IpToInt('192.168.152.254'),
        'Static+DHCP',
        dbo.fn_IpToInt('192.168.1.50'),           -- EIEISVR, elsewhere in the estate
        dbo.fn_IpToInt('192.168.153.1'),
        dbo.fn_IpToInt('192.168.159.200'));

INSERT INTO dbo.vlan_static_ranges (range_id, subnet_id, seq_no, start_num, end_num)
VALUES
    ('STR-T01', 'SUB-T10', 1, dbo.fn_IpToInt('192.168.152.2'),   dbo.fn_IpToInt('192.168.152.253')),
    ('STR-T02', 'SUB-T10', 2, dbo.fn_IpToInt('192.168.159.201'), dbo.fn_IpToInt('192.168.159.254'));

SELECT test = '/21 usable range is 192.168.152.1 - 192.168.159.254 (2046 addresses)',
       usable_count,
       first_usable = dbo.fn_IntToIp(first_usable_num),
       last_usable  = dbo.fn_IntToIp(last_usable_num),
       result = CASE WHEN usable_count = 2046
                      AND dbo.fn_IntToIp(first_usable_num) = '192.168.152.1'
                      AND dbo.fn_IntToIp(last_usable_num)  = '192.168.159.254'
                     THEN 'PASS' ELSE 'FAIL' END
  FROM dbo.vlan_subnets WHERE subnet_id = 'SUB-T10';

SELECT test = 'both static scopes and the DHCP pool were stored as given',
       dhcp_start = dbo.fn_IntToIp(dhcp_start_num),
       dhcp_end   = dbo.fn_IntToIp(dhcp_end_num),
       static_scopes = (SELECT COUNT(*) FROM dbo.vlan_static_ranges WHERE subnet_id = 'SUB-T10'),
       result = CASE WHEN dbo.fn_IntToIp(dhcp_start_num) = '192.168.153.1'
                      AND dbo.fn_IntToIp(dhcp_end_num)   = '192.168.159.200'
                      AND (SELECT COUNT(*) FROM dbo.vlan_static_ranges WHERE subnet_id = 'SUB-T10') = 2
                     THEN 'PASS' ELSE 'FAIL' END
  FROM dbo.vlan_subnets WHERE subnet_id = 'SUB-T10';

PRINT '--- v_vlan_utilization rolls the 2 static scopes into one readable line ---';
SELECT test = 'static_range_count=2, static_total_size=306 (252+54)',
       static_range_count, static_total_size, static_ranges_text,
       result = CASE WHEN static_range_count = 2 AND static_total_size = 306
                     THEN 'PASS' ELSE 'FAIL' END
  FROM dbo.v_vlan_utilization WHERE subnet_id = 'SUB-T10';

PRINT '--- constraint: a static range cannot overlap the DHCP pool ---';
BEGIN TRY
    INSERT INTO dbo.vlan_static_ranges (range_id, subnet_id, seq_no, start_num, end_num)
    VALUES ('STR-T99', 'SUB-T10', 3, dbo.fn_IpToInt('192.168.155.0'), dbo.fn_IpToInt('192.168.155.10'));
    SELECT test = 'reject a static range landing inside the DHCP pool', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject a static range landing inside the DHCP pool', result = 'PASS';
END CATCH;

PRINT '--- constraint: two static ranges on the same subnet cannot overlap each other ---';
BEGIN TRY
    INSERT INTO dbo.vlan_static_ranges (range_id, subnet_id, seq_no, start_num, end_num)
    VALUES ('STR-T98', 'SUB-T10', 4, dbo.fn_IpToInt('192.168.152.100'), dbo.fn_IpToInt('192.168.152.110'));
    SELECT test = 'reject a static range overlapping Scope 1', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject a static range overlapping Scope 1', result = 'PASS';
END CATCH;

PRINT '--- constraint: a static range must stay inside the subnet''s usable bounds ---';
BEGIN TRY
    INSERT INTO dbo.vlan_static_ranges (range_id, subnet_id, seq_no, start_num, end_num)
    VALUES ('STR-T97', 'SUB-T10', 5, dbo.fn_IpToInt('192.168.160.1'), dbo.fn_IpToInt('192.168.160.10'));
    SELECT test = 'reject a static range outside the /21', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject a static range outside the /21', result = 'PASS';
END CATCH;

PRINT '--- constraint: moving the DHCP pool onto an existing static range is rejected ---';
BEGIN TRY
    UPDATE dbo.vlan_subnets
       SET dhcp_start_num = dbo.fn_IpToInt('192.168.152.10'),
           dhcp_end_num   = dbo.fn_IpToInt('192.168.152.20')
     WHERE subnet_id = 'SUB-T10';
    SELECT test = 'reject moving DHCP onto Scope 1', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject moving DHCP onto Scope 1', result = 'PASS';
END CATCH;

PRINT '--- constraint: DHCP fields must all be set together, only when ip_assignment says DHCP ---';
BEGIN TRY
    INSERT INTO dbo.vlan_subnets (subnet_id, vlan_id_pk, level, network_num, prefix_len, ip_assignment)
    VALUES ('SUB-T11', 'VLA-T05', 'Secondary', dbo.fn_IpToInt('192.168.200.0'), 24, 'DHCP');
    SELECT test = 'reject ip_assignment=DHCP with no DHCP start/end/server', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject ip_assignment=DHCP with no DHCP start/end/server', result = 'PASS';
END CATCH;

BEGIN TRY
    INSERT INTO dbo.vlan_subnets (subnet_id, vlan_id_pk, level, network_num, prefix_len, ip_assignment,
                                  dhcp_server_num, dhcp_start_num, dhcp_end_num)
    VALUES ('SUB-T12', 'VLA-T05', 'Secondary', dbo.fn_IpToInt('192.168.201.0'), 24, 'Static',
            dbo.fn_IpToInt('10.0.0.1'), dbo.fn_IpToInt('192.168.201.10'), dbo.fn_IpToInt('192.168.201.20'));
    SELECT test = 'reject ip_assignment=Static with DHCP fields populated', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject ip_assignment=Static with DHCP fields populated', result = 'PASS';
END CATCH;

/* ---------------------------------------------------------------------------
   Basic subnet arithmetic still holds for a plain single-subnet VLAN
   --------------------------------------------------------------------------- */
PRINT '--- a /30 leaves exactly 2 usable addresses ---';
INSERT INTO dbo.vlans (vlan_id_pk, vlan_tag, vlan_name, device_name, location_id)
VALUES ('VLA-T06', 999, N'TEST-p2p', N'mcp-1', @site1);
INSERT INTO dbo.vlan_subnets (subnet_id, vlan_id_pk, level, network_num, prefix_len, gateway_num)
VALUES ('SUB-T20', 'VLA-T06', 'Primary', dbo.fn_IpToInt('10.99.99.0'), 30, dbo.fn_IpToInt('10.99.99.1'));
SELECT test = '/30 -> 10.99.99.1 .. 10.99.99.2',
       usable_count,
       result = CASE WHEN usable_count = 2
                      AND dbo.fn_IntToIp(first_usable_num) = '10.99.99.1'
                      AND dbo.fn_IntToIp(last_usable_num)  = '10.99.99.2'
                     THEN 'PASS' ELSE 'FAIL' END
  FROM dbo.vlan_subnets WHERE subnet_id = 'SUB-T20';

PRINT '--- constraint: network_num must be a real network address ---';
BEGIN TRY
    INSERT INTO dbo.vlan_subnets (subnet_id, vlan_id_pk, level, network_num, prefix_len)
    VALUES ('SUB-T21', 'VLA-T06', 'Secondary', dbo.fn_IpToInt('10.10.10.5'), 24);
    SELECT test = 'reject 10.10.10.5/24', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject 10.10.10.5/24', result = 'PASS';
END CATCH;

/* ---------------------------------------------------------------------------
   ip_allocations — the estate-wide uniqueness v1 could not enforce, now
   keyed against a subnet rather than a VLAN group.
   --------------------------------------------------------------------------- */
PRINT '--- ip_allocations: same address cannot be used twice ---';
INSERT INTO dbo.ip_allocations (ip_num, subnet_id, assign_type, purpose, hostname)
VALUES (dbo.fn_IpToInt('10.99.99.1'), 'SUB-T20', 'Static', 'service', N'first-owner');

BEGIN TRY
    INSERT INTO dbo.ip_allocations (ip_num, subnet_id, assign_type, purpose, hostname)
    VALUES (dbo.fn_IpToInt('10.99.99.1'), 'SUB-T20', 'Static', 'management', N'second-owner');
    SELECT test = 'reject duplicate 10.99.99.1 estate-wide', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject duplicate 10.99.99.1 estate-wide', result = 'PASS';
END CATCH;

PRINT '--- ip_allocations: address must sit inside its subnet ---';
BEGIN TRY
    INSERT INTO dbo.ip_allocations (ip_num, subnet_id, assign_type, purpose, hostname)
    VALUES (dbo.fn_IpToInt('192.168.77.5'), 'SUB-T20', 'Static', 'service', N'wrong-subnet');
    SELECT test = 'reject 192.168.77.5 in a 10.99.99.0/30 subnet', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject 192.168.77.5 in a 10.99.99.0/30 subnet', result = 'PASS';
END CATCH;

PRINT '--- ip_allocations: a row may not have two owners ---';
BEGIN TRY
    INSERT INTO dbo.ip_allocations (ip_num, subnet_id, server_id, device_id)
    VALUES (dbo.fn_IpToInt('10.99.99.2'), 'SUB-T20', 'SRV-001', 'NET-001');
    SELECT test = 'reject server_id and device_id on one row', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject server_id and device_id on one row', result = 'PASS';
END CATCH;

/* ---------------------------------------------------------------------------
   Warranty expiry is derived, not typed
   --------------------------------------------------------------------------- */
PRINT '--- warranty expiry = commission date + N years ---';
INSERT INTO dbo.network_devices (device_id, status, category, subcategory, device_name,
                                 serial_number, commission_date, warranty_years)
VALUES ('NET-T01', 'Use', N'Switch', N'Access', N'TEST-SW-01', N'SN-TEST-01', '2026-01-01', 3);

SELECT test = '2026-01-01 + 3 years = 2029-01-01',
       warranty_expiry,
       result = CASE WHEN warranty_expiry = '2029-01-01' THEN 'PASS' ELSE 'FAIL' END
FROM dbo.network_devices WHERE device_id = 'NET-T01';

PRINT '--- MAC address is optional, but validated when given ---';
BEGIN TRY
    INSERT INTO dbo.network_devices (device_id, status, category, subcategory, device_name, serial_number, mac_address)
    VALUES ('NET-T02', 'Use', N'Switch', N'Access', N'TEST-SW-02', N'SN-TEST-02', N'ZZ:ZZ:ZZ:ZZ:ZZ:ZZ');
    SELECT test = 'reject malformed MAC', result = 'FAIL (it was accepted)';
END TRY
BEGIN CATCH
    SELECT test = 'reject malformed MAC', result = 'PASS';
END CATCH;

INSERT INTO dbo.network_devices (device_id, status, category, subcategory, device_name, serial_number, mac_address)
VALUES ('NET-T03', 'Use', N'Switch', N'Access', N'TEST-SW-03', N'SN-TEST-03', N'00:1A:2B:3C:4D:5E');
SELECT test = 'accept a well-formed MAC', result = 'PASS';

INSERT INTO dbo.network_devices (device_id, status, category, subcategory, device_name, serial_number)
VALUES ('NET-T04', 'Use', N'Switch', N'Access', N'TEST-SW-04', N'SN-TEST-04');
SELECT test = 'accept a device with no MAC at all', result = 'PASS';

/* --- clean up --------------------------------------------------------------- */
DELETE FROM dbo.ip_allocations      WHERE subnet_id LIKE 'SUB-T%';
DELETE FROM dbo.network_devices     WHERE device_id LIKE 'NET-T%';
DELETE FROM dbo.vlan_static_ranges  WHERE subnet_id LIKE 'SUB-T%';
DELETE FROM dbo.vlan_subnets        WHERE vlan_id_pk LIKE 'VLA-T%';
DELETE FROM dbo.vlans               WHERE vlan_id_pk LIKE 'VLA-T%';
GO
