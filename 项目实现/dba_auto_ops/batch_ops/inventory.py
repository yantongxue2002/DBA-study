"""
数据库资产发现与缓存模块

自动扫描所有配置的SQL Server实例，发现并缓存数据库列表。
避免每次批量操作都连接实例查询元数据。
"""

import logging
from datetime import datetime
from typing import List, Optional

from core.mssql import connector
from core.db import db, DbInventory

logger = logging.getLogger(__name__)


class InventoryManager:
    """数据库资产清单管理器"""

    # 发现数据库列表的SQL
    DISCOVER_SQL = """
    SELECT
        d.name AS db_name,
        d.state_desc AS db_state,
        d.recovery_model_desc AS recovery_model,
        d.create_date AS created_at,
        CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS db_size_mb
    FROM sys.databases d
    LEFT JOIN sys.master_files mf ON d.database_id = mf.database_id
    WHERE d.name NOT IN ('master', 'tempdb', 'model', 'msdb')
      AND d.state = 0  -- ONLINE only
    GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.create_date
    ORDER BY d.name
    """

    def __init__(self):
        connector.load()

    def discover_instance(self, instance_name: str) -> List[dict]:
        """
        发现指定实例上的所有用户数据库

        Args:
            instance_name: 实例名称

        Returns:
            数据库列表，每个数据库包含名称、状态、恢复模式、大小等
        """
        try:
            databases = connector.execute_query(instance_name, self.DISCOVER_SQL)
            logger.info(f"实例 '{instance_name}' 发现 {len(databases)} 个数据库")
            return databases
        except Exception as e:
            logger.error(f"发现实例 '{instance_name}' 数据库失败: {e}")
            return []

    def discover_all(self) -> dict:
        """
        发现所有实例的数据库列表

        Returns:
            {instance_name: [数据库列表], ...}
        """
        results = {}
        for inst in connector.list_instances():
            dbs = self.discover_instance(inst.name)
            results[inst.name] = dbs
        return results

    def sync_to_db(self, clear_old: bool = True) -> dict:
        """
        将发现结果同步到SQLite缓存

        Args:
            clear_old: 是否清除旧的缓存数据

        Returns:
            同步统计: {"total_instances": N, "total_databases": N, "failed_instances": [...]}
        """
        import time
        start_time = time.time()

        if clear_old:
            # 软删除：标记为未启用，稍后再清理
            DbInventory.query.update({"is_enabled": False})
            db.session.commit()

        stats = {
            "total_instances": 0,
            "total_databases": 0,
            "failed_instances": [],
        }

        for inst in connector.list_instances():
            stats["total_instances"] += 1
            databases = self.discover_instance(inst.name)

            if not databases:
                stats["failed_instances"].append(inst.name)
                continue

            for db_info in databases:
                # 检查是否已存在
                inv = DbInventory.query.filter_by(
                    instance_name=inst.name,
                    db_name=db_info["db_name"],
                ).first()

                if inv:
                    # 更新现有记录
                    inv.db_state = db_info.get("db_state", "ONLINE")
                    inv.db_size_mb = db_info.get("db_size_mb")
                    inv.recovery_model = db_info.get("recovery_model")
                    inv.last_discovered = datetime.now()
                    inv.is_enabled = True
                else:
                    # 创建新记录
                    inv = DbInventory(
                        instance_name=inst.name,
                        db_name=db_info["db_name"],
                        db_state=db_info.get("db_state", "ONLINE"),
                        db_size_mb=db_info.get("db_size_mb"),
                        recovery_model=db_info.get("recovery_model"),
                        created_at=db_info.get("created_at"),
                        last_discovered=datetime.now(),
                        is_enabled=True,
                    )
                    db.session.add(inv)

                stats["total_databases"] += 1

            db.session.commit()

        elapsed = round(time.time() - start_time, 2)
        logger.info(f"资产同步完成: {stats['total_instances']} 个实例, "
                   f"{stats['total_databases']} 个数据库, 耗时 {elapsed}s")
        return stats

    def get_inventory(
        self,
        instance_name: Optional[str] = None,
        db_name: Optional[str] = None,
        pattern: Optional[str] = None,
        enabled_only: bool = True,
    ) -> List[DbInventory]:
        """
        查询资产清单

        Args:
            instance_name: 按实例名过滤
            db_name: 按数据库名过滤
            pattern: 数据库名模糊匹配 (SQL LIKE语法)
            enabled_only: 只返回启用的数据库

        Returns:
            DbInventory 对象列表
        """
        query = DbInventory.query

        if enabled_only:
            query = query.filter_by(is_enabled=True)

        if instance_name:
            query = query.filter_by(instance_name=instance_name)

        if db_name:
            query = query.filter_by(db_name=db_name)

        if pattern:
            query = query.filter(DbInventory.db_name.like(pattern))

        return query.order_by(DbInventory.instance_name, DbInventory.db_name).all()

    def get_instances_summary(self) -> List[dict]:
        """获取实例汇总信息"""
        from sqlalchemy import func

        results = db.session.query(
            DbInventory.instance_name,
            func.count(DbInventory.id).label("db_count"),
            func.sum(DbInventory.db_size_mb).label("total_size_mb"),
        ).filter_by(is_enabled=True).group_by(
            DbInventory.instance_name
        ).order_by(DbInventory.instance_name).all()

        return [
            {
                "instance_name": r.instance_name,
                "db_count": r.db_count,
                "total_size_mb": round(r.total_size_mb or 0, 2),
            }
            for r in results
        ]

    def get_statistics(self) -> dict:
        """获取资产统计信息"""
        from sqlalchemy import func

        total_dbs = DbInventory.query.filter_by(is_enabled=True).count()
        total_instances = db.session.query(
            func.count(db.distinct(DbInventory.instance_name))
        ).filter_by(is_enabled=True).scalar()

        total_size = db.session.query(
            func.sum(DbInventory.db_size_mb)
        ).filter_by(is_enabled=True).scalar()

        return {
            "total_instances": total_instances or 0,
            "total_databases": total_dbs,
            "total_size_mb": round(total_size or 0, 2),
            "last_synced": db.session.query(
                func.max(DbInventory.last_discovered)
            ).scalar(),
        }


# 全局单例
inventory_manager = InventoryManager()
