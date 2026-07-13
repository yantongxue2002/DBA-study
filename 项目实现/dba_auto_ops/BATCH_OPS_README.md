# SQL Server 批量操作管理模块

基于现有 `dba_auto_ops` 项目扩展的批量操作管理模块，实现对 14 个 SQL Server 实例、50 个数据库的统一管理和操作。

## 功能特性

- **资产自动发现**：自动扫描所有实例的数据库列表，缓存到 SQLite
- **目标智能选择**：支持按实例、数据库名、模糊匹配选择操作目标
- **并行执行引擎**：多线程并行执行，单点失败不影响整体
- **SQL 操作模板**：预置常用操作模板（创建登录/用户/角色/授权等）
- **执行历史记录**：所有批量操作自动记录，支持审计追溯
- **干运行模式**：先预览 SQL，确认后再执行
- **Claude Code Skill**：支持自然语言操作

## 项目结构

```
dba_auto_ops/
├── core/
│   ├── mssql.py              # SQL Server 连接（已有）
│   ├── db.py                 # 数据库模型（已扩展批量操作表）
│   └── batch_engine.py       # 批量执行引擎核心
├── batch_ops/
│   ├── __init__.py           # 包初始化
│   ├── inventory.py          # 资产发现与缓存
│   ├── templates.py          # SQL 操作模板
│   ├── selector.py           # 目标选择器
│   └── executor.py           # 执行器（基于 batch_engine）
├── cli/
│   └── batch_cli.py          # 命令行工具
└── ...
```

## 快速开始

### 1. 同步资产清单

```bash
cd dba_auto_ops
python -m cli.batch_cli sync
```

### 2. 查看资产

```bash
python -m cli.batch_cli inventory
python -m cli.batch_cli inventory --detail
```

### 3. 创建服务器登录

在所有实例上创建登录账号：

```bash
python -m cli.batch_cli create-login \
  --name report_reader \
  --password "P@ssw0rd123" \
  --instances "*"
```

### 4. 创建数据库用户

在所有数据库上创建只读用户：

```bash
python -m cli.batch_cli create-user \
  --login report_reader \
  --roles db_datareader \
  --dbs "*"
```

指定实例和模糊匹配数据库：

```bash
python -m cli.batch_cli create-user \
  --login app_user \
  --roles db_datareader,db_datawriter \
  --instances 成都,天门 \
  --db-pattern "*prod*"
```

### 5. 授权

给用户在所有数据库上授予 SELECT 权限：

```bash
python -m cli.batch_cli grant \
  --user report_reader \
  --permission SELECT \
  --dbs "*"
```

### 6. 执行任意 SQL

在所有数据库上执行查询：

```bash
python -m cli.batch_cli execute \
  --sql "SELECT COUNT(*) as table_count FROM sys.tables" \
  --dbs "*"
```

### 7. 干运行模式

所有操作都支持 `--dry-run` 先预览：

```bash
python -m cli.batch_cli create-user \
  --login test_user \
  --roles db_datareader \
  --dbs "*" \
  --dry-run
```

## 支持的批量操作

### CLI 命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `sync` | 同步资产 | `sync` |
| `inventory` | 查看资产 | `inventory --detail` |
| `create-login` | 创建服务器登录 | `create-login --name x --password y` |
| `create-user` | 创建数据库用户 | `create-user --login x --roles db_datareader` |
| `create-role` | 创建数据库角色 | `create-role --name x` |
| `grant` | 授权 | `grant --user x --permission SELECT` |
| `add-to-role` | 添加用户到角色 | `add-to-role --user x --role y` |
| `execute` | 执行SQL | `execute --sql "SELECT 1"` |
| `history` | 查看历史 | `history --limit 20` |
| `templates` | 列出模板 | `templates` |

### Python API

```python
from batch_ops.inventory import inventory_manager
from batch_ops.selector import TargetSelector
from batch_ops.executor import BatchExecutor
from batch_ops import templates

# 1. 同步资产
inventory_manager.sync_to_db()

# 2. 选择目标
selector = TargetSelector()
targets = selector.select(
    instances=["成都", "天门"],
    db_pattern="*_prod",
)

# 3. 生成 SQL
sql = templates.create_login("reader", "P@ssw0rd123")

# 4. 执行
executor = BatchExecutor()
result = executor.execute(
    task_name="创建只读登录",
    operation_type="create_login",
    targets=targets,
    sql_generator=lambda t: sql,
)

print(f"成功: {result['success']}, 失败: {result['failed']}")
```

## Claude Code Skill 用法

### 激活方式

在 Claude Code 对话中直接描述操作：

```
给所有实例创建登录账号 report_reader，密码是 P@ssw0rd123
```

### 支持的指令

| 指令类型 | 示例 |
|----------|------|
| 查看资产 | "显示数据库资产清单" / "同步资产" |
| 创建登录 | "在所有实例上创建登录账号 xxx" |
| 创建用户 | "给所有数据库创建只读用户 xxx" |
| 创建角色 | "在所有数据库上创建角色 xxx" |
| 授权 | "给用户 xxx 授予 SELECT 权限" |
| 执行SQL | "在所有数据库上执行 SELECT COUNT(*) FROM sys.tables" |

### 目标选择语法

- **所有实例**："所有实例" / "全部实例"
- **指定实例**："成都实例" / "成都和天门"
- **所有数据库**："所有数据库" / "全部数据库"
- **模糊匹配**："*_prod" / "生产数据库"

## 数据库模型扩展

新增以下表用于批量操作：

### `db_inventory` — 数据库资产清单

| 字段 | 说明 |
|------|------|
| instance_name | 实例名 |
| db_name | 数据库名 |
| db_state | 数据库状态 |
| db_size_mb | 数据库大小(MB) |
| recovery_model | 恢复模式 |
| is_enabled | 是否参与批量操作 |

### `batch_tasks` — 批量任务记录

| 字段 | 说明 |
|------|------|
| task_name | 任务名称 |
| operation_type | 操作类型 |
| status | 状态 |
| total_targets | 总目标数 |
| success_count | 成功数 |
| fail_count | 失败数 |

### `batch_task_details` — 执行详情

| 字段 | 说明 |
|------|------|
| task_id | 关联任务 |
| instance_name | 实例名 |
| db_name | 数据库名 |
| status | 执行状态 |
| sql_executed | 执行的SQL |
| error_message | 错误信息 |

## 注意事项

1. **权限要求**：执行批量操作需要 sysadmin 或相应权限的登录账号
2. **密码安全**：CLI 中密码以明文传递，建议在生产环境使用环境变量或密钥管理
3. **事务安全**：每个目标独立执行，单点失败不影响其他目标
4. **连接数**：并行执行会同时建立多个连接，注意连接池限制
5. **干运行**：首次操作建议先使用 `--dry-run` 预览

## 扩展开发

### 添加新的 SQL 模板

在 `batch_ops/templates.py` 中添加：

```python
def my_new_template(param: str) -> str:
    """我的新模板"""
    return f"YOUR SQL {param}"

# 注册到 TEMPLATE_REGISTRY
TEMPLATE_REGISTRY["my_new_template"] = my_new_template
```

### 添加新的 CLI 命令

在 `cli/batch_cli.py` 中：

```python
def cmd_my_command(args):
    """我的新命令"""
    # 实现逻辑
    pass

# 注册到子命令
my_parser = subparsers.add_parser("my-cmd", help="...")
my_parser.set_defaults(func=cmd_my_command)
```

## 更新日志

### v1.0.0
- 资产发现与缓存
- 批量执行引擎（并行+错误隔离）
- SQL 操作模板（登录/用户/角色/授权）
- CLI 命令行工具
- Claude Code Skill
