# SQL Server Always On 可用性组部署配置教程

## 目录
- [第一部分：Windows 版 Always On 部署](#第一部分 windows-版-always-on-部署)
- [第二部分：Linux 版 Always On 部署](#第二部分 linux-版-always-on-部署)

---

# 第一部分：Windows 版 Always On 部署

## 一、Always On 可用性组概述

### 1.1 什么是 Always On 可用性组
SQL Server Always On 可用性组是一种高可用性和灾难恢复解决方案，它提供：
- **自动故障转移**：在主副本故障时自动切换到辅助副本
- **可读辅助副本**：辅助副本可以用于读取操作和备份
- **多副本支持**：最多支持 8 个副本（2 个同步，6 个异步）
- **数据库级别保护**：可以针对一组数据库进行配置

### 1.2 核心概念
- **可用性组 (Availability Group)**：一组用户数据库的集合，用于故障转移
- **副本 (Replica)**：服务器实例，承载可用性组的数据库副本
- **主副本 (Primary Replica)**：处理所有读写操作的副本
- **辅助副本 (Secondary Replica)**：接收主副本日志并应用的副本
- **监听器 (Listener)**：虚拟网络名称，客户端通过它连接到可用性组

### 1.3 先决条件
#### 硬件和软件要求：
1. **操作系统**：Windows Server 2012 R2 或更高版本（推荐 2019/2022）
2. **SQL Server 版本**：Enterprise Edition（企业版）
3. **.NET Framework**：3.5 SP1 或更高版本
4. **域环境**：所有节点必须在同一个 Active Directory 域中
5. **网络**：稳定的网络连接，建议使用专用心跳网络

#### 环境规划示例：
```
主节点 (Node1):
- 主机名：SQLNODE1.dbadomain.com
- IP 地址：192.168.1.101
- 角色：主副本

辅助节点 (Node2):
- 主机名：SQLNODE2.dbadomain.com
- IP 地址：192.168.1.102
- 角色：同步提交辅助副本

见证节点 (可选):
- 主机名：SQLNODEWITNESS.dbadomain.com
- IP 地址：192.168.1.103
- 角色：文件共享见证

可用性组监听器:
- 监听器名称：AGListener
- IP 地址：192.168.1.200
- 端口：1433
```

---

## 二、Windows 环境准备阶段

### 2.1 配置 Windows Server 故障转移群集 (WSFC)

#### 步骤 1：在所有节点上安装故障转移群集功能
在 **SQLNODE1** 和 **SQLNODE2** 上分别执行（以管理员身份运行 PowerShell）：

```powershell
# 安装故障转移群集功能
Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools

# 验证安装
Get-WindowsFeature -Name Failover-Clustering
```

#### 步骤 2：创建 Active Directory 计算机对象 (可选但推荐)
```powershell
# 在域控制器上执行
New-ADComputer -Name "AGCluster" -ServicePrincipalNames "MSClusterVirtualServer/AGCluster.dbadomain.com"
```

#### 步骤 3：验证群集配置
在任一节点上执行：

```powershell
# 运行群集验证测试
Test-Cluster -Node SQLNODE1,SQLNODE2 -Include "Inventory","Network","System Configuration"

# 查看验证报告
# 验证完成后会在 C:\Windows\Cluster\Reports\ 生成 HTML 报告
```

**重要检查项**：
- ✅ 所有节点在同一域中
- ✅ 网络通信正常
- ✅ 共享存储（如使用）可访问
- ✅ 防火墙规则正确配置

#### 步骤 4：创建故障转移群集
```powershell
# 创建群集（不使用共享存储）
New-Cluster -Name AGCluster -Node SQLNODE1,SQLNODE2 -NoStorage -StaticAddress 192.168.1.100

# 或者使用向导创建（图形界面）
# 打开"故障转移群集管理器" -> "创建群集"
```

#### 步骤 5：配置群集仲裁
```powershell
# 查看当前仲裁配置
Get-ClusterQuorum

# 配置为节点多数（适用于 2 节点）
Set-ClusterQuorum -Cluster AGCluster -NodeMajority

# 或者配置文件共享见证（推荐 2 节点使用）
Set-ClusterQuorum -Cluster AGCluster -FileShareWitness "\\FILESERVER\WitnessShare"
```

### 2.2 配置 Active Directory 权限

#### 为群集创建计算机对象授予权限
```powershell
# 在域控制器上执行，授予群集计算机对象创建子对象的权限
$acl = Get-Acl "OU=Servers,DC=dbadomain,DC=com"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("AGCluster$", "FullControl", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "OU=Servers,DC=dbadomain,DC=com" $acl
```

### 2.3 配置 SQL Server 实例

#### 步骤 1：在所有节点上安装 SQL Server
确保在所有节点上安装：
- ✅ 相同版本的 SQL Server（建议 SQL Server 2019/2022 企业版）
- ✅ 相同的补丁级别
- ✅ 数据库引擎服务
- ✅ SQL Server Management Studio (SSMS)

#### 步骤 2：配置 SQL Server 服务账户
**推荐使用组托管服务账户 (gMSA)**：

```powershell
# 在域控制器上创建 gMSA
Add-KdsRootKey -EffectiveImmediately
New-ADServiceAccount -Name gmsa_sqlservice -DNSHostName gmsa_sqlservice.dbadomain.com -PrincipalsAllowedToRetrieveManagedPassword "SQLNODE1$","SQLNODE2$"

# 在 SQLNODE1 上安装 gMSA
Install-ADServiceAccount -Identity gmsa_sqlservice

# 在 SQLNODE2 上安装 gMSA
Install-ADServiceAccount -Identity gmsa_sqlservice
```

#### 步骤 3：启用 Always On 功能
在 **每个节点** 上执行：

```sql
-- 方法 1：使用 SQL Server 配置管理器（推荐）
-- 右键点击 SQL Server 服务 -> 属性 -> Always On 高可用性 -> 启用 Always On 可用性组

-- 方法 2：使用 PowerShell
Enable-SqlAlwaysOn -Path "SQLSERVER:\SQL\SQLNODE1\DEFAULT" -Force

-- 方法 3：使用 T-SQL（需要重启服务）
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'hadr enabled', 1;
RECONFIGURE;
-- 重启 SQL Server 服务后生效
```

#### 步骤 4：配置防火墙规则
在所有节点上执行（PowerShell 管理员）：

```powershell
# 开放 SQL Server 默认端口
New-NetFirewallRule -DisplayName "SQL Server TCP" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow

# 开放 SQL Server 浏览器端口
New-NetFirewallRule -DisplayName "SQL Server Browser" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow

# 开放 Always On 端点端口 (5022)
New-NetFirewallRule -DisplayName "Always On Endpoint" -Direction Inbound -Protocol TCP -LocalPort 5022 -Action Allow

# 开放 ICMP 用于心跳检测
New-NetFirewallRule -DisplayName "ICMP Heartbeat" -Direction Inbound -Protocol ICMPv4 -Action Allow
```

---

## 三、Windows 创建 Always On 可用性组

### 3.1 创建数据库镜像端点

在 **每个节点** 上执行以下 T-SQL：

```sql
-- 1. 创建数据库镜像端点
CREATE ENDPOINT [Hadr_endpoint] 
    STATE=STARTED
    AS TCP (LISTENER_PORT = 5022, LISTENER_IP = ALL)
    FOR DATA_MIRRORING (
        ROLE = ALL, 
        AUTHENTICATION = CERTIFICATE dbm_cert, 
        ENCRYPTION = REQUIRED ALGORITHM AES
    );

-- 2. 创建证书（如果不存在）
USE master;
CREATE CERTIFICATE dbm_cert 
    WITH SUBJECT = 'dbm_cert';

-- 3. 备份证书以便在其他节点还原
BACKUP CERTIFICATE dbm_cert   
    TO FILE = 'C:\Certificates\dbm_cert.cer';

-- 4. 在其他节点还原证书
-- 在 SQLNODE2 上执行：
USE master;
CREATE CERTIFICATE dbm_cert 
    FROM FILE = 'C:\Certificates\dbm_cert.cer';

-- 5. 授予连接权限
CREATE LOGIN [dbadomain\gmsa_sqlservice] FROM WINDOWS;
GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [dbadomain\gmsa_sqlservice];

-- 6. 验证端点
SELECT endpoint_id, name, state_desc, port 
FROM sys.database_mirroring_endpoints;
```

### 3.2 创建可用性组

#### 方法 1：使用 T-SQL（推荐用于自动化）

在 **主节点 (SQLNODE1)** 上执行：

```sql
-- 1. 创建可用性组
CREATE AVAILABILITY GROUP [AG_DatabaseGroup]
WITH (
    AUTOMATED_BACKUP_PREFERENCE = SECONDARY,  -- 备份偏好：辅助副本
    DATABASE_MIRRITORING_ENDPOINT_PORT = 5022,
    FAILOVER_MODE = AUTOMATIC,                 -- 自动故障转移
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT     -- 同步提交模式
)
FOR REPLICATION OFF
AS REPLICA ON 
    N'SQLNODE1' WITH (
        ENDPOINT_URL = N'TCP://SQLNODE1.dbadomain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        SEEDING_MODE = AUTOMATIC,              -- 自动播种
        BACKUP_PRIORITY = 50,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
    ),
    N'SQLNODE2' WITH (
        ENDPOINT_URL = N'TCP://SQLNODE2.dbadomain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        SEEDING_MODE = AUTOMATIC,
        BACKUP_PRIORITY = 40,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
    );

-- 2. 创建可用性组监听器
ALTER AVAILABILITY GROUP [AG_DatabaseGroup]
ADD LISTENER N'AGListener' (
    WITH IP ((N'192.168.1.200', N'255.255.255.0')),
    PORT = 1433
);
```

#### 方法 2：使用 SSMS 图形界面（适合初学者）

**步骤：**
1. 打开 SSMS，连接到 SQLNODE1
2. 展开"Always On 高可用性"文件夹
3. 右键点击"可用性组" -> "新建可用性组"
4. 输入可用性组名称：`AG_DatabaseGroup`
5. 选择数据库：勾选要添加的数据库
6. 指定副本：
   - 点击"添加副本" -> 选择 SQLNODE2
   - 设置同步提交模式
   - 设置自动故障转移
7. 配置监听器：
   - 名称：AGListener
   - IP 地址：192.168.1.200
   - 端口：1433
8. 配置数据同步方式：选择"自动播种"
9. 完成向导

### 3.3 添加数据库到可用性组

#### 方法 1：T-SQL 方式

```sql
-- 在主节点上执行
-- 1. 确保数据库处于完整恢复模式
USE master;
ALTER DATABASE [YourDatabase] SET RECOVERY FULL WITH NO_WAIT;

-- 2. 备份数据库和日志
BACKUP DATABASE [YourDatabase] TO DISK = '\\SharedFolder\YourDatabase_Full.bak';
BACKUP LOG [YourDatabase] TO DISK = '\\SharedFolder\YourDatabase_Log.trn';

-- 3. 将数据库添加到可用性组
ALTER DATABASE [YourDatabase] 
SET HADR AVAILABILITY GROUP = [AG_DatabaseGroup];

-- 4. 验证数据库状态
SELECT 
    db_name(database_id) as DatabaseName,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.recovery_lsn,
    drs.last_hardened_lsn,
    drs.last_redone_lsn,
    drs.log_send_queue_size,
    drs.redo_queue_size
FROM sys.dm_hadr_database_replica_states
WHERE drs.group_id = (SELECT group_id FROM sys.availability_groups WHERE name = 'AG_DatabaseGroup');
```

#### 方法 2：SSMS 方式
1. 右键点击可用性组 -> "添加数据库"
2. 选择要添加的数据库
3. 系统会自动检查先决条件
4. 选择数据同步方式（自动播种或手动还原）
5. 完成向导

---

## 四、Windows 配置和管理

### 4.1 验证可用性组状态

```sql
-- 1. 查看可用性组整体状态
SELECT 
    ag.name as AGName,
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.operational_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;

-- 2. 查看数据库复制状态
SELECT 
    db_name(drs.database_id) as DatabaseName,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.recovery_lsn,
    drs.last_hardened_lsn,
    drs.last_redone_lsn,
    drs.log_send_queue_size,
    drs.redo_queue_size
FROM sys.dm_hadr_database_replica_states drs;

-- 3. 查看监听器信息
SELECT 
    listener_id,
    dns_name,
    port,
    ip_configuration_string
FROM sys.availability_group_listeners;

-- 4. 查看端点状态
SELECT 
    name,
    state_desc,
    port
FROM sys.database_mirroring_endpoints;
```

### 4.2 配置读取路由（可选）

```sql
-- 配置只读路由，使读操作自动路由到辅助副本
-- 在主节点执行
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] MODIFY REPLICA ON 
    N'SQLNODE1' WITH (
        PRIMARY_ROLE (ALLOW_CONNECTIONS = READ_WRITE),
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY, READ_ONLY_ROUTING_URL = N'TCP://SQLNODE1.dbadomain.com:1433')
    );

ALTER AVAILABILITY GROUP [AG_DatabaseGroup] MODIFY REPLICA ON 
    N'SQLNODE2' WITH (
        PRIMARY_ROLE (ALLOW_CONNECTIONS = READ_WRITE),
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY, READ_ONLY_ROUTING_URL = N'TCP://SQLNODE2.dbadomain.com:1433')
    );

-- 配置读取路由列表
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] MODIFY LISTENER N'AGListener' (
    READ_ONLY_ROUTING_LIST = (N'SQLNODE1', N'SQLNODE2')
);
```

### 4.3 监控性能指标

```sql
-- 1. 监控日志发送延迟
SELECT 
    db_name(database_id) as DatabaseName,
    last_log_sent_time,
    last_hardened_time,
    last_redone_time,
    DATEDIFF(SECOND, last_log_sent_time, GETDATE()) as SendLatencySeconds,
    DATEDIFF(SECOND, last_hardened_time, GETDATE()) as HardenLatencySeconds,
    DATEDIFF(SECOND, last_redone_time, GETDATE()) as RedoLatencySeconds
FROM sys.dm_hadr_database_replica_states;

-- 2. 监控队列大小
SELECT 
    db_name(database_id) as DatabaseName,
    log_send_queue_size as LogSendQueueKB,
    redo_queue_size as RedoQueueKB,
    log_send_rate as LogSendRateKBPerSec,
    redo_rate as RedoRateKBPerSec
FROM sys.dm_hadr_database_replica_states;

-- 3. 监控故障转移历史
SELECT * FROM sys.dm_hadr_cluster_permon_counters 
WHERE counter_name LIKE '%failover%';
```

---

## 五、Windows 故障转移操作

### 5.1 计划内手动故障转移（推荐方式）

```sql
-- 在主节点执行计划内故障转移
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] FAILOVER;

-- 或使用 SSMS:
-- 右键点击可用性组 -> "故障转移" -> 选择目标副本
```

### 5.2 强制故障转移（仅在紧急情况下使用）

```sql
-- 当主节点完全不可用时，在辅助节点执行强制故障转移
-- 注意：可能导致数据丢失
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] FORCE_FAILOVER_ALLOW_DATA_LOSS;
```

### 5.3 测试故障转移

```sql
-- 1. 验证当前主副本
SELECT 
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_state_desc
FROM sys.availability_replicas ar
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ars.role_desc = 'PRIMARY';

-- 2. 执行故障转移
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] FAILOVER;

-- 3. 验证故障转移后的状态
-- 再次执行步骤 1 的查询，确认角色已切换

-- 4. 测试应用程序连接
-- 通过监听器名称连接，验证是否自动连接到新的主节点
```

---

## 六、Windows 常见问题排查

### 6.1 数据不同步问题

```sql
-- 检查同步状态
SELECT 
    db_name(database_id) as DatabaseName,
    synchronization_state_desc,
    synchronization_health_desc,
    last_hardened_lsn,
    last_redone_lsn
FROM sys.dm_hadr_database_replica_states;

-- 如果状态为 NOT_SYNCHRONIZING，检查：
-- 1. 端点连接状态
SELECT 
    ep.name,
    ep.state_desc,
    es.connectivity,
    es.role
FROM sys.database_mirroring_endpoints ep
JOIN sys.dm_hadr_endpoint_states es ON ep.endpoint_id = es.endpoint_id;

-- 2. 登录权限
SELECT 
    sp.state_desc,
    sp.permission_name,
    sp.grantee_principal_id
FROM sys.server_permissions sp
WHERE sp.major_id = (SELECT endpoint_id FROM sys.database_mirroring_endpoints WHERE name = 'Hadr_endpoint');
```

### 6.2 故障转移失败

**排查步骤：**
1. 检查 WSFC 群集状态
```powershell
Get-ClusterResource | Select-Object Name, State, ResourceType
Get-ClusterGroup | Select-Object Name, State, OwnerNode
```

2. 检查仲裁配置
```powershell
Get-ClusterQuorum
```

3. 查看 SQL Server 错误日志
```sql
EXEC xp_readerrorlog 0, 1, 'Always On';
```

4. 检查 Windows 事件日志
```powershell
Get-EventLog -LogName "Application" -Source "MSSQLSERVER" -Newest 50
```

### 6.3 监听器连接问题

```sql
-- 检查监听器状态
SELECT 
    listener_id,
    dns_name,
    port,
    ip_configuration_string,
    number_of_ip_addresses
FROM sys.availability_group_listeners;

-- 测试监听器连接
-- 在客户端机器上执行
-- telnet AGListener.dbadomain.com 1433

-- 检查 DNS 解析
nslookup AGListener.dbadomain.com
```

---

# 第二部分：Linux 版 Always On 部署

## 七、Linux Always On 概述和环境准备

### 7.1 Linux 版 Always On 特性

SQL Server 2017 开始在 Linux 上支持 Always On 可用性组，主要特性：
- ✅ 与 Windows 版本核心功能一致
- ✅ 基于 Pacemaker 集群管理器
- ✅ 支持 Red Hat Enterprise Linux (RHEL)、Ubuntu、SUSE
- ✅ 无需 Active Directory，使用本地认证
- ✅ 成本更低（无需 Windows 许可证）

### 7.2 系统要求

#### 操作系统要求：
1. **Red Hat Enterprise Linux (RHEL)** 7.4 或更高版本
2. **Ubuntu** 16.04 或更高版本
3. **SUSE Linux Enterprise Server (SLES)** 12 SP2 或更高版本

#### SQL Server 要求：
1. SQL Server 2017 CU20 或更高版本
2. SQL Server 2019 或更高版本（推荐）
3. 企业版或标准版（Linux 上两者都支持 Always On）

#### 环境规划示例（Linux）：
```
主节点 (Node1):
- 主机名：rhel1.dbadomain.com
- IP 地址：192.168.1.101
- OS: RHEL 8.4
- SQL Server: 2019 Enterprise

辅助节点 (Node2):
- 主机名：rhel2.dbadomain.com
- IP 地址：192.168.1.102
- OS: RHEL 8.4
- SQL Server: 2019 Enterprise

见证节点（可选）:
- 主机名：rhel3.dbadomain.com
- IP 地址：192.168.1.103

可用性组监听器:
- 监听器名称：aglistener.dbadomain.com
- IP 地址：192.168.1.200
- 端口：1433
```

### 7.3 网络配置要求

**在所有 Linux 节点上执行：**

#### 1. 配置主机名解析
编辑 `/etc/hosts` 文件：
```bash
sudo vi /etc/hosts

# 添加以下内容
192.168.1.101  rhel1.dbadomain.com  rhel1
192.168.1.102  rhel2.dbadomain.com  rhel2
192.168.1.103  rhel3.dbadomain.com  rhel3
192.168.1.200  aglistener.dbadomain.com  aglistener
```

#### 2. 验证主机名解析
```bash
ping rhel1.dbadomain.com
ping rhel2.dbadomain.com
ping aglistener.dbadomain.com
```

#### 3. 配置防火墙
```bash
# RHEL/CentOS/Fedora - 使用 firewalld
sudo firewall-cmd --permanent --add-port=1433/tcp
sudo firewall-cmd --permanent --add-port=5022/tcp
sudo firewall-cmd --permanent --add-port=59999/tcp
sudo firewall-cmd --reload

# Ubuntu - 使用 ufw
sudo ufw allow 1433/tcp
sudo ufw allow 5022/tcp
sudo ufw allow 59999/tcp
sudo ufw reload

# SLES - 使用 SuSEfirewall2
sudo SuSEfirewall2 open EXT TCP 1433
sudo SuSEfirewall2 open EXT TCP 5022
sudo SuSEfirewall2 open EXT TCP 59999
sudo rcSuSEfirewall2 restart
```

---

## 八、Linux 安装和配置 SQL Server

### 8.1 在所有节点上安装 SQL Server

#### RHEL/CentOS 安装步骤：

```bash
# 1. 注册 Microsoft RPM 仓库
sudo rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-mssql-server-2019.repo

# 2. 安装 SQL Server
sudo yum install -y mssql-server

# 3. 运行配置向导
sudo /opt/mssql/bin/mssql-conf setup

# 选择版本（输入 2 表示企业版）
# 接受许可条款
# 设置 SA 密码（需符合复杂度要求）
```

#### Ubuntu 安装步骤：

```bash
# 1. 添加 Microsoft 仓库
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo add-apt-repository "$(wget -qO- https://packages.microsoft.com/config/ubuntu/20.04/mssql-server-2019.list)"

# 2. 更新包列表
sudo apt-get update

# 3. 安装 SQL Server
sudo apt-get install -y mssql-server

# 4. 运行配置向导
sudo /opt/mssql/bin/mssql-conf setup
```

#### SLES 安装步骤：

```bash
# 1. 添加 Microsoft 仓库
sudo zypper addrepo https://packages.microsoft.com/config/sles/15/packages-mssql-server-2019.repo
sudo zypper refresh

# 2. 安装 SQL Server
sudo zypper install -y mssql-server

# 3. 运行配置向导
sudo /opt/mssql/bin/mssql-conf setup
```

### 8.2 验证 SQL Server 安装

```bash
# 检查服务状态
systemctl status mssql-server

# 启动服务
sudo systemctl start mssql-server

# 启用开机自启
sudo systemctl enable mssql-server

# 检查 SQL Server 进程
ps aux | grep sqlservr
```

### 8.3 安装 SQL Server 命令行工具

```bash
# RHEL/CentOS
sudo yum install -y mssql-tools unixODBC-devel

# Ubuntu
sudo apt-get install -y mssql-tools unixodbc-dev

# SLES
sudo zypper install -y mssql-tools unixODBC

# 添加到 PATH
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bash_profile
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 8.4 启用 Always On 功能

在 **每个节点** 上执行：

```bash
# 1. 启用 Always On
sudo /opt/mssql/bin/mssql-conf set hadr.hadr_enabled 1

# 2. 重启 SQL Server 服务
sudo systemctl restart mssql-server

# 3. 验证 Always On 已启用
sudo /opt/mssql/bin/mssql-conf get hadr.hadr_enabled

# 应该返回：true
```

### 8.5 配置 SQL Server 服务账户权限

Linux 上不需要特殊的域账户，使用本地系统账户即可。但需要确保：
- ✅ 所有节点使用相同的 SA 密码
- ✅ 或者配置 Kerberos 认证（可选）

---

## 九、Linux 配置 Pacemaker 集群

### 9.1 在所有节点上安装 Pacemaker

#### RHEL/CentOS:

```bash
# 1. 安装 Pacemaker 和相关工具
sudo yum install -y pacemaker pcs corosync fence-agents-all resource-agents

# 2. 启动 pcsd 服务
sudo systemctl start pcsd
sudo systemctl enable pcsd

# 3. 设置 hacluster 用户密码
sudo passwd hacluster
# 输入相同的密码（所有节点必须一致）
```

#### Ubuntu:

```bash
# 1. 安装 Pacemaker
sudo apt-get install -y pacemaker pcs corosync fence-agents resource-agents

# 2. 启动 pcsd 服务
sudo systemctl start pcsd
sudo systemctl enable pcsd

# 3. 设置 hacluster 用户密码
sudo passwd hacluster
```

#### SLES:

```bash
# 1. 安装 Pacemaker
sudo zypper install -y pacemaker pcs corosync fence-agents resource-agents

# 2. 启动 pcsd 服务
sudo systemctl start pcsd
sudo systemctl enable pcsd

# 3. 设置 hacluster 用户密码
sudo passwd hacluster
```

### 9.2 创建和配置集群

#### 步骤 1：对 hacluster 用户进行身份验证

在 **其中一个节点** 上执行：

```bash
# 清除旧的认证
pcs host auth clean

# 对所有节点进行身份验证
pcs host auth rhel1.dbadomain.com rhel2.dbadomain.com username=hacluster

# 输入 hacluster 用户的密码
```

#### 步骤 2：创建集群

```bash
# 创建集群
pcs cluster setup AGCluster rhel1.dbadomain.com rhel2.dbadomain.com

# 启用集群
pcs cluster enable --all

# 启动集群
pcs cluster start --all

# 查看集群状态
pcs status cluster
pcs status nodes
```

#### 步骤 3：配置集群属性

```bash
# 禁用 STONITH（仅用于测试环境，生产环境建议启用）
pcs property set stonith-enabled=false

# 配置集群策略
pcs property set no-quorum-policy=ignore
pcs property set cluster-infrastructure=corosync
pcs property set cluster-name=AGCluster

# 查看集群属性
pcs property
```

#### 步骤 4：验证集群状态

```bash
# 查看完整集群状态
pcs status

# 应该看到：
# Cluster Summary
# * Stack: corosync
# * Last updated: ...
# * 2 nodes configured
# * 0 resource instances configured
```

### 9.3 创建集群用户（用于 SQL Server 认证）

在 **每个节点** 上执行：

```bash
# 创建 Linux 用户用于集群认证
sudo useradd -m mssql
sudo passwd mssql
# 设置密码（所有节点相同）

# 授予用户必要的权限
sudo usermod -aG mssql mssql
```

---

## 十、Linux 创建 Always On 可用性组

### 10.1 创建数据库镜像端点

在 **每个节点** 上使用 sqlcmd 连接 SQL Server：

```bash
# 连接到 SQLNODE1
sqlcmd -S localhost -U sa -Q "CREATE ENDPOINT [Hadr_endpoint] STATE=STARTED AS TCP (LISTENER_PORT = 5022, LISTENER_IP = ALL) FOR DATA_MIRRORING (ROLE = ALL, AUTHENTICATION = CERTIFICATE dbm_cert, ENCRYPTION = REQUIRED ALGORITHM AES);"

# 创建证书
sqlcmd -S localhost -U sa -d master -Q "CREATE CERTIFICATE dbm_cert WITH SUBJECT = 'dbm_cert';"

# 备份证书
sqlcmd -S localhost -U sa -d master -Q "BACKUP CERTIFICATE dbm_cert TO FILE = '/var/opt/mssql/data/dbm_cert.cer';"
```

**在节点之间传输证书：**

```bash
# 在 rhel1 上执行，将证书复制到 rhel2
scp /var/opt/mssql/data/dbm_cert.cer rhel2:/var/opt/mssql/data/

# 在 rhel2 上还原证书
sqlcmd -S localhost -U sa -d master -Q "CREATE CERTIFICATE dbm_cert FROM FILE = '/var/opt/mssql/data/dbm_cert.cer';"
```

**授予端点连接权限：**

```bash
# 在每个节点上执行
sqlcmd -S localhost -U sa -d master -Q "CREATE LOGIN [mssql] WITH PASSWORD = 'YourStrongPassword!';"
sqlcmd -S localhost -U sa -d master -Q "GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [mssql];"
sqlcmd -S localhost -U sa -d master -Q "ALTER SERVER ROLE [sysadmin] ADD MEMBER [mssql];"
```

### 10.2 创建可用性组

在 **主节点 (rhel1)** 上执行：

```bash
# 创建可用性组
sqlcmd -S localhost -U sa -d master -Q "
CREATE AVAILABILITY GROUP [AG_DatabaseGroup]
WITH (
    CLUSTER_TYPE = EXTERNAL,
    AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
    FAILOVER_MODE = EXTERNAL,
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT
)
FOR REPLICATION OFF
AS REPLICA ON 
    N'rhel1.dbadomain.com' WITH (
        ENDPOINT_URL = N'TCP://rhel1.dbadomain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = EXTERNAL,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
    ),
    N'rhel2.dbadomain.com' WITH (
        ENDPOINT_URL = N'TCP://rhel2.dbadomain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = EXTERNAL,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
    );
"
```

### 10.3 授权集群管理可用性组

在 **每个节点** 上执行：

```bash
# 授权集群控制可用性组
sqlcmd -S localhost -U sa -d master -Q "ALTER AVAILABILITY GROUP [AG_DatabaseGroup] GRANT CREATE ANY DATABASE;"
sqlcmd -S localhost -U sa -d master -Q "ALTER AVAILABILITY GROUP [AG_DatabaseGroup] GRANT CONNECT;"
```

### 10.4 加入辅助节点到可用性组

在 **辅助节点 (rhel2)** 上执行：

```bash
# 加入可用性组
sqlcmd -S localhost -U sa -d master -Q "
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] JOIN WITH (
    CLUSTER_TYPE = EXTERNAL,
    SEEDING_MODE = AUTOMATIC
);
"
```

### 10.5 创建可用性组监听器

在 **主节点** 上执行：

```bash
# 创建监听器
sqlcmd -S localhost -U sa -d master -Q "
ALTER AVAILABILITY GROUP [AG_DatabaseGroup]
ADD LISTENER N'aglistener' (
    WITH IP ((N'192.168.1.200', N'255.255.255.0')),
    PORT = 1433
);
"
```

---

## 十一、Linux 配置 Pacemaker 资源

### 11.1 创建 Pacemaker 资源

在 **任意集群节点** 上执行：

```bash
# 1. 创建 availability-group 资源
pcs resource create ag_ag-database-group ocf:mssql:ag \
    ag_name=AG_DatabaseGroup \
    cluster_login=mssql \
    cluster_passwd=YourStrongPassword! \
    op monitor interval=10s \
    op promote timeout=60s \
    op demote timeout=60s \
    op stop timeout=60s \
    op start timeout=60s \
    meta failure-timeout=60s \
    clone interleave=true \
    promoted-max=1 \
    promoted-name=Master \
    clone-name=Slave

# 2. 创建 listener 资源
pcs resource create listener_ag-database-group ocf:mssql:listener \
    ag_name=AG_DatabaseGroup \
    cluster_login=mssql \
    cluster_passwd=YourStrongPassword! \
    op monitor interval=10s \
    op start timeout=60s \
    op stop timeout=60s
```

### 11.2 配置资源约束

```bash
# 1. 配置监听器依赖于可用性组
pcs constraint order promote ag_ag-database-group-clone then listener_ag-database-group kind=Mandatory

# 2. 配置共置约束（监听器和可用性组在同一节点）
pcs constraint colocation add listener_ag-database-group with ag_ag-database-group-clone score=INFINITY

# 3. 配置故障转移策略
pcs constraint location ag_ag-database-group-clone prefers rhel1.dbadomain.com=50
pcs constraint location ag_ag-database-group-clone prefers rhel2.dbadomain.com=40
```

### 11.3 验证资源配置

```bash
# 查看所有资源
pcs resource show

# 查看资源状态
pcs status resources

# 查看完整集群状态
pcs status

# 预期输出示例：
# Clone Set: ag_ag-database-group-clone [ag_ag-database-group]
#  Promoted: 1 [rhel1.dbadomain.com]
#  Stopped: 1 [rhel2.dbadomain.com]
# Resource Group: listener_ag-database-group
#  listener_ag-database-group (ocf::mssql:listener): Started rhel1.dbadomain.com
```

---

## 十二、Linux 添加数据库到可用性组

### 12.1 创建示例数据库

在 **主节点 (rhel1)** 上执行：

```bash
# 1. 创建测试数据库
sqlcmd -S localhost -U sa -Q "
CREATE DATABASE [TestDB];
ALTER DATABASE [TestDB] SET RECOVERY FULL;
"

# 2. 将数据库添加到可用性组
sqlcmd -S localhost -U sa -d master -Q "
ALTER DATABASE [TestDB] SET HADR AVAILABILITY GROUP = [AG_DatabaseGroup];
"

# 3. 验证数据库状态
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    db_name(database_id) as DatabaseName,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.last_hardened_lsn,
    drs.last_redone_lsn
FROM sys.dm_hadr_database_replica_states drs
WHERE drs.group_id = (SELECT group_id FROM sys.availability_groups WHERE name = 'AG_DatabaseGroup');
"
```

### 12.2 使用 SSMS 添加数据库（可选）

如果你使用 SSMS 连接到 Linux SQL Server：
1. 连接到 rhel1.dbadomain.com
2. 展开"Always On 高可用性" -> "可用性组"
3. 右键点击 AG_DatabaseGroup -> "添加数据库"
4. 选择要添加的数据库
5. 完成向导

---

## 十三、Linux 监控和管理

### 13.1 监控可用性组状态

```bash
# 1. 查看可用性组状态
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    ag.name as AGName,
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.operational_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;
"

# 2. 查看数据库同步状态
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    db_name(drs.database_id) as DatabaseName,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.log_send_queue_size,
    drs.redo_queue_size,
    drs.log_send_rate,
    drs.redo_rate
FROM sys.dm_hadr_database_replica_states drs;
"

# 3. 查看监听器状态
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    listener_id,
    dns_name,
    port,
    ip_configuration_string
FROM sys.availability_group_listeners;
"
```

### 13.2 监控 Pacemaker 集群

```bash
# 查看集群状态
pcs status

# 查看集群日志
journalctl -u pacemaker -f

# 查看资源历史
pcs resource debug-fail ag_ag-database-group-clone

# 监控集群实时日志
tail -f /var/log/cluster/corosync.log
```

### 13.3 性能监控脚本

创建一个监控脚本 `/opt/mssql/scripts/ag_monitor.sh`：

```bash
#!/bin/bash

# SQL Server Always On 监控脚本

SQLCMD="/opt/mssql-tools/bin/sqlcmd"
SA_PASSWORD="YourStrongPassword!"
SERVER="localhost"

echo "=== SQL Server Always On 健康检查 ==="
echo "时间：$(date)"
echo ""

# 检查 SQL Server 服务
if systemctl is-active --quiet mssql-server; then
    echo "✓ SQL Server 服务运行正常"
else
    echo "✗ SQL Server 服务未运行！"
    exit 1
fi

# 检查集群状态
echo ""
echo "=== Pacemaker 集群状态 ==="
pcs status cluster

# 检查可用性组状态
echo ""
echo "=== 可用性组状态 ==="
$SQLCMD -S $SERVER -U sa -P $SA_PASSWORD -d master -Q "
SELECT 
    ar.replica_server_name as '副本服务器',
    ars.role_desc as '角色',
    ars.synchronization_health_desc as '同步健康状态',
    ars.operational_state_desc as '操作状态'
FROM sys.availability_replicas ar
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;
"

# 检查数据库同步延迟
echo ""
echo "=== 数据库同步状态 ==="
$SQLCMD -S $SERVER -U sa -P $SA_PASSWORD -d master -Q "
SELECT 
    db_name(database_id) as '数据库名',
    synchronization_state_desc as '同步状态',
    log_send_queue_size as '日志发送队列 (KB)',
    redo_queue_size as '重做队列 (KB)'
FROM sys.dm_hadr_database_replica_states;
"

echo ""
echo "=== 检查完成 ==="
```

**赋予执行权限并定时执行：**

```bash
# 赋予执行权限
sudo chmod +x /opt/mssql/scripts/ag_monitor.sh

# 添加到 crontab（每 5 分钟执行一次）
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/mssql/scripts/ag_monitor.sh >> /var/log/ag_monitor.log 2>&1") | crontab -
```

---

## 十四、Linux 故障转移操作

### 14.1 计划内手动故障转移

#### 方法 1：使用 Pacemaker 命令（推荐）

```bash
# 执行故障转移到 rhel2
pcs resource move ag_ag-database-group-clone rhel2.dbadomain.com

# 验证故障转移
pcs status resources

# 清除移动约束（让集群自动管理）
pcs resource clear ag_ag-database-group-clone
```

#### 方法 2：使用 T-SQL

```bash
# 在主节点执行
sqlcmd -S localhost -U sa -d master -Q "
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] FAILOVER;
"
```

### 14.2 强制故障转移（紧急情况）

```bash
# 当主节点完全失效时，在辅助节点执行
sqlcmd -S localhost -U sa -d master -Q "
ALTER AVAILABILITY GROUP [AG_DatabaseGroup] FORCE_FAILOVER_ALLOW_DATA_LOSS;
"
```

### 14.3 测试故障转移场景

#### 测试 1：模拟主节点 SQL Server 故障

```bash
# 在主节点停止 SQL Server 服务
sudo systemctl stop mssql-server

# 等待 30 秒，观察集群自动故障转移
pcs status resources

# 重新启动 SQL Server 服务
sudo systemctl start mssql-server
```

#### 测试 2：模拟整个主节点故障

```bash
# 关闭主节点网络
sudo ifconfig eth0 down

# 观察集群行为
# 在辅助节点查看状态
pcs status

# 恢复网络
sudo ifconfig eth0 up
```

#### 测试 3：验证应用程序连接

```bash
# 从客户端持续 ping 监听器
ping aglistener.dbadomain.com

# 使用 sqlcmd 测试连接
sqlcmd -S aglistener.dbadomain.com -U sa -P YourStrongPassword! -Q "SELECT @@SERVERNAME;"

# 在故障转移期间，连接应该短暂中断后自动恢复
```

---

## 十五、Linux 常见问题排查

### 15.1 集群无法启动

```bash
# 1. 检查 pcsd 服务状态
sudo systemctl status pcsd

# 2. 检查 corosync 服务
sudo systemctl status corosync

# 3. 检查 pacemaker 服务
sudo systemctl status pacemaker

# 4. 查看日志
sudo journalctl -u corosync -f
sudo journalctl -u pacemaker -f

# 5. 重新认证集群节点
pcs host auth rhel1.dbadomain.com rhel2.dbadomain.com username=hacluster

# 6. 重新创建集群（最后手段）
pcs cluster destroy
pcs cluster setup AGCluster rhel1.dbadomain.com rhel2.dbadomain.com
```

### 15.2 可用性组不同步

```bash
# 1. 检查端点状态
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    ep.name,
    ep.state_desc,
    es.connectivity,
    es.role
FROM sys.database_mirroring_endpoints ep
JOIN sys.dm_hadr_endpoint_states es ON ep.endpoint_id = es.endpoint_id;
"

# 2. 检查证书是否有效
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    name,
    expiry_date,
    subject
FROM sys.certificates
WHERE name = 'dbm_cert';
"

# 3. 检查端点权限
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    sp.state_desc,
    sp.permission_name,
    sl.name as login_name
FROM sys.server_permissions sp
JOIN sys.server_principals sl ON sp.grantee_principal_id = sl.principal_id
WHERE sp.major_id = (SELECT endpoint_id FROM sys.database_mirroring_endpoints WHERE name = 'Hadr_endpoint');
"

# 4. 重新同步数据库（如有必要）
sqlcmd -S localhost -U sa -d master -Q "
ALTER DATABASE [YourDatabase] SET HADR SUSPEND;
ALTER DATABASE [YourDatabase] SET HADR RESUME;
"
```

### 15.3 监听器无法连接

```bash
# 1. 检查监听器 IP 配置
sqlcmd -S localhost -U sa -d master -Q "
SELECT 
    listener_id,
    dns_name,
    port,
    ip_configuration_string
FROM sys.availability_group_listeners;
"

# 2. 测试网络连通性
ping aglistener.dbadomain.com
telnet aglistener.dbadomain.com 1433

# 3. 检查防火墙规则
sudo firewall-cmd --list-all

# 4. 验证 DNS 解析
nslookup aglistener.dbadomain.com

# 5. 检查 Pacemaker listener 资源状态
pcs resource show listener_ag-database-group
pcs resource debug-fail listener_ag-database-group
```

### 15.4 Pacemaker 资源启动失败

```bash
# 1. 查看资源详细状态
pcs resource show ag_ag-database-group --full

# 2. 查看资源操作历史
pcs resource operations

# 3. 手动测试 OCF 脚本
sudo /usr/lib/ocf/resource.d/mssql/ag monitor ag_name=AG_DatabaseGroup

# 4. 增加超时时间
pcs resource update ag_ag-database-group op start timeout=120s
pcs resource update ag_ag-database-group op stop timeout=120s

# 5. 临时禁用资源监控
pcs resource disable ag_ag-database-group
pcs resource enable ag_ag-database-group
```

### 15.5 有用的诊断查询

```bash
# 保存为 diagnostic_queries.sql
cat > /opt/mssql/scripts/diagnostic_queries.sql << 'EOF'
-- 1. 检查 Always On 配置
SELECT 
    name,
    cluster_type_desc,
    automated_backup_preference_desc,
    failure_condition_level,
    health_check_timeout
FROM sys.availability_groups;

-- 2. 检查副本配置
SELECT 
    replica_server_name,
    role_desc,
    availability_mode_desc,
    failover_mode_desc,
    session_timeout
FROM sys.availability_replicas;

-- 3. 检查端点连接
SELECT 
    local_ep.name as local_endpoint,
    remote_ep.name as remote_endpoint,
    rcs.connected_state_desc,
    rcs.connectivity_error_count
FROM sys.dm_hadr_cluster_members cm
JOIN sys.dm_hadr_cluster_states rcs ON cm.member_id = rcs.member_id
CROSS APPLY sys.database_mirroring_endpoints local_ep
CROSS APPLY sys.database_mirroring_endpoints remote_ep;

-- 4. 检查数据库健康状态
SELECT 
    db_name(database_id) as database_name,
    synchronization_state_desc,
    synchronization_health_desc,
    recovery_lsn,
    last_hardened_lsn,
    last_redone_lsn,
    log_send_queue_size,
    redo_queue_size
FROM sys.dm_hadr_database_replica_states;

-- 5. 检查等待统计
SELECT 
    wait_type,
    waiting_tasks_count,
    wait_delay_ms,
    total_wait_duration_ms
FROM sys.dm_hadr_sync_stats;
EOF

# 执行诊断查询
sqlcmd -S localhost -U sa -P YourStrongPassword! -i /opt/mssql/scripts/diagnostic_queries.sql
```

---

## 十六、最佳实践和性能优化

### 16.1 Linux 系统优化

#### 1. 调整内核参数
编辑 `/etc/sysctl.conf`：

```bash
# 添加到文件末尾
vim /etc/sysctl.conf

# 内存管理
vm.swappiness = 1
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.overcommit_memory = 2
vm.overcommit_ratio = 80

# 网络优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_tw_reuse = 1
net.core.netdev_max_backlog = 5000

# 应用更改
sudo sysctl -p
```

#### 2. 配置透明大页面（THP）
```bash
# 检查 THP 状态
cat /sys/kernel/mm/transparent_hugepage/enabled

# 禁用 THP（推荐用于 SQL Server）
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# 永久禁用（编辑 grub）
sudo vim /etc/default/grub
# 添加：transparent_hugepage=never
GRUB_CMDLINE_LINUX="transparent_hugepage=never"

# 更新 grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot
```

#### 3. 配置 I/O 调度器
```bash
# 查看当前 I/O 调度器
cat /sys/block/sda/queue/scheduler

# 临时更改为 deadline（推荐用于数据库）
echo deadline | sudo tee /sys/block/sda/queue/scheduler

# 永久更改
sudo vim /etc/default/grub
# 添加：elevator=deadline
GRUB_CMDLINE_LINUX="elevator=deadline"

sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot
```

### 16.2 SQL Server 配置优化

#### 1. 配置内存限制
```bash
# 设置最大服务器内存（保留内存给 OS）
sudo /opt/mssql/bin/mssql-conf set memory memorylimitmb 14336
# 示例：16GB 总内存，分配 14GB 给 SQL Server

# 重启 SQL Server
sudo systemctl restart mssql-server
```

#### 2. 配置 TempDB
```bash
# 根据 CPU 核心数配置 TempDB 文件数量
# 推荐：CPU 核心数的 1/4 到 1/2，最多 8 个文件

sudo /opt/mssql/bin/mssql-conf set tempdb filecount 4
sudo /opt/mssql/bin/mssql-conf set tempdb size 1024
sudo /opt/mssql/bin/mssql-conf set tempdb autogrow 512

sudo systemctl restart mssql-server
```

#### 3. 优化最大工作线程数
```bash
# 对于高并发场景
sudo /opt/mssql/bin/mssql-conf set network maxworkerconnections 32767
sudo systemctl restart mssql-server
```

### 16.3 Pacemaker 优化

#### 1. 调整故障转移阈值
```bash
# 配置资源失败阈值
pcs resource update ag_ag-database-group \
    op monitor interval=10s on-fail=restart \
    migration-threshold=3 \
    failure-timeout=300s
```

#### 2. 配置资源依赖
```bash
# 确保网络资源先于 SQL Server 启动
pcs constraint order NetworkManager then ag_ag-database-group-clone
```

#### 3. 优化集群检测间隔
```bash
# 调整集群属性
pcs property set pe-warn-series=5
pcs property set pe-input-series=400
pcs property set dc-deadtime=20s
pcs property set iso-freq-min=1000ms
```

### 16.4 监控告警配置

#### 创建监控脚本 `/opt/mssql/scripts/ag_alert.sh`：

```bash
#!/bin/bash

# Always On 告警脚本
# 配置邮件通知或其他告警方式

ALERT_EMAIL="dba@yourcompany.com"
LOG_FILE="/var/log/ag_alert.log"

check_and_alert() {
    local condition=$1
    local message=$2
    
    if [ "$condition" = true ]; then
        echo "$(date): ALERT - $message" >> $LOG_FILE
        # 发送邮件告警
        echo "$message" | mail -s "SQL Server AG Alert" $ALERT_EMAIL
        # 或者调用其他告警 API
        # curl -X POST -H "Content-Type: application/json" \
        #     -d "{\"text\":\"$message\"}" \
        #     https://hooks.slack.com/services/YOUR/WEBHOOK/URL
    fi
}

# 检查同步延迟
SYNC_DELAY=$(sqlcmd -S localhost -U sa -P YourStrongPassword! -d master -t 5 -h -1 -Q "
SELECT ISNULL(MAX(DATEDIFF(SECOND, last_log_sent_time, GETDATE())), 0)
FROM sys.dm_hadr_database_replica_states;
")

check_and_alert [ $SYNC_DELAY -gt 30 ] "同步延迟超过 30 秒：${SYNC_DELAY}秒"

# 检查队列大小
QUEUE_SIZE=$(sqlcmd -S localhost -U sa -P YourStrongPassword! -d master -t 5 -h -1 -Q "
SELECT ISNULL(MAX(log_send_queue_size), 0)
FROM sys.dm_hadr_database_replica_states;
")

check_and_alert [ $QUEUE_SIZE -gt 102400 ] "日志发送队列过大：${QUEUE_SIZE}KB"

# 检查副本角色变化
ROLE=$(sqlcmd -S localhost -U sa -P YourStrongPassword! -d master -t 5 -h -1 -Q "
SELECT TOP 1 role_desc FROM sys.dm_hadr_availability_replica_states;
")

if [ "$ROLE" = "SECONDARY" ]; then
    check_and_alert true "当前节点已切换为辅助副本"
fi
```

**配置定时任务：**

```bash
# 每 2 分钟检查一次
(crontab -l 2>/dev/null; echo "*/2 * * * * /opt/mssql/scripts/ag_alert.sh") | crontab -
```

---

## 十七、备份和恢复策略

### 17.1 配置备份偏好

```bash
# 设置备份偏好（在辅助副本执行备份）
sqlcmd -S localhost -U sa -d master -Q "
ALTER AVAILABILITY GROUP [AG_DatabaseGroup]
MODIFY SET (AUTOMATED_BACKUP_PREFERENCE = SECONDARY);
"

# 配置备份优先级
sqlcmd -S rhel1.dbadomain.com -U sa -d master -Q "
ALTER AVAILABILITY GROUP [AG_DatabaseGroup]
MODIFY REPLICA ON N'rhel1.dbadomain.com' WITH (BACKUP_PRIORITY = 50);
"

sqlcmd -S rhel2.dbadomain.com -U sa -d master -Q "
ALTER AVAILABILITY GROUP [AG_DatabaseGroup]
MODIFY REPLICA ON N'rhel2.dbadomain.com' WITH (BACKUP_PRIORITY = 40);
"
```

### 17.2 创建备份脚本

创建 `/opt/mssql/scripts/backup_ag.sh`：

```bash
#!/bin/bash

# Always On 环境下的备份脚本
# 只在备份优先级高的副本上执行备份

SA_PASSWORD="YourStrongPassword!"
BACKUP_DIR="/var/opt/mssql/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

# 检查当前节点是否适合备份
IS_PREFERRED=$(sqlcmd -S localhost -U sa -P $SA_PASSWORD -d master -h -1 -t 5 -Q "
DECLARE @backup_priority INT;
SELECT @backup_priority = ars.backup_priority
FROM sys.dm_hadr_availability_replica_states ars
JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
WHERE ag.name = 'AG_DatabaseGroup';

-- 获取其他副本的优先级
DECLARE @other_priority INT;
SELECT @other_priority = MAX(ars.backup_priority)
FROM sys.dm_hadr_availability_replica_states ars
JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
WHERE ag.name = 'AG_DatabaseGroup'
AND ars.role_desc != (SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE group_id = ag.group_id);

-- 如果当前节点优先级更高，或者是唯一可用节点，则执行备份
IF (@backup_priority >= ISNULL(@other_priority, 0)) OR @other_priority IS NULL
    SELECT 1;
ELSE
    SELECT 0;
")

if [ "$IS_PREFERRED" = "1" ]; then
    echo "当前节点执行备份..."
    
    # 备份所有 AG 数据库
    sqlcmd -S localhost -U sa -P $SA_PASSWORD -Q "
    DECLARE @db_name NVARCHAR(128);
    DECLARE backup_cursor CURSOR FOR 
    SELECT db_name(database_id) 
    FROM sys.dm_hadr_database_replica_states 
    WHERE group_id = (SELECT group_id FROM sys.availability_groups WHERE name = 'AG_DatabaseGroup');
    
    OPEN backup_cursor;
    FETCH NEXT FROM backup_cursor INTO @db_name;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @sql NVARCHAR(MAX);
        SET @sql = 'BACKUP DATABASE [' + @db_name + '] TO DISK = ''' + '$BACKUP_DIR/' + @db_name + '_FULL_' + '$DATE' + '.bak'' WITH COMPRESSION, STATS = 10';
        EXEC sp_executesql @sql;
        
        FETCH NEXT FROM backup_cursor INTO @db_name;
    END
    
    CLOSE backup_cursor;
    DEALLOCATE backup_cursor;
    "
    
    echo "备份完成"
else
    echo "当前节点不是首选备份节点，跳过备份"
fi
```

### 17.3 恢复测试

```bash
# 1. 从备份恢复数据库到新实例
sqlcmd -S localhost -U sa -Q "
RESTORE DATABASE [TestDB_Restored] 
FROM DISK = '/var/opt/mssql/backups/TestDB_FULL_20260314_120000.bak'
WITH MOVE 'TestDB' TO '/var/opt/mssql/data/TestDB_Restored.mdf',
MOVE 'TestDB_log' TO '/var/opt/mssql/data/TestDB_Restored_log.ldf',
REPLACE;
"

# 2. 验证恢复结果
sqlcmd -S localhost -U sa -Q "
SELECT name, state_desc, recovery_model_desc 
FROM sys.databases 
WHERE name = 'TestDB_Restored';
"
```

---

## 十八、完整部署示例和验证清单

### 18.1 自动化部署脚本

创建一个完整的自动化部署脚本 `/opt/mssql/scripts/deploy_ag.sh`：

```bash
#!/bin/bash

# SQL Server Always On 自动化部署脚本（Linux）
# 使用前请根据实际情况修改配置

set -e  # 遇到错误立即退出

# ========== 配置参数 ==========
CLUSTER_NAME="AGCluster"
AG_NAME="AG_DatabaseGroup"
LISTENER_NAME="aglistener"
LISTENER_IP="192.168.1.200"
SUBNET_MASK="255.255.255.0"
NODE1="rhel1.dbadomain.com"
NODE2="rhel2.dbadomain.com"
SA_PASSWORD="YourStrongPassword!123"
MSSQL_PASSWORD="YourStrongPassword!123"
ENDPOINT_PORT=5022

# ========== 颜色输出 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ========== 函数定义 ==========
check_prerequisites() {
    log_info "检查先决条件..."
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
    
    # 检查操作系统版本
    if [ -f /etc/redhat-release ]; then
        OS_VERSION=$(cat /etc/redhat-release)
        log_info "操作系统：$OS_VERSION"
    elif [ -f /etc/lsb-release ]; then
        OS_VERSION=$(cat /etc/lsb-release)
        log_info "操作系统：$OS_VERSION"
    else
        log_warn "无法识别操作系统类型"
    fi
    
    # 检查 SQL Server 是否安装
    if ! command -v sqlcmd &> /dev/null; then
        log_error "未找到 sqlcmd，请先安装 SQL Server"
        exit 1
    fi
    
    # 检查 Pacemaker 是否安装
    if ! command -v pcs &> /dev/null; then
        log_error "未找到 pcs，请先安装 Pacemaker"
        exit 1
    fi
    
    log_info "先决条件检查通过"
}

configure_firewall() {
    log_info "配置防火墙..."
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=1433/tcp
        firewall-cmd --permanent --add-port=5022/tcp
        firewall-cmd --permanent --add-port=59999/tcp
        firewall-cmd --reload
        log_info "firewalld 配置完成"
    elif command -v ufw &> /dev/null; then
        ufw allow 1433/tcp
        ufw allow 5022/tcp
        ufw allow 59999/tcp
        ufw reload
        log_info "ufw 配置完成"
    else
        log_warn "未检测到常见的防火墙工具，请手动配置"
    fi
}

setup_pacemaker() {
    log_info "配置 Pacemaker 集群..."
    
    # 设置 hacluster 密码
    echo "$MSSQL_PASSWORD" | passwd --stdin hacluster
    
    # 启动 pcsd
    systemctl start pcsd
    systemctl enable pcsd
    
    # 认证集群节点
    pcs host auth $NODE1 $NODE2 username=hacluster password=$MSSQL_PASSWORD
    
    # 创建集群
    pcs cluster setup $CLUSTER_NAME $NODE1 $NODE2
    
    # 启用并启动集群
    pcs cluster enable --all
    pcs cluster start --all
    
    # 配置集群属性
    pcs property set stonith-enabled=false
    pcs property set no-quorum-policy=ignore
    pcs property set cluster-name=$CLUSTER_NAME
    
    log_info "Pacemaker 集群配置完成"
}

configure_sql_server() {
    log_info "配置 SQL Server..."
    
    # 启用 Always On
    /opt/mssql/bin/mssql-conf set hadr.hadr_enabled 1
    systemctl restart mssql-server
    
    # 验证配置
    /opt/mssql/bin/mssql-conf get hadr.hadr_enabled
    
    log_info "SQL Server 配置完成"
}

create_endpoint() {
    log_info "创建数据库镜像端点..."
    
    sqlcmd -S localhost -U sa -P $SA_PASSWORD -Q "
    CREATE ENDPOINT [Hadr_endpoint] 
    STATE=STARTED
    AS TCP (LISTENER_PORT = $ENDPOINT_PORT, LISTENER_IP = ALL)
    FOR DATA_MIRRORING (
        ROLE = ALL, 
        AUTHENTICATION = CERTIFICATE dbm_cert, 
        ENCRYPTION = REQUIRED ALGORITHM AES
    );
    
    CREATE CERTIFICATE dbm_cert WITH SUBJECT = 'dbm_cert';
    
    BACKUP CERTIFICATE dbm_cert TO FILE = '/var/opt/mssql/data/dbm_cert.cer';
    
    CREATE LOGIN [mssql] WITH PASSWORD = '$MSSQL_PASSWORD';
    GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [mssql];
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [mssql];
    "
    
    log_info "端点创建完成"
}

create_availability_group() {
    log_info "创建可用性组..."
    
    sqlcmd -S localhost -U sa -P $SA_PASSWORD -Q "
    CREATE AVAILABILITY GROUP [$AG_NAME]
    WITH (
        CLUSTER_TYPE = EXTERNAL,
        AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
        FAILOVER_MODE = EXTERNAL,
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT
    )
    FOR REPLICATION OFF
    AS REPLICA ON 
        N'$NODE1' WITH (
            ENDPOINT_URL = N'TCP://$NODE1:$ENDPOINT_PORT',
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            FAILOVER_MODE = EXTERNAL,
            SEEDING_MODE = AUTOMATIC,
            SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
        ),
        N'$NODE2' WITH (
            ENDPOINT_URL = N'TCP://$NODE2:$ENDPOINT_PORT',
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            FAILOVER_MODE = EXTERNAL,
            SEEDING_MODE = AUTOMATIC,
            SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
        );
    
    ALTER AVAILABILITY GROUP [$AG_NAME] GRANT CREATE ANY DATABASE;
    ALTER AVAILABILITY GROUP [$AG_NAME] GRANT CONNECT;
    "
    
    log_info "可用性组创建完成"
}

create_listener() {
    log_info "创建监听器..."
    
    sqlcmd -S localhost -U sa -P $SA_PASSWORD -Q "
    ALTER AVAILABILITY GROUP [$AG_NAME]
    ADD LISTENER N'$LISTENER_NAME' (
        WITH IP ((N'$LISTENER_IP', N'$SUBNET_MASK')),
        PORT = 1433
    );
    "
    
    log_info "监听器创建完成"
}

configure_pacemaker_resources() {
    log_info "配置 Pacemaker 资源..."
    
    # 创建 AG 资源
    pcs resource create ag_$AG_NAME ocf:mssql:ag \
        ag_name=$AG_NAME \
        cluster_login=mssql \
        cluster_passwd=$MSSQL_PASSWORD \
        op monitor interval=10s \
        op promote timeout=60s \
        op demote timeout=60s \
        op stop timeout=60s \
        op start timeout=60s \
        meta failure-timeout=60s \
        clone interleave=true \
        promoted-max=1 \
        promoted-name=Master \
        clone-name=Slave
    
    # 创建监听器资源
    pcs resource create listener_$AG_NAME ocf:mssql:listener \
        ag_name=$AG_NAME \
        cluster_login=mssql \
        cluster_passwd=$MSSQL_PASSWORD \
        op monitor interval=10s \
        op start timeout=60s \
        op stop timeout=60s
    
    # 配置约束
    pcs constraint order promote ag_$AG_NAME-clone then listener_$AG_NAME kind=Mandatory
    pcs constraint colocation add listener_$AG_NAME with ag_$AG_NAME-clone score=INFINITY
    
    log_info "Pacemaker 资源配置完成"
}

verify_deployment() {
    log_info "验证部署..."
    
    echo ""
    echo "=== 集群状态 ==="
    pcs status cluster
    
    echo ""
    echo "=== 资源状态 ==="
    pcs status resources
    
    echo ""
    echo "=== 可用性组状态 ==="
    sqlcmd -S localhost -U sa -P $SA_PASSWORD -d master -Q "
    SELECT 
        ar.replica_server_name as '副本服务器',
        ars.role_desc as '角色',
        ars.synchronization_health_desc as '同步状态'
    FROM sys.availability_replicas ar
    JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;
    "
    
    echo ""
    echo "=== 监听器状态 ==="
    sqlcmd -S localhost -U sa -P $SA_PASSWORD -d master -Q "
    SELECT dns_name, port, ip_configuration_string 
    FROM sys.availability_group_listeners;
    "
    
    log_info "部署验证完成"
}

# ========== 主程序 ==========
main() {
    log_info "开始 SQL Server Always On 部署..."
    
    check_prerequisites
    configure_firewall
    setup_pacemaker
    configure_sql_server
    create_endpoint
    create_availability_group
    create_listener
    configure_pacemaker_resources
    verify_deployment
    
    log_info "🎉 SQL Server Always On 部署完成！"
    echo ""
    echo "下一步操作："
    echo "1. 添加数据库到可用性组"
    echo "2. 配置应用程序连接字符串"
    echo "3. 执行故障转移测试"
    echo "4. 配置监控和告警"
}

# 执行主程序
main
```

**使用脚本：**

```bash
# 赋予执行权限
chmod +x /opt/mssql/scripts/deploy_ag.sh

# 运行部署脚本
sudo /opt/mssql/scripts/deploy_ag.sh
```

### 18.2 部署验证清单

使用以下清单验证部署是否成功：

```bash
#!/bin/bash

# Always On 部署验证清单

echo "=== SQL Server Always On 部署验证清单 ==="
echo ""

# 1. 检查 SQL Server 服务
echo "1. SQL Server 服务状态"
systemctl is-active mssql-server && echo "   ✓ SQL Server 运行正常" || echo "   ✗ SQL Server 未运行"
echo ""

# 2. 检查 Pacemaker 集群
echo "2. Pacemaker 集群状态"
pcs status cluster | grep -q "Online" && echo "   ✓ 集群在线" || echo "   ✗ 集群离线"
echo ""

# 3. 检查 Always On 是否启用
echo "3. Always On 配置"
/opt/mssql/bin/mssql-conf get hadr.hadr_enabled | grep -q "true" && echo "   ✓ Always On 已启用" || echo "   ✗ Always On 未启用"
echo ""

# 4. 检查端点
echo "4. 数据库镜像端点"
sqlcmd -S localhost -U sa -P YourStrongPassword! -d master -h -1 -t 5 -Q "
IF EXISTS (SELECT 1 FROM sys.database_mirroring_endpoints WHERE name = 'Hadr_endpoint' AND state = 0)
    PRINT '   ✓ 端点存在且已启动'
ELSE
    PRINT '   ✗ 端点不存在或未启动'
"
echo ""

# 5. 检查可用性组
echo "5. 可用性组状态"
sqlcmd -S localhost -U sa -P YourStrongPassword! -d master -h -1 -t 5 -Q "
IF EXISTS (SELECT 1 FROM sys.availability_groups WHERE name = 'AG_DatabaseGroup')
    PRINT '   ✓ 可用性组存在'
ELSE
    PRINT '   ✗ 可用性组不存在'
"
echo ""

# 6. 检查监听器
echo "6. 监听器配置"
sqlcmd -S localhost -U sa -P YourStrongPassword! -d master -h -1 -t 5 -Q "
IF EXISTS (SELECT 1 FROM sys.availability_group_listeners WHERE dns_name = 'aglistener')
    PRINT '   ✓ 监听器配置正确'
ELSE
    PRINT '   ✗ 监听器未配置'
"
echo ""

# 7. 测试监听器连接
echo "7. 监听器连接测试"
timeout 2 bash -c "cat < /dev/null > /dev/tcp/aglistener.dbadomain.com/1433" 2>/dev/null && echo "   ✓ 监听器端口可访问" || echo "   ✗ 监听器端口不可访问"
echo ""

echo "=== 验证完成 ==="
```

---

## 十九、参考资料

### Windows 相关：
- [Microsoft Docs - Always On 可用性组 (Windows)](https://docs.microsoft.com/zh-cn/sql/database-engine/availability-groups/windows/always-on-availability-groups-sql-server)
- [SQL Server 技术参考](https://docs.microsoft.com/zh-cn/sql/sql-server/)
- [故障转移群集最佳实践](https://docs.microsoft.com/zh-cn/windows-server/failover-clustering/failover-clustering-overview)

### Linux 相关：
- [Microsoft Docs - Always On 可用性组 (Linux)](https://docs.microsoft.com/zh-cn/sql/linux/sql-server-linux-availability-groups-hadr-pacemaker?view=sql-server-ver15)
- [Red Hat High Availability Add-On](https://access.redhat.com/documentation/zh-cn/red_hat_enterprise_linux/8/html/high_availability_add-on_reference/index)
- [Ubuntu Pacemaker 文档](https://ubuntu.com/server/docs/high-availability)
- [SQL Server on Linux 官方文档](https://docs.microsoft.com/zh-cn/sql/linux/sql-server-linux-overview)

### 工具和脚本：
- [SQLCMD 工具文档](https://docs.microsoft.com/zh-cn/sql/tools/sqlcmd-utility)
- [Pacemaker 官方文档](https://clusterlabs.org/pacemaker/doc/)
- [OCF 资源代理文档](https://github.com/ClusterLabs/resource-agents)

---

## 二十、版本历史和更新说明

**版本历史：**
- v2.0 (2026-03-14)：添加完整的 Linux 版 Always On 部署教程
  - 新增 RHEL/Ubuntu/SLES 平台支持
  - 新增 Pacemaker 集群配置详解
  - 新增 Linux 专用监控和管理脚本
  - 新增自动化部署脚本
  
- v1.0 (2026-03-14)：初始版本，包含完整的 Windows 版 Always On 部署配置教程

**作者备注：**
本教程基于 SQL Server 2019/2022 企业版编写，同时覆盖 Windows 和 Linux 两个平台。Windows 版本基于 WSFC 集群，Linux 版本基于 Pacemaker 集群。生产环境部署前，建议在测试环境中充分验证。如有问题，欢迎反馈和改进。

**贡献指南：**
如果您在使用过程中发现问题或有改进建议，欢迎提交 Issue 或 Pull Request。
