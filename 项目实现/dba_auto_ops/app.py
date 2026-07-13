"""
DBA 自动运维平台 — Flask 主入口
"""

import json
import logging
import os

from flask import Flask, render_template, request, jsonify, redirect, url_for, flash

from config import (
    SECRET_KEY, DEBUG, SQLALCHEMY_DATABASE_URI,
    SQLITE_PATH, INSTANCES_CONFIG,
)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("dba_ops.log", encoding="utf-8"),
    ],
)
logger = logging.getLogger(__name__)


def create_app():
    app = Flask(__name__)
    app.secret_key = SECRET_KEY
    app.config["SQLALCHEMY_DATABASE_URI"] = SQLALCHEMY_DATABASE_URI
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    return app


app = create_app()

# 初始化数据库
from core.db import db
db.init_app(app)

# 确保 data 目录存在
os.makedirs(os.path.dirname(SQLITE_PATH), exist_ok=True)

with app.app_context():
    db.create_all()
    logger.info("SQLite 数据库已初始化")

# 初始化 SQL Server 连接器
from core.mssql import connector
connector.load(INSTANCES_CONFIG)

# 初始化巡检服务和定时任务
from services.inspection import InspectionService
from services.report import ReportService
# from services.scheduler import init_scheduler, start_scheduler  # 定时任务已禁用

inspection_service = InspectionService()
report_service = ReportService()

# 延迟导入采集器并注册
# (采集器文件将在 Phase 2 创建，这里先用占位导入)
try:
    from collectors.disk import DiskCollector
    from collectors.memory import MemoryCollector
    from collectors.jobs import JobsCollector
    from collectors.backups import BackupsCollector
    from collectors.db_integrity import DbIntegrityCollector
    from collectors.blocking import BlockingCollector
    from collectors.slow_query import SlowQueryCollector
    from collectors.index_frag import IndexFragCollector
    from collectors.error_log import ErrorLogCollector
    from collectors.wait_stats import WaitStatsCollector
    from collectors.deadlock import DeadlockCollector

    inspection_service.register(DiskCollector())
    inspection_service.register(MemoryCollector())
    inspection_service.register(JobsCollector())
    inspection_service.register(BackupsCollector())
    inspection_service.register(DbIntegrityCollector())
    inspection_service.register(BlockingCollector())
    inspection_service.register(SlowQueryCollector())
    inspection_service.register(IndexFragCollector())
    inspection_service.register(ErrorLogCollector())
    inspection_service.register(WaitStatsCollector())
    inspection_service.register(DeadlockCollector())
    logger.info("所有采集器已注册")
except ImportError as e:
    logger.warning(f"部分采集器尚未实现: {e}")

# 初始化定时任务
# init_scheduler(inspection_service)   # 定时任务已禁用
# start_scheduler()                     # 定时任务已禁用


# ==================== 路由 ====================

@app.route("/favicon.ico")
def favicon():
    return "", 204


@app.route("/")
def index():
    """首页仪表盘"""
    return render_template("dashboard.html")


@app.route("/api/dashboard")
def api_dashboard():
    """仪表盘数据 API"""
    try:
        data = report_service.build_dashboard_data()
        return jsonify({"success": True, "data": data})
    except Exception as e:
        logger.error(f"获取仪表盘数据失败: {e}")
        return jsonify({"success": False, "error": str(e)})


@app.route("/inspection")
def inspection():
    """巡检结果页"""
    return render_template("inspection.html")


@app.route("/api/inspection")
def api_inspection():
    """巡检结果 API"""
    instance_name = request.args.get("instance")
    category = request.args.get("category")
    results = inspection_service.get_latest_results(
        instance_name=instance_name, category=category
    )
    return jsonify({"success": True, "data": results})


@app.route("/api/inspection/run", methods=["POST"])
def api_run_inspection():
    """手动触发巡检"""
    data = request.get_json(silent=True) or {}
    instance_name = data.get("instance")
    categories = data.get("categories")

    if instance_name:
        results = inspection_service.run_instance(instance_name, categories)
    else:
        results = inspection_service.run_all(categories)

    return jsonify({"success": True, "data": results})


@app.route("/api/inspection/history")
def api_inspection_history():
    """巡检历史 API"""
    instance_name = request.args.get("instance")
    category = request.args.get("category")
    limit = request.args.get("limit", 100, type=int)

    if not instance_name or not category:
        return jsonify({"success": False, "error": "需要 instance 和 category 参数"})

    history = inspection_service.get_history(instance_name, category, limit)
    return jsonify({"success": True, "data": history})


@app.route("/instance/<instance_name>")
def instance_detail(instance_name):
    """单实例详情页"""
    return render_template("instance_detail.html", instance_name=instance_name)


@app.route("/api/instance/<instance_name>")
def api_instance_detail(instance_name):
    """单实例详情 API"""
    data = report_service.build_instance_detail(instance_name)
    return jsonify({"success": True, "data": data})


@app.route("/performance")
def performance():
    """性能分析页"""
    return render_template("performance.html")


@app.route("/api/alerts")
def api_alerts():
    """告警列表 API"""
    instance_name = request.args.get("instance")
    resolved = request.args.get("resolved", "false").lower() == "true"
    limit = request.args.get("limit", 50, type=int)
    alerts = inspection_service.get_alerts(
        instance_name=instance_name, resolved=resolved, limit=limit
    )
    return jsonify({"success": True, "data": alerts})


@app.route("/api/alerts/<int:alert_id>/resolve", methods=["POST"])
def api_resolve_alert(alert_id):
    """标记告警已处理"""
    inspection_service.resolve_alert(alert_id)
    return jsonify({"success": True})


@app.route("/api/instances")
def api_instances():
    """实例列表 API"""
    instances = [
        inst.to_dict() for inst in connector.list_instances()
    ]
    return jsonify({"success": True, "data": instances})


@app.route("/api/instances/<instance_name>/test")
def api_test_connection(instance_name):
    """测试实例连接"""
    result = connector.test_connection(instance_name)
    return jsonify(result)


@app.route("/api/jobs")
def api_jobs():
    """定时任务列表 API"""
    # 定时任务已禁用
    return jsonify({"success": True, "data": [], "message": "定时任务已禁用"})


@app.route("/report")
def report_view():
    """巡检报告页"""
    data = report_service.build_dashboard_data()
    return render_template("report.html", data=data)


# ==================== 启动 ====================

if __name__ == "__main__":
    logger.info("DBA 自动运维平台启动中...")
    app.run(host="0.0.0.0", port=5000, debug=DEBUG)
