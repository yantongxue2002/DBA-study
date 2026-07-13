-- ============================================
-- 备份状态巡检
-- 每个数据库最近 FULL / DIFF / LOG 备份时间
-- ============================================

WITH BackupCTE AS (
    SELECT
        database_name,
        type,
        MAX(backup_finish_date) AS last_backup_date,
        DATEDIFF(HOUR, MAX(backup_finish_date), GETDATE()) AS hours_since_backup,
        DATEDIFF(DAY, MAX(backup_finish_date), GETDATE()) AS days_since_backup
    FROM msdb.dbo.backupset
    WHERE type IN ('D', 'I', 'L')
        AND is_copy_only = 0  -- 排除仅复制备份
    GROUP BY database_name, type
),
DatabaseInfo AS (
    SELECT
        d.name AS database_name,
        d.database_id,
        d.recovery_model_desc,
        d.state_desc,
        d.user_access_desc
    FROM sys.databases d
    WHERE d.name NOT IN ('tempdb')
        AND d.state = 0  -- ONLINE
        AND d.source_database_id IS NULL  -- 非数据库快照
)
SELECT
    di.database_name,
    di.recovery_model_desc,
    di.state_desc,
    -- FULL 备份
    d_cte.last_backup_date AS last_full_backup,
    d_cte.days_since_backup AS days_since_full_backup,
    d_cte.hours_since_backup AS hours_since_full_backup,
    -- DIFF 备份
    i_cte.last_backup_date AS last_diff_backup,
    i_cte.days_since_backup AS days_since_diff_backup,
    -- LOG 备份
    l_cte.last_backup_date AS last_log_backup,
    l_cte.hours_since_backup AS hours_since_log_backup,
    l_cte.days_since_backup AS days_since_log_backup,
    -- 备份大小 (最近一次)
    CAST(bs_full.backup_size / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS last_full_backup_gb,
    bs_full.backup_start_date AS last_full_backup_start,
    DATEDIFF(MINUTE, bs_full.backup_start_date, bs_full.backup_finish_date) AS last_full_backup_duration_min,
    -- 压缩情况
    bs_full.compressed_backup_size AS last_full_compressed_size,
    CASE
        WHEN bs_full.backup_size > 0
        THEN CAST(bs_full.compressed_backup_size * 100.0 / NULLIF(bs_full.backup_size, 0) AS DECIMAL(5,2))
        ELSE NULL
    END AS compression_ratio_pct
FROM DatabaseInfo di
CROSS APPLY (
    SELECT TOP 1 backup_size, compressed_backup_size, backup_start_date, backup_finish_date
    FROM msdb.dbo.backupset
    WHERE database_name = di.database_name
        AND type = 'D'
        AND is_copy_only = 0
    ORDER BY backup_finish_date DESC
) bs_full
OUTER APPLY (
    SELECT TOP 1 backup_finish_date AS last_backup_date,
        DATEDIFF(HOUR, backup_finish_date, GETDATE()) AS hours_since_backup,
        DATEDIFF(DAY, backup_finish_date, GETDATE()) AS days_since_backup
    FROM msdb.dbo.backupset
    WHERE database_name = di.database_name
        AND type = 'D'
        AND is_copy_only = 0
    ORDER BY backup_finish_date DESC
) d_cte
OUTER APPLY (
    SELECT TOP 1 backup_finish_date AS last_backup_date,
        DATEDIFF(HOUR, backup_finish_date, GETDATE()) AS hours_since_backup,
        DATEDIFF(DAY, backup_finish_date, GETDATE()) AS days_since_backup
    FROM msdb.dbo.backupset
    WHERE database_name = di.database_name
        AND type = 'I'
        AND is_copy_only = 0
    ORDER BY backup_finish_date DESC
) i_cte
OUTER APPLY (
    SELECT TOP 1 backup_finish_date AS last_backup_date,
        DATEDIFF(HOUR, backup_finish_date, GETDATE()) AS hours_since_backup,
        DATEDIFF(DAY, backup_finish_date, GETDATE()) AS days_since_backup
    FROM msdb.dbo.backupset
    WHERE database_name = di.database_name
        AND type = 'L'
        AND is_copy_only = 0
    ORDER BY backup_finish_date DESC
) l_cte
ORDER BY di.database_name;
