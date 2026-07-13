"""
备份状态采集器
"""

from collectors.base import BaseCollector
from config import THRESHOLDS


class BackupsCollector(BaseCollector):
    category = "backups"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "backup_status.sql", timeout=60)
        databases = []
        no_full_backup = []
        full_overdue = []
        log_overdue = []
        no_recovery = []  # 完整恢复模式但没有 LOG 备份

        for row in rows:
            db = {
                "database_name": row.get("database_name", ""),
                "recovery_model_desc": row.get("recovery_model_desc", ""),
                "state_desc": row.get("state_desc", ""),
                "last_full_backup": str(row.get("last_full_backup", "")),
                "days_since_full_backup": self._safe_int(row.get("days_since_full_backup")),
                "hours_since_full_backup": self._safe_int(row.get("hours_since_full_backup")),
                "last_diff_backup": str(row.get("last_diff_backup", "")),
                "days_since_diff_backup": self._safe_int(row.get("days_since_diff_backup")),
                "last_log_backup": str(row.get("last_log_backup", "")),
                "hours_since_log_backup": self._safe_int(row.get("hours_since_log_backup")),
                "days_since_log_backup": self._safe_int(row.get("days_since_log_backup")),
                "last_full_backup_gb": self._safe_float(row.get("last_full_backup_gb")),
                "last_full_backup_duration_min": self._safe_int(row.get("last_full_backup_duration_min")),
                "compression_ratio_pct": self._safe_float(row.get("compression_ratio_pct")),
            }

            # 判定告警条件
            if row.get("last_full_backup") is None:
                no_full_backup.append(db["database_name"])
            elif db["days_since_full_backup"] > THRESHOLDS["backup_full_days_warning"]:
                full_overdue.append(db)

            if (db["recovery_model_desc"] == "FULL"
                    and db["hours_since_log_backup"] is not None
                    and db["hours_since_log_backup"] > THRESHOLDS["backup_log_minutes_warning"] / 60):
                log_overdue.append(db)

            if db["recovery_model_desc"] == "FULL" and row.get("last_log_backup") in (None, ""):
                no_recovery.append(db["database_name"])

            databases.append(db)

        return {
            "databases": databases,
            "db_count": len(databases),
            "no_full_backup": no_full_backup,
            "full_overdue_count": len(full_overdue),
            "log_overdue_count": len(log_overdue),
            "no_log_backup_in_full_recovery": no_recovery,
        }

    def evaluate(self, data: dict) -> str:
        if data.get("no_full_backup"):
            return "error"
        if data.get("full_overdue_count", 0) > 0:
            return "warning"
        if data.get("log_overdue_count", 0) > 0:
            return "warning"
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        parts = [f"共{data['db_count']}个数据库"]
        if data["no_full_backup"]:
            parts.append(f"无FULL备份: {', '.join(data['no_full_backup'])}")
        if data["full_overdue_count"] > 0:
            parts.append(f"FULL过期{data['full_overdue_count']}个")
        if data["log_overdue_count"] > 0:
            parts.append(f"LOG过期{data['log_overdue_count']}个")
        if data["no_log_backup_in_full_recovery"]:
            parts.append(f"缺LOG备份: {', '.join(data['no_log_backup_in_full_recovery'])}")
        return "备份: " + ", ".join(parts)

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        for db_name in data.get("no_full_backup", []):
            alerts.append({
                "category": "backups",
                "severity": "critical",
                "message": f"数据库 [{db_name}] 从未进行过 FULL 备份",
            })
        for db in data.get("full_overdue", []):
            alerts.append({
                "category": "backups",
                "severity": "warning",
                "message": (
                    f"数据库 [{db['database_name']}] FULL 备份已过期 "
                    f"{db['days_since_full_backup']} 天 (阈值: {THRESHOLDS['backup_full_days_warning']}天)"
                ),
            })
        for db in data.get("log_overdue", []):
            alerts.append({
                "category": "backups",
                "severity": "warning",
                "message": (
                    f"数据库 [{db['database_name']}] LOG 备份已过期 "
                    f"{db['hours_since_log_backup']:.0f} 小时 (阈值: {THRESHOLDS['backup_log_minutes_warning']}分钟)"
                ),
            })
        return alerts
