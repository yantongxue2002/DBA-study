"""
SQL Agent 作业状态采集器
"""

from collectors.base import BaseCollector
from config import THRESHOLDS


class JobsCollector(BaseCollector):
    category = "jobs"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "job_status.sql", timeout=60)
        jobs = []
        failed_count = 0
        running_count = 0
        disabled_count = 0
        duration_anomaly_count = 0

        for row in rows:
            job = {
                "job_name": row.get("job_name", ""),
                "enabled": bool(row.get("enabled")),
                "description": row.get("description", ""),
                "run_status": row.get("run_status"),
                "run_status_desc": row.get("run_status_desc", ""),
                "last_run_time": str(row.get("last_run_time", "")),
                "run_duration_seconds": self._safe_int(row.get("run_duration_seconds")),
                "run_duration_formatted": row.get("run_duration_formatted", ""),
                "avg_duration_seconds": self._safe_int(row.get("avg_duration_seconds")),
                "duration_deviation_pct": self._safe_float(row.get("duration_deviation_pct")),
                "message_short": row.get("message_short", ""),
            }

            if job["run_status"] == 0:
                failed_count += 1
            elif job["run_status"] == 4:
                running_count += 1

            if not job["enabled"]:
                disabled_count += 1

            if job["duration_deviation_pct"] and job["duration_deviation_pct"] > 50:
                duration_anomaly_count += 1

            jobs.append(job)

        return {
            "jobs": jobs,
            "total_count": len(jobs),
            "failed_count": failed_count,
            "running_count": running_count,
            "disabled_count": disabled_count,
            "duration_anomaly_count": duration_anomaly_count,
        }

    def evaluate(self, data: dict) -> str:
        if data.get("failed_count", 0) > 0:
            return "error"
        if data.get("duration_anomaly_count", 0) > 0:
            return "warning"
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        parts = [f"共{data['total_count']}个作业"]
        if data["failed_count"] > 0:
            parts.append(f"失败{data['failed_count']}个")
        if data["running_count"] > 0:
            parts.append(f"运行中{data['running_count']}个")
        if data["disabled_count"] > 0:
            parts.append(f"禁用{data['disabled_count']}个")
        if data["duration_anomaly_count"] > 0:
            parts.append(f"时长异常{data['duration_anomaly_count']}个")
        return "作业: " + ", ".join(parts)

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        for job in data.get("jobs", []):
            if job["run_status"] == 0:
                alerts.append({
                    "category": "jobs",
                    "severity": "critical",
                    "message": f"作业 [{job['job_name']}] 上次运行失败: {job.get('message_short', '')}",
                })
            elif job["duration_deviation_pct"] and job["duration_deviation_pct"] > 50:
                alerts.append({
                    "category": "jobs",
                    "severity": "warning",
                    "message": (
                        f"作业 [{job['job_name']}] 运行时长异常增长 {job['duration_deviation_pct']:.0f}% "
                        f"(上次: {job['run_duration_formatted']}, 均值: {job['avg_duration_seconds']}s)"
                    ),
                })
        return alerts
