/* =============================================================================
   IS-Inventory v2 — 11: Applications

   A page for cataloguing what runs on a server — the app's name, the port it
   listens on, a link to reach it, and who to call about it — filed under
   that server rather than as its own disconnected inventory. "Server Type"
   from the source spreadsheet is not stored here: it is servers.hosting_type
   / servers.os_type, one join away, so it cannot drift from what the Server
   record actually says.
   ============================================================================= */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.applications', 'U') IS NULL
CREATE TABLE dbo.applications (
    application_id   VARCHAR(20)   NOT NULL CONSTRAINT PK_applications PRIMARY KEY,  -- APP-001
    server_id        VARCHAR(20)   NOT NULL
                     CONSTRAINT FK_applications_server REFERENCES dbo.servers(server_id),

    application_name NVARCHAR(150) NOT NULL,
    /* Text, not INT: real entries are "443", "8080-8090", or "443, 8443". */
    port_number      NVARCHAR(60)  NULL,
    link_url         NVARCHAR(400) NULL,   -- how to reach it — http(s) URL, UNC path, whatever applies
    incharge         NVARCHAR(120) NULL,   -- person or team responsible
    department       NVARCHAR(120) NULL,

    remarks          NVARCHAR(400) NULL,

    is_deleted       BIT           NOT NULL DEFAULT 0,
    deleted_at       DATETIME2(0)  NULL,
    deleted_by       VARCHAR(20)   NULL CONSTRAINT FK_applications_deletedby REFERENCES dbo.app_users(user_id),
    created_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by       VARCHAR(20)   NULL CONSTRAINT FK_applications_createdby REFERENCES dbo.app_users(user_id),
    updated_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_by       VARCHAR(20)   NULL CONSTRAINT FK_applications_updatedby REFERENCES dbo.app_users(user_id)
);
GO

/* Filtered, not a plain UNIQUE: the same app name/port can be re-added to a
   server after a soft-deleted entry for it, same reasoning as everywhere
   else business keys are enforced in this schema. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_applications_server_name_port' AND object_id = OBJECT_ID('dbo.applications'))
CREATE UNIQUE INDEX UQ_applications_server_name_port
    ON dbo.applications(server_id, application_name, port_number) WHERE is_deleted = 0;
GO

/* Speed indexes for this table live here rather than 08_indexes.sql —
   that script runs before this table exists on a from-scratch build. */
CREATE NONCLUSTERED INDEX IX_applications_server  ON dbo.applications(server_id) WHERE is_deleted = 0;
CREATE NONCLUSTERED INDEX IX_applications_deleted ON dbo.applications(deleted_at DESC) WHERE is_deleted = 1;
GO

EXEC dbo.sp_EnableSystemVersioning 'applications';
GO

/* v_server_applications — the page's query. "Server Type" is not a stored
   column here: it is servers.hosting_type/os_type read through the FK
   (defined in 09_views.sql for every other view, but this one has to live
   here since dbo.applications does not exist until this script runs), so
   it can never disagree with what the Server record itself says. */
CREATE OR ALTER VIEW dbo.v_server_applications
AS
SELECT ap.application_id,
       ap.application_name,
       ap.port_number,
       ap.link_url,
       ap.incharge,
       ap.department,
       ap.remarks,
       server_id      = s.server_id,
       server_name    = s.server_name,
       system_name    = s.system_name,
       server_type    = s.hosting_type + ISNULL(N' / ' + s.os_version, N''),
       server_status  = s.status,
       site_name      = lt.site_name
  FROM dbo.applications ap
  JOIN dbo.servers s ON s.server_id = ap.server_id AND s.is_deleted = 0
  LEFT JOIN dbo.cluster_nodes n ON n.node_id = s.node_id
  /* A Physical server owns its chassis directly; a Virtual one reaches it
     through the cluster node it runs on — same COALESCE v_asset_360 uses,
     for the same reason (s.hardware_id alone is NULL for every VM). */
  LEFT JOIN dbo.hardware h ON h.hardware_id = COALESCE(s.hardware_id, n.hardware_id) AND h.is_deleted = 0
  LEFT JOIN dbo.v_location_tree lt ON lt.location_id = h.location_id
 WHERE ap.is_deleted = 0;
GO
