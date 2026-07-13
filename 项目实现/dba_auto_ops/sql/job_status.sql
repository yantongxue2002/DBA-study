-- ============================================
-- SQL Agent 作业状态巡检
-- 最近一次运行结果 & 运行时长
-- ============================================

DECLARE @history_keep_days INT = 30;

WITH JobRunHistory AS (
    SELECT
        j.job_id,
        j.name AS job_name,
        j.enabled,
        j.description,
        jh.run_status,
        jh.run_date,
        jh.run_time,
        jh.run_duration,
        jh.message,
        jh.instance_id,
        -- 格式化运行时长 (HHMMSS -> 秒)
        CAST(jh.run_duration / 10000 AS INT) * 3600 +
        CAST((jh.run_duration % 10000) / 100 AS INT) * 60 +
        CAST(jh.run_duration % 100 AS INT) AS run_duration_seconds,
        -- 格式化执行时间
        CONVERT(DATETIME,
            STUFF(STUFF(CAST(jh.run_date AS CHAR(8)), 5, 0, '-'), 8, 0, '-') + ' ' +
            STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
        ) AS execution_time,
        ROW_NUMBER() OVER (
            PARTITION BY j.job_id
            ORDER BY jh.run_date DESC, jh.run_time DESC
        ) AS rn,
        -- 计算最近30天平均运行时长 (同结果状态的)
        AVG(CAST(jh.run_duration / 10000 AS INT) * 3600 +
            CAST((jh.run_duration % 10000) / 100 AS INT) * 60 +
            CAST(jh.run_duration % 100 AS INT))
        OVER (PARTITION BY j.job_id) AS avg_duration_seconds
    FROM msdb.dbo.sysjobs j
    LEFT JOIN msdb.dbo.sysjobhistory jh
        ON j.job_id = jh.job_id
        AND jh.step_id = 0  -- 只取作业级别记录
    WHERE jh.run_date >= CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY, -@history_keep_days, GETDATE()), 112))
       OR jh.run_date IS NULL
)
SELECT
    job_name,
    enabled,
    description,
    run_status,
    CASE run_status
        WHEN 0 THEN '失败'
        WHEN 1 THEN '成功'
        WHEN 2 THEN '重试'
        WHEN 3 THEN '已取消'
        WHEN 4 THEN '正在运行'
        ELSE '未知'
    END AS run_status_desc,
    execution_time AS last_run_time,
    run_duration_seconds,
    RIGHT('0' + CAST(run_duration_seconds / 3600 AS VARCHAR), 2) + ':' +
    RIGHT('0' + CAST((run_duration_seconds % 3600) / 60 AS VARCHAR), 2) + ':' +
    RIGHT('0' + CAST(run_duration_seconds % 60 AS VARCHAR), 2) AS run_duration_formatted,
    CAST(avg_duration_seconds AS INT) AS avg_duration_seconds,
    -- 时长偏差
    CASE
        WHEN avg_duration_seconds > 0
        THEN CAST((run_duration_seconds - avg_duration_seconds) * 100.0 / avg_duration_seconds AS DECIMAL(5,1))
        ELSE NULL
    END AS duration_deviation_pct,
    SUBSTRING(message, 1, 500) AS message_short
FROM JobRunHistory
WHERE rn = 1
ORDER BY
    CASE
        WHEN run_status = 0 THEN 0  -- 失败排最前
        WHEN run_status = 1 THEN 3  -- 成功排最后
        WHEN run_status = 4 THEN 1  -- 运行中
        ELSE 2
    END,
    job_name;
