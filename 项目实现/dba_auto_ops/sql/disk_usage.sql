-- ============================================
-- 磁盘空间巡检
-- 检查所有驱动器的空间使用情况
-- ============================================

-- 1. 通过 xp_fixeddrives 获取各盘总空间 (MB)
-- 2. 通过 sys.master_files 获取数据文件所在盘符
-- 3. 结合 sys.dm_os_volume_stats 获取详细空间信息

SELECT DISTINCT
    vs.volume_mount_point AS drive_letter,
    vs.logical_volume_name AS volume_name,
    CAST(vs.total_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS total_gb,
    CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS available_gb,
    CAST((vs.total_bytes - vs.available_bytes) / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS used_gb,
    CAST((vs.total_bytes - vs.available_bytes) * 100.0 / NULLIF(vs.total_bytes, 0) AS DECIMAL(5,2)) AS used_pct,
    CAST(vs.available_bytes * 100.0 / NULLIF(vs.total_bytes, 0) AS DECIMAL(5,2)) AS available_pct,
    -- 该盘上存在的数据库文件
    STUFF((
        SELECT DISTINCT ', ' + DB_NAME(mf.database_id)
        FROM sys.master_files mf
        CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs2
        WHERE vs2.volume_mount_point = vs.volume_mount_point
        FOR XML PATH('')
    ), 1, 2, '') AS databases_on_drive
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY vs.volume_mount_point;
