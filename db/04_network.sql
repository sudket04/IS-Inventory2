/* =============================================================================
   IS-Inventory v2 — 04: Network and IP address management

   v1 scattered IP addresses across four tables as NVARCHAR(45):
   servers.ip_address, servers.ip_management, cluster_nodes.ip_host,
   cluster_nodes.ip_management, network_devices.ip_management, plus
   vlans.gateway and vlans.dhcp_server. Only two of those were UNIQUE, and
   only within their own table — so 10.10.120.50 could be a server's address
   and a switch's management address at the same time and nothing complained.

   Here every address in the estate is one row in dbo.ip_allocations with a
   UNIQUE constraint across the whole system. The owning tables no longer
   carry IP columns at all; 09_views.sql exposes each asset's primary address
   so day-to-day queries stay short.

   Addresses are BIGINT (see 01_functions.sql). That is what lets
   "everything in 10.10.120.0/24" be a range scan, and what lets a DHCP
   pool's boundaries be validated by the database instead of trusted from
   the browser.

   ---------------------------------------------------------------------------
   VLAN model — revised after reviewing the site's real firewall/switch
   config export. Three things the first pass got wrong:

   1. One VLAN tag can carry SEVERAL subnets (secondary addressing on the
      same SVI) — the export shows VLAN 4 "FAC1" with five different /24s,
      one marked Primary and four Secondary. A VLAN and a subnet are not the
      same thing, so they are two tables now: dbo.vlans (the tag/identity)
      and dbo.vlan_subnets (one row per IP range hung off it, Level
      Primary/Secondary is a column on the subnet, not the VLAN).

   2. A VLAN tag is not always a number. The native VLAN on an 802.1Q trunk
      carries no tag at all — the export's "ThinServer" row literally reads
      "Untagged" in the VLAN column. vlan_tag is nullable; NULL means
      untagged, not "not entered yet".

   3. Static and DHCP are not mutually exclusive, and static is not always
      one contiguous block. The export's WIFI-Data-Center subnet (a /21) has
      a DHCP pool sitting in the *middle* of the usable range, flanked by two
      separate static blocks — one below it, one above. The first version of
      this schema derived a single DHCP range as "whatever is left after one
      static block", which cannot represent that. DHCP start/end are now
      explicit columns (validated against the subnet, not computed from it),
      and static ranges live in their own child table, dbo.vlan_static_ranges,
      so a subnet can carry as many disjoint static blocks as the network
      actually has.
   ============================================================================= */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   VLANs — the tag/identity, not the IP range
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.vlans', 'U') IS NULL
CREATE TABLE dbo.vlans (
    vlan_id_pk   VARCHAR(20)   NOT NULL CONSTRAINT PK_vlans PRIMARY KEY,   -- VLA-001

    /* NULL = untagged (the trunk's native VLAN), not "not entered". */
    vlan_tag     INT           NULL
                 CONSTRAINT CK_vlans_tag CHECK (vlan_tag BETWEEN 1 AND 4094),
    is_untagged  AS (CASE WHEN vlan_tag IS NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END) PERSISTED,

    vlan_name    NVARCHAR(80)  NOT NULL,
    vlan_status  VARCHAR(10)   NOT NULL DEFAULT 'Active'
                 CONSTRAINT CK_vlans_status CHECK (vlan_status IN ('Active','Inactive')),
    vlan_zone    NVARCHAR(30)  NULL,    -- Trust/Untrust/DMZ — the firewall zone it rides on
    vlan_by      NVARCHAR(60)  NULL,    -- what created/owns it, e.g. "Core Switch"
    device_name  NVARCHAR(80)  NULL,    -- the actual device hostname, e.g. "mcp-1"
    /* NOT NULL: a VLAN must be filed under a site, same as hardware — the
       UI's site selector is a required field on every data-entry form. */
    location_id  VARCHAR(20)   NOT NULL
                 CONSTRAINT FK_vlans_location REFERENCES dbo.locations(location_id),
    routing      NVARCHAR(120) NULL,
    remarks      NVARCHAR(400) NULL,

    is_deleted   BIT           NOT NULL DEFAULT 0,
    deleted_at   DATETIME2(0)  NULL,
    deleted_by   VARCHAR(20)   NULL CONSTRAINT FK_vlans_deletedby REFERENCES dbo.app_users(user_id),
    created_at   DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by   VARCHAR(20)   NULL CONSTRAINT FK_vlans_createdby REFERENCES dbo.app_users(user_id),
    updated_at   DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_by   VARCHAR(20)   NULL CONSTRAINT FK_vlans_updatedby REFERENCES dbo.app_users(user_id)
);
GO

/* A tag only has to be unique on the device that carries it — the same
   number 4 can legitimately exist on two different firewalls/sites. There
   is no uniqueness requirement for untagged rows: SQL Server's unique index
   would only ever allow ONE NULL anyway, and a filtered WHERE vlan_tag IS
   NOT NULL sidesteps that entirely rather than fighting it. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_vlans_tag_device' AND object_id = OBJECT_ID('dbo.vlans'))
CREATE UNIQUE INDEX UQ_vlans_tag_device ON dbo.vlans(vlan_tag, device_name) WHERE vlan_tag IS NOT NULL AND is_deleted = 0;
GO

/* ---------------------------------------------------------------------------
   VLAN subnets — one row per IP range hung off a VLAN. "VLAN Level" in the
   UI (Primary/Secondary) is the `level` column here.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.vlan_subnets', 'U') IS NULL
CREATE TABLE dbo.vlan_subnets (
    subnet_id        VARCHAR(20)   NOT NULL CONSTRAINT PK_vlan_subnets PRIMARY KEY,   -- SUB-001
    vlan_id_pk       VARCHAR(20)   NOT NULL
                     CONSTRAINT FK_subnets_vlan REFERENCES dbo.vlans(vlan_id_pk) ON DELETE CASCADE,
    level            VARCHAR(10)   NOT NULL DEFAULT 'Primary'
                     CONSTRAINT CK_subnets_level CHECK (level IN ('Primary','Secondary')),

    network_num      BIGINT        NOT NULL,
    prefix_len       TINYINT       NOT NULL
                     CONSTRAINT CK_subnets_prefix CHECK (prefix_len BETWEEN 8 AND 32),

    network_address  AS (dbo.fn_IntToIp(network_num))        PERSISTED,
    subnet_mask      AS (dbo.fn_PrefixToMask(prefix_len))    PERSISTED,
    broadcast_num    AS (dbo.fn_Broadcast(network_num, prefix_len))   PERSISTED,
    first_usable_num AS (dbo.fn_FirstUsable(network_num, prefix_len)) PERSISTED,
    last_usable_num  AS (dbo.fn_LastUsable(network_num, prefix_len))  PERSISTED,
    usable_count     AS (dbo.fn_LastUsable(network_num, prefix_len)
                       - dbo.fn_FirstUsable(network_num, prefix_len) + 1) PERSISTED,

    /* network_num must actually be the network address for this prefix —
       10.10.10.5/24 is a typo, not a subnet. */
    CONSTRAINT CK_subnets_is_network_address CHECK (
        network_num = network_num & (CAST(4294967295 AS BIGINT) - (LEFT_SHIFT(CAST(1 AS BIGINT), 32 - prefix_len) - 1))
    ),

    gateway_num      BIGINT        NULL,

    /* A subnet can hand out addresses by static assignment, DHCP, or both at
       once (the WIFI-Data-Center /21: static below and above a DHCP pool in
       the middle). This flag says which apply; the actual ranges live in
       vlan_static_ranges (0..N rows) and the two dhcp_* columns below. */
    ip_assignment    VARCHAR(12)   NOT NULL DEFAULT 'Static'
                     CONSTRAINT CK_subnets_assignment CHECK (ip_assignment IN ('Static','DHCP','Static+DHCP')),

    dhcp_server_num  BIGINT        NULL,
    dhcp_start_num   BIGINT        NULL,
    dhcp_end_num     BIGINT        NULL,

    /* DHCP fields are explicit, not derived — a pool can sit anywhere in the
       range, not only "after the last static block". They still have to be
       real addresses inside this subnet's usable range. */
    CONSTRAINT CK_subnets_dhcp_shape CHECK (
        (ip_assignment NOT LIKE '%DHCP%' AND dhcp_server_num IS NULL AND dhcp_start_num IS NULL AND dhcp_end_num IS NULL)
     OR (ip_assignment LIKE '%DHCP%' AND dhcp_server_num IS NOT NULL
         AND dhcp_start_num IS NOT NULL AND dhcp_end_num IS NOT NULL AND dhcp_end_num >= dhcp_start_num)
    ),
    CONSTRAINT CK_subnets_dhcp_in_range CHECK (
        dhcp_start_num IS NULL
        OR (dhcp_start_num >= first_usable_num AND dhcp_end_num <= last_usable_num)
    ),

    remarks          NVARCHAR(400) NULL,

    is_deleted       BIT           NOT NULL DEFAULT 0,
    deleted_at       DATETIME2(0)  NULL,
    deleted_by       VARCHAR(20)   NULL CONSTRAINT FK_subnets_deletedby REFERENCES dbo.app_users(user_id),
    created_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by       VARCHAR(20)   NULL CONSTRAINT FK_subnets_createdby REFERENCES dbo.app_users(user_id),
    updated_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_by       VARCHAR(20)   NULL CONSTRAINT FK_subnets_updatedby REFERENCES dbo.app_users(user_id)
);
GO

/* At most one Primary subnet per VLAN — Secondary can repeat freely. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_subnets_one_primary' AND object_id = OBJECT_ID('dbo.vlan_subnets'))
CREATE UNIQUE INDEX UQ_subnets_one_primary ON dbo.vlan_subnets(vlan_id_pk) WHERE level = 'Primary' AND is_deleted = 0;
GO
/* No two live subnets anywhere describe the same network, whatever VLAN
   they are attached to. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_subnets_network' AND object_id = OBJECT_ID('dbo.vlan_subnets'))
CREATE UNIQUE INDEX UQ_subnets_network ON dbo.vlan_subnets(network_num, prefix_len) WHERE is_deleted = 0;
GO

/* ---------------------------------------------------------------------------
   Static IP ranges — 0..N per subnet, e.g. one below and one above a
   DHCP pool. A CHECK constraint cannot compare rows against each other or
   against a different table, so the "stay inside the subnet, never overlap
   the DHCP pool or another static range" rules are enforced by the trigger
   further down, once both this table and vlan_subnets exist.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.vlan_static_ranges', 'U') IS NULL
CREATE TABLE dbo.vlan_static_ranges (
    range_id    VARCHAR(20)  NOT NULL CONSTRAINT PK_vlan_static_ranges PRIMARY KEY,  -- STR-001
    subnet_id   VARCHAR(20)  NOT NULL
                CONSTRAINT FK_staticrange_subnet REFERENCES dbo.vlan_subnets(subnet_id) ON DELETE CASCADE,
    seq_no      INT          NOT NULL DEFAULT 1,   -- display order: Scope 1, Scope 2, ...
    start_num   BIGINT       NOT NULL,
    end_num     BIGINT       NOT NULL,
    remarks     NVARCHAR(200) NULL,
    created_at  DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_staticrange_seq UNIQUE (subnet_id, seq_no),
    CONSTRAINT CK_staticrange_order CHECK (end_num >= start_num)
);
GO

/* Every static range must sit inside its subnet's usable bounds, and must
   not overlap the subnet's DHCP pool or any other static range on the same
   subnet. Two disjoint interval-overlap checks, done set-based so a
   multi-row insert/update stays one statement. */
CREATE OR ALTER TRIGGER dbo.trg_vlan_static_ranges_valid
ON dbo.vlan_static_ranges
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
          FROM inserted i
          JOIN dbo.vlan_subnets s ON s.subnet_id = i.subnet_id
         WHERE i.start_num < s.first_usable_num OR i.end_num > s.last_usable_num
    )
        THROW 50002, 'A static range must fall inside the usable range of its subnet.', 1;

    IF EXISTS (
        SELECT 1
          FROM inserted i
          JOIN dbo.vlan_subnets s ON s.subnet_id = i.subnet_id
         WHERE s.dhcp_start_num IS NOT NULL
           AND i.start_num <= s.dhcp_end_num AND i.end_num >= s.dhcp_start_num
    )
        THROW 50003, 'A static range overlaps this subnet''s DHCP pool.', 1;

    IF EXISTS (
        SELECT 1
          FROM inserted i
          JOIN dbo.vlan_static_ranges other
            ON other.subnet_id = i.subnet_id
           AND other.range_id <> i.range_id
           AND i.start_num <= other.end_num AND i.end_num >= other.start_num
    )
        THROW 50004, 'Two static ranges on the same subnet overlap.', 1;
END;
GO

/* The mirror check, from the subnet side: setting/changing a DHCP pool must
   not land it on top of an existing static range. */
CREATE OR ALTER TRIGGER dbo.trg_vlan_subnets_dhcp_no_overlap
ON dbo.vlan_subnets
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
          FROM inserted i
          JOIN dbo.vlan_static_ranges r ON r.subnet_id = i.subnet_id
         WHERE i.dhcp_start_num IS NOT NULL
           AND i.dhcp_start_num <= r.end_num AND i.dhcp_end_num >= r.start_num
    )
        THROW 50005, 'This subnet''s DHCP pool overlaps one of its static ranges.', 1;
END;
GO

GO

/* ---------------------------------------------------------------------------
   Network devices — switches, routers, firewalls, APs
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.network_devices', 'U') IS NULL
CREATE TABLE dbo.network_devices (
    device_id       VARCHAR(20)   NOT NULL CONSTRAINT PK_network_devices PRIMARY KEY,  -- NET-001
    status          VARCHAR(20)   NOT NULL
                    CONSTRAINT CK_netdev_status CHECK (status IN ('Use','Standby','Decommissioned')),
    category        NVARCHAR(60)  NOT NULL,
    subcategory     NVARCHAR(60)  NOT NULL,
    device_name     NVARCHAR(120) NOT NULL,
    brand           NVARCHAR(40)  NULL,
    model           NVARCHAR(120) NULL,
    serial_number   NVARCHAR(120) NOT NULL,
    fixed_asset     NVARCHAR(60)  NULL,
    description     NVARCHAR(400) NULL,
    network_zone    NVARCHAR(30)  NULL,
    device_role     VARCHAR(4)    NULL
                    CONSTRAINT CK_netdev_role CHECK (device_role IS NULL OR device_role IN ('L2','L3')),
    detail          NVARCHAR(120) NULL,

    stack_enabled   BIT           NOT NULL DEFAULT 0,
    stack_id        VARCHAR(10)   NULL,
    stack_role      NVARCHAR(20)  NULL,
    CONSTRAINT CK_netdev_stack_shape CHECK (stack_enabled = 1 OR (stack_id IS NULL AND stack_role IS NULL)),

    /* Optional since the v1 UI change — plenty of gear is catalogued before
       anyone walks over to read the MAC off the label. Format-checked when
       present; the filtered index below keeps it unique among live rows.
       REGEXP_LIKE is SQL Server 2025+. On 2022 swap the constraint for:
         CHECK (mac_address IS NULL OR mac_address LIKE
                '[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]') */
    mac_address     NVARCHAR(20)  NULL
                    CONSTRAINT CK_netdev_mac_format
                    CHECK (mac_address IS NULL OR REGEXP_LIKE(mac_address, '^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$')),

    location_id     VARCHAR(20)   NULL
                    CONSTRAINT FK_netdev_location REFERENCES dbo.locations(location_id),
    rack_u_start    INT           NULL,

    commission_date DATE          NULL,
    warranty_years  TINYINT       NULL
                    CONSTRAINT CK_netdev_warranty_years
                    CHECK (warranty_years IS NULL OR warranty_years BETWEEN 1 AND 5),
    warranty_expiry AS (dbo.fn_WarrantyExpiry(commission_date, warranty_years)) PERSISTED,
    eol_date        DATE          NULL,

    is_deleted      BIT           NOT NULL DEFAULT 0,
    deleted_at      DATETIME2(0)  NULL,
    deleted_by      VARCHAR(20)   NULL CONSTRAINT FK_netdev_deletedby REFERENCES dbo.app_users(user_id),
    created_at      DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by      VARCHAR(20)   NULL CONSTRAINT FK_netdev_createdby REFERENCES dbo.app_users(user_id),
    updated_at      DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_by      VARCHAR(20)   NULL CONSTRAINT FK_netdev_updatedby REFERENCES dbo.app_users(user_id)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_netdev_serial' AND object_id = OBJECT_ID('dbo.network_devices'))
CREATE UNIQUE INDEX UQ_netdev_serial ON dbo.network_devices(serial_number) WHERE is_deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_netdev_name' AND object_id = OBJECT_ID('dbo.network_devices'))
CREATE UNIQUE INDEX UQ_netdev_name ON dbo.network_devices(device_name) WHERE is_deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_netdev_mac' AND object_id = OBJECT_ID('dbo.network_devices'))
CREATE UNIQUE INDEX UQ_netdev_mac ON dbo.network_devices(mac_address) WHERE mac_address IS NOT NULL AND is_deleted = 0;
GO

/* ---------------------------------------------------------------------------
   IP allocations — the single registry of every address in the estate
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.ip_allocations', 'U') IS NULL
CREATE TABLE dbo.ip_allocations (
    /* Surrogate BIGINT rather than the 'IPA-001' style used elsewhere: these
       rows are plumbing generated in bulk, never quoted by a person the way
       "SRV-042" is. */
    alloc_id     BIGINT        IDENTITY(1,1) CONSTRAINT PK_ip_allocations PRIMARY KEY,
    ip_num       BIGINT        NOT NULL,
    ip_address   AS (dbo.fn_IntToIp(ip_num)) PERSISTED,

    subnet_id    VARCHAR(20)   NULL
                 CONSTRAINT FK_ipalloc_subnet REFERENCES dbo.vlan_subnets(subnet_id),

    assign_type  VARCHAR(10)   NOT NULL DEFAULT 'Static'
                 CONSTRAINT CK_ipalloc_assign CHECK (assign_type IN ('Static','DHCP','Reserved')),
    purpose      VARCHAR(20)   NOT NULL DEFAULT 'service'
                 CONSTRAINT CK_ipalloc_purpose
                 CHECK (purpose IN ('service','management','gateway','vip','dhcp-server','other')),

    /* Polymorphic ownership done with real foreign keys: one nullable column
       per possible owner, and a CHECK that at most one is filled. A single
       "owner_table + owner_id" pair would have been shorter but would carry
       no referential integrity at all — which is exactly how v1 lost track of
       software allocations when a server was renamed. */
    server_id    VARCHAR(20)   NULL CONSTRAINT FK_ipalloc_server REFERENCES dbo.servers(server_id),
    device_id    VARCHAR(20)   NULL CONSTRAINT FK_ipalloc_device REFERENCES dbo.network_devices(device_id),
    node_id      VARCHAR(20)   NULL CONSTRAINT FK_ipalloc_node   REFERENCES dbo.cluster_nodes(node_id),
    hardware_id  VARCHAR(20)   NULL CONSTRAINT FK_ipalloc_hw     REFERENCES dbo.hardware(hardware_id),

    CONSTRAINT CK_ipalloc_one_owner CHECK (
        (CASE WHEN server_id   IS NOT NULL THEN 1 ELSE 0 END)
      + (CASE WHEN device_id   IS NOT NULL THEN 1 ELSE 0 END)
      + (CASE WHEN node_id     IS NOT NULL THEN 1 ELSE 0 END)
      + (CASE WHEN hardware_id IS NOT NULL THEN 1 ELSE 0 END) <= 1
    ),

    hostname     NVARCHAR(120) NULL,
    remarks      NVARCHAR(400) NULL,
    created_at   DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by   VARCHAR(20)   NULL CONSTRAINT FK_ipalloc_createdby REFERENCES dbo.app_users(user_id),
    updated_at   DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_by   VARCHAR(20)   NULL CONSTRAINT FK_ipalloc_updatedby REFERENCES dbo.app_users(user_id),

    /* The whole point: an address belongs to one thing, estate-wide. */
    CONSTRAINT UQ_ipalloc_address UNIQUE (ip_num)
);
GO

/* An IP has to sit inside the subnet it claims to belong to. A CHECK
   constraint cannot read another table, so this is a trigger — kept to the
   one rule it exists for, and set-based so a bulk insert stays one statement. */
CREATE OR ALTER TRIGGER dbo.trg_ip_allocations_in_subnet
ON dbo.ip_allocations
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
          FROM inserted i
          JOIN dbo.vlan_subnets s ON s.subnet_id = i.subnet_id
         WHERE i.ip_num NOT BETWEEN s.network_num AND s.broadcast_num
    )
    BEGIN
        THROW 50001, 'IP address falls outside the network range of the subnet it is assigned to.', 1;
    END
END;
GO
