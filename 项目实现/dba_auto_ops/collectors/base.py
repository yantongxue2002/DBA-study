"""
采集器基类 — 定义巡检采集的标准接口和公共逻辑
"""

import json
import logging
import os
from datetime import datetime
from typing import Any

from core.mssql import connector

logger = logging.getLogger(__name__)


class BaseCollector:
    """巡检采集器基类

    每个巡检指标继承此类，实现:
    1. category 属性 — 巡检分类名
    2. collect(instance_name) 方法 — 采集逻辑
    3. evaluate(result) 方法 — 评估是否告警
    """

    # 子类必须覆盖
    category: str = "base"

    # SQL 文件夹路径
    SQL_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "sql")

    def __init__(self):
        self.connector = connector

    def load_sql(self, filename: str) -> str:
        """从 sql/ 目录加载 SQL 脚本"""
        filepath = os.path.join(self.SQL_DIR, filename)
        if not os.path.exists(filepath):
            raise FileNotFoundError(f"SQL 脚本不存在: {filepath}")
        with open(filepath, "r", encoding="utf-8") as f:
            return f.read()

    def execute_sql_file(self, instance_name: str, filename: str,
                         timeout: int = None) -> list[dict]:
        """加载并执行 SQL 脚本文件 (单结果集)"""
        sql = self.load_sql(filename)
        return self.connector.execute_query(instance_name, sql, timeout=timeout)

    def execute_sql_file_all(self, instance_name: str, filename: str,
                             timeout: int = None) -> list[list[dict]]:
        """加载并执行 SQL 脚本文件 (多结果集)"""
        sql = self.load_sql(filename)
        return self.connector.execute_query_all(instance_name, sql, timeout=timeout)

    def collect(self, instance_name: str) -> dict:
        """采集巡检数据 — 子类必须实现"""
        raise NotImplementedError("子类必须实现 collect() 方法")

    def evaluate(self, data: dict) -> str:
        """
        评估巡检结果 — 子类可选覆盖
        返回: "ok" / "warning" / "error"
        """
        return "ok"

    def run(self, instance_name: str) -> dict:
        """
        完整执行一次巡检: 采集 → 评估 → 返回标准化结果
        """
        result = {
            "instance_name": instance_name,
            "category": self.category,
            "check_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "status": "ok",
            "data": {},
            "summary": "",
            "alerts": [],
            "error": None,
        }

        try:
            raw_data = self.collect(instance_name)
            result["data"] = raw_data
            result["status"] = self.evaluate(raw_data)
            result["summary"] = self._generate_summary(raw_data, result["status"])
            result["alerts"] = self._generate_alerts(raw_data, result["status"])
        except Exception as e:
            logger.error(f"[{self.category}] {instance_name} 采集失败: {e}")
            result["status"] = "error"
            result["error"] = str(e)
            result["summary"] = f"采集失败: {e}"

        return result

    def _generate_summary(self, data: dict, status: str) -> str:
        """生成巡检摘要 — 子类可覆盖"""
        return f"{self.category} 巡检完成, 状态: {status}"

    def _generate_alerts(self, data: dict, status: str) -> list[dict]:
        """生成告警列表 — 子类可覆盖"""
        if status in ("warning", "error"):
            return [{
                "category": self.category,
                "severity": "warning" if status == "warning" else "critical",
                "message": self._generate_summary(data, status),
            }]
        return []

    def _safe_float(self, value: Any) -> float:
        """安全转换为 float"""
        try:
            return float(value) if value is not None else 0.0
        except (ValueError, TypeError):
            return 0.0

    def _safe_int(self, value: Any) -> int:
        """安全转换为 int"""
        try:
            return int(value) if value is not None else 0
        except (ValueError, TypeError):
            return 0
