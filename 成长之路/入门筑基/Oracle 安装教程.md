# Oracle 数据库安装教程

## 一、安装前准备

### 1.1 系统要求

#### Windows 系统要求
- **操作系统**: Windows 10/11 或 Windows Server 2016/2019/2022
- **内存**: 至少 2GB（推荐 4GB 以上）
- **磁盘空间**: 至少 10GB 可用空间
- **处理器**: x86-64 架构，至少 2 核

#### Linux 系统要求
- **操作系统**: Oracle Linux 7/8, RHEL 7/8, CentOS 7/8
- **内存**: 至少 2GB（推荐 4GB 以上）
- **磁盘空间**: 至少 10GB 可用空间
- **Swap 空间**: 至少 2GB

### 1.2 下载 Oracle 数据库

1. 访问 Oracle 官网下载页面
   - 官网地址：https://www.oracle.com/database/technologies/oracle-database-software-downloads.html
   
2. 选择合适的版本下载
   - Oracle 19c（长期支持版本，推荐）
   - Oracle 21c（创新版本）
   - Oracle 12c（较老版本）

3. 需要 Oracle 账号（免费注册）
   - 注册地址：https://account.oracle.com

### 1.3 检查系统环境

#### Windows 环境检查
```powershell
# 检查系统版本
winver

# 检查内存
systeminfo | findstr /C:"Total Physical Memory"

# 检查磁盘空间
wmic logicaldisk get size,freespace,caption
```

#### Linux 环境检查
```bash
# 检查系统版本
cat /etc/redhat-release
uname -r

# 检查内存
free -g

# 检查磁盘空间
df -h

# 检查 swap
swapon -s

# 检查操作系统内核参数
sysctl -a | grep sem
sysctl -a | grep shm
```

## 二、Windows 系统安装 Oracle 19c

### 2.1 下载解压软件

下载 Oracle 19c for Windows x64 安装包：
- 文件名：`WINDOWS.X64_193000_db_home.zip`
- 大小：约 4.5GB

### 2.2 创建 Oracle 目录

```cmd
# 以管理员身份运行 CMD
mkdir C:\app\oracle\product\19.3.0\dbhome_1
mkdir C:\app\oracle\oradata
mkdir C:\app\oracle\inventory
```

### 2.3 解压安装包

1. 使用 WinRAR 或 7-Zip 解压
2. 将 ZIP 文件内容解压到 `C:\app\oracle\product\19.3.0\dbhome_1`
3. **注意**: 不要直接双击运行 ZIP 文件

### 2.4 配置环境变量

1. 右键"此电脑" → "属性" → "高级系统设置"
2. 点击"环境变量"
3. 添加系统变量：
   ```
   ORACLE_BASE = C:\app\oracle
   ORACLE_HOME = C:\app\oracle\product\19.3.0\dbhome_1
   PATH = %ORACLE_HOME%\bin;%PATH%
   ```

### 2.5 运行安装程序

1. 以管理员身份运行 CMD
2. 进入 Oracle Home 目录：
   ```cmd
   cd C:\app\oracle\product\19.3.0\dbhome_1
   ```

3. 运行安装程序：
   ```cmd
   setup.exe
   ```

### 2.6 安装步骤详解

#### 步骤 1: 配置安全更新
- 取消勾选"我希望通过 My Oracle Support 接收安全更新"
- 点击"是"确认

#### 步骤 2: 选择安装选项
- 选择"创建和配置数据库"
- 点击"下一步"

#### 步骤 3: 选择系统类
- **桌面类**: 用于学习和开发（自动创建数据库）
- **服务器类**: 用于生产环境（手动配置）
- 选择"桌面类"，点击"下一步"

#### 步骤 4: 选择安装类型
- **典型安装**: 推荐初学者（自动配置）
- **高级安装**: 自定义配置
- 选择"典型安装"

#### 步骤 5: 典型安装配置
填写以下信息：
```
Oracle 基目录：C:\app\oracle
软件位置：C:\app\oracle\product\19.3.0\dbhome_1
数据库文件位置：C:\app\oracle\oradata
数据库版本：Oracle Database 19c
全局数据库名：orcl
数据库标识符（SID）：orcl
密码：设置 SYSTEM 和 SYS 用户的密码（建议复杂密码）
```

#### 步骤 6: 先决条件检查
- 等待检查完成
- 确保所有检查项通过（显示绿色对勾）
- 如有警告，根据提示修复

#### 步骤 7: 概要
- 查看安装配置摘要
- 点击"完成"开始安装

#### 步骤 8: 安装产品
- 等待安装完成（约 20-30 分钟）
- 安装过程中会创建数据库

#### 步骤 9: 完成
- 安装成功后点击"关闭"
- 记录重要信息（密码、SID 等）

### 2.7 验证安装

1. 打开 CMD，运行以下命令：
   ```cmd
   sqlplus / as sysdba
   ```

2. 执行 SQL 查询验证：
   ```sql
   SELECT * FROM v$version;
   SELECT status FROM v$instance;
   ```

3. 检查服务是否运行：
   ```cmd
   sc query OracleServiceORCL
   sc query OracleTNSListener
   ```

## 三、Linux 系统安装 Oracle 19c

### 3.1 安装前准备

#### 3.1.1 检查系统要求
```bash
# 检查内存
grep MemTotal /proc/meminfo

# 检查 swap
grep SwapTotal /proc/meminfo

# 检查磁盘空间
df -h /tmp
df -h /u01
```

#### 3.1.2 创建 Oracle 用户和组
```bash
# 创建 Oracle 组
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
groupadd -g 54324 backupdba
groupadd -g 54325 dgdba
groupadd -g 54326 kmdba
groupadd -g 54327 asmdba

# 创建 Oracle 用户
useradd -u 54321 -g oinstall -G dba,oper,backupdba,dgdba,kmdba,asmdba oracle

# 设置 Oracle 用户密码
passwd oracle
```

#### 3.1.3 创建安装目录
```bash
# 创建目录
mkdir -p /u01/app/oracle/product/19.3.0/dbhome_1
mkdir -p /u01/app/oraInventory
mkdir -p /u01/app/oracle/oradata

# 设置权限
chown -R oracle:oinstall /u01
chmod -R 775 /u01
```

### 3.2 安装系统依赖包

#### CentOS/RHEL 7/8
```bash
# 安装依赖包
yum install -y bc binutils compat-libcap1 compat-libstdc++-33 \
elfutils-libelf elfutils-libelf-devel fontconfig-devel glibc \
glibc-devel ksh libaio libaio-devel libX11 libX11-devel \
libXau libXau-devel libXi libXrender libXrender-devel \
libXtst libXtst-devel libxcb libxcb-devel make nfs-utils \
net-tools smartmontools sysstat unixODBC unixODBC-devel \
gcc gcc-c++
```

### 3.3 配置系统内核参数

#### 3.3.1 编辑 sysctl.conf
```bash
vi /etc/sysctl.conf
```

添加以下内容：
```
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = 2097152
kernel.shmmax = 1073741824
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
```

#### 3.3.2 使配置生效
```bash
sysctl -p
```

### 3.4 配置用户限制

#### 3.4.1 编辑 limits.conf
```bash
vi /etc/security/limits.conf
```

添加以下内容：
```
oracle   soft   nproc   2047
oracle   hard   nproc   16384
oracle   soft   nofile  1024
oracle   hard   nofile  65536
oracle   soft   stack   10240
oracle   hard   stack   32768
```

#### 3.4.2 编辑 login.conf
```bash
vi /etc/pam.d/login
```

添加以下内容：
```
session    required     pam_limits.so
```

#### 3.4.3 编辑 profile
```bash
vi /etc/profile
```

添加以下内容：
```bash
if [ $USER = "oracle" ]; then
  if [ $SHELL = "/bin/ksh" ]; then
    ulimit -p 16384
    ulimit -n 65536
  else
    ulimit -u 16384
    ulimit -n 65536
  fi
fi
```

### 3.5 配置 Oracle 用户环境变量

```bash
su - oracle
vi ~/.bash_profile
```

添加以下内容：
```bash
# Oracle Settings
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.3.0/dbhome_1
export ORACLE_SID=orcl
export ORACLE_UNQNAME=orcl
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
export PATH=$PATH:$ORACLE_HOME/bin

# Alias
alias sqlplus='rlwrap sqlplus'
alias lsnrctl='rlwrap lsnrctl'
```

使配置生效：
```bash
source ~/.bash_profile
```

### 3.6 解压安装包

```bash
# 切换到 oracle 用户
su - oracle

# 进入安装目录
cd /u01/app/oracle/product/19.3.0/dbhome_1

# 解压安装包
unzip -q /path/to/LINUX.X64_193000_db_home.zip
```

### 3.7 运行安装程序

#### 3.7.1 图形界面安装（需要 X11）

1. 配置 X11 转发（从远程连接时）
   ```bash
   # Windows 使用 Xmanager 或 VcXsrv
   # Mac 使用 XQuartz
   ```

2. 运行安装程序
   ```bash
   ./runInstaller
   ```

3. 按照图形界面步骤操作（类似 Windows 安装）

#### 3.7.2 命令行静默安装（推荐）

1. 创建响应文件
   ```bash
   vi /tmp/oracle_install.rsp
   ```

2. 填写响应文件内容：
   ```
   oracle.install.option=INSTALL_DB_SW_CONFIGURE_DB
   UNIX_GROUP_NAME=oinstall
   INVENTORY_LOCATION=/u01/app/oraInventory
   SELECTED_LANGUAGES=en
   ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
   ORACLE_BASE=/u01/app/oracle
   oracle.install.db.InstallEdition=EE
   oracle.install.db.OSDBA_GROUP=dba
   oracle.install.db.OSOPER_GROUP=oper
   oracle.install.db.OSBACKUPDBA_GROUP=backupdba
   oracle.install.db.OSDGDBA_GROUP=dgdba
   oracle.install.db.OSKMDBA_GROUP=kmdba
   oracle.install.db.OSRACDBA_GROUP=racdba
   oracle.install.db.rootconfig.executeRootScript=false
   oracle.install.db.ConfigureAsContainerDB=false
   oracle.install.db.userDBAOption=true
   oracle.install.db.DATABASE_TYPE=GENERAL_PURPOSE
   oracle.install.db.STARTUP_TYPE=AUTOMATIC
   oracle.install.db.MEMORY_LIMIT=2048
   oracle.install.db.SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
   DECLINE_SECURITY_UPDATES=true
   oracle.install.db.ConfigureDB=true
   oracle.install.db.globalDBName=orcl
   oracle.install.db.SID=orcl
   oracle.install.db.characterSet=AL32UTF8
   oracle.install.db.password.SYS=Oracle123
   oracle.install.db.password.SYSTEM=Oracle123
   ```

3. 运行静默安装
   ```bash
   cd /u01/app/oracle/product/19.3.0/dbhome_1
   ./runInstaller -silent -responseFile /tmp/oracle_install.rsp
   ```

4. 执行 root 脚本（新终端，root 用户）
   ```bash
   /u01/app/oraInventory/orainstRoot.sh
   /u01/app/oracle/product/19.3.0/dbhome_1/root.sh
   ```

### 3.8 创建数据库（如未自动创建）

```bash
# 使用 DBCA 创建数据库
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname orcl \
  -sid orcl \
  -responseFile NO_VALUE \
  -characterSet AL32UTF8 \
  -sysPassword Oracle123 \
  -systemPassword Oracle123 \
  -createAsContainerDatabase false \
  -databaseType MULTIPURPOSE \
  -memoryMgmtType auto_sga \
  -totalMemory 2048 \
  -storageType FS \
  -datafileDestination "/u01/app/oracle/oradata" \
  -redoLogFileSize 50 \
  -emConfiguration NONE \
  -ignorePreReqs
```

### 3.9 配置监听器

```bash
# 使用 NETCA 创建监听器
netca -silent -responseFile /u01/app/oracle/product/19.3.0/dbhome_1/assistants/netca/netca.rsp
```

或手动配置：
```bash
lsnrctl start

lsnrctl << EOF
add_listener
set listener_address (ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521))
end
save_config
exit
EOF
```

### 3.10 验证安装

```bash
# 检查数据库状态
sqlplus / as sysdba

SQL> SELECT status FROM v$instance;
SQL> SELECT * FROM v$version;
SQL> EXIT

# 检查监听器状态
lsnrctl status

# 检查进程
ps -ef | grep pmon
ps -ef | grep smon
```

## 四、常见问题及解决方案

### 4.1 Windows 常见问题

#### 问题 1: 安装时提示"无法找到 oracle.install.db.config.managedoption.OS_AUTHENTICATION"
**解决方案**:
- 确保解压完整，不要有文件缺失
- 以管理员身份运行安装程序

#### 问题 2: 服务无法启动
**解决方案**:
```cmd
# 检查服务
sc query OracleServiceORCL

# 手动启动服务
net start OracleServiceORCL
net start OracleTNSListener

# 检查事件查看器
eventvwr.msc
```

#### 问题 3: 密码忘记
**解决方案**:
```cmd
sqlplus / as sysdba
ALTER USER sys IDENTIFIED BY new_password;
ALTER USER system IDENTIFIED BY new_password;
```

### 4.2 Linux 常见问题

#### 问题 1: 依赖包缺失
**解决方案**:
```bash
# 使用 yum 自动解决依赖
yum install -y <package_name>

# 或安装所有依赖
yum install -y bc binutils compat-libcap1 compat-libstdc++-33
```

#### 问题 2: 权限问题
**解决方案**:
```bash
# 确保目录权限正确
chown -R oracle:oinstall /u01/app/oracle
chmod -R 775 /u01/app/oracle

# 切换用户
su - oracle
```

#### 问题 3: 监听器无法启动
**解决方案**:
```bash
# 检查监听器配置
lsnrctl status

# 重新配置监听器
netca

# 检查端口是否被占用
netstat -tlnp | grep 1521
```

#### 问题 4: 内存不足
**解决方案**:
```bash
# 增加 swap
dd if=/dev/zero of=/swapfile bs=1G count=4
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

## 五、连接测试

### 5.1 本地连接

```bash
# Linux
sqlplus sys/Oracle123@localhost:1521/orcl as sysdba

# Windows
sqlplus sys/Oracle123@localhost:1521/orcl as sysdba
```

### 5.2 远程连接

1. 配置防火墙允许 1521 端口

   **Linux**:
   ```bash
   # firewalld
   firewall-cmd --add-port=1521/tcp --permanent
   firewall-cmd --reload
   
   # iptables
   iptables -A INPUT -p tcp --dport 1521 -j ACCEPT
   ```

   **Windows**:
   - 控制面板 → Windows Defender 防火墙
   - 高级设置 → 入站规则 → 新建规则
   - 端口 → TCP 1521 → 允许连接

2. 使用 SQL Developer 或 PL/SQL Developer 连接
   ```
   主机名：服务器 IP 地址
   端口：1521
   SID: orcl
   用户名：sys 或 system
   密码：设置的密码
   连接类型：SYSDBA（sys 用户）
   ```

### 5.3 使用 TNS 连接

编辑 `tnsnames.ora` 文件：
```
ORCL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = orcl)
    )
  )
```

连接命令：
```bash
sqlplus sys/Oracle123@ORCL as sysdba
```

## 六、基本管理命令

### 6.1 启动和停止数据库

```sql
-- 启动数据库
STARTUP

-- 关闭数据库
SHUTDOWN IMMEDIATE

-- 重启数据库
SHUTDOWN IMMEDIATE
STARTUP

-- 只启动实例，不挂载数据库
STARTUP NOMOUNT

-- 启动实例并挂载数据库，但不打开
STARTUP MOUNT
```

### 6.2 查看数据库信息

```sql
-- 查看数据库版本
SELECT * FROM v$version;

-- 查看数据库状态
SELECT status FROM v$instance;

-- 查看数据库名称
SELECT name FROM v$database;

-- 查看表空间
SELECT tablespace_name FROM dba_tablespaces;

-- 查看数据文件
SELECT file_name, tablespace_name FROM dba_data_files;

-- 查看用户
SELECT username FROM dba_users;

-- 查看会话
SELECT sid, serial#, username, status FROM v$session;
```

### 6.3 创建用户和授权

```sql
-- 创建用户
CREATE USER test_user IDENTIFIED BY test_password;

-- 授权
GRANT CONNECT, RESOURCE TO test_user;
GRANT DBA TO test_user;

-- 撤销权限
REVOKE DBA FROM test_user;

-- 删除用户
DROP USER test_user CASCADE;
```

## 七、卸载 Oracle

### 7.1 Windows 卸载

1. 停止所有 Oracle 服务
   ```cmd
   net stop OracleServiceORCL
   net stop OracleTNSListener
   ```

2. 运行卸载程序
   ```cmd
   C:\app\oracle\product\19.3.0\dbhome_1\deinstall\deinstall.bat
   ```

3. 删除注册表项（谨慎操作）
   ```cmd
   regedit
   # 删除 HKEY_LOCAL_MACHINE\SOFTWARE\ORACLE
   ```

4. 删除环境变量
   - 删除 ORACLE_BASE、ORACLE_HOME
   - 从 PATH 中删除 Oracle 相关路径

5. 删除文件
   ```cmd
   rmdir /s /q C:\app\oracle
   ```

### 7.2 Linux 卸载

```bash
# 停止数据库
sqlplus / as sysdba
SHUTDOWN IMMEDIATE
EXIT

# 停止监听器
lsnrctl stop

# 运行卸载程序
cd $ORACLE_HOME/deinstall
./deinstall

# 删除用户和组
userdel -r oracle
groupdel oinstall
groupdel dba

# 删除目录
rm -rf /u01/app/oracle
rm -rf /u01/app/oraInventory
```

## 八、学习资源

### 8.1 官方文档
- Oracle 官方文档：https://docs.oracle.com/en/database/
- Oracle 19c 文档：https://docs.oracle.com/en/database/oracle/oracle-database/19/

### 8.2 学习网站
- Oracle Technology Network (OTN)
- Oracle Base
- Ask Tom

### 8.3 推荐书籍
- 《Oracle 权威指南》
- 《Oracle 数据库管理艺术》
- 《Oracle 19c 从入门到精通》

---

**注意事项**:
1. 生产环境安装前务必在测试环境验证
2. 记住所有设置的密码，建议妥善保管
3. 定期备份重要数据
4. 关注 Oracle 官方安全补丁
5. 学习阶段建议使用虚拟机安装，方便快照和恢复
