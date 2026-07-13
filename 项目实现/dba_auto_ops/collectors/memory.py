"""
内存使用采集器
"""

from collectors.base import BaseCollector
from config import THRESHOLDS


class MemoryCollector(BaseCollector):
    category = "memory"

    def collect(self, instance_name: str) -> dict:
        all_sets = self.execute_sql_file_all(instance_name, "memory_usage.sql", timeout=60)

        # 结果集1: sys.dm_os_sys_memory (1行)
        # 结果集2: sys.dm_os_performance_counters (多行)
        # 结果集3: sys.dm_exec_cached_plans (多行)
        sys_memory_rows = all_sets[0] if len(all_sets) > 0 else []
        perf_counter_rows = all_sets[1] if len(all_sets) > 1 else []
        plan_cache_rows = all_sets[2] if len(all_sets) > 2 else []

        # 解析 sys.dm_os_sys_memory 数据
        sys_memory = {}
        perf_counters = {}
        plan_cache = []

        if sys_memory_rows:
            row = sys_memory_rows[0]
            sys_memory = {
                "total_physical_memory_mb": self._safe_float(row.get("total_physical_memory_mb")),
                "available_physical_memory_mb": self._safe_float(row.get("available_physical_memory_mb")),
                "os_memory_used_pct": self._safe_float(row.get("os_memory_used_pct")),
                "system_memory_state_desc": row.get("system_memory_state_desc", ""),
                "sqlserver_memory_usage_mb": self._safe_float(row.get("sqlserver_memory_usage_mb")),
                "max_physical_memory_limit_mb": self._safe_float(row.get("max_physical_memory_limit_mb")),
                "locked_page_allocations_kb": self._safe_int(row.get("locked_page_allocations_kb")),
            }

        for row in perf_counter_rows:
            if "counter_name" in row and "cntr_value" in row:
                # 去除尾随空格 (SQL Server 2019 DMV 返回的列名有大量空格)
                key = row["counter_name"].strip()
                perf_counters[key] = self._safe_int(row.get("cntr_value"))

        for row in plan_cache_rows:
            plan_cache.append({
                "type": row.get("cacheobjtype", ""),
                "cached_plans_count": self._safe_int(row.get("cached_plans_count")),
                "total_size_mb": self._safe_float(row.get("total_size_mb")),
                "avg_size_kb": self._safe_float(row.get("avg_size_kb")),
            })

        # 提取关键指标
        buffer_cache_hit = perf_counters.get("Buffer cache hit ratio", 0)
        ple = perf_counters.get("Page life expectancy", 0)
        memory_grants_pending = perf_counters.get("Memory Grants Pending", 0)
        free_pages = perf_counters.get("Free pages", 0)
        total_pages = perf_counters.get("Total pages", 0)
        database_pages = perf_counters.get("Database pages", 0)

        return {
            "sys_memory": sys_memory,
            "buffer_cache_hit_ratio": buffer_cache_hit,
            "page_life_expectancy_seconds": ple,
            "memory_grants_pending": memory_grants_pending,
            "free_pages": free_pages,
            "total_pages": total_pages,
            "database_pages": database_pages,
            "buffer_pool_used_pct": self._safe_float(
                (database_pages * 100.0 / total_pages) if total_pages > 0 else 0
            ),
            "plan_cache": plan_cache,
        }

    def evaluate(self, data: dict) -> str:
        ple = data.get("page_life_expectancy_seconds", 999)
        buffer_hit = data.get("buffer_cache_hit_ratio", 100)
        grants_pending = data.get("memory_grants_pending", 0)

        if ple < THRESHOLDS["memory_ple_warning"]:
            return "warning"
        if grants_pending > 0:
            return "warning"
        if buffer_hit < THRESHOLDS["memory_buffer_cache_hit_warning"]:
            return "warning"
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        ple = data.get("page_life_expectancy_seconds", 0)
        buffer_hit = data.get("buffer_cache_hit_ratio", 0)
        grants = data.get("memory_grants_pending", 0)
        sys_mem = data.get("sys_memory", {})

        parts = [
            f"PLE={ple}s",
            f"BufferHit={buffer_hit}%",
        ]
        if grants > 0:
            parts.append(f"MemoryGrantsPending={grants} ⚠")
        if sys_mem:
            parts.append(
                f"SQL内存={sys_mem.get('sqlserver_memory_usage_mb', 0):.0f}MB"
            )

        return "内存: " + ", ".join(parts)

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        ple = data.get("page_life_expectancy_seconds", 999)
        grants = data.get("memory_grants_pending", 0)
        buffer_hit = data.get("buffer_cache_hit_ratio", 100)

        if ple < THRESHOLDS["memory_ple_warning"]:
            alerts.append({
                "category": "memory",
                "severity": "warning",
                "message": f"Page Life Expectancy 仅 {ple}s (阈值: {THRESHOLDS['memory_ple_warning']}s), 可能存在内存压力",
            })
        if grants > 0:
            alerts.append({
                "category": "memory",
                "severity": "warning",
                "message": f"Memory Grants Pending = {grants}, 有查询在等待内存授予",
            })
        if buffer_hit < THRESHOLDS["memory_buffer_cache_hit_warning"]:
            alerts.append({
                "category": "memory",
                "severity": "warning",
                "message": f"Buffer Cache Hit Ratio = {buffer_hit}% (阈值: {THRESHOLDS['memory_buffer_cache_hit_warning']}%)",
            })
        return alerts
