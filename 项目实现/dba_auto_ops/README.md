# DBA 自动运维平台

对 35 个 SQL Server 2019 实例的集中式巡检、性能分析和报表平台。

## 技术栈

- **后端**: Python 3.9+ / Flask 3.x
- **数据库连接**: pyodbc + ODBC Driver 17 for SQL Server
- **本地存储**: SQLite + SQLAlchemy
- **任务调度**: APScheduler
- **前端**: Bootstrap 5 + ECharts

## 快速开始

### 1. 环境准备 (Windows)

```bash
# 安装 Python 3.9+
# 安装 ODBC Driver 17: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server

# 安装 Python 依赖
pip install -r requirements.txt
```

### 2. 配置实例

编辑 `instances.yaml`，填入你的 35 个 SQL Server 实例信息：

```yaml
instances:
  - name: "PROD-SRV-01"
    host: "192.168.1.101"
    port: 1433
    user: "dba_monitor"
    password: "your_password"
    description: "核心业务系统"
    enabled: true
```

**建议**: 创建一个专用监控账号，只需以下权限：
- `VIEW SERVER STATE`
- `VIEW ANY DEFINITION`
- `msdb` 中 `SQLAgentReaderRole` 角色
- `msdb` 中 `db_datareader` 角色
- `master` 中读取错误日志的权限 (`EXEC xp_readerrorlog`)

### 3. 启动

```bash
# 方式1: 直接运行
python app.py

# 方式2: 使用批处理脚本
start.bat
```

浏览器访问: **http://localhost:5000**

## 功能模块

### 巡检指标 (11项)

| 指标 | 频率 | 说明 |
|------|------|------|
| 磁盘空间 | 30分钟 | 各盘总/已用/可用，数据文件分布 |
| 内存使用 | 30分钟 | Buffer Cache命中率、PLE、内存分配 |
| SQL Agent作业 | 4小时 | 运行状态、时长、失败/异常检测 |
| 备份状态 | 4小时 | FULL/DIFF/LOG备份时间、过期告警 |
| DBCC CHECKDB | 4小时 | 执行记录、完整性结果 |
| 阻塞链 | 5分钟 | 阻塞会话、等待时长、阻塞源 |
| 慢查询/Top CPU | 1小时 | Plan Cache中高消耗SQL |
| 索引碎片 | 每日2:00 | 碎片率、REBUILD/REORGANIZE建议 |
| 等待统计 | 1小时 | Top等待类型、信号等待分析 |
| 错误日志扫描 | 每日8:00 | 严重错误关键字匹配 |
| 死锁抓取 | 1小时 | system_health XEvent解析 |

### Web 仪表盘

- **首页**: 35个实例红绿灯状态、告警汇总卡片
- **巡检页**: 按实例/类别筛选巡检结果
- **实例详情**: 单实例所有指标聚合 + 趋势
- **性能分析**: 等待统计图表、慢查询TOP20、索引建议
- **巡检报告**: HTML报告、支持打印/导出

### 告警阈值

可调整阈值见 `config.py` → `THRESHOLDS`：

| 阈值项 | 默认值 |
|--------|--------|
| 磁盘可用 < | 10% 或 50GB |
| PLE < | 300秒 |
| FULL备份过期 > | 7天 |
| LOG备份过期 > | 60分钟 |
| 阻塞 > | 30秒 |
| CHECKDB未执行 > | 7天 |
| 索引碎片 > 30% | REBUILD |

## 项目结构

```
dba_auto_ops/
├── app.py              # Flask 主入口
├── config.py           # 全局配置 & 阈值
├── instances.yaml      # 实例连接信息
├── start.bat           # Windows 启动脚本
├── core/               # 核心模块
│   ├── db.py           # SQLite 模型
│   └── mssql.py        # pyodbc 连接池
├── collectors/         # 巡检采集器
│   ├── base.py         # 基类
│   ├── disk.py         # 磁盘
│   ├── memory.py       # 内存
│   ├── jobs.py         # 作业
│   ├── backups.py      # 备份
│   ├── db_integrity.py # DBCC
│   ├── blocking.py     # 阻塞
│   ├── slow_query.py   # 慢查询
│   ├── index_frag.py   # 索引碎片
│   ├── error_log.py    # 错误日志
│   ├── wait_stats.py   # 等待统计
│   └── deadlock.py     # 死锁
├── services/           # 服务层
│   ├── inspection.py   # 巡检调度
│   ├── scheduler.py    # 定时任务
│   └── report.py       # 报告生成
├── sql/                # T-SQL 脚本
├── templates/          # Jinja2 模板
├── static/             # CSS/JS
└── data/               # SQLite 数据库文件
```

## 后续扩展建议

- 钉钉/企业微信告警推送
- 实例分组 (生产/测试/开发)
- Always On AG 同步状态巡检
- 数据库自动增长事件监控
- 统计信息过期检测
- 用户自定义巡检脚本接口
- 权限审计
- SSL证书到期提醒
