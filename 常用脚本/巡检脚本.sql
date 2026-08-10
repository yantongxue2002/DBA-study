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

SELECT name, state_desc FROM sys.databases;
-- 2.2 数据库文件详细信息查询（路径、大小、增长方式，排查文件异常）

SELECT
    db.name AS 数据库名称,
    mf.name AS 文件名称,
    mf.type_desc AS 文件类型, -- ROWS=数据文件，LOG=日志文件
    CAST(mf.size * 8.0 / 1024 /1024 AS DECIMAL(10,2)) AS 文件当前大小_GB,
    CAST(mf.max_size * 8.0 / 1024 /1024 AS DECIMAL(10,2)) AS 文件最大大小_GB, -- 0=无限制
    CAST(mf.growth AS DECIMAL(10,2)) AS 增长值,
    mf.physical_name AS 文件物理路径,
    CASE mf.is_percent_growth WHEN 1 THEN '百分比增长' ELSE '固定大小增长(MB)' END AS 增长方式,
    mf.state_desc AS 文件状态
FROM sys.master_files mf
LEFT JOIN sys.databases db ON mf.database_id = db.database_id
WHERE db.name NOT IN ('master', 'tempdb', 'model', 'msdb') -- 排除系统数据库
ORDER BY db.name, mf.type_desc;

DBCC SHRINKFILE (N'MES.EDI_log', 102400);
GO
-- 3. 磁盘空间不足预警
EXEC master.dbo.xp_fixeddrives;

-- 日志状态/是否截断
SELECT
    name AS 数据库名,
    recovery_model_desc AS 恢复模式,
    log_reuse_wait_desc AS 日志等待原因,
    CASE
        WHEN log_reuse_wait_desc = 'NOTHING' THEN '✅ 正常，可截断'
        WHEN log_reuse_wait_desc = 'LOG_BACKUP' THEN '❌ 等待日志备份（必须备份日志才能截断）'
        WHEN log_reuse_wait_desc = 'ACTIVE_TRANSACTION' THEN '⚠️ 有长事务卡住'
        ELSE '⚠️ 其他原因阻塞'
    END AS 日志截断状态
FROM sys.databases
WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') -- 只看业务库
ORDER BY 日志截断状态 DESC


-- 数据库备份状态
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
    --WHERE b.backup_start_date > DATEADD(DAY, -7, GETDATE()) -- 只查最近7天的备份
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
WHERE 备份序号 <= 1 -- 显示最近3次备份
ORDER BY 数据库名称, 备份类型, 备份结束时间 DESC;


-- 5.2 会话阻塞检查（重点排查长期阻塞）
SELECT
    -- 阻塞信息
    r.blocking_session_id                                     AS 阻塞者会话ID,
    r.session_id                                              AS 被阻塞会话ID,
    r.wait_type                                               AS 等待类型,
    r.wait_time                                               AS 等待时间_毫秒,
    -- 数据库与程序信息 (来自会话视图)
    DB_NAME(s.database_id)                                    AS 数据库名称,
    s.program_name                                            AS 应用程序名称,
    s.login_name                                              AS 登录账号,
    s.host_name                                               AS 客户端主机名,
    -- 持续时间
    DATEDIFF(SECOND, s.last_request_start_time, GETDATE())    AS 持续时间_秒,
    -- SQL语句 (使用 CROSS APPLY 获取文本)
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
              ((CASE r.statement_end_offset
                    WHEN -1 THEN DATALENGTH(t.text)
                    ELSE r.statement_end_offset
                    END - r.statement_start_offset) / 2) + 1) AS 正在执行的SQL语句
FROM sys.dm_exec_requests r
         JOIN
     sys.dm_exec_sessions s ON r.session_id = s.session_id
         CROSS APPLY
     sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0 -- 只筛选被阻塞的请求
ORDER BY r.wait_time DESC;


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
    DATEDIFF(SECOND, r.start_time, GETDATE()) > 10 -- 执行时间超过30秒
    AND r.session_id > 50; -- 排除系统会话


-- 6.1 索引碎片查询（按碎片率排序，建议定期重建/重组）
SET NOCOUNT ON;

DECLARE @DBID_Index INT;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @DBName SYSNAME;

-- 声明游标
DECLARE DBIndexCursor CURSOR FOR
SELECT database_id, name
FROM sys.databases
WHERE state_desc = 'ONLINE' AND database_id > 4 -- and name = 'AoiAPIServer'; -- 排除系统库

OPEN DBIndexCursor;
FETCH NEXT FROM DBIndexCursor INTO @DBID_Index, @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- 使用 RAISERROR 可以立即在消息框输出，不用等缓冲区满
    RAISERROR('------------------------------ 正在检查数据库ID：%d (%s) 索引碎片情况 ------------------------------', 0, 1, @DBID_Index, @DBName) WITH NOWAIT;

    -- 将 DB_ID 作为变量传入，避免 USE 切换上下文
    SET @SQL = N'
    SELECT
        DB_NAME(@DBID) AS 数据库名称,
        OBJECT_SCHEMA_NAME(s.object_id, @DBID) + ''.'' + OBJECT_NAME(s.object_id, @DBID) AS 表名称,
        i.name AS 索引名称,
        i.type_desc AS 索引类型,
        s.avg_fragmentation_in_percent AS 平均碎片率,
        s.page_count AS 索引页数,
        CASE
            WHEN s.avg_fragmentation_in_percent < 5 THEN ''无需处理''
            WHEN s.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN ''建议重组（REORGANIZE）''
            WHEN s.avg_fragmentation_in_percent > 30 THEN ''建议重建（REBUILD）''
            ELSE ''无需处理''
        END AS 处理建议
    FROM sys.dm_db_index_physical_stats(@DBID, NULL, NULL, NULL, ''LIMITED'') s
    LEFT JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
    WHERE
        s.index_id > 0
        AND s.page_count > 100
    ORDER BY s.avg_fragmentation_in_percent DESC;';

    BEGIN TRY
        -- 使用 sp_executesql 并传递参数
        EXEC sp_executesql @SQL, N'@DBID INT', @DBID = @DBID_Index;
    END TRY
    BEGIN CATCH
        PRINT '检查数据库 ' + @DBName + ' 时出错: ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM DBIndexCursor INTO @DBID_Index, @DBName;
END

CLOSE DBIndexCursor;
DEALLOCATE DBIndexCursor;


-- 分区异常巡检
USE [MES.WGWTB];
GO

SELECT
    表名 = OBJECT_NAME(t.object_id),
    分区函数 = pf.name,
    分区方案 = ps.name,
    分区编号 = p.partition_number,
    边界值 = CONVERT(VARCHAR(50), prv.value),
    分区行数 = p.rows,
    文件组 = fg.name,
    分区状态 =
        CASE
            WHEN p.rows = 0 THEN '空分区（异常）'
            WHEN p.partition_number = (SELECT MAX(partition_number)
                                       FROM sys.partitions p2
                                       WHERE p2.object_id = p.object_id)
                 AND p.rows > 1000000 THEN '尾分区过大（需新建分区）'
            ELSE '正常'
        END
FROM sys.tables t
JOIN sys.indexes i
    ON t.object_id = i.object_id
JOIN sys.partition_schemes ps
    ON i.data_space_id = ps.data_space_id
JOIN sys.partition_functions pf
    ON ps.function_id = pf.function_id
JOIN sys.partitions p
    ON t.object_id = p.object_id
    AND i.index_id = p.index_id
LEFT JOIN sys.partition_range_values prv
    ON pf.function_id = prv.function_id
    AND prv.boundary_id = p.partition_number
LEFT JOIN sys.destination_data_spaces dds
    ON ps.data_space_id = dds.partition_scheme_id
    AND dds.destination_id = p.partition_number
LEFT JOIN sys.filegroups fg
    ON dds.data_space_id = fg.data_space_id
WHERE
    i.index_id IN (0,1) -- 堆表/聚集索引
    AND t.is_ms_shipped = 0 -- 只查业务表
ORDER BY
    表名, 分区编号;


-- 作业状态检查
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

-- 账号台账
SELECT
    ROW_NUMBER() OVER(ORDER BY sp.name) AS 序号,
    sp.name AS 账号名,
    CASE WHEN sp.type IN ('U','G') THEN 'Windows账号' ELSE 'SQL账号' END AS 账号类型,
    STUFF((
        SELECT ', ' + r2.name
        FROM sys.server_role_members rm2
        JOIN sys.server_principals r2 ON rm2.role_principal_id = r2.principal_id
        WHERE rm2.member_principal_id = sp.principal_id
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS 所属角色,
    sp.create_date AS 创建时间,
    sp.modify_date AS 最后修改时间,
    sp.is_disabled AS 是否禁用
FROM sys.server_principals sp
WHERE sp.type IN ('S','U','G')
AND sp.name NOT LIKE '##%'
AND sp.name NOT LIKE 'NT SERVICE%'
-- AND sp.name <> 'sa'
GROUP BY sp.name, sp.type, sp.create_date, sp.modify_date, sp.is_disabled, sp.principal_id


SELECT
    s.login_name AS [登录账号],
    s.host_name AS [客户端主机名],
    c.client_net_address AS [客户端IP地址],
    s.program_name AS [应用程序名称],
    DB_NAME(s.database_id) AS [当前所在数据库],
    s.status AS [连接状态],
    s.login_time AS [登录时间]
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_connections AS c
    ON s.session_id = c.session_id
WHERE s.is_user_process = 1 --and DB_NAME(s.database_id) = 'mes.wgwtb'
ORDER BY s.login_time DESC;

-- 7.1 指定表索引大小查询
-- 说明：请将 'YourTableName' 替换为实际需要查询的表名（支持 schema.table 格式，如 dbo.Orders）
DECLARE @TargetTable NVARCHAR(255) = N'dbo.LotAction'; -- <--- 在此处修改表名

SELECT
    t.name AS 表名,
    i.name AS 索引名称,
    i.type_desc AS 索引类型, -- CLUSTERED=聚集索引, NONCLUSTERED=非聚集索引, HEAP=堆
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(10, 2)) AS 索引总大小_MB,
    CAST(SUM(a.used_pages) * 8.0 / 1024 AS DECIMAL(10, 2)) AS 索引已用大小_MB,
    CAST((SUM(a.total_pages) - SUM(a.used_pages)) * 8.0 / 1024 AS DECIMAL(10, 2)) AS 索引未用空间_MB,
    p.rows AS 行数
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name = PARSENAME(@TargetTable, 1) -- 获取表名部分
  AND (@TargetTable NOT LIKE '%.%' OR SCHEMA_NAME(t.schema_id) = PARSENAME(@TargetTable, 2)) -- 如果指定了架构，则匹配架构
GROUP BY t.name, i.name, i.type_desc, p.rows
ORDER BY 索引总大小_MB DESC;





SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time,
    t.text AS sql_text,
    qp.query_plan,
    -- 关键指标：逻辑读 vs 物理读
    qs.total_logical_reads,
    qs.total_physical_reads,
    qs.execution_count
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) qp
LEFT JOIN sys.dm_exec_query_stats qs ON r.sql_handle = qs.sql_handle AND r.plan_handle = qs.plan_handle
WHERE r.session_id > 50 -- 排除系统进程
ORDER BY r.logical_reads + r.reads DESC; -- 按当前读取量排序


SELECT
    s.login_name AS [登录账号],
    s.host_name AS [客户端主机名],
    c.client_net_address AS [客户端IP地址],
    s.program_name AS [应用程序名称],
    DB_NAME(s.database_id) AS [当前所在数据库],
    s.status AS [连接状态],
    s.login_time AS [登录时间]
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_connections AS c
    ON s.session_id = c.session_id
WHERE s.is_user_process = 1 and DB_NAME(s.database_id) = 'MES.WGOEM'
ORDER BY s.login_time DESC;

SELECT TOP 20
    migs.user_seeks,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    mid.statement AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_groups mig
INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
ORDER BY migs.avg_total_user_cost * (migs.user_seeks + migs.user_scans) DESC;

SELECT
    (CAST(SUM(CASE WHEN counter_name = 'Buffer cache hit ratio' THEN cntr_value ELSE 0 END) AS FLOAT) /
    CAST(SUM(CASE WHEN counter_name = 'Buffer cache hit ratio base' THEN cntr_value ELSE 0 END) AS FLOAT)) * 100 AS BufferCacheHitRatio
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Buffer Manager%';
-- 检查 LotAction 表的分区情况
SELECT
    t.name AS 表名,
    i.name AS 索引名称,
    i.type_desc AS 索引类型,
    ps.name AS 分区方案名称,
    pf.name AS 分区函数名称,
    p.partition_number AS 分区编号,
    p.rows AS 当前分区行数,
    prv.value AS 边界值,
    fg.name AS 文件组名称
FROM sys.tables t
JOIN sys.indexes i ON t.object_id = i.object_id
JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
LEFT JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
LEFT JOIN sys.partition_functions pf ON ps.function_id = pf.function_id
LEFT JOIN sys.partition_range_values prv ON pf.function_id = prv.function_id AND p.partition_number = prv.boundary_id + CASE WHEN pf.boundary_value_on_right = 1 THEN 0 ELSE 1 END
LEFT JOIN sys.destination_data_spaces dds ON ps.data_space_id = dds.partition_scheme_id AND p.partition_number = dds.destination_id
LEFT JOIN sys.filegroups fg ON dds.data_space_id = fg.data_space_id
WHERE t.name = 'LotAction'
ORDER BY p.partition_number;


select count(*) from LotAction WHERE CreateDate >= '2026-05-01' AND CreateDate < '2026-06-01'
select distinct MoID into #tmpMo from LotAction with (nolock) where CreateDate >= @BeginDate and CreateDate < @EndDate and OperateMode in ('IN', 'OUT')


SELECT
    r.session_id,
    r.start_time,
    r.percent_complete,
    t.text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.command IN ('ALTER INDEX', 'DBCC', 'BACKUP DATABASE');


UPDATE #TmpWIPMO
SET
    Inventory = TB.Inventory,
    OutStock = TB.OutStock
FROM
    #TmpWIPMO
INNER JOIN (
    SELECT
        TWM.MoNo,
        -- Sum(1) as EntryQty,
        SUM(CASE WHEN CT.StockStatus = 'O' THEN 1 ELSE 0 END) AS OutStock,
        SUM(CASE WHEN CT.StockStatus IN ('I', 'P') THEN 1 ELSE 0 END) AS Inventory
    FROM
        #TmpWIPMO TWM WITH (NOLOCK)
    INNER JOIN Carton CT WITH (NOLOCK) ON TWM.MoNo = CT.MONO
    INNER JOIN CartonItem CI WITH (NOLOCK) ON CT.CartonID = CI.CartonID
    INNER JOIN dbo.Lot l ON l.LotID = CI.LotID  -- 2025-09-16 何幼
    WHERE
        CT.IsActive = 'Y'
        AND CT.SourceType = '670001'
    GROUP BY
        TWM.MoNo
) AS TB ON #TmpWIPMO.MoNo = TB.MoNo;

select count(*) from Lot

fetch next from CurSNRule  into @SNRuleID,@Sequence,@factoryCode,@RuleLength,@Rules,@Start,@ends,@RuleType,@ishead
  ----************ print '@Rules——'+@Rules
  	40698	13658	0	0	351108	20	10	MES.WGWTB



  	SELECT
  @LotID = LotID
        FROM Lot with (nolock)
        WHERE (MoLotSn = @MONO OR MONO=@MONO ) AND IsCancel=0	6	32	16	0	6230	37	1	MES.WGWTB

        select * from Lot where IsCancel=0 and IsRework=0  and (LotSn ='L1P6511A920164A' or molotsn='L1P6511A920164A') 	219	2	MES.WGWTB	2	0	0	700	0


 update #TmpWIPMO set Inventory = TB.Inventory, OutStock = TB.OutStock from ( select TWM.MoNo, --Sum(1) as EntryQty, Sum(case when CT.StockStatus = 'O' then 1 else 0 end) as OutStock, Sum(case when CT.StockStatus in ('I', 'P') then 1 else 0 end) as Inventory from #TmpWIPMO TWM with (nolock) inner join Carton CT with (nolock) on TWM.MoNo = CT.MONO inner join CartonItem CI with (nolock) on CT.CartonID = CI.CartonID INNER JOIN dbo.Lot l ON l.LotID = ci.LotID --2025-09-16 何幼 where CT.IsActive = 'Y' and CT.SourceType = '670001' group by TWM.MoNo) as TB where #TmpWIPMO.MoNo = TB.MoNo

SELECT
    r.session_id AS 会话ID,
    DB_NAME(s.database_id) AS 数据库名称,
    s.login_name AS 登录账号,
    s.program_name AS 应用程序名称,
    r.status AS 执行状态,
    r.wait_type AS 等待类型,
    r.wait_time AS 等待时间_ms,
    r.blocking_session_id AS 阻塞会话ID,
    DATEDIFF(SECOND, r.start_time, GETDATE()) AS 执行时间_秒,
    r.cpu_time AS CPU时间_ms,
    r.logical_reads AS 逻辑读,
    r.reads AS 物理读,
    r.writes AS 写入次数,
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
        ((CASE WHEN r.statement_end_offset = -1
               THEN LEN(CONVERT(NVARCHAR(MAX), t.text)) * 2
               ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1) AS 执行SQL语句,
    t.text AS 完整批处理SQL
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
    AND s.is_user_process = 1  -- 只查用户进程
ORDER BY r.logical_reads + r.reads DESC;  -- 按I/O降序排列



-- 1. 创建登录名
CREATE LOGIN dev_user WITH PASSWORD = 'Wg@123456..';
-- 1. 创建登录名
CREATE LOGIN ops_user WITH PASSWORD = 'Wg#123456..';
-- 4. 授予服务器级别权限（运维需要）
-- 查看任何数据库
GRANT VIEW ANY DATABASE TO ops_user;
-- 查看服务器状态
GRANT VIEW SERVER STATE TO ops_user;


-- 2. 在目标数据库中创建用户
CREATE USER dev_user FOR LOGIN dev_user;
CREATE USER ops_user FOR LOGIN ops_user;

-- 3. 授予角色权限
-- db_datareader: 可以查询所有表
-- db_datawriter: 可以增删改所有表
-- db_ddladmin: 可以创建/修改/删除表、视图、存储过程等对象
EXEC sp_addrolemember 'db_datareader', 'dev_user';
EXEC sp_addrolemember 'db_datawriter', 'dev_user';
EXEC sp_addrolemember 'db_ddladmin', 'dev_user';
EXEC sp_addrolemember 'db_datareader', 'ops_user';
EXEC sp_addrolemember 'db_backupoperator', 'ops_user';





DBCC SHRINKFILE (N'MES.WGWTB_log', 204800);
GO


select distinct t.LotSN,t.MONO,t.Memo,t.ProductCode,PD.ProductName,t.MoLotSn CurrentMoLotSN,MR.OldMoLotSN,case when t.IsCut='1' then '切割品' else '非切割品'end as IsCut,
    case when t.IsRIns='1' then '已抽检' else '未抽检'end as IsRIns,case when t.IsRework='1' then '重工品' else '正常品'end as IsRework,case when t.LotStatus='1' then '正常' else '禁用'end as LotStatus,t.ActionStatus,t.GradeCode,t.GroupCode,t1.OperationName,t.Carton,
 mc.MFGCartonNO as InCartonNO,MC2.MFGCartonNO as OutCartonNO,MP.MFGPalletSN as PalletSN
    from lot as t with (nolock)
  inner join Product as PD with (nolock) on PD.ProductCode = t.ProductCode
  inner join Operation as t1 with (nolock) on t.OperationID=t1.OperationID
  left join MoLotSNRecord as MR with (nolock) on MR.LotID = t.LotID
  left join MFGCartonItem mi with (nolock) on t.LotID=mi.LotID
     left join MFGCarton mc with (nolock) on mi.MFGCartonID=mc.MFGCartonID
  left join MFGCartonItem MI2 with (nolock) on MI2.InMFGCartonID = MC.MFGCartonID
  left join MFGCarton MC2 with (nolock) on MC2.MFGCartonID = MI2.MFGCartonID
  left join MFGPalletItem MPI with (nolock) on MPI.MFGCarton = MC2.MFGCartonNO
  left join MFGPallet MP with (nolock) on MP.MFGPalletID = MPI.MFGPalletID
    where t.MoLotSn=@MoLotSn and isnull(t.isCancel, '')=0
 union
 select distinct t.LotSN,t.MONO,t.Memo,t.ProductCode,PD.ProductName,t.MoLotSn CurrentMoLotSN,MR.OldMoLotSN,case when t.IsCut='1' then '切割品' else '非切割品'end as IsCut,
    case when t.IsRIns='1' then '已抽检' else '未抽检'end as IsRIns,case when t.IsRework='1' then '重工品' else '正常品'end as IsRework,case when t.LotStatus='1' then '正常' else '禁用'end as LotStatus,t.ActionStatus,t.GradeCode,t.GroupCode,t1.OperationName,t.Carton,
 mc.Carton as InCartonNO,MC2.Carton as OutCartonNO,MP.PalletSN as PalletSN
    from lot as t with (nolock)
  inner join Product as PD with (nolock) on PD.ProductCode = t.ProductCode
  inner join Operation as t1 with (nolock) on t.OperationID=t1.OperationID
  left join MoLotSNRecord as MR with (nolock) on MR.LotID = t.LotID
  left join CartonItem mi with (nolock) on t.LotID=mi.LotID
     left join Carton mc with (nolock) on mi.CartonID=mc.CartonID
  left join CartonItem MI2 with (nolock) on MI2.InCartonID = MC.CartonID
  left join Carton MC2 with (nolock) on MC2.CartonID = MI2.CartonID
  left join PalletItem MPI with (nolock) on MPI.Carton = MC2.Carton
  left join Pallet MP with (nolock) on MP.PalletID = MPI.PalletID
    where t.MoLotSn=@MoLotSn and isnull(t.isCancel, '')=0



