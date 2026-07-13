"""
批量操作模块包

提供SQL Server多实例批量操作能力：
- inventory: 资产发现与缓存
- templates: SQL操作模板
- selector: 目标选择器
- executor: 批量执行引擎
"""

from batch_ops.inventory import inventory_manager
from batch_ops.executor import batch_executor
from batch_ops.selector import TargetSelector, Target

__all__ = [
    "inventory_manager",
    "batch_executor",
    "TargetSelector",
    "Target",
]
