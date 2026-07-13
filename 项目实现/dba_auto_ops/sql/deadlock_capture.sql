-- ============================================
-- 死锁抓取 (SQL Server 2019 兼容)
-- 从 system_health Extended Event 会话提取死锁
-- ============================================

-- 1. 最近死锁记录
SELECT TOP 10
    DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()),
        xed.event_data.value('(/event/@timestamp)[1]', 'datetime2')) AS deadlock_time,
    xed.event_data.value('(/event/data/value/deadlock/process-list/process/@spid)[1]', 'INT') AS victim_spid,
    xed.event_data.value('(/event/data/value/deadlock/process-list/process/@clientapp)[1]', 'VARCHAR(200)') AS victim_app,
    xed.event_data.value('(/event/data/value/deadlock/process-list/process/@hostname)[1]', 'VARCHAR(200)') AS victim_host,
    xed.event_data.value('(/event/data/value/deadlock/process-list/process/@currentdbname)[1]', 'VARCHAR(200)') AS database_name,
    xed.event_data.value('(/event/data/value/deadlock/process-list/process/inputbuf)[1]', 'NVARCHAR(MAX)') AS victim_query,
    xed.event_data.value('(/event/data/value/deadlock)[1]', 'NVARCHAR(MAX)') AS deadlock_graph
FROM (
    SELECT TRY_CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = 'xml_deadlock_report'
) xed
ORDER BY deadlock_time DESC;

-- 2. 死锁频率统计 (最近7天) — 先物化XML列再GROUP BY
;WITH DeadlockEvents AS (
    SELECT
        DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()),
            TRY_CAST(event_data AS XML).value('(/event/@timestamp)[1]', 'datetime2')) AS event_time
    FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = 'xml_deadlock_report'
)
SELECT
    CONVERT(DATE, event_time) AS deadlock_date,
    COUNT(*) AS deadlock_count
FROM DeadlockEvents
WHERE event_time >= DATEADD(DAY, -7, GETDATE())
GROUP BY CONVERT(DATE, event_time)
ORDER BY deadlock_date DESC;
