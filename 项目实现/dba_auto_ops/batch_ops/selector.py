"""
目标选择器模块

根据用户指定的条件，筛选出需要执行操作的目标（实例+数据库）。
支持的条件：
- 全部实例/全部数据库
- 指定实例名
- 指定数据库名
- 数据库名模糊匹配
- 排除特定数据库（如系统数据库）
"""

import fnmatch
from dataclasses import dataclass
from typing import List, Optional, Union

from core.mssql import connector
from batch_ops.inventory import inventory_manager


@dataclass
class Target:
    """执行目标"""
    instance_name: str
    db_name: Optional[str] = None  # None 表示实例级操作

    def __repr__(self):
        if self.db_name:
            return f"{self.instance_name}/{self.db_name}"
        return self.instance_name

    def __hash__(self):
        return hash((self.instance_name, self.db_name))

    def __eq__(self, other):
        if isinstance(other, Target):
            return self.instance_name == other.instance_name and self.db_name == other.db_name
        return False


class TargetSelector:
    """
    目标选择器

    用法示例:
        selector = TargetSelector()

        # 选择所有实例的所有数据库
        targets = selector.select(databases="*")

        # 选择指定实例
        targets = selector.select(instances=["成都", "天门"])

        # 选择指定数据库（跨所有实例）
        targets = selector.select(databases=["Production", "ReportDB"])

        # 模糊匹配数据库名
        targets = selector.select(db_pattern="*_prod")

        # 实例级操作（不指定数据库）
        targets = selector.select(instances=["成都"])  # 仅实例级
    """

    # 默认排除的系统数据库
    DEFAULT_EXCLUDED_DBS = {"master", "tempdb", "model", "msdb"}

    def __init__(self):
        # 确保资产缓存已加载
        connector.load()

    def _get_all_instances(self) -> List[str]:
        """获取所有配置的实例名"""
        return [inst.name for inst in connector.list_instances()]

    def _get_instance_databases(self, instance_name: str) -> List[str]:
        """获取指定实例的所有用户数据库"""
        inv_items = inventory_manager.get_inventory(
            instance_name=instance_name,
            enabled_only=True,
        )
        return [item.db_name for item in inv_items]

    def select(
        self,
        instances: Optional[Union[str, List[str]]] = None,
        databases: Optional[Union[str, List[str]]] = None,
        db_pattern: Optional[str] = None,
        exclude_dbs: Optional[List[str]] = None,
        instance_only: bool = False,
    ) -> List[Target]:
        """
        选择目标

        Args:
            instances: 实例名或列表。None表示所有实例，str表示单个实例
            databases: 数据库名或列表。None表示不筛选数据库（返回实例级目标），
                      str "*" 表示所有数据库，list表示指定数据库
            db_pattern: 数据库名模糊匹配 (如 "*_prod", "Report*")
            exclude_dbs: 要排除的数据库名列表
            instance_only: 是否只返回实例级目标（忽略数据库）

        Returns:
            Target 列表
        """
        # 1. 确定实例范围
        if instances is None:
            instance_names = self._get_all_instances()
        elif isinstance(instances, str):
            instance_names = [instances]
        else:
            instance_names = instances

        # 2. 确定排除列表
        excluded = set(exclude_dbs or [])
        excluded.update(self.DEFAULT_EXCLUDED_DBS)

        targets = []

        # 3. 如果只选择实例级目标
        if instance_only or (databases is None and db_pattern is None):
            for inst in instance_names:
                targets.append(Target(instance_name=inst))
            return targets

        # 4. 确定数据库范围
        for inst_name in instance_names:
            inst_dbs = self._get_instance_databases(inst_name)

            if databases == "*":
                # 所有数据库
                matched_dbs = inst_dbs
            elif isinstance(databases, str):
                # 单个数据库名
                matched_dbs = [databases] if databases in inst_dbs else []
            elif isinstance(databases, list):
                # 指定数据库列表
                matched_dbs = [db for db in databases if db in inst_dbs]
            else:
                matched_dbs = inst_dbs

            # 应用模糊匹配
            if db_pattern:
                matched_dbs = [db for db in matched_dbs if fnmatch.fnmatch(db, db_pattern)]

            # 应用排除
            matched_dbs = [db for db in matched_dbs if db not in excluded]

            for db_name in matched_dbs:
                targets.append(Target(instance_name=inst_name, db_name=db_name))

        return targets

    def select_from_filter(self, filter_dict: dict) -> List[Target]:
        """
        从字典条件中选择目标

        Args:
            filter_dict: {
                "instances": [...],      # 实例列表
                "databases": [...],      # 数据库列表
                "db_pattern": "...",     # 模糊匹配
                "exclude_dbs": [...],    # 排除列表
                "instance_only": False,  # 是否仅实例级
            }
        """
        return self.select(
            instances=filter_dict.get("instances"),
            databases=filter_dict.get("databases"),
            db_pattern=filter_dict.get("db_pattern"),
            exclude_dbs=filter_dict.get("exclude_dbs"),
            instance_only=filter_dict.get("instance_only", False),
        )


def build_target_summary(targets: List[Target]) -> dict:
    """构建目标选择摘要"""
    instances = set()
    databases = set()
    instance_level = 0

    for t in targets:
        instances.add(t.instance_name)
        if t.db_name:
            databases.add(t.db_name)
        else:
            instance_level += 1

    return {
        "total_targets": len(targets),
        "unique_instances": len(instances),
        "unique_databases": len(databases),
        "instance_level_targets": instance_level,
        "instances": sorted(instances),
        "databases": sorted(databases),
    }
