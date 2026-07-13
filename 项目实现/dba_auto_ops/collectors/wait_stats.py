"""
等待统计采集器
"""

from collectors.base import BaseCollector


class WaitStatsCollector(BaseCollector):
    category = "wait_stats"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "top_waits.sql", timeout=30)

        wait_stats = []
        high_signal_waits = []  # 信号等待占比高通常意味着 CPU 压力

        for row in rows:
            ws = {
                "wait_type": row.get("wait_type", ""),
                "wait_time_ms": self._safe_int(row.get("wait_time_ms")),
                "wait_time_minutes": self._safe_float(row.get("wait_time_minutes")),
                "waiting_tasks_count": self._safe_int(row.get("waiting_tasks_count")),
                "signal_wait_time_ms": self._safe_int(row.get("signal_wait_time_ms")),
                "resource_wait_time_ms": self._safe_int(row.get("resource_wait_time_ms")),
                "wait_pct": self._safe_float(row.get("wait_pct")),
                "signal_wait_pct": self._safe_float(row.get("signal_wait_pct")),
                "avg_wait_ms_per_task": self._safe_float(row.get("avg_wait_ms_per_task")),
            }

            wait_stats.append(ws)

            # 信号等待占比 > 30% 通常意味着 CPU 压力
            if ws["signal_wait_pct"] > 30 and ws["wait_time_minutes"] > 10:
                high_signal_waits.append(ws)

        return {
            "wait_stats": wait_stats,
            "total_wait_types": len(wait_stats),
            "high_signal_waits": high_signal_waits,
            "high_signal_count": len(high_signal_waits),
        }

    def evaluate(self, data: dict) -> str:
        if data.get("high_signal_count", 0) > 2:
            return "warning"
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        waits = data.get("wait_stats", [])
        if not waits:
            return "等待统计: 无数据"

        top3 = [w["wait_type"] for w in waits[:3]]
        signal = data.get("high_signal_count", 0)

        parts = [f"Top3: {', '.join(top3)}"]
        if signal > 0:
            parts.append(f"高信号等待 {signal} 个 (可能CPU压力)")

        return "等待统计: " + ", ".join(parts)

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        for ws in data.get("high_signal_waits", []):
            alerts.append({
                "category": "wait_stats",
                "severity": "warning",
                "message": (
                    f"等待类型 [{ws['wait_type']}] 信号等待占比 {ws['signal_wait_pct']:.0f}%, "
                    f"总等待 {ws['wait_time_minutes']:.1f} 分钟, 可能存在 CPU 压力"
                ),
            })
        return alerts
