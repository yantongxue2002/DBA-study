# SQL Server 数据库字典生成工具

自动从 SQL Server 数据库中提取表结构信息，按照模板格式生成 Excel 数据字典。

## 功能特性

- 自动扫描所有业务库（排除系统库）
- 每个业务库生成一个独立的 Excel 文件
- 每个 Schema 生成一个 Sheet
- 包含字段名、类型、精度、是否可空、默认值、字段说明、是否主键
- 按照 `数据字典模板.xlsx` 的格式输出

## 环境要求

- Python 3.7+
- `pyodbc` — 数据库连接
- `openpyxl` — Excel 生成
- ODBC Driver 17 for SQL Server（或更高版本）

## 安装依赖

```bash
pip install pyodbc openpyxl
```

## 使用方法

1. **修改配置**

编辑 `config.py`，设置数据库连接信息和排除库列表：

```python
DB_CONFIG = {
    "server": "10.20.1.193,1433",
    "uid": "dba_admin",
    "pwd": "your_password",
    "driver": "ODBC Driver 17 for SQL Server",
}
```

2. **运行生成**

```bash
cd db_dict_generator
python generate_dict.py
```

3. **查看输出**

生成的 Excel 文件保存在 `output/` 目录下：

```
output/
  ├── mes_数据字典.xlsx
  ├── mes_report_数据字典.xlsx
  ├── nuva_mom_数据字典.xlsx
  └── wms_数据字典.xlsx
```

## Excel 文件格式

每个 Sheet 的结构与模板文件一致：

```
库名 | <数据库名>
备注 |
字段 | 字段名称 | 类型 | 精度 | 允许为空 | 默认值 | 说明 | 是否主键
<字段数据行...>

表名 | <schema>.<table_name>
备注 | <表说明>
字段 | 字段名称 | 类型 | 精度 | 允许为空 | 默认值 | 说明 | 是否主键
<字段数据行...>
```

## 配置说明

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `server` | 数据库服务器地址 | `10.20.1.193,1433` |
| `uid` | 数据库用户名 | `dba_admin` |
| `pwd` | 数据库密码 | - |
| `driver` | ODBC 驱动名称 | `ODBC Driver 17 for SQL Server` |
| `EXCLUDE_DB_LIST` | 排除的系统数据库 | `master, model, msdb, tempdb, distribution` |
| `OUTPUT_DIR` | 输出目录 | `output` |
