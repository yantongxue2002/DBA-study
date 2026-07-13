-- ============================================
-- 阻塞链巡检 (SQL Server 2019 兼容)
-- ============================================

-- 1. 当前阻塞汇总
SELECT
    blkr_sess.session_id AS blocking_spid,
    blkd_req.session_id AS blocked_spid,
    blkd_req.wait_time / 1000 AS wait_seconds,
    blkd_req.wait_type,
    blkd_req.last_wait_type,
    DB_NAME(blkd_req.database_id) AS database_name,
    blkd_req.blocking_session_id,
    -- 被阻塞的查询文本
    SUBSTRING(ISNULL(blkd_sql.text, ''), 1, 1500) AS blocked_query,
    -- 阻塞源查询文本 (通过 sys.dm_exec_connections 获取)
    SUBSTRING(ISNULL(blkr_sql2.text, ''), 1, 800) AS blocking_query,
    -- 被阻塞的会话信息
    blkd_sess.login_name AS blocked_login,
    blkd_sess.host_name AS blocked_host,
    blkd_sess.program_name AS blocked_program,
    DATEDIFF(SECOND, blkd_sess.last_request_start_time, GETDATE()) AS blocked_duration_seconds,
    -- 阻塞源会话信息
    blkr_sess.login_name AS blocking_login,
    blkr_sess.host_name AS blocking_host,
    blkr_sess.program_name AS blocking_program,
    DATEDIFF(SECOND, blkr_sess.last_request_start_time, GETDATE()) AS blocking_duration_seconds,
    blkr_sess.status AS blocking_session_status,
    blkr_sess.open_transaction_count AS blocking_tran_count
FROM sys.dm_exec_requests blkd_req
JOIN sys.dm_exec_sessions blkd_sess
    ON blkd_req.session_id = blkd_sess.session_id
CROSS APPLY sys.dm_exec_sql_text(blkd_req.sql_handle) blkd_sql
LEFT JOIN sys.dm_exec_sessions blkr_sess
    ON blkd_req.blocking_session_id = blkr_sess.session_id
LEFT JOIN sys.dm_exec_connections blkr_conn
    ON blkr_conn.session_id = blkd_req.blocking_session_id
OUTER APPLY sys.dm_exec_sql_text(blkr_conn.most_recent_sql_handle) blkr_sql2
WHERE blkd_req.blocking_session_id <> 0
    AND blkd_req.wait_time > 5000
ORDER BY blkd_req.wait_time DESC;

-- 2. 长时间运行的事务
SELECT
    s_tran.session_id,
    s_tran.transaction_id,
    at.name AS transaction_type,
    at.transaction_begin_time,
    at.transaction_state,
    DATEDIFF(SECOND, at.transaction_begin_time, GETDATE()) AS transaction_duration_seconds,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    s.open_transaction_count
FROM sys.dm_tran_session_transactions s_tran
JOIN sys.dm_tran_active_transactions at
    ON s_tran.transaction_id = at.transaction_id
LEFT JOIN sys.dm_exec_sessions s
    ON s_tran.session_id = s.session_id
WHERE DATEDIFF(SECOND, at.transaction_begin_time, GETDATE()) > 60
    AND s.session_id > 50
    AND at.transaction_type <> 2
ORDER BY at.transaction_begin_time;