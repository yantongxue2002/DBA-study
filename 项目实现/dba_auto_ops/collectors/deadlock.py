"""
死锁抓取采集器
"""

from collectors.base import BaseCollector


class DeadlockCollector(BaseCollector):
    category = "deadlock"

    def collect(self, instance_name: str) -> dict:
        # 先检查 system_health 是否可用
        try:
            xe_check = self.connector.execute_query(
                instance_name,
                "SELECT 1 AS xe_available FROM sys.dm_xe_sessions WHERE name = 'system_health'",
                timeout=10
            )
            has_system_health = len(xe_check) > 0
        except Exception:
            has_system_health = False

        if not has_system_health:
            return {
                "deadlocks": [],
                "deadlock_count_recent": 0,
                "deadlock_frequency": [],
                "has_system_health": False,
            }

        # 有 system_health，采集死锁数据
        rows = self.execute_sql_file(instance_name, "deadlock_capture.sql", timeout=60)

        deadlocks = []
        frequency = []

        for row in rows:
            # 死锁记录
            if "deadlock_time" in row:
                dl = {
                    "deadlock_time": str(row.get("deadlock_time", "")),
                    "victim_spid": self._safe_int(row.get("victim_spid")),
                    "victim_app": row.get("victim_app", ""),
                    "victim_host": row.get("victim_host", ""),
                    "victim_query": row.get("victim_query", ""),
                    "deadlock_graph": row.get("deadlock_graph", ""),
                    "database_name": row.get("database_name", ""),
                }
                deadlocks.append(dl)

            # 死锁频率统计
            elif "deadlock_date" in row:
                frequency.append({
                    "date": str(row.get("deadlock_date", "")),
                    "count": self._safe_int(row.get("deadlock_count")),
                })

            # 错误信息
            elif "error_message" in row:
                pass  # system_health 会话不存在

        return {
            "deadlocks": deadlocks,
            "deadlock_count_recent": len(deadlocks),
            "deadlock_frequency": frequency,
            "has_system_health": has_system_health,
        }

    def evaluate(self, data: dict) -> str:
        if not data.get("has_system_health"):
            return "warning"  # system_health 不可用
        if data.get("deadlock_count_recent", 0) > 5:
            return "warning"
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        if not data.get("has_system_health"):
            return "死锁: system_health 会话不可用, 无法收集死锁信息"

        count = data.get("deadlock_count_recent", 0)
        if count == 0:
            return "死锁: 最近无死锁"

        # 统计频率
        freq = data.get("deadlock_frequency", [])
        total_7days = sum(f["count"] for f in freq)
        return f"死锁: 最近 {count} 个, 近7天共 {total_7days} 个"

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        if not data.get("has_system_health"):
            alerts.append({
                "category": "deadlock",
                "severity": "warning",
                "message": "system_health Extended Event 会话不可用, 无法收集死锁信息",
            })

        for dl in data.get("deadlocks", []):
            alerts.append({
                "category": "deadlock",
                "severity": "warning",
                "message": (
                    f"死锁发生: 受害者 SPID {dl['victim_spid']}, "
                    f"库: {dl['database_name']}, 应用: {dl['victim_app']}"
                ),
            })
        return alerts[:10]  # 最多10条
