-- ============================================
-- 索引碎片巡检
-- 碎片率 & 建议 (REBUILD / REORGANIZE)
-- 包含缺失索引统计
-- ============================================

-- 1. 索引碎片分析 (用户数据库, 碎片率 > 5%)
DECLARE @sql NVARCHAR(MAX) = '';

SELECT @sql = @sql + '
SELECT
    ''' + name + ''' AS database_name,
    SCHEMA_NAME(o.schema_id) AS schema_name,
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    ps.avg_fragmentation_in_percent,
    ps.fragment_count,
    ps.avg_fragment_size_in_pages,
    ps.page_count,
    CAST(ps.avg_page_space_used_in_percent AS DECIMAL(5,2)) AS avg_page_density_pct,
    ps.record_count,
    CASE
        WHEN ps.avg_fragmentation_in_percent > 30 THEN ''REBUILD''
        WHEN ps.avg_fragmentation_in_percent > 10 THEN ''REORGANIZE''
        ELSE ''OK''
    END AS recommendation,
    -- 生成维护脚本
    CASE
        WHEN ps.avg_fragmentation_in_percent > 30
        THEN ''ALTER INDEX ['' + i.name + ''] ON ['' + SCHEMA_NAME(o.schema_id) + ''].['' + OBJECT_NAME(i.object_id) + ''] REBUILD WITH (ONLINE = ON);''
        WHEN ps.avg_fragmentation_in_percent > 10
        THEN ''ALTER INDEX ['' + i.name + ''] ON ['' + SCHEMA_NAME(o.schema_id) + ''].['' + OBJECT_NAME(i.object_id) + ''] REORGANIZE;''
        ELSE NULL
    END AS ddl_script
FROM [' + name + '].sys.dm_db_index_physical_stats(
    DB_ID(''' + name + '''), NULL, NULL, NULL, ''LIMITED''
) ps
JOIN [' + name + '].sys.indexes i
    ON ps.object_id = i.object_id AND ps.index_id = i.index_id
JOIN [' + name + '].sys.objects o
    ON i.object_id = o.object_id
WHERE ps.avg_fragmentation_in_percent > 5
    AND ps.page_count > 100  -- 忽略小表
    AND i.type_desc <> ''HEAP''
    AND o.is_ms_shipped = 0
ORDER BY ps.avg_fragmentation_in_percent DESC;
'
FROM sys.databases
WHERE state = 0
    AND database_id > 4
    AND is_read_only = 0;

EXEC sp_executesql @sql;

-- 2. 缺失索引建议 (Top 20 by impact)
SELECT TOP 20
    migs.avg_user_impact AS avg_impact_pct,
    migs.avg_total_user_cost,
    migs.user_seeks,
    migs.user_scans,
    migs.last_user_seek,
    migs.last_user_scan,
    mid.statement AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    -- 生成的 CREATE INDEX 语句
    'CREATE NONCLUSTERED INDEX [IX_' +
    REPLACE(REPLACE(REPLACE(
        ISNULL(mid.equality_columns, '') + ISNULL(mid.inequality_columns, ''),
        ']', ''), '[', ''), ', ', '_') +
    '] ON ' + mid.statement +
    ' (' + ISNULL(mid.equality_columns, '') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL
         THEN ',' ELSE '' END +
    ISNULL(mid.inequality_columns, '') + ')' +
    CASE WHEN mid.included_columns IS NOT NULL
         THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END +
    ';' AS create_index_statement
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs
    ON mig.index_group_handle = migs.group_handle
JOIN sys.dm_db_missing_index_details mid
    ON mig.index_handle = mid.index_handle
WHERE mid.database_id > 4
ORDER BY migs.avg_user_impact * migs.avg_total_user_cost DESC;
