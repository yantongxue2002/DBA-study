"""
定时任务调度 — 基于 APScheduler
"""

import logging
from datetime import datetime

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger

logger = logging.getLogger(__name__)

# 全局调度器实例
scheduler = BackgroundScheduler(
    timezone="Asia/Shanghai",
    job_defaults={
        "coalesce": True,       # 合并错过的任务
        "max_instances": 1,     # 同一任务最多同时运行1个
        "misfire_grace_time": 300,  # 5分钟容错
    },
)


def init_scheduler(inspection_service):
    """初始化所有定时任务"""
    global scheduler

    # ---- 资源巡检 ----
    # 磁盘巡检: 每30分钟
    scheduler.add_job(
        func=lambda: inspection_service.run_all(
            categories=["disk", "memory"]
        ),
        trigger=IntervalTrigger(minutes=30),
        id="resource_check",
        name="磁盘/内存巡检",
        replace_existing=True,
    )

    # ---- 常规巡检 ----
    # 作业+备份: 每4小时
    scheduler.add_job(
        func=lambda: inspection_service.run_all(
            categories=["jobs", "backups", "db_integrity"]
        ),
        trigger=IntervalTrigger(hours=4),
        id="routine_check",
        name="作业/备份/完整性巡检",
        replace_existing=True,
    )

    # ---- 阻塞检查 ----
    # 每5分钟
    scheduler.add_job(
        func=lambda: inspection_service.run_all(categories=["blocking"]),
        trigger=IntervalTrigger(minutes=5),
        id="blocking_check",
        name="阻塞检查",
        replace_existing=True,
    )

    # ---- 性能快照 ----
    # 慢查询 + Wait Stats: 每小时
    scheduler.add_job(
        func=lambda: inspection_service.run_all(
            categories=["slow_query", "wait_stats"]
        ),
        trigger=IntervalTrigger(hours=1),
        id="performance_snapshot",
        name="性能快照",
        replace_existing=True,
    )

    # ---- 索引碎片 ----
    # 每天凌晨 2:00
    scheduler.add_job(
        func=lambda: inspection_service.run_all(
            categories=["index_frag"]
        ),
        trigger=CronTrigger(hour=2, minute=0),
        id="index_frag_check",
        name="索引碎片检查",
        replace_existing=True,
    )

    # ---- 错误日志扫描 ----
    # 每天 8:00
    scheduler.add_job(
        func=lambda: inspection_service.run_all(
            categories=["error_log"]
        ),
        trigger=CronTrigger(hour=8, minute=0),
        id="error_log_scan",
        name="错误日志扫描",
        replace_existing=True,
    )

    # ---- 死锁检测 ----
    # 每小时
    scheduler.add_job(
        func=lambda: inspection_service.run_all(
            categories=["deadlock"]
        ),
        trigger=IntervalTrigger(hours=1),
        id="deadlock_check",
        name="死锁检测",
        replace_existing=True,
    )

    logger.info("所有定时任务已注册")


def start_scheduler():
    """启动调度器"""
    if not scheduler.running:
        scheduler.start()
        logger.info("定时任务调度器已启动")


def stop_scheduler():
    """停止调度器"""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("定时任务调度器已停止")


def get_jobs() -> list[dict]:
    """获取所有已注册的定时任务"""
    jobs = []
    for job in scheduler.get_jobs():
        jobs.append({
            "id": job.id,
            "name": job.name,
            "next_run_time": job.next_run_time.strftime("%Y-%m-%d %H:%M:%S")
            if job.next_run_time else None,
            "trigger": str(job.trigger),
        })
    return jobs
