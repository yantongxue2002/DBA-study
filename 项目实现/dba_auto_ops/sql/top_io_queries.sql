-- ============================================
-- 高 IO 查询定位
-- 按物理读和写排序 (Plan Cache)
-- ============================================

SELECT TOP 20
    DB_NAME(qt.dbid) AS database_name,
    qs.total_physical_reads,
    qs.total_logical_reads,
    qs.total_logical_writes,
    CAST(qs.total_physical_reads * 1.0 / NULLIF(qs.execution_count, 0) AS BIGINT) AS avg_physical_reads,
    CAST(qs.total_logical_reads * 1.0 / NULLIF(qs.execution_count, 0) AS BIGINT) AS avg_logical_reads,
    qs.execution_count,
    qs.total_worker_time / 1000 AS total_cpu_ms,
    qs.total_elapsed_time / 1000 AS total_duration_ms,
    qs.total_rows,
    qs.total_spills,
    qs.last_execution_time,
    SUBSTRING(qt.text,
        (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text) ELSE qs.statement_end_offset END
          - qs.statement_start_offset) / 2) + 1
    ) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.dbid > 4
ORDER BY qs.total_physical_reads DESC;
