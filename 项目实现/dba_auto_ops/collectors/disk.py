"""
磁盘空间采集器
"""

from collectors.base import BaseCollector
from config import THRESHOLDS


class DiskCollector(BaseCollector):
    category = "disk"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "disk_usage.sql")
        drives = []
        for row in rows:
            drives.append({
                "drive_letter": row.get("drive_letter", ""),
                "volume_name": row.get("volume_name", ""),
                "total_gb": self._safe_float(row.get("total_gb")),
                "available_gb": self._safe_float(row.get("available_gb")),
                "used_gb": self._safe_float(row.get("used_gb")),
                "used_pct": self._safe_float(row.get("used_pct")),
                "available_pct": self._safe_float(row.get("available_pct")),
                "databases": row.get("databases_on_drive", ""),
            })
        return {"drives": drives, "drive_count": len(drives)}

    def evaluate(self, data: dict) -> str:
        """检查是否有磁盘空间不足的情况"""
        drives = data.get("drives", [])
        has_warning = False

        for d in drives:
            available_pct = d.get("available_pct", 100)
            available_gb = d.get("available_gb", 999)
            if available_pct < THRESHOLDS["disk_free_pct_warning"]:
                return "error"
            if available_gb < THRESHOLDS["disk_free_gb_warning"]:
                has_warning = True

        return "warning" if has_warning else "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        drives = data.get("drives", [])
        if not drives:
            return "无磁盘数据"

        warnings = []
        for d in drives:
            if d["available_pct"] < THRESHOLDS["disk_free_pct_warning"]:
                warnings.append(
                    f'{d["drive_letter"]} 可用仅 {d["available_pct"]:.1f}%'
                )
            elif d["available_gb"] < THRESHOLDS["disk_free_gb_warning"]:
                warnings.append(
                    f'{d["drive_letter"]} 可用仅 {d["available_gb"]:.1f}GB'
                )

        if warnings:
            return "磁盘告警: " + "; ".join(warnings)
        return f"所有磁盘正常 (共{len(drives)}个盘符)"

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        for d in data.get("drives", []):
            if d["available_pct"] < THRESHOLDS["disk_free_pct_warning"]:
                alerts.append({
                    "category": "disk",
                    "severity": "critical",
                    "message": (
                        f'{d["drive_letter"]}盘 可用空间仅 {d["available_pct"]:.1f}% '
                        f'({d["available_gb"]:.1f}GB / {d["total_gb"]:.1f}GB)'
                    ),
                })
            elif d["available_gb"] < THRESHOLDS["disk_free_gb_warning"]:
                alerts.append({
                    "category": "disk",
                    "severity": "warning",
                    "message": (
                        f'{d["drive_letter"]}盘 可用空间仅 {d["available_gb"]:.1f}GB '
                        f'(占比 {d["available_pct"]:.1f}%)'
                    ),
                })
        return alerts
