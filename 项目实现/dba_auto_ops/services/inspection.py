"""
巡检调度服务 — 统一调度所有采集器，汇总结果并持久化
"""

import json
import logging
from datetime import datetime
from typing import Optional

from core.mssql import connector
from core.db import db, InspectionResult, Alert, InstanceStatus

logger = logging.getLogger(__name__)


class InspectionService:
    """巡检调度服务"""

    def __init__(self):
        self._collectors = {}  # category -> collector instance

    def register(self, collector):
        """注册采集器"""
        self._collectors[collector.category] = collector
        logger.info(f"注册采集器: {collector.category}")

    def get_registered_categories(self) -> list:
        return list(self._collectors.keys())

    def run_single(self, instance_name: str, category: str) -> dict:
        """执行单个实例的单项巡检"""
        if category not in self._collectors:
            return {"error": f"未知的巡检类型: {category}"}

        collector = self._collectors[category]
        result = collector.run(instance_name)
        self._save_result(result)
        return result

    def run_instance(self, instance_name: str,
                     categories: list = None) -> list[dict]:
        """对某个实例执行全部巡检 (可指定分类)"""
        cats = categories or list(self._collectors.keys())
        results = []
        for cat in cats:
            result = self.run_single(instance_name, cat)
            results.append(result)

        # 更新实例巡检时间
        self._update_instance_status(instance_name, results)
        return results

    def run_all(self, categories: list = None) -> dict:
        """对所有已配置实例执行全部巡检"""
        all_results = {}
        instances = connector.list_instances()

        for inst in instances:
            logger.info(f"开始巡检: {inst.name}")
            results = self.run_instance(inst.name, categories)
            all_results[inst.name] = results

        return {
            "total_instances": len(instances),
            "check_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "results": all_results,
        }

    def _save_result(self, result: dict):
        """将巡检结果持久化到 SQLite"""
        try:
            inspection = InspectionResult(
                instance_name=result["instance_name"],
                category=result["category"],
                check_time=datetime.strptime(
                    result["check_time"], "%Y-%m-%d %H:%M:%S"
                ),
                status=result["status"],
                data=json.dumps(result["data"], ensure_ascii=False, default=str),
                summary=result.get("summary", ""),
            )
            db.session.add(inspection)

            # 保存告警
            for alert_data in result.get("alerts", []):
                alert = Alert(
                    instance_name=result["instance_name"],
                    category=alert_data.get("category", result["category"]),
                    severity=alert_data.get("severity", "warning"),
                    message=alert_data.get("message", ""),
                )
                db.session.add(alert)

            db.session.commit()
        except Exception as e:
            db.session.rollback()
            logger.error(f"保存巡检结果失败: {e}")

    def _update_instance_status(self, instance_name: str, results: list):
        """更新实例状态"""
        try:
            status = InstanceStatus.query.filter_by(
                instance_name=instance_name
            ).first()
            if not status:
                status = InstanceStatus(instance_name=instance_name)
                db.session.add(status)

            status.last_inspection_time = datetime.now()
            status.is_connected = not all(
                r.get("status") == "error" and r.get("error")
                for r in results
            )
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            logger.error(f"更新实例状态失败: {e}")

    def get_latest_results(self, instance_name: str = None,
                           category: str = None) -> list[dict]:
        """获取最新巡检结果"""
        # 获取每个实例每个 category 的最新记录
        from sqlalchemy import func, and_

        subq = db.session.query(
            InspectionResult.instance_name,
            InspectionResult.category,
            func.max(InspectionResult.check_time).label("max_time"),
        )
        if instance_name:
            subq = subq.filter(InspectionResult.instance_name == instance_name)
        if category:
            subq = subq.filter(InspectionResult.category == category)
        subq = subq.group_by(
            InspectionResult.instance_name,
            InspectionResult.category,
        ).subquery()

        query = InspectionResult.query.join(
            subq,
            and_(
                InspectionResult.instance_name == subq.c.instance_name,
                InspectionResult.category == subq.c.category,
                InspectionResult.check_time == subq.c.max_time,
            )
        )
        return [r.to_dict() for r in query.all()]

    def get_history(self, instance_name: str, category: str,
                    limit: int = 100) -> list[dict]:
        """获取某个实例某类巡检的历史记录"""
        results = InspectionResult.query.filter_by(
            instance_name=instance_name,
            category=category,
        ).order_by(
            InspectionResult.check_time.desc()
        ).limit(limit).all()
        return [r.to_dict() for r in results]

    def get_alerts(self, instance_name: str = None,
                   resolved: bool = False, limit: int = 50) -> list[dict]:
        """获取告警列表"""
        query = Alert.query.filter_by(is_resolved=resolved)
        if instance_name:
            query = query.filter_by(instance_name=instance_name)
        query = query.order_by(Alert.created_at.desc()).limit(limit)
        return [a.to_dict() for a in query.all()]

    def resolve_alert(self, alert_id: int):
        """标记告警为已处理"""
        alert = Alert.query.get(alert_id)
        if alert:
            alert.is_resolved = True
            alert.resolved_at = datetime.now()
            db.session.commit()
