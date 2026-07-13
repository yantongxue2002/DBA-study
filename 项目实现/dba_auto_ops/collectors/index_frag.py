"""
索引碎片采集器
"""

from collectors.base import BaseCollector
from config import THRESHOLDS


class IndexFragCollector(BaseCollector):
    category = "index_frag"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "index_frag.sql", timeout=120)

        fragmented_indexes = []
        missing_indexes = []
        rebuild_count = 0
        reorganize_count = 0

        for row in rows:
            # 碎片索引
            if "avg_fragmentation_in_percent" in row:
                idx = {
                    "database_name": row.get("database_name", ""),
                    "schema_name": row.get("schema_name", ""),
                    "table_name": row.get("table_name", ""),
                    "index_name": row.get("index_name", ""),
                    "index_type": row.get("index_type", ""),
                    "avg_fragmentation_in_percent": self._safe_float(
                        row.get("avg_fragmentation_in_percent")
                    ),
                    "fragment_count": self._safe_int(row.get("fragment_count")),
                    "page_count": self._safe_int(row.get("page_count")),
                    "avg_page_density_pct": self._safe_float(row.get("avg_page_density_pct")),
                    "recommendation": row.get("recommendation", ""),
                    "ddl_script": row.get("ddl_script", ""),
                }

                if idx["recommendation"] == "REBUILD":
                    rebuild_count += 1
                elif idx["recommendation"] == "REORGANIZE":
                    reorganize_count += 1

                fragmented_indexes.append(idx)

            # 缺失索引
            elif "avg_impact_pct" in row:
                missing_indexes.append({
                    "avg_impact_pct": self._safe_float(row.get("avg_impact_pct")),
                    "avg_total_user_cost": self._safe_float(row.get("avg_total_user_cost")),
                    "user_seeks": self._safe_int(row.get("user_seeks")),
                    "user_scans": self._safe_int(row.get("user_scans")),
                    "table_name": row.get("table_name", ""),
                    "equality_columns": row.get("equality_columns", ""),
                    "inequality_columns": row.get("inequality_columns", ""),
                    "included_columns": row.get("included_columns", ""),
                    "create_index_statement": row.get("create_index_statement", ""),
                })

        return {
            "fragmented_indexes": fragmented_indexes,
            "missing_indexes": missing_indexes,
            "fragmented_count": len(fragmented_indexes),
            "rebuild_count": rebuild_count,
            "reorganize_count": reorganize_count,
            "missing_count": len(missing_indexes),
        }

    def evaluate(self, data: dict) -> str:
        if data.get("rebuild_count", 0) > 20:
            return "warning"  # 大量索引需要重建
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        parts = []
        if data["fragmented_count"] > 0:
            parts.append(
                f"碎片索引{data['fragmented_count']}个 "
                f"(REBUILD {data['rebuild_count']}, REORG {data['reorganize_count']})"
            )
        else:
            parts.append("无高碎片索引")
        if data["missing_count"] > 0:
            parts.append(f"缺失索引建议{data['missing_count']}条")
        return "索引: " + ", ".join(parts)

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        if data.get("rebuild_count", 0) > 50:
            alerts.append({
                "category": "index_frag",
                "severity": "warning",
                "message": f"有 {data['rebuild_count']} 个索引碎片率 > 30%, 建议安排重建",
            })
        return alerts
