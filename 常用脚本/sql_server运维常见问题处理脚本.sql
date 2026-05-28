-- 一、日志收缩操作
-- 1.1 建议先切换到 master 库，避免目标库被占用
USE [master] 
GO
-- 1.2 数据库文件详细信息查询（路径、大小、增长方式，排查文件异常）
SELECT
    db.name AS 数据库名称,
    mf.name AS 文件名称,
    mf.physical_name AS 文件物理路径,
    mf.type_desc AS 文件类型, -- ROWS=数据文件，LOG=日志文件
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(10,2)) AS 文件当前大小_MB,
    CAST(mf.max_size * 8.0 / 1024 AS DECIMAL(10,2)) AS 文件最大大小_MB, -- 0=无限制
    CAST(mf.growth AS DECIMAL(10,2)) AS 增长值,
    CASE mf.is_percent_growth WHEN 1 THEN '百分比增长' ELSE '固定大小增长(MB)' END AS 增长方式,
    mf.state_desc AS 文件状态
FROM sys.master_files mf
LEFT JOIN sys.databases db ON mf.database_id = db.database_id
ORDER BY db.name, mf.type_desc;
-- 1.3 日志备份
BACKUP LOG [MES.WGWTB] 
TO DISK = 'D:\Backup\MES_WGWTB_LogBackup.trn' 
WITH INIT; -- INIT 表示覆盖同名文件
-- 1.4 收缩日志
DBCC SHRINKFILE (N'mes_log', 204800); 
GO
-- 1.5 修改最大文件大小 (例如限制为 50GB)
ALTER DATABASE [mes]
MODIFY FILE (
    NAME = N'mes_log', -- 还是填第一步查出来的名字
    MAXSIZE = 204800MB -- 限制最大为 200GB
);
-- 1.6 如果日志收缩不成功，看看日志重用等待原因，如果是 LOG_BACKUP 收缩是无效的需要再执行一次数据库备份，NOTHING正常收缩
SELECT 
    name AS [数据库名], 
    recovery_model_desc AS [恢复模式], 
    log_reuse_wait_desc AS [日志重用等待原因]
FROM sys.databases 
WHERE name = 'nuva_mom'; 


-- 二、性能排查步骤
-- 2.1 慢查询检查（查询执行时间超过30秒的语句）
SELECT
    r.session_id AS 会话ID,
    DB_NAME(s.database_id) AS 数据库名称, -- 修正：从会话视图获取数据库ID
    s.login_name AS 登录账号,             -- 修正：从会话视图获取
    s.program_name AS 应用程序名称,       -- 修正：从会话视图获取
    r.status AS 执行状态,
    DATEDIFF(SECOND, r.start_time, GETDATE()) AS 执行时间_秒,
    -- 获取正在执行的SQL语句
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1, 
        ((CASE WHEN r.statement_end_offset = -1 
               THEN LEN(CONVERT(NVARCHAR(MAX), t.text)) * 2 
               ELSE r.statement_end_offset 
          END - r.statement_start_offset) / 2) + 1) AS 执行SQL语句
FROM 
    sys.dm_exec_requests r
JOIN 
    sys.dm_exec_sessions s ON r.session_id = s.session_id  -- 关联会话视图
CROSS APPLY 
    sys.dm_exec_sql_text(r.sql_handle) t
WHERE 
    DATEDIFF(SECOND, r.start_time, GETDATE()) > 10 -- 执行时间超过10秒
    AND r.session_id > 50;

-- 2.2 阻塞会话检查（查找被阻塞的会话和阻塞源）
SELECT
    -- 阻塞信息
    r.blocking_session_id AS 阻塞者会话ID,
    r.session_id AS 被阻塞会话ID,
    r.wait_type AS 等待类型,
    r.wait_time AS 等待时间_毫秒,
    
    -- 数据库与程序信息 (来自会话视图)
    DB_NAME(s.database_id) AS 数据库名称,
    s.program_name AS 应用程序名称,
    s.login_name AS 登录账号,
    s.host_name AS 客户端主机名,
    
    -- 持续时间
    DATEDIFF(SECOND, s.last_request_start_time, GETDATE()) AS 持续时间_秒,

    -- SQL语句 (使用 CROSS APPLY 获取文本)
    SUBSTRING(t.text, (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset
          WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset
          END - r.statement_start_offset)/2) + 1) AS 正在执行的SQL语句
FROM 
    sys.dm_exec_requests r
JOIN 
    sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY 
    sys.dm_exec_sql_text(r.sql_handle) t
WHERE 
    r.blocking_session_id > 0 -- 只筛选被阻塞的请求
ORDER BY 
    r.wait_time DESC; 

-- 2.3 等待统计信息分析（查看系统级等待类型，识别性能瓶颈）
SELECT TOP 20
    wait_type AS 等待类型,
    waiting_tasks_count AS 等待任务数,
    wait_time_ms AS 总等待时间毫秒,
    max_wait_time_ms AS 最大等待时间毫秒,
    signal_wait_time_ms AS 信号等待时间毫秒,
    CASE 
        WHEN wait_time_ms = 0 THEN 0
        ELSE CAST(wait_time_ms AS FLOAT) * 100 / SUM(wait_time_ms) OVER()
    END AS 等待时间百分比
FROM 
    sys.dm_os_wait_stats
WHERE 
    wait_type NOT IN (
        'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
        'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
        'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'LAZYWRITER_SLEEP',
        'LOGMGR_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'RESOURCE_QUEUE',
        'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
        'WAITFOR', 'XE_DISPATCHER_JOIN', 'XE_TIMER_EVENT',
        'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
    )
    AND waiting_tasks_count > 0
ORDER BY 
    wait_time_ms DESC;

-- 2.4 缓冲池和内存使用情况（检查内存压力）
SELECT 
    (total_physical_memory_kb / 1024) AS 物理内存总量_MB,
    (available_physical_memory_kb / 1024) AS 可用物理内存_MB
FROM 
    sys.dm_os_sys_memory;

-- 2,5查看SQL Server进程内存使用情况
SELECT 
    (physical_memory_in_use_kb / 1024) AS SQLServer内存使用_MB,
    process_physical_memory_low AS 进程物理内存低,
    process_virtual_memory_low AS 进程虚拟内存低
FROM 
    sys.dm_os_process_memory;

-- 2,6 查看缓冲池详细信息
SELECT 
    COUNT(*) * 8 / 1024 AS 缓冲池页数_MB,
    COUNT(CASE WHEN database_id = 32767 THEN 1 END) * 8 / 1024 AS ResourceDB页数_MB,
    COUNT(CASE WHEN database_id BETWEEN 1 AND 32766 THEN 1 END) * 8 / 1024 AS 用户数据库页数_MB
FROM 
    sys.dm_os_buffer_descriptors;

-- 2,7 索引碎片分析（检查高碎片索引，影响查询性能）
SELECT 
    DB_NAME(database_id) AS 数据库名称,
    OBJECT_NAME(object_id, database_id) AS 表名,
    index_id AS 索引ID,
    index_level AS 索引层级,
    avg_fragmentation_in_percent AS 平均碎片百分比,
    page_count AS 页数,
    avg_page_space_used_in_percent AS 平均页空间使用百分比
FROM 
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
WHERE 
    avg_fragmentation_in_percent > 10  -- 碎片超过10%的索引
    AND page_count > 100               -- 页数大于100的索引
    AND index_id > 0                   -- 排除堆表
ORDER BY 
    avg_fragmentation_in_percent DESC;

-- 2,8 执行计划缓存分析（查找消耗CPU最多的查询）
SELECT TOP 10
    qs.total_worker_time / qs.execution_count AS 平均CPU时间,
    qs.total_worker_time AS 总CPU时间,
    qs.execution_count AS 执行次数,
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        ((CASE WHEN qs.statement_end_offset = -1
               THEN LEN(CONVERT(NVARCHAR(MAX), qt.text)) * 2
               ELSE qs.statement_end_offset
          END - qs.statement_start_offset) / 2) + 1) AS SQL语句,
    qp.query_plan AS 执行计划
FROM 
    sys.dm_exec_query_stats qs
CROSS APPLY 
    sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY 
    sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY 
    qs.total_worker_time DESC;

-- 2,9 I/O 性能分析（检查慢速I/O操作）
SELECT 
    database_id AS 数据库ID,
    DB_NAME(database_id) AS 数据库名称,
    file_id AS 文件ID,
    io_stall_read_ms AS 读取等待时间毫秒,
    num_of_reads AS 读取次数,
    CASE WHEN num_of_reads > 0 THEN io_stall_read_ms / num_of_reads ELSE 0 END AS 平均每次读取等待毫秒,
    io_stall_write_ms AS 写入等待时间毫秒,
    num_of_writes AS 写入次数,
    CASE WHEN num_of_writes > 0 THEN io_stall_write_ms / num_of_writes ELSE 0 END AS 平均每次写入等待毫秒,
    io_stall AS "总I/O等待时间毫秒"
FROM 
    sys.dm_io_virtual_file_stats(NULL, NULL)
WHERE 
    io_stall > 0
ORDER BY 
    io_stall DESC;

-- 三、具体的表开启CDC
-- 3.1 如果第一次开启的话，先生成cdc的架构
USE mes;
GO
EXEC sys.sp_cdc_enable_db;
GO
-- 3.2 检查数据库是否已经开启了 CDC ，1 就是开启了
SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME();
-- 3.3 给具体的表开启CDC
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',           -- 原表的架构名
    @source_name   = N'YourTable',     -- 原表的表名
    @role_name     = NULL,             -- 访问控制角色，NULL表示不限制
    @supports_net_changes = 1;         -- 是否支持净更改查询（可选，建议设为1）

-- 3.4 查看当前数据库中已启用 CDC 的表
SELECT name, is_tracked_by_cdc 
FROM sys.tables  
WHERE is_tracked_by_cdc > 0

-- 四、