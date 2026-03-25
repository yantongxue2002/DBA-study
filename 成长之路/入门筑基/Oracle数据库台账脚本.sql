-- 查看sga的分配情况
SELECT component, current_size/1024/1024 AS size_mb 
FROM v$sga_dynamic_components 
ORDER BY component;
-- 查看sga的总内存
SELECT SUM(current_size)/1024/1024 AS total_sga_mb FROM v$sga_dynamic_components;
SHOW PARAMETER sga_target;
-- 查看pga的分配情况
SELECT name, value/1024/1024 AS value_mb 
FROM v$pgastat 
WHERE name IN ('aggregate PGA target parameter', 'aggregate PGA auto target', 'total PGA allocated', 'maximum PGA allocated');
-- 查看游标参数配置
SELECT name, value, isdefault FROM v$parameter WHERE name = 'open_cursors';
-- 
SELECT 
    sid, 
    serial#, 
    username, 
    program, 
    open_cursors_count
FROM (
    -- 第一层子查询：按游标数降序排序并添加行号
    SELECT 
        s.sid, 
        s.serial#, 
        s.username, 
        s.program, 
        COUNT(a.cursor_id) AS open_cursors_count,
        ROWNUM AS rn
    FROM v$session s
    -- 11g关键修改：用sid关联v$session和v$open_cursor
    JOIN v$open_cursor a ON s.sid = a.sid
    GROUP BY s.sid, s.serial#, s.username, s.program
    ORDER BY open_cursors_count DESC
) t
-- 筛选前10行
WHERE rn <= 10
-- 最终结果保持降序
ORDER BY open_cursors_count DESC;
-- 查看连接数限制与使用情况
SELECT 
    resource_name, 
    current_utilization AS current_used, 
    max_utilization AS peak_used, 
    limit_value AS max_limit,
    (limit_value - current_utilization) AS available
FROM v$resource_limit
WHERE resource_name IN ('processes', 'sessions');
-- 查看当前活跃会话状态概览
SELECT status, COUNT(*) AS count 
FROM v$session 
GROUP BY status;
-- 核心实例信息
SELECT name AS db_name, dbid, created, open_mode, log_mode, database_role 
FROM v$database;
-- 所有用户概览
SELECT username, account_status, created, profile, default_tablespace, temporary_tablespace
FROM dba_users
ORDER BY created DESC;
-- 拥有 DBA 角色或 SYSDBA/SYSOPER 权限的用户（最危险账户）
SELECT grantee, granted_role
FROM dba_role_privs
WHERE granted_role IN ('DBA', 'DATAPUMP_EXP_FULL_DATABASE', 'DATAPUMP_IMP_FULL_DATABASE')
   OR grantee IN (
       -- 修正部分：从 V$PWFILE_USERS 获取拥有 SYSDBA 或 SYSOPER 的用户
       SELECT username 
       FROM v$pwfile_users 
       WHERE sysdba = 'TRUE' OR sysoper = 'TRUE'
   )
ORDER BY grantee;
-- 密码策略（profile）关键限制
SELECT profile, resource_name, limit
FROM dba_profiles
WHERE resource_name IN (
    'FAILED_LOGIN_ATTEMPTS','PASSWORD_LIFE_TIME','PASSWORD_LOCK_TIME',
    'PASSWORD_GRACE_TIME','PASSWORD_REUSE_TIME','PASSWORD_REUSE_MAX',
    'PASSWORD_VERIFY_FUNCTION'
)
ORDER BY profile, resource_name;
-- 有密码验证函数的用户
SELECT profile, resource_name, limit
FROM dba_profiles
WHERE resource_name = 'PASSWORD_VERIFY_FUNCTION' AND limit != 'NULL';
-- 最近创建或修改的用户（近半年）
SELECT username, created, profile, account_status
FROM dba_users
WHERE created > SYSDATE - 180
ORDER BY created DESC;
-- 系统用户是否修改过默认密码（粗略判断）
-- （生产环境应全部锁定或改密）
SELECT username, account_status
FROM dba_users
WHERE username IN ('SYS','SYSTEM','OUTLN','DBSNMP','APPQOSSYS','WMSYS','CTXSYS','EXFSYS','MDSYS','LBACSYS')
ORDER BY username;
-- 错误日志的地址
SELECT value FROM v$diag_info WHERE name = 'Diag Trace';
-- SQL 查看具体的等待时间
SELECT event, total_waits, time_waited, average_wait
FROM v$system_event
WHERE event LIKE 'log file switch%';
--查看Redo Log 日志组
SELECT group#, bytes/1024/1024 MB, status FROM v$log;
SELECT * FROM v$log;
-- 确认redo Log的路径
SELECT 
    l.group#,    -- 明确指定来自 v$log
    l.status,    -- 明确指定来自 v$log
    l.bytes/1024/1024 AS "SIZE_MB",
    f.member
FROM v$log l
JOIN v$logfile f ON l.group# = f.group#
ORDER BY l.group#;
-- 1. 当前总会话数 (包含后台进程和空闲会话)
SELECT COUNT(*) AS total_sessions FROM v$session;
-- 2. 当前活跃会话数 (正在执行 SQL 的，最反映真实负载)
SELECT COUNT(*) AS active_sessions FROM v$session WHERE status = 'ACTIVE';
-- 3. 当前用户会话数 (排除后台进程 SYS$BACKGROUND 等)
SELECT COUNT(*) AS user_sessions FROM v$session WHERE type = 'USER';
-- 查看实例启动以来的最大并发连接数记录
SELECT resource_name, current_utilization, max_utilization, limit_value 
FROM v$resource_limit 
WHERE resource_name IN ('processes', 'sessions');
-- 查看数据库版本
SELECT * FROM v$version;
-- 当前表空间使用率（最重要之一，看空间是否紧张）
SELECT 
    tablespace_name,
    ROUND(SUM(bytes)/1024/1024/1024, 2)          AS "已分配GB",
    ROUND(SUM(maxbytes)/1024/1024/1024, 2)       AS "最大可扩展GB",
    ROUND((SUM(bytes) / SUM(maxbytes)) * 100, 1) AS "使用率%",
    ROUND(SUM(bytes - used_bytes)/1024/1024/1024, 2) AS "剩余GB"
FROM (
    SELECT 
        f.tablespace_name,
        f.bytes,
        f.maxbytes,
        NVL((SELECT SUM(bytes) FROM dba_free_space fs 
             WHERE fs.tablespace_name = f.tablespace_name 
             AND fs.file_id = f.file_id), 0) AS used_bytes
    FROM dba_data_files f
) 
GROUP BY tablespace_name
ORDER BY "使用率%" DESC;
-- 2. 临时表空间使用情况（非常容易被忽略，但经常出问题）
SELECT 
    tablespace_name,
    ROUND(SUM(bytes_used)/1024/1024/1024, 2)    AS "当前使用GB",
    ROUND(SUM(bytes_free)/1024/1024/1024, 2)    AS "剩余GB",
    ROUND(SUM(bytes_used + bytes_free)/1024/1024/1024, 2) AS "总大小GB"
FROM v$temp_space_header
GROUP BY tablespace_name;
-- 3. SGA / PGA 当前实际使用与目标对比
SELECT 
    name,
    ROUND(value/1024/1024, 1) AS "MB",
    CASE 
        WHEN name LIKE '%target%' THEN '目标值'
        WHEN name LIKE '%current%' THEN '当前值'
        ELSE '其他'
    END AS 类型
FROM v$sga
UNION ALL
SELECT name, ROUND(value/1024/1024, 1) AS "MB", 'PGA' 
FROM v$pgastat 
WHERE name IN ('aggregate PGA target parameter', 'aggregate PGA auto target', 'total PGA inuse');
-- 4. 内存结构详细分配（看各个池是否合理）
SELECT 
    pool || ' ' || name AS component,
    ROUND(bytes/1024/1024, 1) AS "MB"
FROM v$sgastat
WHERE pool IS NOT NULL
   OR name IN ('buffer_cache','shared pool','large pool','java pool','streams pool','fixed_sga','variable_sga')
ORDER BY bytes DESC;
-- 5. Top 等待事件（过去1小时或自启动以来最严重的等待）
SELECT 
    event,
    total_waits,
    time_waited / 100 AS "等待时间秒",
    -- 增加除数非空判断，避免除以0报错
    ROUND(CASE WHEN total_waits > 0 THEN time_waited / total_waits / 100 ELSE 0 END, 2) AS "平均等待毫秒",
    ROUND((time_waited / SUM(time_waited) OVER ()) * 100, 2) AS "占比%"
FROM (
    -- 11g用子查询+ROWNUM实现Top15
    SELECT 
        event,
        total_waits,
        time_waited,
        -- 先按time_waited降序排序，再取前15行
        ROWNUM AS rn
    FROM (
        SELECT 
            event,
            total_waits,
            time_waited
        FROM v$system_event
        WHERE event NOT IN (
            'SQL*Net message from client',
            'class slave wait',
            'PX Idle Wait',
            'pmon timer',
            'smon timer',
            'rdbms ipc message'
        )
          AND total_waits > 0
        ORDER BY time_waited DESC
    ) t1
    WHERE ROWNUM <= 15
) t2
ORDER BY time_waited DESC;
-- 6. 参数是否为非默认值（快速看哪些被改过）
SELECT 
    name, 
    value, 
    issys_modifiable, 
    ismodified, 
    isdefault
FROM v$parameter
WHERE isdefault = 'FALSE'
   OR ismodified != 'SYSTEM_MOD'
ORDER BY name;
-- 7. 最近一次 AWR 快照时间（看是否有定期生成 AWR）
SELECT *
FROM (
    SELECT 
        snap_id, 
        begin_interval_time, 
        end_interval_time,
        instance_number
    FROM dba_hist_snapshot
    ORDER BY begin_interval_time DESC
)
WHERE ROWNUM <= 10;
-- 8. 当前活动会话 Top 10（看是否有长事务、锁、CPU/IO 消耗大户）
SELECT 
    sid,
    serial#,
    username,
    status,
    sql_id,
    cpu_sec,
    wait_sec,
    event,
    program,
    machine
FROM (
    SELECT 
        s.sid,
        s.serial#,
        s.username,
        s.status,
        s.sql_id,
        -- 将微秒(Value)转换为秒，保留1位小数
        ROUND(tm.value / 1000000, 1) AS cpu_sec,
        -- v$session.wait_time 在11g中代表当前/最后一次等待耗时(百分之一秒)
        ROUND(s.wait_time / 100, 1) AS wait_sec,
        s.event,
        s.program,
        s.machine
    FROM v$session s
    JOIN v$sess_time_model tm ON s.sid = tm.sid
    WHERE s.status = 'ACTIVE'
      AND s.username IS NOT NULL
      AND tm.stat_name = 'DB CPU'  -- 确保只取CPU耗时统计
    ORDER BY tm.value DESC
)
WHERE ROWNUM <= 10;
-- 9. Undo 表空间与 undo_retention 相关（看是否容易出现 ORA-01555）
SELECT 
    tablespace_name,
    status,
    SUM(bytes)/1024/1024 AS "MB"
FROM dba_undo_extents
GROUP BY tablespace_name, status;
-- 10. Redo 日志组与切换频率（看是否太频繁导致性能抖动）
SELECT 
    l.group#,
    l.thread#,
    l.bytes/1024/1024 AS "MB",
    l.status AS group_status,   -- 明确这是 v$log 的状态
    f.member,
    f.status AS file_status    -- 明确这是 v$logfile 的状态
FROM v$log l
JOIN v$logfile f ON l.group# = f.group#
ORDER BY l.group#;
-- 11. 排序/哈希区使用峰值（PGA 是否够用）
SELECT 
    name,
    value
FROM v$sysstat
WHERE name LIKE '%sort%memory%' 
   OR name LIKE '%work area%';
-- 查看库库名
SELECT name FROM v$database;
-- 查看所有的表
SELECT table_name FROM all_tables;
-- 查看会话连接情况
select * from v$session where username is not null;
--
SELECT count(*) FROM EKP.KM_COLLABORATE_MAIN  KM_COLLABORATE_LOGGER_RECEIVER
--按占用空间大小降序，显示前 50 大表
SELECT *
FROM (
    SELECT 
        owner 用户名,
        segment_name 表名,
        tablespace_name 表空间,
        ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) 占用_GB,
        ROUND(SUM(bytes) / 1024 / 1024, 2)      占用_MB
    FROM dba_segments
    WHERE segment_type = 'TABLE'  -- 只查表
      AND owner NOT IN ('SYS','SYSTEM','SYSMAN','DBSNMP')  -- 排除系统用户
    GROUP BY owner, segment_name, tablespace_name
    ORDER BY 占用_GB DESC
)
WHERE ROWNUM <= 50;
-- 统计表的数据量
SELECT count(*) FROM EKP.SYS_LOG_APP_BAK
-- 查看表空间占用存储
SELECT 
    TO_CHAR(FD_CREATED, 'YYYY-MM') AS "月份",
    COUNT(*) AS "数据量"
FROM "EKP"."SYS_LOG_APP_BAK"
GROUP BY TO_CHAR(FD_CREATED, 'YYYY-MM')
ORDER BY "月份" DESC;
-- 查询 EKP 模式的总大小 (GB)
SELECT 
    owner AS "所属用户",
    ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS "总空间(GB)",
    ROUND(SUM(CASE WHEN segment_type LIKE 'TABLE%' THEN bytes ELSE 0 END) / 1024 / 1024 / 1024, 2) AS "表数据(GB)",
    ROUND(SUM(CASE WHEN segment_type LIKE 'INDEX%' THEN bytes ELSE 0 END) / 1024 / 1024 / 1024, 2) AS "索引(GB)",
    ROUND(SUM(CASE WHEN segment_type LIKE 'LOB%' THEN bytes ELSE 0 END) / 1024 / 1024 / 1024, 2) AS "大字段LOB(GB)"
FROM dba_segments
WHERE owner = 'EKP'
GROUP BY owner;
--确认数据库文件及存储路径
SELECT name FROM v$datafile;
-- 检查表空间的备份情况
SELECT * FROM v$backup;
-- 查看连接情况
SELECT COUNT(*) FROM V$SESSION WHERE USERNAME IS NOT NULL;

-- 归档日志的情况
SELECT LOG_MODE FROM V$DATABASE;
-- 检查数据库实例状态
SELECT 
    instance_name AS "实例名", 
    status AS "状态",           -- 应为 OPEN
    database_status AS "数据库状态", -- 应为 ACTIVE
    archiver AS "归档状态",     -- 应为 STARTED
    to_char(startup_time, 'YYYY-MM-DD HH24:MI:SS') AS "启动时间"
FROM v$instance;
-- 检查数据文件与表空间
SELECT 
    tablespace_name AS "表空间",
    file_name AS "文件路径",
    status AS "状态",    -- 应为 AVAILABLE 或 ONLINE
    online_status
FROM dba_data_files;
