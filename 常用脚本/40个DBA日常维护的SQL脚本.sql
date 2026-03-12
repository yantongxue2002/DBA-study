-- ================================================
-- 40个DBA日常维护SQL脚本
-- 适用于MySQL、PostgreSQL等主流数据库
-- ================================================

-- ===================================================================
-- MySQL 相关脚本
-- ===================================================================

-- 1. 查看MySQL版本和基本信息
SELECT VERSION() AS mysql_version, @@hostname AS hostname, @@port AS port;

-- 2. 查看当前连接数和最大连接数
SHOW STATUS LIKE 'Threads_connected';
SHOW VARIABLES LIKE 'max_connections';

-- 3. 查看活跃进程列表
SHOW PROCESSLIST;

-- 4. 查看慢查询日志状态
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';

-- 5. 查看InnoDB缓冲池状态
SHOW ENGINE INNODB STATUS\G

-- 6. 查看数据库大小（按数据库统计）
SELECT 
    table_schema AS 'Database',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
FROM information_schema.tables 
GROUP BY table_schema 
ORDER BY SUM(data_length + index_length) DESC;

-- 7. 查看表大小（按表统计）
SELECT 
    table_schema AS 'Database',
    table_name AS 'Table',
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'Size (MB)'
FROM information_schema.tables 
ORDER BY (data_length + index_length) DESC 
LIMIT 20;

-- 8. 查找未使用索引的表
SELECT 
    t.TABLE_SCHEMA,
    t.TABLE_NAME,
    s.INDEX_NAME
FROM information_schema.tables t
JOIN information_schema.statistics s ON t.TABLE_SCHEMA = s.TABLE_SCHEMA AND t.TABLE_NAME = s.TABLE_NAME
LEFT JOIN performance_schema.table_io_waits_summary_by_index_usage i ON s.TABLE_SCHEMA = i.OBJECT_SCHEMA 
    AND s.TABLE_NAME = i.OBJECT_NAME AND s.INDEX_NAME = i.INDEX_NAME
WHERE t.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND i.INDEX_NAME IS NULL
ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME;

-- 9. 查看重复索引
SELECT 
    TABLE_SCHEMA,
    TABLE_NAME,
    INDEX_NAME,
    GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns
FROM information_schema.statistics
WHERE TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
GROUP BY TABLE_SCHEMA, TABLE_NAME, INDEX_NAME
HAVING COUNT(*) > 1;

-- 10. 查看表的碎片化情况
SELECT 
    table_schema,
    table_name,
    data_free,
    ROUND((data_free / (data_length + index_length)) * 100, 2) AS fragmentation_percent
FROM information_schema.tables 
WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND data_free > 0
    AND (data_length + index_length) > 0
ORDER BY fragmentation_percent DESC;

-- 11. 优化表（减少碎片）
-- OPTIMIZE TABLE table_name;

-- 12. 查看二进制日志状态
SHOW MASTER STATUS;
SHOW BINARY LOGS;

-- 13. 查看主从复制状态
SHOW SLAVE STATUS\G

-- 14. 查看全局变量
SHOW VARIABLES;

-- 15. 查看全局状态
SHOW GLOBAL STATUS;

-- 16. 查找长时间运行的查询
SELECT 
    id,
    user,
    host,
    db,
    command,
    time,
    state,
    info
FROM information_schema.processlist 
WHERE time > 60 
    AND info IS NOT NULL
ORDER BY time DESC;

-- 17. 查看锁等待情况
SELECT 
    r.trx_id waiting_trx_id,
    r.trx_mysql_thread_id waiting_thread,
    r.trx_query waiting_query,
    b.trx_id blocking_trx_id,
    b.trx_mysql_thread_id blocking_thread,
    b.trx_query blocking_query
FROM information_schema.innodb_lock_waits w
INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;

-- 18. 查看死锁信息
SHOW ENGINE INNODB STATUS LIKE '%LATEST DETECTED DEADLOCK%';

-- 19. 查看临时表使用情况
SHOW STATUS LIKE 'Created_tmp%';

-- 20. 查看查询缓存状态（MySQL 5.7及以下）
SHOW STATUS LIKE 'Qcache%';

-- ===================================================================
-- PostgreSQL 相关脚本
-- ===================================================================

-- 21. 查看PostgreSQL版本
SELECT version();

-- 22. 查看数据库大小
SELECT 
    pg_database.datname,
    pg_size_pretty(pg_database_size(pg_database.datname)) as size
FROM pg_database
ORDER BY pg_database_size(pg_database.datname) DESC;

-- 23. 查看表大小（包括索引）
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) as total_size
FROM pg_tables
WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 20;

-- 24. 查看索引大小
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(schemaname || '.' || indexname)) as index_size
FROM pg_indexes
WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
ORDER BY pg_relation_size(schemaname || '.' || indexname) DESC
LIMIT 20;

-- 25. 查看活跃会话
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    backend_start,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY backend_start;

-- 26. 查看长时间运行的查询
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    now() - query_start as duration,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle' 
    AND now() - query_start > interval '5 minutes'
ORDER BY duration DESC;

-- 27. 终止长时间运行的查询
-- SELECT pg_cancel_backend(pid);
-- SELECT pg_terminate_backend(pid);

-- 28. 查看锁信息
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

-- 29. 查看表膨胀情况
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(real_size) as real_size,
    pg_size_pretty(extra_size) as extra_size,
    bloat_pct
FROM (
    SELECT 
        schemaname,
        tablename,
        cc.reltuples,
        cc.relpages,
        bs,
        CEIL((cc.reltuples*((datahdr+ma-(CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta,
        COALESCE(c2.relname,'?') AS iname,
        COALESCE(c2.reltuples,0) AS ituples,
        COALESCE(c2.relpages,0) AS ipages,
        COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta,
        bs*(cc.relpages-otta)::bigint AS real_size,
        bs*(cc.relpages-otta)::bigint AS extra_size,
        CASE WHEN cc.relpages > otta THEN round(100*(cc.relpages-otta)::numeric/cc.relpages,1) ELSE 0 END AS bloat_pct
    FROM (
        SELECT 
            ma,
            bs,
            schemaname,
            tablename,
            (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
            (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
        FROM (
            SELECT 
                schemaname,
                tablename,
                hdr,
                ma,
                bs,
                SUM((1-null_frac)*avg_width) AS datawidth,
                MAX(null_frac) AS maxfracsum,
                hdr+(
                    SELECT 1+count(*)/8
                    FROM pg_stats s2
                    WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
                ) AS nullhdr
            FROM pg_stats s,
            (
                SELECT 
                    (SELECT current_setting('block_size')::numeric) AS bs,
                    CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
                    CASE WHEN v ~ 'mingw32' OR v ~ '64-bit' THEN 8 ELSE 4 END AS ma
                FROM (SELECT version() AS v) AS foo
            ) AS constants
            GROUP BY 1,2,3,4,5
        ) AS foo
    ) AS rs
    JOIN pg_class cc ON cc.relname = rs.tablename
    JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname
    LEFT JOIN pg_index i ON indrelid = cc.oid
    LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS s
WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
ORDER BY bloat_pct DESC
LIMIT 20;

-- 30. 查看未使用索引
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY schemaname, tablename, indexname;

-- 31. 查看重复索引
SELECT 
    a.schemaname,
    a.tablename,
    a.indexname,
    b.indexname as duplicate_index
FROM pg_indexes a
JOIN pg_indexes b ON a.schemaname = b.schemaname 
    AND a.tablename = b.tablename 
    AND a.indexname < b.indexname
WHERE a.indexdef = b.indexdef;

-- 32. 查看VACUUM和ANALYZE状态
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY last_vacuum, last_analyze;

-- 33. 手动执行VACUUM和ANALYZE
-- VACUUM ANALYZE table_name;

-- 34. 查看WAL（Write-Ahead Log）状态
SELECT 
    pg_current_wal_lsn(),
    pg_walfile_name(pg_current_wal_lsn()),
    pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS wal_bytes;

-- 35. 查看复制状态
SELECT 
    pid,
    usesysid,
    usename,
    application_name,
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
FROM pg_stat_replication;

-- ===================================================================
-- 通用维护脚本
-- ===================================================================

-- 36. 查找大表（跨数据库通用思路）
-- MySQL: 使用information_schema.tables
-- PostgreSQL: 使用pg_tables和pg_total_relation_size

-- 37. 查找长时间未使用的表
-- MySQL: 
SELECT 
    table_schema,
    table_name,
    update_time
FROM information_schema.tables 
WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND update_time < NOW() - INTERVAL 6 MONTH
ORDER BY update_time;

-- PostgreSQL:
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE GREATEST(last_vacuum, last_autovacuum, last_analyze, last_autoanalyze) < NOW() - INTERVAL '6 months'
ORDER BY GREATEST(last_vacuum, last_autovacuum, last_analyze, last_autoanalyze);

-- 38. 查看用户权限
-- MySQL:
SELECT 
    User,
    Host,
    Select_priv,
    Insert_priv,
    Update_priv,
    Delete_priv,
    Create_priv,
    Drop_priv
FROM mysql.user;

-- PostgreSQL:
SELECT 
    rolname,
    rolsuper,
    rolcreatedb,
    rolcreaterole,
    rolcanlogin
FROM pg_roles
ORDER BY rolname;

-- 39. 查找空表
-- MySQL:
SELECT 
    table_schema,
    table_name
FROM information_schema.tables 
WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND table_rows = 0;

-- PostgreSQL:
SELECT 
    schemaname,
    tablename
FROM pg_tables
WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
    AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = schemaname AND c.relname = tablename) = 0;

-- 40. 数据库健康检查综合脚本
-- MySQL健康检查
SELECT 
    'MySQL Health Check' as check_type,
    @@version as version,
    @@hostname as hostname,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') as connected_threads,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') as max_connections,
    (SELECT ROUND(AVG(VARIABLE_VALUE), 2) FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME IN ('Threads_connected')) as avg_connections,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Uptime')/86400 as uptime_days;

-- PostgreSQL健康检查
SELECT 
    'PostgreSQL Health Check' as check_type,
    version() as version,
    current_database() as database_name,
    (SELECT count(*) FROM pg_stat_activity WHERE state != 'idle') as active_connections,
    (SELECT setting FROM pg_settings WHERE name = 'max_connections')::int as max_connections,
    pg_postmaster_start_time() as start_time,
    now() - pg_postmaster_start_time() as uptime;

-- ===================================================================
-- 使用说明：
-- 1. 根据实际数据库类型选择相应的脚本执行
-- 2. 在生产环境执行前请先在测试环境验证
-- 3. 某些脚本可能需要特定的权限才能执行
-- 4. 定期执行这些脚本来监控数据库健康状况
-- 5. 根据业务需求调整阈值和参数
-- ===================================================================