# MySQL 进阶原理：InnoDB、锁机制与主从复制

本文档深入解析 MySQL 核心原理，涵盖 InnoDB 存储引擎架构、锁机制详解、死锁排查方法以及主从复制原理与部署实战。

---

## 一、InnoDB 存储引擎核心架构

InnoDB 是 MySQL 的默认存储引擎，支持事务（ACID）、行级锁和外键。其核心架构分为内存结构和磁盘结构。

### 1. 缓冲池 (Buffer Pool)
Buffer Pool 是 InnoDB 内存中最大的区域，用于缓存磁盘上的数据页（Data Page）和索引页（Index Page）。

*   **作用**：弥补 CPU 速度与磁盘 I/O 速度的巨大鸿沟。读取数据时，先判断是否在 BP 中；修改数据时，先修改 BP 中的页（变为脏页），再通过 Checkpoint 机制异步刷盘。
*   **管理算法 (LRU)**：
    *   采用改进的 LRU（Least Recently Used）算法，分为 **Young 区**（热数据，约 63%）和 **Old 区**（冷数据，约 37%）。
    *   新读取的页先放入 Old 区头部。只有在 Old 区停留超过一定时间（`innodb_old_blocks_time`，默认 1000ms）后再次被访问，才移入 Young 区。
    *   **目的**：防止全表扫描瞬间将热点数据挤出缓存。
*   **核心参数**：
    *   `innodb_buffer_pool_size`：建议设置为物理内存的 50%-75%。
    *   `innodb_buffer_pool_instances`：将 BP 划分为多个实例，减少并发锁竞争（内存 > 1GB 时生效）。

### 2. Redo Log (重做日志) —— 保证持久性 (Durability)
Redo Log 记录的是“物理日志”，即“在某个数据页上做了什么修改”。

*   **WAL (Write-Ahead Logging)**：先写日志，再写磁盘。只要 Redo Log 写入成功，事务就算提交成功，即使数据库宕机，也能通过 Redo Log 恢复数据（Crash Safe）。
*   **结构**：
    *   **Redo Log Buffer**：内存中的日志缓冲。
    *   **Redo Log File** (`ib_logfile0`, `ib_logfile1`)：磁盘上的日志文件，循环写入。
*   **刷盘策略 (`innodb_flush_log_at_trx_commit`)**：
    *   `0`：每秒将 Log Buffer 写入 OS Cache 并 fsync 到磁盘（性能最好，宕机丢1秒数据）。
    *   `1`：每次事务提交都 fsync 到磁盘（默认，最安全）。
    *   `2`：每次事务提交写入 OS Cache，每秒 fsync（介于两者之间，OS 宕机才丢数据）。

### 3. Undo Log (回滚日志) —— 保证原子性 (Atomicity) 与 MVCC
Undo Log 记录的是“逻辑日志”，用于记录数据被修改前的样子。

*   **作用**：
    1.  **事务回滚**：执行 ROLLBACK 时，根据 Undo Log 做逆向操作（Insert 变 Delete，Update 变反向 Update）。
    2.  **MVCC (多版本并发控制)**：构建一致性读取视图（Read View），让查询能看到旧版本的数据。

### 4. MVCC (多版本并发控制)
MVCC 使得 InnoDB 在 Read Committed (RC) 和 Repeatable Read (RR) 隔离级别下，读操作不需要加锁（快照读），大幅提升并发性能。

*   **实现原理**：
    1.  **隐藏字段**：每行数据包含 `DB_TRX_ID`（最近修改的事务ID）和 `DB_ROLL_PTR`（回滚指针，指向 Undo Log）。
    2.  **Undo Log 链**：通过回滚指针将数据的历史版本串联起来。
    3.  **Read View (读视图)**：事务启动时生成的快照，包含当前活跃事务列表。
*   **可见性规则**：
    *   **RC**：每次 Select 都生成新的 Read View（能读到其他事务已提交的修改）。
    *   **RR**：第一次 Select 生成 Read View，后续复用（保证可重复读）。

---

## 二、锁机制 (Locking Mechanism)

InnoDB 支持行级锁，锁也是基于索引实现的。如果 SQL 语句没有走索引，会退化为表锁。

### 1. 锁的粒度
*   **行锁 (Record Lock)**：锁定单行记录（实际上是锁索引记录）。
*   **间隙锁 (Gap Lock)**：锁定索引记录之间的间隙，防止插入（解决幻读问题）。仅在 RR 隔离级别有效。
*   **临键锁 (Next-Key Lock)**：Record Lock + Gap Lock，锁定左开右闭区间 `(a, b]`。InnoDB 在 RR 级别下默认使用 Next-Key Lock。
*   **表锁**：`LOCK TABLES` 或 DDL 操作时触发。

### 2. 锁的模式
*   **共享锁 (S Lock)**：读锁。`SELECT ... LOCK IN SHARE MODE`。
*   **排他锁 (X Lock)**：写锁。`UPDATE`, `DELETE`, `INSERT`, `SELECT ... FOR UPDATE`。
*   **意向锁 (IS/IX)**：表级锁，用于快速判断表中是否有行被锁定，避免遍历。

### 3. 死锁 (Deadlock)
两个或多个事务互相持有对方需要的锁，形成循环等待。

#### 死锁排查
1.  **查看当前死锁**：
    ```sql
    SHOW ENGINE INNODB STATUS\G
    -- 关注 LATEST DETECTED DEADLOCK 部分
    ```
2.  **开启死锁日志**：
    在配置文件中设置 `innodb_print_all_deadlocks = 1`，死锁信息会记录到 MySQL 错误日志中。
3.  **系统表查询**：
    ```sql
    SELECT * FROM sys.innodb_lock_waits;
    SELECT * FROM performance_schema.data_locks;
    ```

#### 死锁解决与避免
*   **自动回滚**：MySQL 默认开启 `innodb_deadlock_detect = on`，发现死锁后自动回滚持有锁较少的事务。
*   **避免策略**：
    *   保持事务简短，减少锁持有时间。
    *   统一加锁顺序（如总是先更新 User 表再更新 Order 表）。
    *   为 Update/Delete 语句添加合适的索引，避免锁全表或过大的间隙。

---

## 三、主从复制 (Master-Slave Replication)

### 1. 复制原理
MySQL 复制是基于 **Binlog (二进制日志)** 的。
1.  **Master**：将数据变更写入 Binlog。
2.  **Master**：Dump 线程将 Binlog 事件发送给 Slave。
3.  **Slave**：I/O 线程接收 Binlog 并写入 Relay Log（中继日志）。
4.  **Slave**：SQL 线程读取 Relay Log 并重放 SQL，应用变更。

### 2. 复制模式
*   **异步复制 (Asynchronous)**：Master 写完 Binlog 只要发送给 Slave 就不管了，直接返回成功。**性能最好，但可能丢数据**。
*   **半同步复制 (Semi-Synchronous)**：Master 至少收到一个 Slave 的 ACK（写入 Relay Log）才返回成功。**数据安全性高，性能略损**。
*   **全同步复制 (Group Replication - MGR)**：基于 Paxos 协议，多节点强一致性。

### 3. GTID (Global Transaction ID)
GTID 是 MySQL 5.6 引入的全局事务 ID，格式为 `UUID:Sequence`。
*   **优势**：
    *   全局唯一，方便追踪事务。
    *   主从切换（Failover）极其简单，不再需要寻找 Binlog 文件名和 Position。
    *   支持多源复制。

### 4. 部署实战 (基于 GTID)

#### 步骤 1：主库 (Master) 配置
编辑 `my.cnf`：
```ini
[mysqld]
server-id = 1
log-bin = mysql-bin
gtid_mode = ON
enforce_gtid_consistency = ON
binlog_format = ROW
```
创建复制用户：
```sql
CREATE USER 'repl'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
```

#### 步骤 2：从库 (Slave) 配置
编辑 `my.cnf`：
```ini
[mysqld]
server-id = 2
gtid_mode = ON
enforce_gtid_consistency = ON
# 可选：只读
read_only = 1
```

#### 步骤 3：数据同步 (若主库已有数据)
使用 `mysqldump` 导出全量数据（包含 GTID 信息）：
```bash
mysqldump -u root -p --all-databases --master-data=2 --single-transaction > full_backup.sql
```
在从库导入：
```bash
mysql -u root -p < full_backup.sql
```

#### 步骤 4：启动复制
在从库执行：
```sql
CHANGE MASTER TO
    MASTER_HOST='master_ip',
    MASTER_PORT=3306,
    MASTER_USER='repl',
    MASTER_PASSWORD='password',
    MASTER_AUTO_POSITION=1; -- 关键：开启 GTID 自动定位

START SLAVE;
```

#### 步骤 5：验证状态
```sql
SHOW SLAVE STATUS\G
-- 确保以下两项为 Yes
-- Slave_IO_Running: Yes
-- Slave_SQL_Running: Yes
```