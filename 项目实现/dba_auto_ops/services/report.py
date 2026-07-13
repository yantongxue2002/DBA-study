"""
巡检报告生成服务
"""

import json
from datetime import datetime, timedelta
from typing import Optional

from core.db import db, InspectionResult, Alert, InstanceStatus
from core.mssql import connector


class ReportService:
    """报告生成服务"""

    def build_dashboard_data(self) -> dict:
        """构建仪表盘首页数据"""
        instances = connector.list_instances()
        now = datetime.now()

        # 每个实例的最新巡检状态汇总
        instance_summaries = []

        for inst in instances:
            status = InstanceStatus.query.filter_by(
                instance_name=inst.name
            ).first()

            # 获取该实例最新的各分类巡检结果
            from sqlalchemy import func, and_

            subq = db.session.query(
                InspectionResult.category,
                func.max(InspectionResult.check_time).label("max_time"),
            ).filter(
                InspectionResult.instance_name == inst.name
            ).group_by(InspectionResult.category).subquery()

            latest_results = InspectionResult.query.join(
                subq,
                and_(
                    InspectionResult.instance_name == inst.name,
                    InspectionResult.category == subq.c.category,
                    InspectionResult.check_time == subq.c.max_time,
                )
            ).all()

            # 统计告警数
            warning_count = sum(
                1 for r in latest_results if r.status == "warning"
            )
            error_count = sum(
                1 for r in latest_results if r.status == "error"
            )

            # 红绿灯判定
            if error_count > 0:
                light = "red"
            elif warning_count > 0:
                light = "yellow"
            else:
                light = "green"

            instance_summaries.append({
                "name": inst.name,
                "description": inst.description,
                "is_connected": status.is_connected if status else False,
                "last_inspection": status.last_inspection_time.strftime(
                    "%Y-%m-%d %H:%M:%S"
                ) if status and status.last_inspection_time else None,
                "light": light,
                "warning_count": warning_count,
                "error_count": error_count,
                "latest_results": [
                    {
                        "category": r.category,
                        "status": r.status,
                        "check_time": r.check_time.strftime("%Y-%m-%d %H:%M:%S"),
                        "summary": r.summary,
                    }
                    for r in latest_results
                ],
            })

        # 活跃告警统计
        active_alerts = Alert.query.filter_by(is_resolved=False).order_by(
            Alert.created_at.desc()
        ).limit(50).all()

        alert_summary = {
            "total": len(active_alerts),
            "critical": sum(1 for a in active_alerts if a.severity == "critical"),
            "warning": sum(1 for a in active_alerts if a.severity == "warning"),
            "items": [a.to_dict() for a in active_alerts[:10]],
        }

        # 整体概览
        total_instances = len(instance_summaries)
        connected_count = sum(1 for s in instance_summaries if s["is_connected"])
        red_count = sum(1 for s in instance_summaries if s["light"] == "red")
        yellow_count = sum(1 for s in instance_summaries if s["light"] == "yellow")
        green_count = sum(1 for s in instance_summaries if s["light"] == "green")

        return {
            "generated_at": now.strftime("%Y-%m-%d %H:%M:%S"),
            "overview": {
                "total_instances": total_instances,
                "connected": connected_count,
                "disconnected": total_instances - connected_count,
                "green": green_count,
                "yellow": yellow_count,
                "red": red_count,
            },
            "alert_summary": alert_summary,
            "instances": instance_summaries,
        }

    def build_instance_detail(self, instance_name: str) -> dict:
        """构建单个实例的详情数据"""
        inst = connector.get_instance(instance_name)
        if not inst:
            return {"error": f"实例 '{instance_name}' 未配置"}

        status = InstanceStatus.query.filter_by(
            instance_name=instance_name
        ).first()

        # 每种巡检的最新结果 + 最近24小时趋势
        categories = [
            "disk", "memory", "jobs", "backups", "db_integrity",
            "blocking", "slow_query", "index_frag", "error_log",
            "wait_stats", "deadlock",
        ]

        inspection_data = {}
        for cat in categories:
            latest = InspectionResult.query.filter_by(
                instance_name=instance_name,
                category=cat,
            ).order_by(
                InspectionResult.check_time.desc()
            ).first()

            # 获取趋势数据 (用于图表)
            history = InspectionResult.query.filter_by(
                instance_name=instance_name,
                category=cat,
            ).filter(
                InspectionResult.check_time >= datetime.now() - timedelta(days=7)
            ).order_by(
                InspectionResult.check_time.asc()
            ).all()

            inspection_data[cat] = {
                "latest": latest.to_dict() if latest else None,
                "trend": [
                    {
                        "time": h.check_time.strftime("%m-%d %H:%M"),
                        "status": h.status,
                    }
                    for h in history
                ],
            }

        # 该实例的活跃告警
        alerts = Alert.query.filter_by(
            instance_name=instance_name,
            is_resolved=False,
        ).order_by(Alert.created_at.desc()).limit(20).all()

        return {
            "instance": inst.to_dict(),
            "is_connected": status.is_connected if status else False,
            "last_inspection": status.last_inspection_time.strftime(
                "%Y-%m-%d %H:%M:%S"
            ) if status and status.last_inspection_time else None,
            "inspection_data": inspection_data,
            "alerts": [a.to_dict() for a in alerts],
        }

    def generate_html_report(self, inspection_result: dict) -> str:
        """生成 HTML 巡检报告"""
        # 这将在 Flask 视图层用 Jinja2 渲染, 这里只做数据准备
        return json.dumps(inspection_result, ensure_ascii=False, default=str)
