-- 说明：本脚本适配 Microsoft SQL Server Enterprise: Core-based Licensing (64-bit) 15.0.2000.5 版本，
-- 涵盖DBA日常巡检全部核心维度，可直接在SSMS中执行，所有模块均添加详细注释，便于理解和排查问题；
-- 执行前请使用具有sysadmin权限的账号登录，建议每天早间（业务低峰期）执行，执行完成后留存输出结果用于对比分析。
-- 脚本执行顺序：实例基础信息 → 数据库状态 → 备份状态 → 存储资源 → 性能监控 → 索引与碎片 → 安全权限 → 日志检查 → 系统相关 → 异常汇总，各模块独立可单独执行，也可全量执行。

-- 一、实例基础信息巡检（核心必查）
-- 功能：检查SQL Server实例运行状态、版本信息、配置参数，确认实例正常启动且配置合规
-- 1.1 实例基本信息查询（版本、启动时间、运行状态、实例名称）
SELECT
    SERVERPROPERTY('ServerName') AS 实例名称,
    SERVERPROPERTY('ProductVersion') AS SQL版本号,
    SERVERPROPERTY('ProductLevel') AS 版本级别, -- RTM/SP/CU
    SERVERPROPERTY('Edition') AS '版本 editions', -- 此处应为Enterprise: Core-based Licensing
    SERVERPROPERTY('EngineEdition') AS 引擎版本, -- 3=Enterprise Edition
    SERVERPROPERTY('IsClustered') AS 是否集群, -- 1=集群环境，0=非集群
    SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS 主机名,
    SERVERPROPERTY('InstanceDefaultDataPath') AS 默认数据路径,
    SERVERPROPERTY('InstanceDefaultLogPath') AS 默认日志路径,
    sqlserver_start_time AS 实例启动时间,
    DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) AS 连续运行小时数
FROM sys.dm_os_sys_info;

-- 1.2 实例核心配置参数查询（重点检查内存、最大连接数、恢复模式等）
SELECT
    name AS 配置项名称,
    value AS 当前值,
    value_in_use AS 实际生效值,
    minimum AS 最小值,
    maximum AS 最大值,
    description AS 配置说明
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)', -- 最大内存，需根据服务器配置合理设置
    'min server memory (MB)', -- 最小内存
    'max user connections', -- 最大用户连接数
    'recovery interval (minutes)', -- 恢复间隔
    'backup compression default', -- 备份压缩默认设置
    'remote access', -- 远程访问开关
    'xp_cmdshell', -- xp_cmdshell开关（建议禁用，除非必要）
    'show advanced options' -- 高级选项显示状态
);

-- 1.3 实例服务状态查询（通过系统存储过程检查核心服务）
EXEC master.dbo.xp_servicecontrol 'querystate', 'MSSQLSERVER'; -- 数据库服务状态
EXEC master.dbo.xp_servicecontrol 'querystate', 'SQLSERVERAGENT'; -- 代理服务状态（若启用）
EXEC master.dbo.xp_servicecontrol 'querystate', 'SQLBrowser'; -- Browser服务状态（若启用）

-- 1.4 实例网络配置查询（端口、协议等）
SELECT 
    session_id,
    connect_time,
    net_transport,      -- 网络传输协议 (TCP, Shared Memory等)
    encrypt_option,     -- 是否加密
    client_net_address, -- 客户端IP
    local_net_address,  -- 服务器本地IP
    local_tcp_port      -- 【关键】本地监听的TCP端口
FROM sys.dm_exec_connections; -- TCP协议监听信息

-- 1.5 实例当前连接数查询（排查连接异常）
SELECT
    COUNT(session_id) AS 当前总连接数,
    SUM(CASE WHEN status = 'RUNNABLE' THEN 1 ELSE 0 END) AS 可运行连接数,
    SUM(CASE WHEN status = 'SLEEPING' THEN 1 ELSE 0 END) AS 休眠连接数,
    SUM(CASE WHEN status = 'BLOCKED' THEN 1 ELSE 0 END) AS 被阻塞连接数,
    SUM(CASE WHEN status = 'RUNNING' THEN 1 ELSE 0 END) AS 正在运行连接数
FROM sys.dm_exec_sessions
WHERE session_id > 50; -- 排除系统会话（session_id≤50为系统会话）

-- 二、数据库状态巡检（核心必查）
-- 功能：检查所有数据库（含系统库、用户库）的运行状态、恢复模式、文件状态，排查数据库异常
-- 2.1 所有数据库基本状态查询（重点关注用户库，排除tempdb多个实例）
SELECT
    db.name AS 数据库名称,
    db.database_id AS 数据库ID,
    CASE db.state_desc WHEN 'ONLINE' THEN '正常' ELSE db.state_desc END AS 数据库状态,
    db.recovery_model_desc AS 恢复模式,
    db.collation_name AS 排序规则,
    db.create_date AS 创建时间,
    db.compatibility_level AS 兼容级别,
    CASE db.is_read_only WHEN 1 THEN '只读' ELSE '读写' END AS 读写状态,
    CASE db.is_auto_close_on WHEN 1 THEN '启用' ELSE '禁用' END AS 自动关闭,
    CASE db.is_auto_shrink_on WHEN 1 THEN '启用' ELSE '禁用' END AS 自动收缩, -- 建议禁用
    db.log_reuse_wait_desc AS 日志重用等待原因, -- 排查日志无法收缩的原因
    -- 数据库大小统计（单位：GB）
    CAST(SUM(mf.size) * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS 数据库总大小_GB,
    CAST(SUM(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS 数据文件大小_GB,
    CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS 日志文件大小_GB
FROM sys.databases db
LEFT JOIN sys.master_files mf ON db.database_id = mf.database_id
GROUP BY
    db.name, db.database_id, db.state_desc, db.recovery_model_desc, db.collation_name,
    db.create_date, db.compatibility_level, db.is_read_only, db.is_auto_close_on,
    db.is_auto_shrink_on, db.log_reuse_wait_desc
ORDER BY db.database_id;

-- 2.2 数据库文件详细信息查询（路径、大小、增长方式，排查文件异常）
SELECT
    db.name AS 数据库名称,
    mf.name AS 文件名称,
    mf.physical_name AS 文件物理路径,
    mf.type_desc AS 文件类型, -- ROWS=数据文件，LOG=日志文件
    CAST(mf.size * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS 文件当前大小_GB,
    CAST(mf.max_size * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS 文件最大大小_GB, -- 0=无限制
    CAST(mf.growth AS DECIMAL(10,2)) AS 增长值,
    CASE mf.is_percent_growth WHEN 1 THEN '百分比增长' ELSE '固定大小增长(MB)' END AS 增长方式,
    mf.state_desc AS 文件状态
FROM sys.master_files mf
LEFT JOIN sys.databases db ON mf.database_id = db.database_id
ORDER BY db.name, mf.type_desc;

-- 2.3 数据库可用性检查（针对Always On AG环境，若存在）
SELECT
    ag.name AS 可用性组名称,
    ar.replica_server_name AS 副本服务器名称,
    ar.availability_mode_desc AS 可用性模式,
    ar.failover_mode_desc AS 故障转移模式,
    -- 副本角色（PRIMARY/SECONDARY）
    ars.role_desc AS 副本角色,
    ars.operational_state_desc AS 操作状态, -- 副本层面的状态（如正常、挂起）
    ars.connected_state_desc AS 连接状态,    -- 副本是否已连接
    -- 下面是数据库层面的同步信息（来自 sys.dm_hadr_database_replica_states）
    drs.synchronization_state_desc AS 数据库同步状态, -- 正在同步/已同步
    drs.synchronization_health_desc AS 同步健康状态,
    drs.last_hardened_lsn AS 最后硬化LSN,
    drs.database_id AS 数据库ID -- 用于区分是哪个数据库（如果AG里有多个库）
FROM sys.availability_groups ag
JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
-- 关键修正：关联数据库级视图以获取同步进度
LEFT JOIN sys.dm_hadr_database_replica_states drs ON ars.replica_id = drs.replica_id AND ags.group_id = drs.group_id
ORDER BY ag.name, ar.replica_server_name;

-- 2.4 数据库镜像状态检查（若启用镜像）
IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE database_id > 4)
BEGIN
    SELECT
        db.name AS 数据库名称,
        dm.mirroring_state_desc AS 镜像状态,
        dm.mirroring_role_desc AS 镜像角色,
        dm.mirroring_safety_level_desc AS 安全级别,
        dm.mirroring_partner_name AS 镜像伙伴名称,
        dm.mirroring_partner_instance AS 镜像伙伴实例
    FROM sys.database_mirroring dm
    LEFT JOIN sys.databases db ON dm.database_id = db.database_id
    WHERE db.database_id > 4; -- 排除系统库
END
ELSE
BEGIN
    PRINT '当前实例未启用数据库镜像';
END

-- 2.5 检查可疑数据库（紧急排查项）
SELECT
    name AS 可疑数据库名称,
    state_desc AS 状态,
    recovery_model_desc AS 恢复模式
FROM sys.databases
WHERE state_desc IN ('SUSPECT', 'RECOVERY_PENDING', 'EMERGENCY'); -- 异常状态数据库

-- 三、备份状态巡检（核心必查）
-- 功能：检查最近备份执行情况、备份文件有效性，确保备份策略正常执行，避免数据丢失风险
-- 3.1 最近备份记录查询（按数据库分组，显示最近3次备份）
WITH BackupHistory AS (
    SELECT
        db.name AS 数据库名称,
        b.type AS 备份类型, -- D=完整备份，I=差异备份，L=日志备份
        CASE b.type WHEN 'D' THEN '完整备份' WHEN 'I' THEN '差异备份' WHEN 'L' THEN '日志备份' ELSE '其他' END AS 备份类型描述,
        b.backup_start_date AS 备份开始时间,
        b.backup_finish_date AS 备份结束时间,
        DATEDIFF(SECOND, b.backup_start_date, b.backup_finish_date) AS 备份耗时_秒,
        CAST(b.backup_size / 1024 / 1024 AS DECIMAL(10,2)) AS 备份大小_MB,
        b.backup_set_id AS 备份集ID,
        b.media_set_id AS 介质集ID,
        b.user_name AS 备份执行用户,
        b.server_name AS 备份服务器,
        -- 按备份时间降序排序，标记序号
        ROW_NUMBER() OVER (PARTITION BY db.name, b.type ORDER BY b.backup_finish_date DESC) AS 备份序号
    FROM msdb.dbo.backupset b
    LEFT JOIN sys.databases db ON b.database_name = db.name
    WHERE b.backup_start_date > DATEADD(DAY, -7, GETDATE()) -- 只查最近7天的备份
)
SELECT
    数据库名称,
    备份类型描述,
    备份开始时间,
    备份结束时间,
    备份耗时_秒,
    备份大小_MB,
    备份执行用户
FROM BackupHistory
WHERE 备份序号 <= 3 -- 显示最近3次备份
ORDER BY 数据库名称, 备份类型, 备份结束时间 DESC;

-- 3.2 检查未备份的数据库（重点排查用户库）
SELECT
    db.name AS 未备份数据库名称,
    db.recovery_model_desc AS 恢复模式,
    '无最近备份记录' AS 异常说明
FROM sys.databases db
LEFT JOIN msdb.dbo.backupset b ON db.name = b.database_name
WHERE
    db.database_id > 4 -- 排除系统库
    AND (b.backup_finish_date IS NULL OR b.backup_finish_date < DATEADD(DAY, -1, GETDATE())) -- 超过1天未备份
    AND db.state_desc = 'ONLINE'; -- 仅检查在线数据库

-- 3.3 备份文件有效性检查（验证最近一次完整备份是否可用）
DECLARE @DBName NVARCHAR(128), @BackupPath NVARCHAR(500);

DECLARE BackupCursor CURSOR FOR
SELECT
    db.name,
    bmf.physical_device_name AS 最近完整备份路径 -- 修正：从 backupmediafamily 表获取
FROM sys.databases db
-- 1. 关联 backupset 获取备份集信息
JOIN msdb.dbo.backupset bs ON db.name = bs.database_name AND bs.type = 'D'
-- 2. 关联 backupmediafamily 获取物理文件路径
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE db.database_id > 4 
  AND db.state_desc = 'ONLINE'
  -- 3. 确保获取的是“最近一次”备份（通过子查询或窗口函数过滤）
  AND bs.backup_finish_date = (
      SELECT MAX(backup_finish_date) 
      FROM msdb.dbo.backupset 
      WHERE database_name = db.name AND type = 'D'
  )
ORDER BY db.name;

OPEN BackupCursor;
FETCH NEXT FROM BackupCursor INTO @DBName, @BackupPath;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '数据库: ' + @DBName + ' | 备份路径: ' + ISNULL(@BackupPath, '无备份记录');
    -- 在这里写你的后续逻辑，例如：RESTORE VERIFYONLY...
    FETCH NEXT FROM BackupCursor INTO @DBName, @BackupPath;
END

CLOSE BackupCursor;
DEALLOCATE BackupCursor;

-- 3.4 备份设备检查（若使用备份设备，检查设备状态）
IF EXISTS (SELECT 1 FROM msdb.dbo.backupmediafamily)
BEGIN
    SELECT
        mf.media_set_id AS 介质集ID,
        mf.physical_device_name AS 备份设备路径,
        ms.backup_start_date AS 最近备份时间,
        ms.database_name AS 备份数据库,
        CASE ms.type WHEN 'D' THEN '完整备份' WHEN 'I' THEN '差异备份' WHEN 'L' THEN '日志备份' ELSE '其他' END AS 备份类型
    FROM msdb.dbo.backupmediafamily mf
    LEFT JOIN msdb.dbo.backupset ms ON mf.media_set_id = ms.media_set_id
    GROUP BY mf.media_set_id, mf.physical_device_name, ms.backup_start_date, ms.database_name, ms.type
    ORDER BY mf.media_set_id, ms.backup_start_date DESC;
END
ELSE
BEGIN
    PRINT '当前实例未使用备份设备，备份均为文件备份';
END

-- 四、存储资源巡检（核心必查）
-- 功能：检查数据库所在磁盘空间、文件增长情况，避免磁盘满导致数据库异常
-- 4.1 磁盘空间使用情况查询（通过xp_fixeddrives，需启用xp_cmdshell，若禁用可手动查询）
IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'xp_cmdshell' AND value_in_use = 1)
BEGIN
    -- 1. 创建临时表存储 xp_fixeddrives 的结果
    CREATE TABLE #DiskSpace (
        Drive CHAR(1),
        FreeSpaceMB INT
    );

    -- 2. 独立执行存储过程插入数据
    INSERT INTO #DiskSpace (Drive, FreeSpaceMB)
    EXEC master.dbo.xp_fixeddrives;

    -- 3. 查询并计算
    SELECT
        Drive AS 磁盘盘符,
        FreeSpaceMB AS 剩余空间_MB,
        CAST(FreeSpaceMB / 1024.0 AS DECIMAL(10,2)) AS 剩余空间_GB,
        '建议重点关注剩余空间是否低于 20GB' AS 建议
    FROM #DiskSpace
    WHERE FreeSpaceMB < 20480 -- 举例：如果剩余空间小于 20GB，显示出来（可选过滤）
    ORDER BY Drive;

    -- 4. 清理临时表
    DROP TABLE #DiskSpace;
END
ELSE
BEGIN
    PRINT 'xp_cmdshell 已禁用，无法直接查询磁盘空间。';
    PRINT '请手动检查服务器磁盘，或使用 SSMS 报表查看。';
END

-- 4.2 数据库文件空间使用详情（排查文件过大、空间浪费）
SET NOCOUNT ON;

DECLARE @DBID INT;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @DBName SYSNAME;

-- 1. 创建一个临时表来存放 DBCC SQLPERF 的结果
IF OBJECT_ID('tempdb..#LogSpaceInfo') IS NOT NULL DROP TABLE #LogSpaceInfo;
CREATE TABLE #LogSpaceInfo (
    DatabaseName sysname,
    LogSizeMB DECIMAL(10,2),
    LogUsedPercent DECIMAL(5,2),
    Status INT
);

-- 2. 声明游标
DECLARE DBCursor CURSOR FOR
SELECT database_id, name 
FROM sys.databases 
WHERE state_desc = 'ONLINE' AND database_id > 4;

OPEN DBCursor;
FETCH NEXT FROM DBCursor INTO @DBID, @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '------------------------------ 数据库ID：' + CAST(@DBID AS VARCHAR(10)) + ' (' + @DBName + ') ------------------------------';

    -- 3. 构建动态 SQL
    SET @SQL = N'
    USE [' + @DBName + N'];
    
    -- 3.1 清空临时表并重新获取日志信息
    TRUNCATE TABLE #LogSpaceInfo;
    INSERT INTO #LogSpaceInfo (DatabaseName, LogSizeMB, LogUsedPercent, Status)
    EXEC (''DBCC SQLPERF(LOGSPACE)'');

    -- 3.2 声明变量获取当前库的日志使用率
    DECLARE @CurrentLogUsedPercent DECIMAL(5,2);
    SELECT @CurrentLogUsedPercent = LogUsedPercent 
    FROM #LogSpaceInfo 
    WHERE DatabaseName = ''' + @DBName + ''';

    -- 3.3 查询数据文件
    SELECT
        name AS 数据文件名称,
        physical_name AS 文件路径,
        CAST(size * 8.0 / 1024 AS DECIMAL(10,2)) AS 文件总大小_MB,
        CAST(FILEPROPERTY(name, ''SpaceUsed'') * 8.0 / 1024 AS DECIMAL(10,2)) AS 文件已使用大小_MB,
        CAST((size - FILEPROPERTY(name, ''SpaceUsed'')) * 8.0 / 1024 AS DECIMAL(10,2)) AS 文件空闲大小_MB,
        CAST(FILEPROPERTY(name, ''SpaceUsed'') * 100.0 / NULLIF(size, 0) AS DECIMAL(5,2)) AS 空间使用率,
        CASE WHEN CAST(FILEPROPERTY(name, ''SpaceUsed'') * 100.0 / NULLIF(size, 0) AS DECIMAL(5,2)) > 90 THEN ''警告：空间使用率过高'' ELSE ''正常'' END AS 状态
    FROM sys.database_files
    WHERE type_desc = ''ROWS'';

    -- 3.4 查询日志文件 (使用 DBCC 获取的百分比)
    SELECT
        name AS 日志文件名称,
        physical_name AS 文件路径,
        CAST(size * 8.0 / 1024 AS DECIMAL(10,2)) AS 文件总大小_MB,
        CAST((size * 8.0 / 1024) * (@CurrentLogUsedPercent / 100.0) AS DECIMAL(10,2)) AS 日志已使用大小_MB,
        CAST((size * 8.0 / 1024) * (1 - @CurrentLogUsedPercent / 100.0) AS DECIMAL(10,2)) AS 日志空闲大小_MB,
        @CurrentLogUsedPercent AS 日志使用率,
        CASE WHEN ISNULL(@CurrentLogUsedPercent, 0) > 80 THEN ''警告：日志使用率过高'' ELSE ''正常'' END AS 状态
    FROM sys.database_files
    WHERE type_desc = ''LOG'';
    ';

    BEGIN TRY
        EXEC sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        PRINT '错误发生在数据库: ' + @DBName + ' - ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM DBCursor INTO @DBID, @DBName;
END

-- 4. 清理资源
CLOSE DBCursor;
DEALLOCATE DBCursor;
DROP TABLE #LogSpaceInfo;

-- 4.3 检查磁盘空间不足的数据库文件（预警项）
SELECT
    db.name AS 数据库名称,
    mf.name AS 文件名称,
    mf.physical_name AS 文件路径,
    mf.type_desc AS 文件类型,
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(10,2)) AS 文件总大小_MB,
    CAST((mf.size - FILEPROPERTY(mf.name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(10,2)) AS 空闲大小_MB,
    CAST(FILEPROPERTY(mf.name, 'SpaceUsed') * 100.0 / mf.size AS DECIMAL(5,2)) AS '使用率_%',
    '警告：空间使用率过高，需及时扩容或清理' AS 预警信息
FROM sys.master_files mf
LEFT JOIN sys.databases db ON mf.database_id = db.database_id
WHERE
    db.state_desc = 'ONLINE'
    AND CAST(FILEPROPERTY(mf.name, 'SpaceUsed') * 100.0 / mf.size AS DECIMAL(5,2)) > 90; -- 使用率超过90%预警

--五、性能监控巡检（核心必查）
-- 功能：检查CPU、内存、IO、会话阻塞、慢查询等，排查性能瓶颈，确保数据库运行流畅
-- 5.1 服务器资源使用情况（CPU、内存、IO）
SELECT 
    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
    100 - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS CPU使用率_百分比
FROM (
    SELECT TOP 1 CONVERT(XML, record) AS record 
    FROM sys.dm_os_ring_buffers 
    WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' 
    AND record LIKE '%<SystemHealth>%'
    ORDER BY timestamp DESC
) AS t;
SELECT 
    CAST(total_physical_memory_kb / 1024.0 AS DECIMAL(10,2)) AS 服务器总内存_GB,
    CAST(available_physical_memory_kb / 1024.0 AS DECIMAL(10,2)) AS 服务器可用内存_GB,
    CAST(100.0 - (available_physical_memory_kb * 100.0 / total_physical_memory_kb) AS DECIMAL(5,2)) AS 内存使用率_百分比
FROM sys.dm_os_sys_memory;
SELECT 
    sqlserver_start_time AS 实例启动时间,
    DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) AS 已运行小时数
FROM sys.dm_os_sys_info;

-- 5.2 会话阻塞检查（重点排查长期阻塞）
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
    r.wait_time DESC; -- 阻塞持续超过10秒，需关注

-- 5.3 慢查询检查（查询执行时间超过30秒的语句）
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
    DATEDIFF(SECOND, r.start_time, GETDATE()) > 30 -- 执行时间超过30秒
    AND r.session_id > 50; -- 排除系统会话

-- 5.4 缓存使用情况（排查缓存命中率，优化内存配置）
SELECT
    COUNT(*) AS 缓存计划总数,
    -- 先转换为 BIGINT 再求和，防止溢出
    SUM(CAST(usecounts AS BIGINT)) AS 缓存计划总使用次数,
    -- 先转换为 BIGINT 再求和
    CAST(SUM(CAST(size_in_bytes AS BIGINT)) / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS 缓存总大小_MB,
    
    -- 修正缓存命中率计算逻辑
    (SELECT TOP 1 
        CAST(a.cntr_value * 100.0 / b.cntr_value AS DECIMAL(5,2))
     FROM sys.dm_os_performance_counters a
     JOIN sys.dm_os_performance_counters b 
       ON a.counter_name = 'Buffer cache hit ratio'
      AND b.counter_name = 'Buffer cache hit ratio base'
      AND a.object_name = b.object_name
     WHERE a.object_name LIKE '%Buffer Manager%') AS 缓存命中率,

    -- 状态判断
    CASE 
        WHEN (SELECT TOP 1 CAST(a.cntr_value * 100.0 / b.cntr_value AS DECIMAL(5,2))
              FROM sys.dm_os_performance_counters a
              JOIN sys.dm_os_performance_counters b 
                ON a.counter_name = 'Buffer cache hit ratio'
               AND b.counter_name = 'Buffer cache hit ratio base'
               AND a.object_name = b.object_name
              WHERE a.object_name LIKE '%Buffer Manager%') < 90 
        THEN '警告：缓存命中率过低' 
        ELSE '正常' 
    END AS 状态
FROM sys.dm_exec_cached_plans;

-- 5.5 等待类型检查（排查主要等待事件，定位性能瓶颈）
SELECT
    COUNT(*) AS 缓存计划总数,
    SUM(CAST(usecounts AS BIGINT)) AS 缓存计划总使用次数,
    -- 缓存总大小：改用 DECIMAL(28,2)，最大支持数千亿 MB
    CAST(SUM(CAST(size_in_bytes AS BIGINT)) / 1024.0 / 1024.0 AS DECIMAL(28,2)) AS 缓存总大小_MB,
    
    -- 命中率计算：这里改用更稳妥的精度
    (SELECT TOP 1 
        CAST(a.cntr_value * 100.0 / NULLIF(b.cntr_value, 0) AS DECIMAL(10,2))
     FROM sys.dm_os_performance_counters a
     JOIN sys.dm_os_performance_counters b 
       ON a.counter_name = 'Buffer cache hit ratio'
      AND b.counter_name = 'Buffer cache hit ratio base'
      AND a.object_name = b.object_name
     WHERE a.object_name LIKE '%Buffer Manager%') AS 缓存命中率,

    CASE 
        WHEN (SELECT TOP 1 a.cntr_value * 100.0 / NULLIF(b.cntr_value, 0)
              FROM sys.dm_os_performance_counters a
              JOIN sys.dm_os_performance_counters b 
                ON a.counter_name = 'Buffer cache hit ratio'
               AND b.counter_name = 'Buffer cache hit ratio base'
              WHERE a.object_name LIKE '%Buffer Manager%') < 90 
        THEN '警告：缓存命中率过低' 
        ELSE '正常' 
    END AS 状态
FROM sys.dm_exec_cached_plans;

-- 六、索引与碎片巡检（优化必查）
-- 功能：检查索引碎片情况、无效索引，优化索引性能，提升查询效率
-- 6.1 索引碎片查询（按碎片率排序，建议定期重建/重组）
SET NOCOUNT ON;

DECLARE @DBID_Index INT;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @DBName SYSNAME;

-- 声明游标
DECLARE DBIndexCursor CURSOR FOR
SELECT database_id, name 
FROM sys.databases 
WHERE state_desc = 'ONLINE' AND database_id > 4;

OPEN DBIndexCursor;
FETCH NEXT FROM DBIndexCursor INTO @DBID_Index, @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '------------------------------ 数据库ID：' + CAST(@DBID_Index AS VARCHAR(10)) + ' (' + @DBName + ') 索引碎片情况 ------------------------------';

    -- 使用 sp_executesql 进行参数化查询，避免字符串拼接导致的语法错误
    SET @SQL = N'
    USE [' + @DBName + N']; -- 切换上下文

    SELECT
        OBJECT_NAME(s.object_id) AS 表名称,
        i.name AS 索引名称,
        i.type_desc AS 索引类型,
        s.index_type_desc AS 索引类型描述,
        s.avg_fragmentation_in_percent AS 平均碎片率,
        s.page_count AS 索引页数,
        -- 碎片处理建议
        CASE
            WHEN s.avg_fragmentation_in_percent < 5 THEN ''无需处理''
            WHEN s.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN ''建议重组索引（REORGANIZE）''
            WHEN s.avg_fragmentation_in_percent > 30 THEN ''建议重建索引（REBUILD）''
            ELSE ''无需处理''
        END AS 处理建议
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''DETAILED'') s
    LEFT JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
    WHERE
        s.index_id > 0 -- 排除堆表
        AND s.page_count > 100 -- 仅检查页数>100的索引
    ORDER BY s.avg_fragmentation_in_percent DESC;';

    BEGIN TRY
        EXEC sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        PRINT '检查数据库 ' + @DBName + ' 时出错: ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM DBIndexCursor INTO @DBID_Index, @DBName;
END

CLOSE DBIndexCursor;
DEALLOCATE DBIndexCursor;

-- 6.2 无效索引查询（从未使用或使用率极低的索引，可考虑删除）
SELECT
    DB_NAME(s.database_id) AS 数据库名称,
    OBJECT_NAME(s.object_id, s.database_id) AS 表名称, -- 修改点1: 指定 s.object_id 并传入 database_id
    i.name AS 索引名称,
    s.user_seeks AS 索引查找次数,
    s.user_scans AS 索引扫描次数,
    s.user_lookups AS 索引查找次数,
    s.user_updates AS 索引更新次数,
    -- 索引使用率判断
    CASE 
        WHEN s.user_seeks + s.user_scans + s.user_lookups = 0 THEN '从未使用'
        WHEN (s.user_seeks + s.user_scans + s.user_lookups) / NULLIF(s.user_updates, 0) < 0.1 THEN '使用率极低'
        ELSE '正常使用' 
    END AS 索引使用状态
FROM sys.dm_db_index_usage_stats s
LEFT JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE
    s.database_id > 4 -- 排除系统库
    AND i.type_desc <> 'HEAP' -- 排除堆表
    AND (s.user_seeks + s.user_scans + s.user_lookups = 0 OR (s.user_seeks + s.user_scans + s.user_lookups) / NULLIF(s.user_updates, 0) < 0.1)
ORDER BY s.database_id, s.user_seeks + s.user_scans + s.user_lookups ASC;

-- 6.3 缺失索引建议（SQL Server自动推荐的缺失索引，提升查询性能）
SELECT
    DB_NAME(mid.database_id) AS 数据库名称,
    OBJECT_NAME(mid.object_id) AS 表名称,
    mid.equality_columns AS 等值条件列,
    mid.inequality_columns AS 非等值条件列,
    mid.included_columns AS 包含列,
    migs.user_seeks AS 查找次数,
    migs.user_scans AS 扫描次数,
    migs.avg_total_user_cost AS 平均用户成本,
    migs.avg_user_impact AS 平均影响度,
    -- 缺失索引创建语句（可直接复制执行）
    'CREATE NONCLUSTERED INDEX IX_' + OBJECT_NAME(mid.object_id) + '_' + REPLACE(REPLACE(mid.equality_columns + ISNULL(',' + mid.inequality_columns, ''), '[', ''), ']', '') + 
    ' ON ' + QUOTENAME(DB_NAME(mid.database_id)) + '.' + QUOTENAME(OBJECT_SCHEMA_NAME(mid.object_id)) + '.' + QUOTENAME(OBJECT_NAME(mid.object_id)) +
    ' (' + ISNULL(mid.equality_columns, '') + ISNULL(',' + mid.inequality_columns, '') + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS 缺失索引创建语句
FROM sys.dm_db_missing_index_groups mig
LEFT JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
LEFT JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_user_impact > 30 -- 仅显示影响度>30%的缺失索引
ORDER BY migs.avg_user_impact DESC;

-- 七、安全与权限巡检（核心必查）
-- 功能：检查登录账号、数据库用户、权限配置，排查安全风险，确保数据库安全
-- 7.1 登录账号检查（排查异常登录、弱密码账号）
SELECT
    sp.name AS 登录账号名称,
    sp.type_desc AS 账号类型,
    sp.is_disabled AS 是否禁用,
    sp.create_date AS 账号创建时间,
    sp.modify_date AS 账号修改时间,
    -- 密码状态：通过关联 sys.sql_logins 判断是否为 SQL 账号
    CASE WHEN sl.name IS NOT NULL THEN 'SQL账号(有密码)' ELSE 'Windows账号' END AS 密码状态,
    -- 弱密码/弱账号名检查
    CASE 
        WHEN sp.name IN ('sa', 'admin', 'root', 'test', 'guest') THEN '警告：使用默认或弱账号名'
        WHEN sp.name LIKE '%admin%' OR sp.name LIKE '%sa%' THEN '提示：账号名包含敏感词'
        WHEN sl.name IS NOT NULL THEN '已设置密码' -- 无法直接检测密码复杂度，只能确认有密码
        ELSE 'Windows集成认证' 
    END AS 安全状态,
    -- 权限检查：通过关联 sys.server_role_members 判断是否为 sysadmin
    CASE 
        WHEN srm.role_principal_id IS NOT NULL THEN '具备sysadmin权限（高危）'
        ELSE '普通权限' 
    END AS 服务器权限
FROM sys.server_principals sp
-- 关联 SQL 登录名视图，用于确认是否为 SQL 账号
LEFT JOIN sys.sql_logins sl ON sp.principal_id = sl.principal_id
-- 关联服务器角色成员视图，专门筛选 sysadmin 角色 (role_principal_id = 1 代表 sysadmin)
LEFT JOIN sys.server_role_members srm ON sp.principal_id = srm.member_principal_id AND srm.role_principal_id = 1
WHERE
    sp.type IN ('S', 'G', 'U') -- S=SQL登录，G=Windows组，U=Windows用户
    AND sp.name NOT LIKE 'NT AUTHORITY\%' -- 排除系统内置账号
    AND sp.name NOT LIKE 'BUILTIN\%';

-- 7.2 数据库用户权限检查（排查过高权限用户）
SET NOCOUNT ON;

DECLARE @DBID_Security INT;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @DBName SYSNAME;

-- 声明游标
DECLARE DBSecurityCursor CURSOR FOR
SELECT database_id, name 
FROM sys.databases 
WHERE state_desc = 'ONLINE' AND database_id > 4;

OPEN DBSecurityCursor;
FETCH NEXT FROM DBSecurityCursor INTO @DBID_Security, @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '------------------------------ 数据库ID：' + CAST(@DBID_Security AS VARCHAR(10)) + ' (' + @DBName + ') 用户权限情况 ------------------------------';

    -- 使用 sp_executesql 进行参数化查询，避免字符串拼接错误
    SET @SQL = N'
    USE [' + @DBName + N'];

    -- 使用子查询和 sys.database_role_members 来准确判断每个用户的角色
    SELECT
        dp.name AS 数据库用户名,
        dp.type_desc AS 用户类型,
        dp.create_date AS 创建时间,
        -- 数据库角色权限
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM sys.database_role_members drm 
                JOIN sys.database_principals drp ON drm.role_principal_id = drp.principal_id 
                WHERE drm.member_principal_id = dp.principal_id AND drp.name = ''db_owner''
            ) THEN ''具备db_owner权限（高危）''
            WHEN EXISTS (
                SELECT 1 
                FROM sys.database_role_members drm 
                JOIN sys.database_principals drp ON drm.role_principal_id = drp.principal_id 
                WHERE drm.member_principal_id = dp.principal_id AND drp.name = ''db_ddladmin''
            ) THEN ''具备db_ddladmin权限''
            WHEN EXISTS (
                SELECT 1 
                FROM sys.database_role_members drm 
                JOIN sys.database_principals drp ON drm.role_principal_id = drp.principal_id 
                WHERE drm.member_principal_id = dp.principal_id AND drp.name = ''db_datawriter''
            ) THEN ''具备db_datawriter权限''
            WHEN EXISTS (
                SELECT 1 
                FROM sys.database_role_members drm 
                JOIN sys.database_principals drp ON drm.role_principal_id = drp.principal_id 
                WHERE drm.member_principal_id = dp.principal_id AND drp.name = ''db_datareader''
            ) THEN ''具备db_datareader权限''
            ELSE ''普通权限或无角色'' 
        END AS 数据库权限,
        -- 关联登录账号
        sp.name AS 关联登录账号
    FROM sys.database_principals dp
    LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE
        dp.type IN (''S'', ''U'', ''G'') -- S=SQL用户，U=Windows用户，G=Windows组
        AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys''); -- 排除系统内置用户';

    BEGIN TRY
        EXEC sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        PRINT '检查数据库 ' + @DBName + ' 时出错: ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM DBSecurityCursor INTO @DBID_Security, @DBName;
END

CLOSE DBSecurityCursor;
DEALLOCATE DBSecurityCursor;

-- 7.3 服务器角色成员检查（排查高危角色成员）
SELECT
    sr.name AS 服务器角色名称,
    sp.name AS 角色成员账号,
    sp.type_desc AS 账号类型,
    CASE WHEN sr.name IN ('sysadmin', 'serveradmin', 'dbcreator') THEN '高危角色，需严格管控' ELSE '普通角色' END AS 角色风险等级
FROM sys.server_role_members srm
-- 修正点：使用 sys.server_principals 并筛选 type = 'R' 来获取角色信息
LEFT JOIN sys.server_principals sr ON srm.role_principal_id = sr.principal_id AND sr.type = 'R'
LEFT JOIN sys.server_principals sp ON srm.member_principal_id = sp.principal_id
WHERE sr.name IN ('sysadmin', 'serveradmin', 'dbcreator', 'securityadmin', 'processadmin');

-- 7.4 登录审计（检查最近登录失败、异常登录记录）
SELECT
    login_name AS 登录账号,
    session_id AS 会话ID,
    status AS 登录状态,
    login_time AS 登录时间,
    host_name AS 客户端主机名,
    program_name AS 应用程序名称,
    client_interface_name AS 客户端接口,
    -- 登录失败原因
    CASE WHEN status = 'FAILED' THEN '登录失败，可能密码错误或权限不足' ELSE '登录成功' END AS 登录说明
FROM sys.dm_exec_sessions
WHERE login_time > DATEADD(HOUR, -24, GETDATE()) -- 最近24小时登录记录
ORDER BY login_time DESC;

-- 7.5 权限异常检查（排查非授权的高权限访问）
SELECT
    dp.name AS 数据库用户,
    OBJECT_NAME(perm.major_id) AS 对象名称,
    perm.permission_name AS 权限名称,
    perm.state_desc AS 权限状态,
    '警告：非授权高权限，需核查' AS 预警信息
FROM sys.database_permissions perm
LEFT JOIN sys.database_principals dp ON perm.grantee_principal_id = dp.principal_id
WHERE
    perm.permission_name IN ('ALTER ANY TABLE', 'DROP ANY TABLE', 'ALTER ANY DATABASE', 'CONTROL')
    AND dp.name NOT IN ('dbo', 'sa') -- 排除合法高权限用户
    AND dp.type_desc NOT IN ('SERVER_ROLE', 'DATABASE_ROLE'); -- 排除系统角色

-- 八、日志检查巡检（核心必查）
-- 功能：检查SQL Server错误日志、数据库日志，排查异常报错、故障记录
-- 8.1 SQL Server错误日志查询（最近24小时的错误、警告记录）
DECLARE @StartTime DATETIME = DATEADD(HOUR, -24, GETDATE());
DECLARE @EndTime DATETIME = GETDATE();

EXEC master.dbo.sp_readerrorlog 
    0,          -- 日志文件：0=当前
    1,          
    @StartTime, -- 开始时间
    @EndTime    -- 结束时间
    -- 说明：sp_readerrorlog 参数说明
-- 0：当前日志，1：上一个日志，2：上上个日志，以此类推
-- 1：按错误日志类型筛选（1=错误日志，2=SQL Agent日志）
-- 第三个参数：搜索关键词（NULL=不筛选）
-- 第四个参数：搜索关键词（NULL=不筛选）
-- 第五个参数：开始时间
-- 第六个参数：结束时间
-- 第七个参数：排序方式（ASC=升序，DESC=降序）

-- 8.2 数据库错误日志查询（排查数据库级别的错误）
SET NOCOUNT ON;

DECLARE @DBID_Log INT;
DECLARE @DBName SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

-- 声明游标
DECLARE DBLogCursor CURSOR FOR
SELECT database_id, name 
FROM sys.databases 
WHERE state_desc = 'ONLINE' AND database_id > 4;

OPEN DBLogCursor;
FETCH NEXT FROM DBLogCursor INTO @DBID_Log, @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '------------------------------ 数据库ID：' + CAST(@DBID_Log AS VARCHAR(10)) + ' (' + @DBName + ') 错误日志 ------------------------------';

    -- 使用 sp_readerrorlog 查询SQL Server错误日志
    -- 通过搜索字符串 '@DBName' 来筛选与当前数据库相关的日志
    SET @SQL = N'
    EXEC master.dbo.sp_readerrorlog 
        0,                  -- 读取当前错误日志
        1                 -- SQL Server 日志';        -- 降序排列

    BEGIN TRY
        EXEC sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        PRINT '检查数据库 ' + @DBName + ' 时出错: ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM DBLogCursor INTO @DBID_Log, @DBName;
END

CLOSE DBLogCursor;
DEALLOCATE DBLogCursor;

-- 8.3 检查数据库恢复日志（排查恢复异常）
SELECT
    rh.destination_database_name AS 数据库名称,
    rh.restore_date AS 恢复时间,
    rh.user_name AS 恢复执行用户,
    CASE bs.type
        WHEN 'D' THEN '完整数据库'
        WHEN 'I' THEN '差异数据库'
        WHEN 'L' THEN '事务日志'
        WHEN 'F' THEN '文件或文件组'
        ELSE '其他'
    END AS 恢复类型描述,
    bs.server_name AS 备份来源服务器
FROM msdb.dbo.restorehistory rh
-- 关联 backupset 表以获取备份类型和来源服务器等详细信息
LEFT JOIN msdb.dbo.backupset bs ON rh.backup_set_id = bs.backup_set_id
WHERE rh.restore_date > DATEADD(DAY, -7, GETDATE()) -- 查询最近7天的记录
ORDER BY rh.restore_date DESC;

-- 8.4 检查死锁日志（排查死锁异常，需启用死锁跟踪）
SELECT 
    xdr.value('(/event/@timestamp)[1]', 'datetime') AS [死锁发生时间],
    xdr.query('(event/data[@name="xml_report"]/value/deadlock)[1]') AS [死锁XML详情]
FROM 
    (
        SELECT CAST(target_data AS XML) AS TargetData
        FROM sys.dm_xe_session_targets st
        INNER JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
        WHERE s.name = 'system_health' 
          AND st.target_name = 'ring_buffer'
    ) AS Data
CROSS APPLY 
    TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(xdr)
ORDER BY 
    [死锁发生时间] DESC;

-- 九、系统相关巡检（辅助必查）
-- 功能：检查SQL Agent作业、扩展存储过程、系统配置等，确保数据库周边环境正常
-- 9.1 SQL Agent作业状态检查（排查作业执行失败、未执行情况）
SELECT
    j.name AS 作业名称,
    CASE j.enabled WHEN 1 THEN '是' ELSE '否' END AS 作业是否启用,
    j.description AS 作业描述,
    j.date_created AS 作业创建时间,
    j.date_modified AS 作业修改时间,
    
    -- 最近一次执行情况
    CASE 
        WHEN js.last_run_date = 0 THEN '从未执行' 
        ELSE '已执行' 
    END AS 执行状态,
    
    -- 格式化最近执行时间
    CASE WHEN js.last_run_date = 0 THEN NULL
         ELSE CAST(CAST(js.last_run_date AS CHAR(8)) + ' ' + 
             STUFF(STUFF(RIGHT('000000' + CAST(js.last_run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS DATETIME)
    END AS 最近执行时间,
    
    -- 执行结果
    CASE js.last_run_outcome 
        WHEN 0 THEN '失败（需排查）' 
        WHEN 1 THEN '成功' 
        WHEN 2 THEN '重试' 
        WHEN 3 THEN '取消' 
        ELSE '未知' 
    END AS 执行结果描述,
    
    -- 运行持续时间
    STUFF(STUFF(RIGHT('000000' + CAST(js.last_run_duration AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS 上次运行耗时,

    -- 下次执行计划 (修正：字段来自 sysjobschedules 表，别名 jsch)
    CASE WHEN jsch.next_run_date = 0 THEN NULL
         ELSE CAST(CAST(jsch.next_run_date AS CHAR(8)) + ' ' + 
             STUFF(STUFF(RIGHT('000000' + CAST(jsch.next_run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS DATETIME)
    END AS 下次执行时间,
    
    -- 计划名称 (来自 sysschedules 表)
    ISNULL(sch.name, '无计划') AS 计划名称

FROM msdb.dbo.sysjobs j
-- 关联服务器信息（包含上次运行结果）
LEFT JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
-- 关联计划信息（包含下次运行时间）
LEFT JOIN msdb.dbo.sysjobschedules jsch ON j.job_id = jsch.job_id
-- 关联具体的计划定义（获取计划名称等）
LEFT JOIN msdb.dbo.sysschedules sch ON jsch.schedule_id = sch.schedule_id

ORDER BY j.enabled DESC, js.last_run_outcome ASC;

-- 9.2 扩展存储过程检查（排查异常扩展存储过程，防范安全风险）
SELECT
    name AS 扩展存储过程名称,
    type_desc AS 类型描述,
    create_date AS 创建时间,
    modify_date AS 修改时间,
    CASE WHEN name LIKE 'xp_%' AND name NOT IN ('xp_servicecontrol', 'xp_fixeddrives') THEN '警告：未知扩展存储过程，需核查' ELSE '正常' END AS 安全状态
FROM sys.system_objects
WHERE type = 'X' -- X=扩展存储过程
ORDER BY name;

-- 9.3 数据库链接服务器检查（排查异常链接服务器）
IF EXISTS (SELECT 1 FROM sys.servers WHERE server_id > 0)
BEGIN
    SELECT
        name AS 链接服务器名称,
        product AS 产品类型,
        data_source AS 数据源,
        provider AS 提供程序,
        is_linked AS 是否启用,
        modify_date AS 最后修改时间,
        CASE WHEN is_linked = 1 AND data_source NOT IN ('localhost', '127.0.0.1') THEN '需确认链接服务器合法性' ELSE '正常' END AS 状态
    FROM sys.servers
    WHERE server_id > 0; -- 排除本地服务器
END
ELSE
BEGIN
    PRINT '当前实例未配置链接服务器';
END

-- 9.4 系统触发器检查（排查异常系统触发器）
SELECT 
    name AS 触发器名称,
    parent_class_desc AS 父类描述,
    create_date AS 创建时间,
    modify_date AS 修改时间,
    is_disabled AS 是否禁用,
    OBJECT_DEFINITION(object_id) AS 触发器定义 -- 使用函数获取定义
FROM sys.server_triggers
WHERE type = 'TR';

-- 9.5 检查数据库自动统计信息更新情况（确保统计信息最新，优化查询性能）
SELECT 
    DB_NAME() AS 数据库名称,          -- 获取当前数据库名称
    OBJECT_NAME(s.object_id) AS 表名称, -- 获取表名
    s.name AS 统计信息名称,           -- 从 sys.stats 获取统计信息名称
    sp.last_updated AS 最后更新时间,
    sp.rows AS 行数,
    sp.rows_sampled AS 采样行数,
    sp.modification_counter AS 修改次数, -- 自上次更新后的修改次数
    CASE 
        WHEN DATEDIFF(DAY, sp.last_updated, GETDATE()) > 7 THEN '警告：超过7天未更新'
        WHEN sp.modification_counter > 1000 THEN '警告：修改次数过多，建议更新'
        ELSE '正常' 
    END AS 状态
FROM sys.stats s
-- 关联动态管理函数获取详细属性
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1 -- 仅查询用户表
ORDER BY sp.last_updated ASC;

-- 十、异常汇总（巡检收尾）
-- 功能：汇总本次巡检所有异常项，便于快速定位和处理问题
-- 异常汇总查询（执行此脚本，直接输出所有异常项，无需手动筛选）
PRINT '==================================== 本次巡检异常汇总 ====================================';

-- 1. 异常状态数据库
IF EXISTS (SELECT 1 FROM sys.databases WHERE state_desc IN ('SUSPECT', 'RECOVERY_PENDING', 'EMERGENCY'))
BEGIN
    PRINT '【异常1：可疑/异常状态数据库】';
    SELECT name AS 异常数据库名称, state_desc AS 状态 FROM sys.databases WHERE state_desc IN ('SUSPECT', 'RECOVERY_PENDING', 'EMERGENCY');
END
ELSE
BEGIN
    PRINT '【异常1：可疑/异常状态数据库】无异常';
END

-- 2. 未备份数据库
IF EXISTS (SELECT 1 FROM sys.databases db LEFT JOIN msdb.dbo.backupset b ON db.name = b.database_name WHERE db.database_id > 4 AND (b.backup_finish_date IS NULL OR b.backup_finish_date < DATEADD(DAY, -1, GETDATE())) AND db.state_desc = 'ONLINE')
BEGIN
    PRINT CHAR(13) + '【异常2：未及时备份数据库】';
    SELECT db.name AS 未备份数据库名称 FROM sys.databases db LEFT JOIN msdb.dbo.backupset b ON db.name = b.database_name WHERE db.database_id > 4 AND (b.backup_finish_date IS NULL OR b.backup_finish_date < DATEADD(DAY, -1, GETDATE())) AND db.state_desc = 'ONLINE';
END
ELSE
BEGIN
    PRINT CHAR(13) + '【异常2：未及时备份数据库】无异常';
END

-- 3. 磁盘空间不足预警
EXEC master.dbo.xp_fixeddrives;


