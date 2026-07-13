"""
错误日志扫描采集器
"""

import re
from collectors.base import BaseCollector


# 关键字匹配规则 (在 Python 端做，避免 xp_readerrorlog INSERT..EXEC 的问题)
KEYWORD_RULES = [
    (re.compile(r'Severity:\s*1[6-9]|Severity:\s*2[0-5]', re.I), 'critical'),
    (re.compile(r'corrupt|stack dump|assertion|suspect|out of memory', re.I), 'critical'),
    (re.compile(r'Error:\s*(?!.*0 errors)', re.I), 'error'),
    (re.compile(r'login failed', re.I), 'warning'),
    (re.compile(r'deadlock', re.I), 'warning'),
    (re.compile(r'timeout', re.I), 'warning'),
    (re.compile(r'I/O is frozen', re.I), 'warning'),
    (re.compile(r'insufficient', re.I), 'warning'),
    (re.compile(r'failed', re.I), 'error'),
    (re.compile(r'Could not|Unable to|Cannot', re.I), 'warning'),
    (re.compile(r'terminated', re.I), 'error'),
    (re.compile(r'IO requests taking longer', re.I), 'warning'),
    (re.compile(r'defunct', re.I), 'error'),
    (re.compile(r'blocked', re.I), 'warning'),
]


class ErrorLogCollector(BaseCollector):
    category = "error_log"

    def collect(self, instance_name: str) -> dict:
        rows = self.execute_sql_file(instance_name, "error_log_scan.sql", timeout=60)

        errors = []
        critical_count = 0
        error_count = 0
        warning_count = 0

        for row in rows:
            log_text = row.get("Text") or row.get("LogText") or ""
            log_date = row.get("LogDate") or row.get("log_time") or ""

            # 匹配关键字
            matched_severity = None
            matched_pattern = None
            for pattern, severity in KEYWORD_RULES:
                if pattern.search(log_text):
                    matched_severity = severity
                    matched_pattern = pattern.pattern
                    break

            if not matched_severity:
                continue

            entry = {
                "log_time": str(log_date),
                "process_info": row.get("ProcessInfo") or "",
                "matched_keyword": matched_pattern or "",
                "severity": matched_severity,
                "message": log_text[:500],
            }

            if matched_severity == "critical":
                critical_count += 1
            elif matched_severity == "error":
                error_count += 1
            elif matched_severity == "warning":
                warning_count += 1

            errors.append(entry)

        return {
            "errors": errors,
            "total_count": len(errors),
            "critical_count": critical_count,
            "error_count": error_count,
            "warning_count": warning_count,
        }

    def evaluate(self, data: dict) -> str:
        if data.get("critical_count", 0) > 0:
            return "error"
        if data.get("error_count", 0) > 5:
            return "warning"
        if data.get("warning_count", 0) > 20:
            return "warning"
        return "ok"

    def _generate_summary(self, data: dict, status: str) -> str:
        parts = [f"最近24h共{data['total_count']}条匹配"]
        if data["critical_count"] > 0:
            parts.append(f"严重 {data['critical_count']} 条")
        if data["error_count"] > 0:
            parts.append(f"错误 {data['error_count']} 条")
        if data["warning_count"] > 0:
            parts.append(f"警告 {data['warning_count']} 条")
        return "错误日志: " + ", ".join(parts)

    def _generate_alerts(self, data: dict, status: str) -> list:
        alerts = []
        for err in data.get("errors", []):
            if err["severity"] in ("critical", "error"):
                alerts.append({
                    "category": "error_log",
                    "severity": "critical" if err["severity"] == "critical" else "warning",
                    "message": (
                        f"[{err['severity']}] {err['message'][:200]} "
                        f"(匹配: {err['matched_keyword']})"
                    ),
                })
        return alerts[:20]