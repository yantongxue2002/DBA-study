-- ============================================
-- 数据库完整性巡检 (DBCC CHECKDB)
-- 通过错误日志搜索 CHECKDB 执行记录
-- ============================================

-- 方法1: 从错误日志中搜索 CHECKDB 记录
DECLARE @search_start DATETIME = DATEADD(DAY, -14, GETDATE());
DECLARE @search_end   DATETIME = GETDATE();

CREATE TABLE #ErrorLog (
    LogDate     DATETIME,
    ProcessInfo VARCHAR(50),
    LogText     VARCHAR(4000)
);

-- 读取错误日志 (最近2个日志文件)
DECLARE @log_num INT = 0;
WHILE @log_num <= 1
BEGIN
    BEGIN TRY
        INSERT INTO #ErrorLog
        EXEC xp_readerrorlog @log_num, 1, N'CHECKDB', NULL, @search_start, @search_end;
    END TRY
    BEGIN CATCH
        BREAK;
    END CATCH
    SET @log_num = @log_num + 1;
END;

-- 解析 CHECKDB 结果
SELECT
    LogDate AS check_time,
    ProcessInfo,
    CASE
        WHEN LogText LIKE '%found 0 errors%' THEN 'OK'
        WHEN LogText LIKE '%CHECKDB found%' THEN '有错误'
        WHEN LogText LIKE '%could not be completed%' THEN '未完成'
        ELSE '运行中'
    END AS check_result,
    -- 提取数据库名
    SUBSTRING(LogText,
        CHARINDEX('''', LogText) + 1,
        CHARINDEX('''', LogText, CHARINDEX('''', LogText) + 1) - CHARINDEX('''', LogText) - 1
    ) AS database_name,
    -- 检查是否完成
    CASE WHEN LogText LIKE '%found 0 errors%' THEN 1
         WHEN LogText LIKE '%CHECKDB found%' THEN 1
         ELSE 0
    END AS is_completed,
    DATEDIFF(HOUR, LogDate, GETDATE()) / 24 AS days_since_check,
    LogText AS full_message
FROM #ErrorLog
ORDER BY LogDate DESC;

DROP TABLE #ErrorLog;

-- ============================================
-- 方法2: 从默认跟踪查找 CHECKDB (备用)
-- ============================================
SELECT TOP 20
    t.StartTime,
    t.DatabaseName,
    t.EventSubClass,
    CASE t.EventSubClass
        WHEN 0 THEN '开始'
        WHEN 1 THEN '完成'
        ELSE '其他'
    END AS event_type,
    t.TextData,
    DATEDIFF(DAY, t.StartTime, GETDATE()) AS days_ago
FROM sys.traces t_c
CROSS APPLY fn_trace_gettable(
    REVERSE(SUBSTRING(REVERSE(t_c.path), CHARINDEX('\', REVERSE(t_c.path)), 260)) + 'log.trc',
    DEFAULT
) t
WHERE t_c.is_default = 1
    AND t.EventClass = 22  -- ErrorLog
    AND t.DatabaseName IS NOT NULL
ORDER BY t.StartTime DESC;
