"""
慢查询 / 高消耗查询采集器
"""

from collectors.base import BaseCollector


class SlowQueryCollector(BaseCollector):
    category = "slow_query"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "top_cpu_queries.sql", timeout=60)

        top_queries_cpu = []
        top_queries_io = []
        top_queries_duration = []

        for row in rows:
            q = {
                "database_name": row.get("database_name", ""),
                "object_name": row.get("object_name", ""),
                "execution_count": self._safe_int(row.get("execution_count")),
                "total_cpu_ms": self._safe_int(row.get("total_cpu_ms")),
                "avg_cpu_ms": self._safe_float(row.get("avg_cpu_ms")),
                "total_logical_reads": self._safe_int(row.get("total_logical_reads")),
                "avg_logical_reads": self._safe_int(row.get("avg_logical_reads")),
                "total_physical_reads": self._safe_int(row.get("total_physical_reads")),
                "total_duration_ms": self._safe_int(row.get("total_duration_ms")),
                "avg_duration_ms": self._safe_float(row.get("avg_duration_ms")),
                "total_rows": self._safe_int(row.get("total_rows")),
                "total_grant_kb": self._safe_int(row.get("total_grant_kb")),
                "total_spills": self._safe_int(row.get("total_spills")),
                "cpu_rank": self._safe_int(row.get("cpu_rank")),
                "io_rank": self._safe_int(row.get("io_rank")),
                "duration_rank": self._safe_int(row.get("duration_rank")),
                "query_text": row.get("query_text", ""),
                "last_execution_time": str(row.get("last_execution_time", "")),
            }

            if q["cpu_rank"] and q["cpu_rank"] <= 10:
                top_queries_cpu.append(q)
            if q["io_rank"] and q["io_rank"] <= 10:
                top_queries_io.append(q)
            if q["duration_rank"] and q["duration_rank"] <= 10:
                top_queries_duration.append(q)

        return {
            "top_queries_cpu": top_queries_cpu,
            "top_queries_io": top_queries_io,
            "top_queries_duration": top_queries_duration,
            "total_unique_queries": len(rows),
        }

    def evaluate(self, data: dict) -> str:
        # 慢查询采集器不主动告警，仅记录数据
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        cpu_count = len(data.get("top_queries_cpu", []))
        io_count = len(data.get("top_queries_io", []))
        dur_count = len(data.get("top_queries_duration", []))
        return (
            f"慢查询快照: Top CPU {cpu_count}条, "
            f"Top IO {io_count}条, Top Duration {dur_count}条 "
            f"(共{data['total_unique_queries']}条缓存查询)"
        )
