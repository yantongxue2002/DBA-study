# MySQL 单机多实例快速部署步骤（基于Linux+二进制/包安装，通用版）
以部署**3306、3307两个实例**为例，核心原则：**目录独立、配置独立、端口独立、server-id独立**，其他实例可按此模板批量扩展，操作前确保服务器已安装MySQL（未安装可先执行`yum install -y mysql-community-server`/二进制解压安装）。

### 一、基础环境准备（创建独立目录）
为每个实例创建专属的**数据目录、日志目录、临时目录**，统一根目录便于管理，执行以下命令：
```bash
# 根目录，可自定义
mkdir -p /data/mysql/{3306,3307}/{data,log,tmp}
# 授权mysql用户（必须，否则启动失败）
chown -R mysql:mysql /data/mysql
chmod -R 755 /data/mysql
```

### 二、编写各实例独立配置文件
**禁止共用my.cnf**，为3306、3307分别创建配置文件，建议放在`/etc/my.cnf.d/`（规范路径），核心参数差异化，其余参数可通用。
#### 1. 3306实例配置：/etc/my.cnf.d/mysql3306.cnf
```ini
[mysqld]
# 核心差异化参数（必改）
port=3306
server-id=6  # 唯一，建议和端口尾号一致，主从复制必须不同
datadir=/data/mysql/3306/data
socket=/data/mysql/3306/mysql.sock
# 日志独立（必改）
log-error=/data/mysql/3306/log/mysql_error.log
slow_query_log_file=/data/mysql/3306/log/mysql_slow.log
binlog_index=/data/mysql/3306/log/mysql_bin.index
relay-log=/data/mysql/3306/log/relay-bin
# 通用基础参数（可根据服务器配置调整）
basedir=/usr/local/mysql  # MySQL安装目录，按实际修改
tmpdir=/data/mysql/3306/tmp
character-set-server=utf8mb4
collation-server=utf8mb4_general_ci
innodb_buffer_pool_size=512M  # 按服务器内存分配，多实例总和不超物理内存70%
max_connections=500
slow_query_log=1
long_query_time=1
log_bin=mysql_bin  # 开启binlog，主从/备份用
binlog_format=ROW
[mysqld_safe]
log-error=/data/mysql/3306/log/mysql_error.log
pid-file=/data/mysql/3306/mysql.pid
```
#### 2. 3307实例配置：/etc/my.cnf.d/mysql3307.cnf
**仅修改差异化参数**，其余和3306一致，直接复制后替换以下内容：
```ini
port=3307
server-id=7
datadir=/data/mysql/3307/data
socket=/data/mysql/3307/mysql.sock
log-error=/data/mysql/3307/log/mysql_error.log
slow_query_log_file=/data/mysql/3307/log/mysql_slow.log
binlog_index=/data/mysql/3307/log/mysql_bin.index
relay-log=/data/mysql/3307/log/relay-bin
tmpdir=/data/mysql/3307/tmp
pid-file=/data/mysql/3307/mysql.pid
```

### 三、初始化各MySQL实例
使用`mysqld --initialize`为每个实例单独初始化，生成临时密码，**必须指定配置文件**，否则会走全局配置导致冲突：
```bash
# 初始化3306实例
mysqld --initialize --user=mysql --defaults-file=/etc/my.cnf.d/mysql3306.cnf
# 初始化3307实例
mysqld --initialize --user=mysql --defaults-file=/etc/my.cnf.d/mysql3307.cnf
```
#### 关键：获取临时密码
初始化完成后，从错误日志中提取临时密码，用于首次登录：
```bash
# 3306实例临时密码
grep 'temporary password' /data/mysql/3306/log/mysql_error.log
# 3307实例临时密码
grep 'temporary password' /data/mysql/3307/log/mysql_error.log
```
输出示例：`A temporary password is generated for root@localhost: xxxxxx`，`xxxxxx`即为临时密码。

### 四、创建系统服务，独立启停（推荐systemd）
为每个实例创建专属systemd服务文件，实现`systemctl`启停，避免手动启动的繁琐，服务文件放在`/usr/lib/systemd/system/`。
#### 1. 3306服务文件：/usr/lib/systemd/system/mysqld3306.service
```ini
[Unit]
Description=MySQL Server 3306
After=network.target remote-fs.target nss-lookup.target
[Service]
Type=notify
User=mysql
Group=mysql
# 关键：指定配置文件
ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf.d/mysql3306.cnf
LimitNOFILE=5000
[Install]
WantedBy=multi-user.target
```
#### 2. 3307服务文件：/usr/lib/systemd/system/mysqld3307.service
仅修改**Description**和**ExecStart**中的配置文件路径：
```ini
[Unit]
Description=MySQL Server 3307
After=network.target remote-fs.target nss-lookup.target
[Service]
Type=notify
User=mysql
Group=mysql
ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf.d/mysql3307.cnf
LimitNOFILE=5000
[Install]
WantedBy=multi-user.target
```
#### 3. 重载服务并设置开机自启
```bash
# 重载systemd配置
systemctl daemon-reload
# 开机自启（可选）
systemctl enable mysqld3306 mysqld3307
# 启动实例
systemctl start mysqld3306 mysqld3307
# 查看状态（确认启动成功，显示active(running)即可）
systemctl status mysqld3306 mysqld3307
```

### 五、首次登录并修改密码
多实例登录**必须指定端口和socket**，否则默认连接3306，执行以下命令登录并修改密码（替换临时密码和端口）：
```bash
# 登录3306实例（输入临时密码）
mysql -uroot -p -P3306 -S /data/mysql/3306/mysql.sock
# 登录3307实例（输入临时密码）
mysql -uroot -p -P3307 -S /data/mysql/3307/mysql.sock
```
登录后执行SQL修改密码（统一密码或独立密码均可）：
```sql
# 修改root密码，123456替换为你的密码
ALTER USER 'root'@'localhost' IDENTIFIED BY '123456';
# 允许远程登录（可选，生产环境建议限制IP）
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '123456' WITH GRANT OPTION;
FLUSH PRIVILEGES;
exit;
```

### 六、多实例常用运维命令（核心）
所有操作**必须指定实例标识（端口/socket/配置文件）**，禁止用全局`mysql`/`systemctl`命令，避免影响其他实例：
#### 1. 启停/状态查看
```bash
# 启动
systemctl start mysqld3306 mysqld3307
# 停止
systemctl stop mysqld3306 mysqld3307
# 重启
systemctl restart mysqld3306 mysqld3307
# 状态查看
systemctl status mysqld3306
```
#### 2. 登录实例
```bash
# 方式1：指定端口+socket（推荐，无冲突）
mysql -uroot -p123456 -P3306 -S /data/mysql/3306/mysql.sock
# 方式2：仅指定端口（需确保socket路径正确）
mysql -uroot -p123456 -P3307 -h127.0.0.1
```
#### 3. 日志查看/备份/配置修改
- 日志：直接查看对应实例的log目录，如`tail -f /data/mysql/3306/log/mysql_error.log`
- 备份：按实例独立备份（和你之前的xtrabackup备份逻辑一致），指定配置文件/socket即可
- 配置修改：修改对应实例的cnf文件，重启该实例生效，如`systemctl restart mysqld3306`

### 七、核心注意事项（避坑关键）
1. **资源分配**：多实例共享服务器CPU、内存、磁盘，**innodb_buffer_pool_size总和不超物理内存70%**，max_connections按需分配，防止单个实例占满资源导致其他实例崩溃；
2. **端口/server-id唯一**：server-id在主从复制中是唯一标识，即使单机多实例，也不能重复，建议和端口尾号绑定；
3. **权限问题**：所有目录必须授权`mysql:mysql`，否则启动会报权限错误，这是最常见的坑；
4. **禁止全局操作**：不要用`systemctl start mysqld`（全局）、`mysqldump --all-databases`等命令，否则只会操作默认3306实例；
5. **监控隔离**：监控工具（如Zabbix、Prometheus）按**端口/实例目录**单独监控，重点关注各实例的CPU、内存、磁盘IO、连接数；
6. **生产环境建议**：单机多实例**仅用于测试/开发/低流量小业务**，生产高并发业务建议物理机/虚拟机单独部署单实例，避免资源竞争。

### 扩展：新增更多实例（如3308）
1. 复制目录：`mkdir -p /data/mysql/3308/{data,log,tmp} && chown -R mysql:mysql /data/mysql/3308`；
2. 复制配置文件：复制3306.cnf，替换端口3308、server-id=8、所有目录路径为3308；
3. 初始化：`mysqld --initialize --user=mysql --defaults-file=/etc/my.cnf.d/mysql3308.cnf`；
4. 创服务文件：复制3306.service，修改描述和配置文件路径；
5. 重载服务+启动：`systemctl daemon-reload && systemctl start mysqld3308`。
