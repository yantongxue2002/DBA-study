-- ============================================
-- 缺失索引详细分析
-- 结合缺失索引建议与已有索引判断
-- ============================================

SELECT TOP 20
    DB_NAME(mid.database_id) AS database_name,
    mid.statement AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.unique_compiles,
    migs.user_seeks,
    migs.user_scans,
    migs.last_user_seek,
    migs.last_user_scan,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    -- 预估收益 = impact * cost (越大越值得建)
    CAST(migs.avg_user_impact * migs.avg_total_user_cost AS DECIMAL(20,2)) AS improvement_measure,
    -- 生成 CREATE INDEX 脚本
    'CREATE NONCLUSTERED INDEX [IX_' +
    LEFT(
        REPLACE(REPLACE(REPLACE(REPLACE(
            ISNULL(mid.equality_columns, '') +
            CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL
                 THEN '_' ELSE '' END +
            ISNULL(mid.inequality_columns, ''),
            '[', ''), ']', ''), ' ', '_'), ',', ''),
        60
    ) +
    '] ON ' + mid.statement +
    ' (' + ISNULL(mid.equality_columns, '') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL
         THEN ', ' ELSE '' END +
    ISNULL(mid.inequality_columns, '') + ')' +
    CASE WHEN mid.included_columns IS NOT NULL
         THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END +
    ' WITH (ONLINE = ON);' AS create_index_statement,
    -- 简化版 DDL (用于快速查看)
    'CREATE INDEX [IX_' + PARSENAME(REPLACE(mid.statement,'[',''),1) + '_' +
    REPLACE(REPLACE(ISNULL(mid.equality_columns,''),'[',''),']','') +
    '] ON ' + mid.statement + '(...)' AS ddl_script
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs
    ON mig.index_group_handle = migs.group_handle
JOIN sys.dm_db_missing_index_details mid
    ON mig.index_handle = mid.index_handle
WHERE mid.database_id > 4
    AND migs.user_seeks > 0
ORDER BY improvement_measure DESC;
