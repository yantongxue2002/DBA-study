# DBA 高阶面试题集锦 (资深/专家级)

本文档汇编了高级 DBA 面试中常见的高难度问题，重点考察对数据库内核原理、高可用架构设计、故障排查能力以及分布式数据库的理解。

---

## 一、MySQL 内核与原理深挖

### Q1: 详细描述 MySQL 的 Undo Log 是如何实现 MVCC 的？(必考)
**核心点**：隐藏字段、Undo Log 链、Read View、可见性算法。
**回答**：
1.  **隐藏字段**：InnoDB 为每行记录添加了三个隐藏字段：
    *   `DB_TRX_ID`：最后修改该行的事务 ID。
    *   `DB_ROLL_PTR`：回滚指针，指向 Undo Log 中该行的上一个版本。
    *   `DB_ROW_ID`：隐藏主键（若无主键时）。
2.  **Undo Log 链**：通过 `DB_ROLL_PTR` 指针，将数据的历史版本在 Undo Log 中串联成一个链表，最新的在表里，旧的在 Log 里。
3.  **Read View (读视图)**：快照读（Select）时生成。包含：
    *   `m_ids`：生成时刻活跃（未提交）的事务 ID 列表。
    *   `min_trx_id`：活跃事务中最小 ID。
    *   `max_trx_id`：生成时刻系统最大事务 ID + 1。
4.  **可见性规则**：读取数据时，拿记录的 `DB_TRX_ID` 与 Read View 比较：
    *   若 `trx_id < min_trx_id`：说明事务早己提交，**可见**。
    *   若 `trx_id >= max_trx_id`：说明是未来事务生成的，**不可见**。
    *   若在 `m_ids` 列表中：说明事务还没提交，**不可见**（除非是自己）。
    *   若不可见，则顺着 Undo Log 链找下一个版本，直到符合条件。

### Q2: Redo Log 的写入机制是怎样的？什么是 Log Buffer 的刷盘策略？
**核心点**：WAL、Log Buffer、OS Cache、fsync、双 1 设置。
**回答**：
1.  **WAL (Write-Ahead Logging)**：先写日志，再写磁盘数据页。
2.  **写入流程**：事务执行 -> 写 Log Buffer -> 写 OS Page Cache -> fsync 到磁盘。
3.  **`innodb_flush_log_at_trx_commit` 策略**：
    *   `0`：每秒将 Log Buffer -> OS Cache -> Disk。进程崩丢 1s 数据。
    *   `1` (默认)：每次 Commit 都 fsync。最安全，IO 压力大。
    *   `2`：每次 Commit 将 Log Buffer -> OS Cache，每秒 fsync。OS 崩才丢数据。
4.  **Group Commit (组提交)**：为了缓解 fsync 压力，MySQL 支持将多个并发事务的 Redo Log 一次性刷盘。

### Q3: MySQL 的 Doublewrite Buffer (双写缓冲) 解决了什么问题？
**核心点**：Partial Page Write (页断裂)、页大小不一致。
**回答**：
*   **问题**：InnoDB 页大小默认 16KB，而文件系统页大小通常 4KB。刷盘时，可能只写了前 4KB 系统就断电了，导致页损坏 (Partial Page Write)。Redo Log 记录的是物理修改，如果页本身坏了，Redo Log 无法恢复。
*   **机制**：
    1.  内存中脏页先 Copy 到 Doublewrite Buffer。
    2.  顺序写入共享表空间中的 Doublewrite 区域（磁盘），并 fsync。
    3.  再离散写入真正的数据文件。
*   **恢复**：如果恢复时发现页损坏，先从 Doublewrite 区域找到完整的页副本覆盖，再应用 Redo Log。

---

## 二、高可用架构与容灾

### Q4: MGR (MySQL Group Replication) 与传统主从复制的区别？
**核心点**：Paxos 协议、强一致性、多写冲突检测。
**回答**：
1.  **一致性协议**：
    *   传统复制：异步或半同步，无法保证数据零丢失（Failover 时可能丢）。
    *   MGR：基于 Paxos 分布式一致性协议，保证大多数节点收到日志才提交。
2.  **故障切换**：
    *   传统复制：依赖外部工具（MHA/Orchestrator）进行选主和 VIP 漂移。
    *   MGR：原生自带选主机制，成员自动管理。
3.  **多写支持**：
    *   MGR 支持多主模式（Multi-Primary），所有节点可写。通过 Certify 阶段进行乐观并发控制，检测写冲突（基于 Write Set）。

### Q5: 生产环境主从延迟如何排查和解决？
**核心点**：I/O 瓶颈、SQL 线程单线程瓶颈、大事务、无主键。
**排查**：
1.  `SHOW SLAVE STATUS` 观察 `Seconds_Behind_Master`。
2.  对比主从 Binlog 位点。
**原因与解决**：
1.  **大事务**：主库执行一个 Delete 用了 10分钟，从库回放也要 10分钟。-> 拆分大事务。
2.  **无主键表**：Row 模式下，更新无主键表，从库回放可能退化为全表扫描。-> 强制所有表加主键。
3.  **主库并发高，从库单线程回放慢**：
    *   MySQL 5.6：基于库 (Schema) 的并行复制。
    *   MySQL 5.7：基于组提交 (Logical Clock) 的并行复制（`slave_parallel_workers` > 0）。
    *   MySQL 8.0：基于 Write Set 的并行复制（彻底解决依赖关系）。
4.  **硬件差异**：从库配置比主库差。

---

## 三、性能调优与故障排查

### Q6: 遇到 CPU 100% 如何排查？
**核心点**：定位线程、关联 SQL、执行计划分析。
**回答**：
1.  **OS 层**：`top -c` 找到 mysqld 进程 PID，再 `top -H -p PID` 找到消耗 CPU 最高的线程 ID (TID)。
2.  **MySQL 层**：
    *   查询 `performance_schema.threads` 表，将 OS 的 TID 映射为 MySQL 的 `PROCESSLIST_ID`。
    *   或者直接 `SHOW PROCESSLIST` 查看状态为 `Sending data`, `Copying to tmp table`, `Sorting result` 的连接。
3.  **分析 SQL**：
    *   拿到 SQL 后 `EXPLAIN`。
    *   常见原因：全表扫描、未使用索引、死锁回滚自旋、大量聚合计算。
4.  **解决**：Kill 掉问题会话，优化索引。

### Q7: 数据库连接数爆满 (Too many connections) 怎么处理？
**回答**：
1.  **紧急恢复**：
    *   如果是普通用户无法登录，使用 `root`（MySQL 保留了一个管理连接）。
    *   批量 Kill 掉 Sleep 连接或慢查询连接（使用 `pt-kill` 工具）。
2.  **根因分析**：
    *   **慢查询堆积**：SQL 执行慢，导致连接无法释放。-> 优化 SQL。
    *   **应用连接池配置不当**：最大连接数设置过大，且未正确复用。
    *   **死锁/锁等待**：大量事务被阻塞。
3.  **参数调整**：
    *   调大 `max_connections`。
    *   调小 `wait_timeout` 和 `interactive_timeout`（回收空闲连接）。

---

## 四、分布式数据库与架构设计

### Q8: 分库分表后，如何解决分页查询 (Limit Offset) 问题？
**核心点**：全局排序、性能衰减、二次查询法、ES 辅助。
**回答**：
问题：`LIMIT 10000, 10`。如果分了 10 张表，需要在每张表查前 10010 条，汇总排序后再取。
**解决方案**：
1.  **禁止深分页**：产品设计上限制只能看前 N 页，或使用“下一页”（基于上次 ID 搜索）。
2.  **二次查询法**：
    *   先查出全局的 ID 列表（只查 ID，且用 `WHERE id > last_max_id` 优化）。
    *   再根据 ID 回表查详情。
3.  **搜索引擎 (ES) 辅助**：
    *   复杂查询和分页走 ES，查出 ID 后再去 MySQL 查详情。

### Q9: 什么是 Raft 协议的 Log Replication 过程？(TiDB/OceanBase 相关)
**核心点**：Leader, Follower, AppendEntries, Commit Index.
**回答**：
1.  Client 发送写请求给 Leader。
2.  Leader 将日志条目 (Log Entry) 写入本地日志。
3.  Leader 并行向所有 Followers 发送 `AppendEntries` RPC。
4.  Follower 收到后写入本地日志，并返回 Success。
5.  一旦 Leader 收到 **大多数 (Majority)** 节点的成功响应：
    *   Leader 将该日志状态改为 Committed。
    *   Leader 应用该日志到状态机（执行 SQL）。
    *   Leader 返回结果给 Client。
    *   Leader 通知 Followers 提交日志。

### Q10: 讲一下 MySQL 8.0 的新特性？
1.  **原子 DDL**：DDL 操作（如 Drop Table）要么全成功要么全失败，不再会有残留元数据。
2.  **Instant Add Column**：秒级加字段（只修改元数据，不重写表数据）。
3.  **降序索引**：支持 `DESC` 索引，优化倒序查询。
4.  **CTE (公共表表达式)**：`WITH` 子句，递归查询。
5.  **窗口函数**：`RANK()`, `ROW_NUMBER()` 等，方便做排名统计。
6.  **角色管理 (Role)**：方便权限管理。