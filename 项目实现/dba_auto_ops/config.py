"""
DBA 自动运维平台 - 全局配置
"""

import os

# 项目根目录
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Flask 配置
SECRET_KEY = os.environ.get("SECRET_KEY", "dba-ops-secret-key-change-in-production")
DEBUG = os.environ.get("DEBUG", "true").lower() == "true"

# SQLite 数据库路径
SQLITE_PATH = os.environ.get("SQLITE_PATH", os.path.join(BASE_DIR, "data", "dba_ops.db"))
SQLALCHEMY_DATABASE_URI = f"sqlite:///{SQLITE_PATH}"

# 实例配置文件
INSTANCES_CONFIG = os.environ.get("INSTANCES_CONFIG", os.path.join(BASE_DIR, "instances.yaml"))

# ODBC 驱动名称 (Windows)
ODBC_DRIVER = os.environ.get("ODBC_DRIVER", "ODBC Driver 17 for SQL Server")

# 查询超时 (秒)
QUERY_TIMEOUT = int(os.environ.get("QUERY_TIMEOUT", "30"))

# 连接重试次数
CONNECT_RETRY = int(os.environ.get("CONNECT_RETRY", "2"))

# ==================== 巡检告警阈值 ====================

THRESHOLDS = {
    # 磁盘: 可用空间低于 10% 或 50GB
    "disk_free_pct_warning": 10,
    "disk_free_gb_warning": 50,

    # 内存: Page Life Expectancy < 300 秒
    "memory_ple_warning": 300,
    # Buffer Cache Hit Ratio < 95%
    "memory_buffer_cache_hit_warning": 95,

    # 备份: FULL 超过 7 天
    "backup_full_days_warning": 7,
    # LOG 备份超过 1 小时 (60分钟)
    "backup_log_minutes_warning": 60,

    # 作业失败
    "job_failure_warning": True,
    # 作业运行时长增长超过 50%
    "job_duration_increase_warning": 0.5,

    # 阻塞超过 30 秒
    "blocking_seconds_warning": 30,

    # 索引碎片: >30% 建议重建
    "index_frag_rebuild": 30,
    # >10% 建议重组
    "index_frag_reorganize": 10,

    # DBCC CHECKDB 超过 7 天未执行
    "checkdb_days_warning": 7,
}

# 性能基线 (首次采集后自动建立)
PERFORMANCE_BASELINE_ENABLED = True
