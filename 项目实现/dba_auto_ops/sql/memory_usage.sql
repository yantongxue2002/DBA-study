-- ============================================
-- 内存使用巡检 (SQL Server 2019 兼容)
-- ============================================

-- 1. 操作系统内存 + SQL Server 已提交内存
SELECT
    -- 操作系统内存
    osm.total_physical_memory_kb,
    osm.available_physical_memory_kb,
    CAST(osm.total_physical_memory_kb / 1024.0 AS DECIMAL(10,1)) AS total_physical_memory_mb,
    CAST(osm.available_physical_memory_kb / 1024.0 AS DECIMAL(10,1)) AS available_physical_memory_mb,
    CAST((osm.total_physical_memory_kb - osm.available_physical_memory_kb) * 100.0
         / NULLIF(osm.total_physical_memory_kb, 0) AS DECIMAL(5,2)) AS os_memory_used_pct,
    osm.system_memory_state_desc,
    -- SQL Server 已提交内存 (来自 sys.dm_os_sys_info)
    osi.committed_kb AS sqlserver_memory_usage_kb,
    CAST(osi.committed_kb / 1024.0 AS DECIMAL(10,1)) AS sqlserver_memory_usage_mb,
    osi.committed_target_kb AS max_physical_memory_kb_limit_kb,
    CAST(osi.committed_target_kb / 1024.0 AS DECIMAL(10,1)) AS max_physical_memory_limit_mb,
    -- 锁内存页 (SQL Server 2019 需从 sys.dm_os_process_memory 获取)
    opm.locked_page_allocations_kb
FROM sys.dm_os_sys_memory osm
CROSS JOIN sys.dm_os_sys_info osi
CROSS JOIN sys.dm_os_process_memory opm;

-- ============================================
-- 2. Buffer Cache 命中率 (累计值)
-- ============================================
SELECT
    object_name,
    counter_name,
    cntr_value,
    CASE
        WHEN counter_name = 'Buffer cache hit ratio'
            THEN CAST(cntr_value AS VARCHAR) + '%'
        WHEN counter_name IN ('Page life expectancy')
            THEN CAST(cntr_value AS VARCHAR) + ' seconds'
        ELSE CAST(cntr_value AS VARCHAR)
    END AS display_value
FROM sys.dm_os_performance_counters
WHERE (object_name LIKE '%Buffer Manager%' AND counter_name IN (
          'Buffer cache hit ratio',
          'Page life expectancy',
          'Free pages',
          'Total pages',
          'Database pages'
      ))
   OR (object_name LIKE '%Memory Manager%' AND counter_name IN (
          'Memory Grants Pending',
          'Memory Grants Outstanding',
          'Target Server Memory (KB)',
          'Total Server Memory (KB)'
      ))
ORDER BY object_name, counter_name;

-- ============================================
-- 3. 计划缓存使用情况
-- ============================================
SELECT
    objtype AS cacheobjtype,
    COUNT(*) AS cached_plans_count,
    CAST(SUM(CAST(size_in_bytes AS BIGINT)) / 1024.0 / 1024 AS DECIMAL(10,2)) AS total_size_mb,
    CAST(AVG(CAST(size_in_bytes AS BIGINT)) / 1024.0 AS DECIMAL(10,2)) AS avg_size_kb
FROM sys.dm_exec_cached_plans
GROUP BY objtype
ORDER BY total_size_mb DESC;