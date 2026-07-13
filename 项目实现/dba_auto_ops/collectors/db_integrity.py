"""
数据库完整性采集器 (DBCC CHECKDB)
"""

from collectors.base import BaseCollector
from config import THRESHOLDS


class DbIntegrityCollector(BaseCollector):
    category = "db_integrity"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "dbcc_history.sql", timeout=120)
        checks = []
        error_db = []
        no_recent_check = []

        for row in rows:
            check = {
                "check_time": str(row.get("check_time", "")),
                "database_name": row.get("database_name", ""),
                "check_result": row.get("check_result", ""),
                "is_completed": bool(row.get("is_completed")),
                "days_since_check": self._safe_int(row.get("days_since_check")),
                "full_message": row.get("full_message", ""),
            }

            if check["check_result"] == "有错误":
                error_db.append(check["database_name"])
            elif check["check_result"] == "未完成":
                error_db.append(check["database_name"])

            if check["days_since_check"] > THRESHOLDS["checkdb_days_warning"]:
                if check["database_name"] not in no_recent_check:
                    no_recent_check.append(check["database_name"])

            checks.append(check)

        return {
            "checks": checks,
            "check_count": len(checks),
            "error_databases": list(set(error_db)),
            "no_recent_check": list(set(no_recent_check)),
        }

    def evaluate(self, data: dict) -> str:
        if data.get("error_databases"):
            return "error"
        if data.get("no_recent_check"):
            return "warning"
        if data["check_count"] == 0:
            return "warning"  # 没有找到 CHECKDB 记录
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        parts = [f"找到{data['check_count']}条CHECKDB记录"]
        if data["error_databases"]:
            parts.append(f"错误库: {', '.join(data['error_databases'])}")
        if data["no_recent_check"]:
            parts.append(f"超期未检: {', '.join(data['no_recent_check'])}")
        if data["check_count"] == 0:
            return "DBCC CHECKDB: 最近14天无执行记录, 请确认是否有其他巡检机制!"
        return "DBCC CHECKDB: " + ", ".join(parts)

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        for db in data.get("error_databases", []):
            alerts.append({
                "category": "db_integrity",
                "severity": "critical",
                "message": f"数据库 [{db}] DBCC CHECKDB 发现错误, 请立即检查!",
            })
        for db in data.get("no_recent_check", []):
            alerts.append({
                "category": "db_integrity",
                "severity": "warning",
                "message": f"数据库 [{db}] 超过 {THRESHOLDS['checkdb_days_warning']} 天未执行 DBCC CHECKDB",
            })
        if data["check_count"] == 0:
            alerts.append({
                "category": "db_integrity",
                "severity": "warning",
                "message": "未找到任何 DBCC CHECKDB 执行记录, 请确认巡检机制",
            })
        return alerts
