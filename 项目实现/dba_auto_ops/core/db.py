"""
SQLite 数据库模型 — 存储巡检历史、性能快照、告警记录
"""

from datetime import datetime
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import Text, JSON

db = SQLAlchemy()


class InspectionResult(db.Model):
    """巡检结果表"""
    __tablename__ = "inspection_results"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    instance_name = db.Column(db.String(100), nullable=False, index=True)
    category = db.Column(db.String(50), nullable=False, index=True)
    check_time = db.Column(db.DateTime, default=datetime.now, index=True)
    status = db.Column(db.String(20), default="ok")  # ok / warning / error
    data = db.Column(Text)  # JSON 字符串 — 巡检详细数据
    summary = db.Column(Text)  # 巡检摘要

    def to_dict(self):
        import json
        return {
            "id": self.id,
            "instance_name": self.instance_name,
            "category": self.category,
            "check_time": self.check_time.strftime("%Y-%m-%d %H:%M:%S") if self.check_time else None,
            "status": self.status,
            "data": json.loads(self.data) if self.data else {},
            "summary": self.summary,
        }


class PerformanceSnapshot(db.Model):
    """性能快照表"""
    __tablename__ = "performance_snapshots"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    instance_name = db.Column(db.String(100), nullable=False, index=True)
    snapshot_time = db.Column(db.DateTime, default=datetime.now, index=True)
    category = db.Column(db.String(50), nullable=False)  # wait_stats, top_queries, etc.
    data = db.Column(Text)  # JSON 字符串

    def to_dict(self):
        import json
        return {
            "id": self.id,
            "instance_name": self.instance_name,
            "snapshot_time": self.snapshot_time.strftime("%Y-%m-%d %H:%M:%S") if self.snapshot_time else None,
            "category": self.category,
            "data": json.loads(self.data) if self.data else {},
        }


class Alert(db.Model):
    """告警记录表"""
    __tablename__ = "alerts"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    instance_name = db.Column(db.String(100), nullable=False, index=True)
    category = db.Column(db.String(50), nullable=False, index=True)
    severity = db.Column(db.String(20), nullable=False)  # info / warning / critical
    message = db.Column(Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.now, index=True)
    is_resolved = db.Column(db.Boolean, default=False)
    resolved_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "instance_name": self.instance_name,
            "category": self.category,
            "severity": self.severity,
            "message": self.message,
            "created_at": self.created_at.strftime("%Y-%m-%d %H:%M:%S") if self.created_at else None,
            "is_resolved": self.is_resolved,
            "resolved_at": self.resolved_at.strftime("%Y-%m-%d %H:%M:%S") if self.resolved_at else None,
        }


class InstanceStatus(db.Model):
    """实例连接状态表 (记录最近一次连接情况)"""
    __tablename__ = "instance_status"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    instance_name = db.Column(db.String(100), nullable=False, unique=True, index=True)
    is_connected = db.Column(db.Boolean, default=False)
    last_connect_time = db.Column(db.DateTime, nullable=True)
    last_inspection_time = db.Column(db.DateTime, nullable=True)
    error_message = db.Column(Text, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "instance_name": self.instance_name,
            "is_connected": self.is_connected,
            "last_connect_time": self.last_connect_time.strftime("%Y-%m-%d %H:%M:%S") if self.last_connect_time else None,
            "last_inspection_time": self.last_inspection_time.strftime("%Y-%m-%d %H:%M:%S") if self.last_inspection_time else None,
            "error_message": self.error_message,
        }


# ==================== 批量操作模块模型 ====================

class DbInventory(db.Model):
    """数据库资产清单 — 缓存所有实例的数据库列表"""
    __tablename__ = "db_inventory"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    instance_name = db.Column(db.String(100), nullable=False, index=True)
    db_name = db.Column(db.String(128), nullable=False, index=True)
    db_state = db.Column(db.String(20), default="ONLINE")  # ONLINE / OFFLINE / RESTORING / etc.
    db_size_mb = db.Column(db.Float, nullable=True)
    recovery_model = db.Column(db.String(20), nullable=True)  # FULL / SIMPLE / BULK_LOGGED
    created_at = db.Column(db.DateTime, nullable=True)
    last_discovered = db.Column(db.DateTime, default=datetime.now)
    is_enabled = db.Column(db.Boolean, default=True)  # 是否参与批量操作

    __table_args__ = (
        db.UniqueConstraint("instance_name", "db_name", name="uix_instance_db"),
    )

    def to_dict(self):
        return {
            "id": self.id,
            "instance_name": self.instance_name,
            "db_name": self.db_name,
            "db_state": self.db_state,
            "db_size_mb": self.db_size_mb,
            "recovery_model": self.recovery_model,
            "created_at": self.created_at.strftime("%Y-%m-%d %H:%M:%S") if self.created_at else None,
            "last_discovered": self.last_discovered.strftime("%Y-%m-%d %H:%M:%S") if self.last_discovered else None,
            "is_enabled": self.is_enabled,
        }


class BatchTask(db.Model):
    """批量任务记录"""
    __tablename__ = "batch_tasks"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    task_name = db.Column(db.String(200), nullable=False)
    operation_type = db.Column(db.String(50), nullable=False, index=True)  # create_login / create_user / grant / execute_sql / etc.
    target_filter = db.Column(Text)  # JSON: {"instances": [...], "databases": [...], "pattern": "..."}
    sql_template = db.Column(Text, nullable=False)  # 执行的SQL模板
    parameters = db.Column(Text)  # JSON: 模板参数
    status = db.Column(db.String(20), default="pending")  # pending / running / completed / partial_failed / failed
    total_targets = db.Column(db.Integer, default=0)
    success_count = db.Column(db.Integer, default=0)
    fail_count = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.now)
    started_at = db.Column(db.DateTime, nullable=True)
    completed_at = db.Column(db.DateTime, nullable=True)
    created_by = db.Column(db.String(100), default="system")

    def to_dict(self):
        import json
        return {
            "id": self.id,
            "task_name": self.task_name,
            "operation_type": self.operation_type,
            "target_filter": json.loads(self.target_filter) if self.target_filter else {},
            "sql_template": self.sql_template,
            "parameters": json.loads(self.parameters) if self.parameters else {},
            "status": self.status,
            "total_targets": self.total_targets,
            "success_count": self.success_count,
            "fail_count": self.fail_count,
            "created_at": self.created_at.strftime("%Y-%m-%d %H:%M:%S") if self.created_at else None,
            "started_at": self.started_at.strftime("%Y-%m-%d %H:%M:%S") if self.started_at else None,
            "completed_at": self.completed_at.strftime("%Y-%m-%d %H:%M:%S") if self.completed_at else None,
            "created_by": self.created_by,
        }


class BatchTaskDetail(db.Model):
    """批量任务执行详情 — 每个目标的执行结果"""
    __tablename__ = "batch_task_details"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    task_id = db.Column(db.Integer, db.ForeignKey("batch_tasks.id"), nullable=False, index=True)
    instance_name = db.Column(db.String(100), nullable=False, index=True)
    db_name = db.Column(db.String(128), nullable=True, index=True)  # 为空表示实例级操作
    status = db.Column(db.String(20), default="pending")  # success / failed / skipped
    sql_executed = db.Column(Text)  # 实际执行的SQL
    error_message = db.Column(Text, nullable=True)
    execution_time_ms = db.Column(db.Integer, nullable=True)
    executed_at = db.Column(db.DateTime, default=datetime.now)

    def to_dict(self):
        return {
            "id": self.id,
            "task_id": self.task_id,
            "instance_name": self.instance_name,
            "db_name": self.db_name,
            "status": self.status,
            "sql_executed": self.sql_executed,
            "error_message": self.error_message,
            "execution_time_ms": self.execution_time_ms,
            "executed_at": self.executed_at.strftime("%Y-%m-%d %H:%M:%S") if self.executed_at else None,
        }
