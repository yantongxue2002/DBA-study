"""
阻塞链采集器
"""

from collectors.base import BaseCollector
from config import THRESHOLDS


class BlockingCollector(BaseCollector):
    category = "blocking"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "blocking_chain.sql", timeout=30)

        blocking_chain = []
        long_transactions = []
        max_wait_seconds = 0
        total_blocked_sessions = 0

        for row in rows:
            # 阻塞链数据
            if "blocking_spid" in row:
                chain = {
                    "blocking_spid": self._safe_int(row.get("blocking_spid")),
                    "blocked_spid": self._safe_int(row.get("blocked_spid")),
                    "wait_seconds": self._safe_int(row.get("wait_seconds")),
                    "wait_type": row.get("wait_type", ""),
                    "database_name": row.get("database_name", ""),
                    "blocked_query": row.get("blocked_query", ""),
                    "blocking_query": row.get("blocking_query", ""),
                    "blocked_login": row.get("blocked_login", ""),
                    "blocked_host": row.get("blocked_host", ""),
                    "blocked_program": row.get("blocked_program", ""),
                    "blocked_duration_seconds": self._safe_int(row.get("blocked_duration_seconds")),
                    "blocking_login": row.get("blocking_login", ""),
                    "blocking_host": row.get("blocking_host", ""),
                    "blocking_program": row.get("blocking_program", ""),
                    "blocking_duration_seconds": self._safe_int(row.get("blocking_duration_seconds")),
                    "blocking_tran_count": self._safe_int(row.get("blocking_tran_count")),
                }
                blocking_chain.append(chain)
                if chain["wait_seconds"] > max_wait_seconds:
                    max_wait_seconds = chain["wait_seconds"]
                total_blocked_sessions += 1

            # 长时间运行事务
            elif "transaction_id" in row:
                long_tran = {
                    "session_id": self._safe_int(row.get("session_id")),
                    "transaction_duration_seconds": self._safe_int(row.get("transaction_duration_seconds")),
                    "database_name": row.get("database_name", ""),
                    "login_name": row.get("login_name", ""),
                    "host_name": row.get("host_name", ""),
                    "program_name": row.get("program_name", ""),
                    "transaction_type": row.get("transaction_type", ""),
                }
                long_transactions.append(long_tran)

        return {
            "blocking_chain": blocking_chain,
            "blocked_session_count": total_blocked_sessions,
            "max_wait_seconds": max_wait_seconds,
            "long_transactions": long_transactions,
            "long_tran_count": len(long_transactions),
        }

    def evaluate(self, data: dict) -> str:
        if data.get("max_wait_seconds", 0) > THRESHOLDS["blocking_seconds_warning"]:
            return "warning"
        if data.get("blocked_session_count", 0) > 5:
            return "warning"
        if data.get("long_tran_count", 0) > 0:
            return "warning"
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        parts = []
        if data["blocked_session_count"] > 0:
            parts.append(
                f"阻塞: {data['blocked_session_count']}个会话被阻塞, "
                f"最长等待 {data['max_wait_seconds']}s"
            )
        else:
            parts.append("无阻塞")
        if data["long_tran_count"] > 0:
            parts.append(f"长事务: {data['long_tran_count']}个")
        return " | ".join(parts) if parts else "无阻塞, 无长事务"

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        for chain in data.get("blocking_chain", []):
            if chain["wait_seconds"] > THRESHOLDS["blocking_seconds_warning"]:
                alerts.append({
                    "category": "blocking",
                    "severity": "warning",
                    "message": (
                        f"SPID {chain['blocked_spid']} 被 SPID {chain['blocking_spid']} 阻塞 "
                        f"已 {chain['wait_seconds']}s, 库: {chain['database_name']}"
                    ),
                })
        for tran in data.get("long_transactions", []):
            alerts.append({
                "category": "blocking",
                "severity": "warning",
                "message": (
                    f"SPID {tran['session_id']} 事务运行 {tran['transaction_duration_seconds']}s, "
                    f"库: {tran['database_name']}, 用户: {tran['login_name']}"
                ),
            })
        return alerts
