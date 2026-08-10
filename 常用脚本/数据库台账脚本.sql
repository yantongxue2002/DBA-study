-- 当前数据库的所有数据库用户（排除系统角色、guest 等）
SELECT 
    name AS 用户名,
    create_date AS 创建时间,
    modify_date AS 修改时间,
    type_desc AS 类型,                    -- SQL_USER / WINDOWS_USER 等
    authentication_type_desc AS 认证类型,
    sid AS SID
FROM sys.database_principals
WHERE type NOT IN ('A', 'G', 'R', 'X')     -- 排除 Application Role、Group、Role、External Group
  AND sid IS NOT NULL
  AND name != 'guest'
ORDER BY name;

EXEC sp_helpuser;

-- 所有服务器登录名
SELECT 
    name AS 登录名,
    type_desc AS 类型,
    create_date AS 创建时间,
    is_disabled AS 是否禁用,
    default_database_name AS 默认数据库
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G')               -- S=SQL Login, U=Windows User, G=Windows Group
ORDER BY name;


SELECT name AS 用户名, type_desc AS 用户类型
FROM sys.database_principals
WHERE type IN ('S', 'U', 'G');


-- ===================== 1. SQL Server 实例台账查询 =====================
SELECT
    ROW_NUMBER() OVER(ORDER BY (SELECT 1)) AS 序号,
    'SQL-' + CAST(SERVERPROPERTY('MachineName') AS VARCHAR(100)) + '-01' AS 实例唯一标识,
    CAST(SERVERPROPERTY('MachineName') AS VARCHAR(100)) AS 服务器IP_主机名,
    ISNULL(CAST(SERVERPROPERTY('InstanceName') AS VARCHAR(100)), '默认实例MSSQLSERVER') AS 实例名,
    CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(100)) AS 版本号,
    CAST(SERVERPROPERTY('Edition') AS VARCHAR(100)) AS 版本类型,

    -- 修复部分：必须显式 CONVERT sql_variant
    CONVERT(VARCHAR(20), 
        (SELECT TOP 1 value_data 
         FROM sys.dm_server_registry 
         WHERE registry_key LIKE '%Tcp\IPAll' 
           AND value_name = 'TcpPort'
           AND value_data IS NOT NULL 
           AND value_data <> '0')
    ) AS 端口号,

    @@VERSION AS 操作系统版本,
    SUSER_SNAME() AS 运行账户,                                      -- 推荐改成这个，更常用
    (SELECT physical_memory_kb / 1024.0 / 1024.0 
     FROM sys.dm_os_sys_info) AS 内存配置GB,
    (SELECT cpu_count FROM sys.dm_os_sys_info) AS CPU核心数,
    'DBA' AS 负责人,
    CASE WHEN SERVERPROPERTY('IsClustered') = 1 THEN '集群' ELSE '单机' END AS 备注
FROM sys.dm_os_sys_info;   -- 随便加一个 FROM，保证是查询（可选）

-- ===================== 2. 数据库基础信息台账查询 =====================
SELECT
    ROW_NUMBER() OVER(ORDER BY d.database_id) AS 序号,
    'SQL-' + CAST(SERVERPROPERTY('MachineName') AS VARCHAR) + '-01' AS 关联实例标识,
    d.name AS 数据库名,
    d.database_id AS 数据库ID,
    SUSER_SNAME(d.owner_sid) AS 所有者,
    d.create_date AS 创建时间,
    CAST(SUM(m.size * 8 / 1024 / 1024) AS DECIMAL(10,2)) AS 总大小GB,
    d.state_desc AS 状态,
    d.recovery_model_desc AS 恢复模式,
    d.name AS 业务模块,
    'DBA' AS 负责人,
    CASE WHEN d.name IN ('master','model','msdb','tempdb') THEN '系统库' ELSE '业务库' END AS 备注
FROM sys.databases d
JOIN sys.master_files m ON d.database_id = m.database_id
GROUP BY d.name,d.database_id,d.owner_sid,d.create_date,d.state_desc,d.recovery_model_desc
ORDER BY d.database_id

-- ===================== 3. 数据表结构台账查询 =====================
SELECT
    ROW_NUMBER() OVER(ORDER BY t.name) AS 序号,
    DB_NAME() AS 关联数据库名,
    SCHEMA_NAME(t.schema_id) AS 架构名,
    t.name AS 表名,
    ISNULL(ep.value, '无注释') AS 表中文注释,
    -- 多个主键字段用逗号连接
    ISNULL(
        STUFF((
            SELECT ',' + c.name
            FROM sys.indexes pk
            JOIN sys.index_columns ic ON pk.object_id = ic.object_id AND pk.index_id = ic.index_id
            JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE pk.object_id = t.object_id 
              AND pk.is_primary_key = 1
              AND ic.key_ordinal > 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 1, ''),
        '无主键'
    ) AS 主键字段,
    COUNT(c.column_id) AS 字段总数,
    SUM(p.rows) AS 数据量行数,
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(10, 2)) AS 占用空间MB,
    t.modify_date AS 最后修改时间,
    COUNT(DISTINCT i.index_id) AS 索引数量,
    '东莞241distribution' as '数据库'
FROM sys.tables t
LEFT JOIN sys.extended_properties ep 
    ON t.object_id = ep.major_id AND ep.minor_id = 0 AND ep.name = 'MS_Description'
LEFT JOIN sys.partitions p 
    ON t.object_id = p.object_id AND p.index_id < 2
LEFT JOIN sys.allocation_units a 
    ON p.partition_id = a.container_id
LEFT JOIN sys.indexes i 
    ON t.object_id = i.object_id AND i.index_id > 0
LEFT JOIN sys.columns c 
    ON t.object_id = c.object_id
WHERE t.is_ms_shipped = 0
GROUP BY 
    t.object_id,
    t.name,
    SCHEMA_NAME(t.schema_id),
    ep.value,
    t.modify_date
ORDER BY t.name;

-- ===================== 4. 存储过程台账查询 =====================
SELECT
    ROW_NUMBER() OVER(ORDER BY p.name) AS 序号,
    DB_NAME() AS 关联数据库名,
    SCHEMA_NAME(p.schema_id) AS 架构名,
    p.name AS 存储过程名,
    '业务逻辑存储过程' AS 业务功能描述,
    CASE 
        WHEN OBJECT_DEFINITION(p.object_id) LIKE '%SELECT *%' THEN '高风险'
        WHEN OBJECT_DEFINITION(p.object_id) LIKE '%UPDATE%' 
          OR OBJECT_DEFINITION(p.object_id) LIKE '%DELETE%' THEN '中风险'
        ELSE '低风险' 
    END AS 风险等级,
    '未审核' AS 整改状态,
    p.create_date AS 创建时间,
    p.modify_date AS 最后修改时间,
    
    -- 修复：存储过程是否加密的正确写法
    CASE WHEN OBJECTPROPERTY(p.object_id, 'IsEncrypted') = 1 
         THEN '加密' 
         ELSE '未加密' 
    END AS 是否加密,
    
    'DBA' AS 负责人
FROM sys.procedures p
WHERE p.is_ms_shipped = 0 
  AND SCHEMA_NAME(p.schema_id) = 'dbo'
ORDER BY p.name;

-- ===================== 5. 数据库账号权限台账查询 =====================
SELECT
    ROW_NUMBER() OVER(ORDER BY sp.name) AS 序号,
    'SQL-' + CAST(SERVERPROPERTY('MachineName') AS VARCHAR) + '-01' AS 关联实例标识,
    sp.name AS 账号名,
    CASE WHEN sp.type IN ('U','G') THEN 'Windows账号' ELSE 'SQL账号' END AS 账号类型,
    r.name AS 所属角色,
    sp.create_date AS 创建时间,
    sp.modify_date AS 最后修改时间,
    sp.is_disabled AS 是否禁用,
    'DBA' AS 负责人
FROM sys.server_principals sp
LEFT JOIN sys.server_role_members rm ON sp.principal_id=rm.member_principal_id
LEFT JOIN sys.server_principals r ON rm.role_principal_id=r.principal_id
WHERE sp.type IN ('S','U','G') 
AND sp.name NOT LIKE '##%' AND sp.name NOT LIKE 'NT SERVICE%' AND sp.name<>'sa'


-- 实例台账
SELECT 
    ROW_NUMBER() OVER(ORDER BY (SELECT 1)) AS 序号,
    GETDATE() AS 执行日期,
    'DBA' AS 负责人,
    'SQL-' + CAST(SERVERPROPERTY('MachineName') AS VARCHAR(100)) + '-01' AS 实例唯一标识,
    CAST(SERVERPROPERTY('MachineName') AS VARCHAR(100)) AS 服务器主机名,
    ISNULL(CAST(SERVERPROPERTY('InstanceName') AS VARCHAR(100)), 'MSSQLSERVER') AS 实例名,
    CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)) AS SQL版本号,
    CAST(SERVERPROPERTY('Edition') AS VARCHAR(100)) AS 版本类型,
    CONVERT(VARCHAR(20),
        ISNULL(
            (SELECT value_data FROM sys.dm_server_registry 
             WHERE registry_key LIKE '%\IPAll' AND value_name = 'TcpPort' AND value_data <> '0'),
            (SELECT value_data FROM sys.dm_server_registry 
             WHERE registry_key LIKE '%\IPAll' AND value_name = 'TcpDynamicPorts' AND value_data <> '0')
        )
    ) AS 端口号,
    @@VERSION AS 操作系统版本,
    SUSER_SNAME() AS 运行账户,
    (SELECT physical_memory_kb / 1024.0 / 1024.0 FROM sys.dm_os_sys_info) AS 内存配置_GB,
    (SELECT cpu_count FROM sys.dm_os_sys_info) AS CPU核心数,
    CASE WHEN SERVERPROPERTY('IsClustered') = 1 THEN '是（集群）' ELSE '否（单机）' END AS 是否集群,
    SERVERPROPERTY('Collation') AS 实例排序规则,
    '生产环境' AS 环境类型,
    'MES系统核心实例' AS 备注
FROM sys.dm_os_sys_info;

-- 数据库基础设施台账（实例下所有数据库）
SELECT 
    ROW_NUMBER() OVER(ORDER BY d.name) AS 序号,
    @@SERVERNAME AS 实例标识, -- 新增：显示当前连接的SQL Server实例名
    d.name AS 数据库名,
    d.database_id as 数据库ID,
    SUSER_SNAME(d.owner_sid) AS 数据库所有者,
    d.create_date AS 创建时间,
    
    -- 计算数据库总大小 (GB)
    (SELECT SUM(size) * 8.0 / 1024 / 1024 
     FROM sys.master_files 
     WHERE database_id = d.database_id) AS 数据文件大小_GB,
     
    -- 新增：提取主数据文件路径 (.mdf)
    (SELECT MAX(CASE WHEN type_desc = 'ROWS' THEN physical_name END)
     FROM sys.master_files 
     WHERE database_id = d.database_id) AS 数据文件路径,
     
    -- 新增：提取事务日志文件路径 (.ldf)
    (SELECT MAX(CASE WHEN type_desc = 'LOG' THEN physical_name END)
     FROM sys.master_files 
     WHERE database_id = d.database_id) AS 日志文件路径,
     
    d.state_desc AS 状态,
    d.recovery_model_desc AS 恢复模式,
    d.name,
    'DBA' AS 负责人,
    CASE WHEN d.name IN ('master','model','msdb','tempdb') THEN '系统库' ELSE '用户库' END AS 库类型,
    '东莞100MES生产' AS 备注
FROM sys.databases d
ORDER BY d.database_id;

-- 数据表台账（当前数据库 mes）
USE [MES.WGWTB];
SELECT 
    ROW_NUMBER() OVER(ORDER BY s.name, t.name) AS 序号,
    GETDATE() AS 执行日期,
    'DBA' AS 负责人,
    DB_NAME() AS 数据库名,
    s.name AS 架构名,
    t.name AS 表名,
    t.create_date AS 创建时间,
    t.modify_date AS 最后修改时间,
    p.rows AS 行数,
    CAST(ROUND((SUM(a.total_pages) * 8.0 / 1024), 2) AS DECIMAL(18,2)) AS 数据大小_MB,
    CAST(ROUND((SUM(a.used_pages) * 8.0 / 1024), 2) AS DECIMAL(18,2)) AS 已用空间_MB,
    (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS 字段数量,
    CASE WHEN t.is_ms_shipped = 1 THEN '系统表' ELSE '业务表' END AS 表类型,
    'MES在制品/生产数据' AS 业务描述,
    '' AS 备注
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name, t.create_date, t.modify_date, p.rows, t.is_ms_shipped
ORDER BY s.name, t.name;

-- 权限与账号台账（实例 + 当前数据库）
SELECT 
    ROW_NUMBER() OVER(ORDER BY sp.name, dp.name) AS 序号,
    GETDATE() AS 执行日期,
    'DBA' AS 负责人,
    DB_NAME() AS 数据库名,
    sp.name AS 服务器登录名,
    sp.type_desc AS 登录类型,
    CASE WHEN sp.is_disabled = 1 THEN '已禁用' ELSE '启用' END AS 登录状态,
    dp.name AS 数据库用户名,
    dp.type_desc AS 用户类型,
    r.name AS 所属数据库角色,
    STRING_AGG(perm.permission_name + ' ON ' + 
               ISNULL(OBJECT_NAME(perm.major_id), 'DATABASE'), ', ') 
        AS 显式权限,
    'MES系统' AS 业务系统,
    '' AS 备注
FROM sys.server_principals sp
LEFT JOIN sys.database_principals dp 
    ON sp.sid = dp.sid
LEFT JOIN sys.database_role_members drm 
    ON dp.principal_id = drm.member_principal_id
LEFT JOIN sys.database_principals r 
    ON drm.role_principal_id = r.principal_id
LEFT JOIN sys.database_permissions perm 
    ON dp.principal_id = perm.grantee_principal_id
WHERE sp.type IN ('S','U','G')          -- SQL登录、Windows登录、组
  AND dp.type NOT IN ('A','R','X')      -- 排除应用角色和系统
GROUP BY sp.name, sp.type_desc, sp.is_disabled, 
         dp.name, dp.type_desc, r.name, DB_NAME()
ORDER BY sp.name, dp.name;


-----------------------------------------oracle数据库台账脚本-----------------------------------------------
