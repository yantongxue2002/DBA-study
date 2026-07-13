-- ============================================
-- 高消耗查询定位 (Top CPU / IO / Duration)
-- 从 Plan Cache 中提取
-- ============================================

-- 合并 Top CPU + Top IO + Top Duration 查询
WITH PlanCacheQueries AS (
    SELECT
        DB_NAME(qt.dbid) AS database_name,
        OBJECT_NAME(qt.objectid, qt.dbid) AS object_name,
        qs.creation_time,
        qs.last_execution_time,
        qs.execution_count,
        -- CPU
        qs.total_worker_time / 1000 AS total_cpu_ms,
        CAST(qs.total_worker_time * 1.0 / NULLIF(qs.execution_count, 0) / 1000 AS DECIMAL(10,2)) AS avg_cpu_ms,
        -- IO (逻辑读)
        qs.total_logical_reads AS total_logical_reads,
        CAST(qs.total_logical_reads * 1.0 / NULLIF(qs.execution_count, 0) AS BIGINT) AS avg_logical_reads,
        qs.total_physical_reads,
        -- Duration
        qs.total_elapsed_time / 1000 AS total_duration_ms,
        CAST(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count, 0) / 1000 AS DECIMAL(10,2)) AS avg_duration_ms,
        -- 其他
        qs.total_rows,
        qs.total_grant_kb,
        qs.total_spills,
        -- 查询文本
        SUBSTRING(qt.text,
            (qs.statement_start_offset / 2) + 1,
            ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text) ELSE qs.statement_end_offset END
              - qs.statement_start_offset) / 2) + 1
        ) AS query_text,
        qt.text AS full_text,
        -- 排名 (分别按CPU/IO/Duration)
        ROW_NUMBER() OVER (ORDER BY qs.total_worker_time DESC) AS cpu_rank,
        ROW_NUMBER() OVER (ORDER BY qs.total_logical_reads DESC) AS io_rank,
        ROW_NUMBER() OVER (ORDER BY qs.total_elapsed_time DESC) AS duration_rank
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
    WHERE qt.dbid > 4  -- 排除系统数据库
)
SELECT
    database_name,
    object_name,
    execution_count,
    total_cpu_ms,
    avg_cpu_ms,
    total_logical_reads,
    avg_logical_reads,
    total_physical_reads,
    total_duration_ms,
    avg_duration_ms,
    total_rows,
    total_grant_kb,
    total_spills,
    cpu_rank,
    io_rank,
    duration_rank,
    query_text,
    last_execution_time
FROM PlanCacheQueries
WHERE cpu_rank <= 10 OR io_rank <= 10 OR duration_rank <= 10
ORDER BY total_cpu_ms DESC;
