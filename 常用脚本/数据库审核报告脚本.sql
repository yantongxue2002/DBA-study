/* =========================================
   1. 服务器实例信息
   ========================================= */
-- 当前实例基本信息（版本、edition、补丁级别、启动时间等）
SELECT 
    @@SERVERNAME AS ServerName,
    SERVERPROPERTY('InstanceName') AS InstanceName,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,   -- RTM / SPx / CUxx
    SERVERPROPERTY('ProductUpdateLevel') AS UpdateLevel,
    SERVERPROPERTY('Collation') AS Collation,
    sqlserver_start_time FROM sys.dm_os_sys_info;

-- 服务器级设置汇总
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
SELECT * FROM sys.configurations ORDER BY name;

-- 磁盘剩余空间
EXEC master.dbo.xp_fixeddrives;

/* =========================================
   2. 数据库状态与文件信息
   ========================================= */
-- 快速看一下所有数据库清单 + 大小 + 状态
SELECT 
    d.name AS DatabaseName,
    d.state_desc AS Status,
    d.recovery_model_desc AS RecoveryModel,
    d.log_reuse_wait_desc, -- 新增：日志重用等待状态
    d.create_date,
    (mf.size * 8.0 / 1024) AS Size_MB
FROM sys.master_files mf
INNER JOIN sys.databases d ON mf.database_id = d.database_id
WHERE mf.type_desc = 'ROWS'  -- 只看数据文件
ORDER BY Size_MB DESC;

-- 所有数据库文件位置、大小、自动增长（包含 tempdb）
SELECT 
    DB_NAME(mf.database_id) AS DBName,
    mf.name AS LogicalName,
    mf.physical_name AS PhysicalPath,
    mf.type_desc AS FileType,
    mf.size * 8.0 / 1024 AS CurrentSize_MB,
    CASE WHEN mf.max_size = -1 THEN 'Unlimited' 
         ELSE CAST(mf.max_size * 8.0 / 1024 AS varchar) + ' MB' END AS MaxSize,
    mf.growth * 8.0 / 1024 AS Growth_MB,
    mf.is_percent_growth AS IsPercentGrowth
FROM sys.master_files mf
ORDER BY DBName, FileType, CurrentSize_MB DESC;

/* =========================================
   3. 备份检查
   ========================================= */
-- 最近 30 天备份记录（重点看 Full 和 Log）
SELECT 
    d.name AS DatabaseName,
    bs.type AS BackupType,          -- D=Full, I=Diff, L=Log
    bs.backup_start_date,
    bs.backup_finish_date,
    bs.backup_size / 1024.0 / 1024 AS Size_MB,
    bmf.physical_device_name AS BackupFilePath,
    DATEDIFF(DAY, bs.backup_start_date, GETDATE()) AS DaysAgo
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
INNER JOIN sys.databases d ON bs.database_name = d.name
WHERE bs.backup_start_date >= DATEADD(DAY, -30, GETDATE())
ORDER BY bs.backup_start_date DESC;

-- 哪些数据库 30 天内没有 Full 备份？
SELECT name 
FROM sys.databases 
WHERE database_id > 4  -- 排除系统库
AND source_database_id IS NULL -- 排除快照
AND name NOT IN (
    SELECT DISTINCT database_name 
    FROM msdb.dbo.backupset 
    WHERE type = 'D' 
    AND backup_start_date >= DATEADD(DAY, -30, GETDATE())
);

/* =========================================
   4. 安全与登录检查
   ========================================= */
-- 所有登录账号概览
SELECT 
    sp.name AS LoginName,
    sp.type_desc,
    sp.create_date,
    sp.is_disabled,
    -- 只有当是 SQL 登录名时，才显示密码策略
    CASE 
        WHEN sp.type = 'S' THEN CASE WHEN sl.is_expiration_checked = 1 THEN 'Yes' ELSE 'No' END
        ELSE 'N/A' 
    END AS PasswordExpiration,
    CASE 
        WHEN sp.type = 'S' THEN CASE WHEN sl.is_policy_checked = 1 THEN 'Yes' ELSE 'No' END
        ELSE 'N/A' 
    END AS PasswordPolicy,
    sp.default_database_name
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sp.sid = sl.sid
WHERE sp.type IN ('S', 'U', 'G') 
  AND sp.name NOT LIKE '##%' 
  AND sp.name NOT LIKE 'NT %'
  AND sp.name NOT LIKE 'NT SERVICE%'
ORDER BY sp.create_date DESC;

-- 当前 sysadmin 成员（危险账号列表）
SELECT 
    p.name AS LoginName
FROM sys.server_role_members rm
INNER JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id
INNER JOIN sys.server_principals p ON rm.member_principal_id = p.principal_id
WHERE r.name = 'sysadmin'
ORDER BY p.name;

-- sa 账号状态
SELECT 
    name, 
    is_disabled, 
    is_expiration_checked, 
    is_policy_checked,
    create_date,
    modify_date
FROM sys.sql_logins 
WHERE name = 'sa';

/* =========================================
   5. 性能与慢查询
   ========================================= */
-- 查看当前数据库最忙的等待
SELECT TOP 10
    wait_type, 
    waiting_tasks_count, 
    wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
    'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE', 'CLR_AUTO_EVENT',
    'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE', 'DBMIRROR_DBM_EVENT',
    'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_WORKER_QUEUE', 'DBMIRRORING_CMD',
    'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE', 'EXECSYNC',
    'FT_IFTS_SCHEDULER_IDLE_WAIT', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
    'ONDEMAND_TASK_QUEUE', 'PREEMPTIVE_OS_LIBRARYOPS',
    'PREEMPTIVE_OS_COMOPS', 'PREEMPTIVE_OS_CRYPTOPS',
    'PREEMPTIVE_OS_PIPEOPS', 'PREEMPTIVE_OS_AUTHENTICATIONOPS',
    'PREEMPTIVE_OS_GENERICOPS', 'PREEMPTIVE_OS_VERIFYTRUST',
    'PREEMPTIVE_XE_DISPATCHER', 'PREEMPTIVE_XE_DISPATCHER_JOIN',
    'PREEMPTIVE_XE_DISPATCHER_LIST', 'PREEMPTIVE_XE_TIMER',
    'REQUEST_FOR_DEADLOCK_SEARCH', 'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK',
    'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP', 'SLEEP_DCOMSTARTUP',
    'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY', 'SLEEP_MASTERUPGRADED',
    'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK', 'SLEEP_TASK',
    'SLEEP_TEMPDBSTARTUP', 'SLEEP_WORKSPACE', 'SQLTRACE_BUFFER_FLUSH',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'SQLTRACE_WAIT_ENTRIES',
    'WAITFOR', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT'
)
ORDER BY wait_time_ms DESC;

-- Top 20 最耗时的查询（按总耗时/平均耗时排序）
SELECT TOP 20
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text) ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS QueryText,
    qs.execution_count AS ExecutionCount,
    qs.total_elapsed_time / 1000 AS TotalElapsedTime_ms,
    (qs.total_elapsed_time / qs.execution_count) / 1000 AS AvgElapsedTime_ms,
    qs.total_worker_time / 1000 AS TotalCPUTime_ms,
    (qs.total_worker_time / qs.execution_count) / 1000 AS AvgCPUTime_ms,
    qs.total_logical_reads AS TotalLogicalReads,
    (qs.total_logical_reads / qs.execution_count) AS AvgLogicalReads
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC;

-- 查看表的数据量 + 索引数量
SELECT 
    t.name AS TableName,
    SUM(p.rows) AS RowCounts,
    COUNT(i.index_id) AS IndexCount
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
INNER JOIN sys.indexes i ON t.object_id = i.object_id
WHERE p.index_id IN (0, 1) -- 0=堆, 1=聚集索引
GROUP BY t.name
ORDER BY SUM(p.rows) DESC;

/* =========================================
   6. 其他检查
   ========================================= */
-- SQL Agent 作业列表
SELECT name, enabled, description FROM msdb.dbo.sysjobs ORDER BY name;

-- 查看最近错误日志
EXEC sp_readerrorlog 0, 1, '错误', '严重';
