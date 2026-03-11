# MySQL 配置文件 (my.cnf / my.ini) 详解

MySQL 的配置文件通常在 Linux 下为 `/etc/my.cnf`，在 Windows 下为 `my.ini`。合理配置该文件对于数据库的稳定性、性能和安全性至关重要。

本文将配置文件分为 **“基础必选配置”** 和 **“进阶可选/调优配置”** 两部分进行详细介绍。

---

## 一、 配置文件结构概览

配置文件通常由多个段（Section）组成，用方括号 `[]` 标识。
*   `[client]`: 影响所有 MySQL 客户端（如 mysql命令行, mysqldump）。
*   `[mysql]`: 仅影响 mysql 命令行客户端。
*   `[mysqld]`: **核心部分**，影响 MySQL 服务端进程。

---

## 二、 [mysqld] 服务端配置详解

### 1. 基础必选配置 (Essential Settings)
这些配置决定了 MySQL 能否正常启动以及数据的存储位置。

| 参数名 | 说明 | 推荐/示例值 |
| :--- | :--- | :--- |
| **`user`** | 运行 MySQL 服务的系统用户 (Linux) | `mysql` |
| **`port`** | 监听端口 | `3306` |
| **`basedir`** | MySQL 安装目录 | `/usr/local/mysql` |
| **`datadir`** | **数据存储目录** (最重要) | `/data/mysql/data` |
| **`socket`** | 本地连接使用的套接字文件 (Linux) | `/tmp/mysql.sock` |
| **`pid-file`** | 进程 ID 文件路径 | `/data/mysql/mysqld.pid` |
| **`character-set-server`** | 服务端默认字符集 | `utf8mb4` |
| **`collation-server`** | 默认排序规则 | `utf8mb4_general_ci` |

### 2. InnoDB 核心调优配置 (Performance Critical)
InnoDB 是 MySQL 8.0 的默认引擎，这些参数直接决定数据库性能。

| 参数名 | 说明 | 推荐/示例值 |
| :--- | :--- | :--- |
| **`innodb_buffer_pool_size`** | **最重要的参数**。缓存数据和索引的内存大小。建议设置为物理内存的 50%-75% (专用服务器)。 | `4G` (视内存而定) |
| **`innodb_buffer_pool_instances`** | 缓冲池实例数，减少内存锁竞争。当 buffer_pool > 1G 时建议设置。 | `4` 或 `8` |
| **`innodb_log_file_size`** | Redo Log 单个文件大小。太小会导致频繁刷盘，太大会增加恢复时间。 | `1G` 或 `2G` |
| **`innodb_log_buffer_size`** | Redo Log 缓冲区大小，未刷盘前的缓存。 | `16M` |
| **`innodb_flush_log_at_trx_commit`** | **ACID 关键参数**。<br>`1`: 每次提交都刷盘 (最安全，性能最低)；<br>`0`: 每秒刷盘 (性能最好，可能丢1秒数据)；<br>`2`: 每次提交写OS缓存，每秒刷盘 (折中)。 | `1` (生产环境) / `2` (允许少量丢失) |
| **`innodb_flush_method`** | 数据文件刷盘方式。Linux 下推荐 `O_DIRECT` 绕过 OS 缓存。 | `O_DIRECT` |
| **`innodb_file_per_table`** | 是否为每个表使用独立的 .ibd 文件。 | `1` (开启，默认) |

### 3. 连接与线程配置 (Connection & Thread)
控制并发连接数和资源限制。

| 参数名 | 说明 | 推荐/示例值 |
| :--- | :--- | :--- |
| **`max_connections`** | 最大允许的并发连接数。 | `1000` - `3000` |
| **`max_user_connections`** | 单个用户最大连接数限制 (防止某个用户占满资源)。 | `0` (不限制) 或 `1000` |
| **`thread_cache_size`** | 线程缓存数，减少创建/销毁线程的开销。 | `64` |
| **`wait_timeout`** | 非交互式连接空闲超时时间 (秒)。太长会导致连接堆积。 | `600` - `1800` |
| **`interactive_timeout`** | 交互式连接 (如 mysql client) 空闲超时时间。 | `600` - `1800` |

### 4. 日志配置 (Logging)
用于故障排查、数据恢复和审计。

| 参数名 | 说明 | 推荐/示例值 |
| :--- | :--- | :--- |
| **`log_error`** | 错误日志路径 (必开)。 | `error.log` |
| **`slow_query_log`** | 是否开启慢查询日志。 | `1` (开启) |
| **`slow_query_log_file`** | 慢查询日志文件路径。 | `slow.log` |
| **`long_query_time`** | 慢查询阈值 (秒)。超过此时间的 SQL 会被记录。 | `1.0` 或 `0.5` |
| **`log_bin`** | 开启二进制日志 (主从复制、恢复必须)。 | `mysql-bin` |
| **`binlog_format`** | Binlog 格式。`ROW` 记录行变更 (推荐)，`STATEMENT` 记录SQL。 | `ROW` |
| **`expire_logs_days`** | Binlog 过期自动清理天数 (MySQL 8.0+ 用 `binlog_expire_logs_seconds`)。 | `7` |

### 5. 主从复制配置 (Replication)
如果此节点参与主从复制，则必须配置。

| 参数名 | 说明 | 推荐/示例值 |
| :--- | :--- | :--- |
| **`server-id`** | **唯一标识**。集群内必须唯一。 | `1` (主) / `2` (从) |
| **`gtid_mode`** | 是否开启 GTID 模式 (全局事务ID)。 | `ON` |
| **`enforce_gtid_consistency`** | 强制 GTID 一致性。 | `ON` |
| **`read_only`** | 是否只读。从库建议开启，主库关闭。 | `0` (主) / `1` (从) |

---

## 三、 [client] 与 [mysql] 客户端配置

这些配置方便本地操作，避免每次都输入参数。

```ini
[client]
port = 3306
socket = /tmp/mysql.sock
default-character-set = utf8mb4

[mysql]
# 开启自动补全
auto-rehash
default-character-set = utf8mb4
```

---

## 四、 生产环境参考模板 (my.cnf)

```ini
[client]
port    = 3306
socket  = /tmp/mysql.sock
default-character-set = utf8mb4

[mysqld]
# --- Basic ---
user     = mysql
port     = 3306
basedir  = /usr/local/mysql
datadir  = /data/mysql/data
socket   = /tmp/mysql.sock
pid-file = /data/mysql/mysqld.pid

# --- Character Set ---
character-set-server = utf8mb4
collation-server     = utf8mb4_general_ci
skip-character-set-client-handshake

# --- Connection ---
max_connections = 2000
max_connect_errors = 100
wait_timeout = 600
interactive_timeout = 600
skip-name-resolve  # 禁用 DNS 解析，加快连接速度

# --- InnoDB (Assuming 8GB RAM) ---
default_storage_engine = InnoDB
innodb_buffer_pool_size = 4G
innodb_buffer_pool_instances = 4
innodb_log_file_size = 1G
innodb_log_buffer_size = 16M
innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_io_capacity = 2000  # 根据磁盘 IOPS 调整

# --- Logging ---
log_error = /data/mysql/logs/error.log
slow_query_log = 1
slow_query_log_file = /data/mysql/logs/slow.log
long_query_time = 1
log_queries_not_using_indexes = 0

# --- Binlog & Replication ---
server-id = 1
log_bin = /data/mysql/binlogs/mysql-bin
binlog_format = ROW
max_binlog_size = 1G
sync_binlog = 1
gtid_mode = ON
enforce_gtid_consistency = ON
binlog_expire_logs_seconds = 604800  # 7 days

# --- Safety ---
# 禁用符号链接，防止安全风险
symbolic-links = 0
```
