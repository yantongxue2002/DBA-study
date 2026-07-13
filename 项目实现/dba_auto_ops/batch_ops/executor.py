"""
批量执行引擎

核心功能：
1. 并行执行SQL到多个目标（实例/数据库）
2. 错误隔离 — 单个目标失败不影响其他目标
3. 执行结果汇总与持久化
4. 支持实例级操作和数据库级操作
"""

import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, List, Optional, Dict, Any

from core.mssql import connector
from core.db import db, BatchTask, BatchTaskDetail
from batch_ops.selector import Target

logger = logging.getLogger(__name__)


@dataclass
class ExecutionResult:
    """单个目标的执行结果"""
    target: Target
    success: bool
    data: List[dict] = field(default_factory=list)  # 查询结果
    sql_executed: str = ""
    error_message: Optional[str] = None
    execution_time_ms: int = 0


class BatchExecutor:
    """
    批量执行引擎

    使用示例:
        executor = BatchExecutor()

        # 1. 定义操作
        def my_operation(target):
            # 返回要在目标上执行的SQL
            return f"CREATE USER [reader] FOR LOGIN [reader]"

        # 2. 选择目标
        targets = selector.select(databases="*")

        # 3. 执行
        results = executor.execute(
            task_name="创建只读用户",
            operation_type="create_db_user",
            targets=targets,
            sql_generator=my_operation,
        )
    """

    def __init__(self, max_workers: int = 10):
        """
        Args:
            max_workers: 最大并行线程数，默认10
        """
        self.max_workers = max_workers

    def _execute_on_target(
        self,
        target: Target,
        sql: str,
        is_query: bool = False,
    ) -> ExecutionResult:
        """
        在单个目标上执行SQL

        Args:
            target: 执行目标
            sql: 要执行的SQL语句
            is_query: 是否为查询操作（返回结果集）

        Returns:
            ExecutionResult
        """
        start_time = time.time()
        result = ExecutionResult(target=target, success=False, sql_executed=sql)

        try:
            if target.db_name:
                # 数据库级操作：切换到目标数据库执行
                # 注意：pyodbc不支持USE语句切换上下文，需要修改连接字符串
                conn_result = self._execute_on_database(
                    target.instance_name,
                    target.db_name,
                    sql,
                    is_query,
                )
            else:
                # 实例级操作
                conn_result = self._execute_on_instance(
                    target.instance_name,
                    sql,
                    is_query,
                )

            result.success = conn_result["success"]
            result.data = conn_result.get("data", [])
            result.error_message = conn_result.get("error")

        except Exception as e:
            result.success = False
            result.error_message = str(e)
            logger.error(f"执行失败 {target}: {e}")

        finally:
            result.execution_time_ms = int((time.time() - start_time) * 1000)

        return result

    def _execute_on_instance(
        self,
        instance_name: str,
        sql: str,
        is_query: bool = False,
    ) -> dict:
        """在实例的master数据库上执行SQL"""
        try:
            if is_query:
                data = connector.execute_query(instance_name, sql)
                return {"success": True, "data": data, "error": None}
            else:
                # DDL/DML操作
                with connector.connect(instance_name) as conn:
                    cursor = conn.cursor()
                    cursor.execute(sql)

                    # 尝试获取结果
                    data = []
                    if cursor.description:
                        columns = [col[0] for col in cursor.description]
                        for row in cursor.fetchall():
                            data.append(dict(zip(columns, row)))

                    cursor.close()
                    return {"success": True, "data": data, "error": None}
        except Exception as e:
            return {"success": False, "data": [], "error": str(e)}

    def _execute_on_database(
        self,
        instance_name: str,
        db_name: str,
        sql: str,
        is_query: bool = False,
    ) -> dict:
        """在指定数据库上执行SQL（通过修改连接字符串）"""
        import pyodbc
        from core.mssql import InstanceConfig

        try:
            inst = connector.get_instance(instance_name)
            if not inst:
                return {"success": False, "data": [], "error": f"实例 '{instance_name}' 未配置"}

            # 构建指向目标数据库的连接字符串
            conn_str = (
                f"DRIVER={inst.connection_string.split('DRIVER=')[1].split(';')[0]};"
                f"SERVER={inst.host},{inst.port};"
                f"DATABASE={db_name};"
                f"UID={inst.user};"
                f"PWD={inst.password};"
                f"TrustServerCertificate=yes;"
                f"Encrypt=yes;"
            )

            conn = pyodbc.connect(conn_str, timeout=30, autocommit=True)
            try:
                cursor = conn.cursor()
                cursor.execute(sql)

                data = []
                if cursor.description:
                    columns = [col[0] for col in cursor.description]
                    for row in cursor.fetchall():
                        data.append(dict(zip(columns, row)))

                cursor.close()
                return {"success": True, "data": data, "error": None}
            finally:
                conn.close()

        except Exception as e:
            return {"success": False, "data": [], "error": str(e)}

    def execute(
        self,
        task_name: str,
        operation_type: str,
        targets: List[Target],
        sql_generator: Callable[[Target], str],
        is_query: bool = False,
        dry_run: bool = False,
        created_by: str = "system",
    ) -> dict:
        """
        执行批量操作

        Args:
            task_name: 任务名称（用于记录）
            operation_type: 操作类型标识
            targets: 目标列表
            sql_generator: SQL生成函数，接收Target返回SQL字符串
            is_query: 是否为查询操作
            dry_run: 是否仅预览SQL而不执行
            created_by: 创建者标识

        Returns:
            执行结果汇总字典
        """
        if not targets:
            logger.warning("没有目标需要执行")
            return {
                "task_id": None,
                "total": 0,
                "success": 0,
                "failed": 0,
                "results": [],
                "elapsed_ms": 0,
            }

        # 创建任务记录
        task = BatchTask(
            task_name=task_name,
            operation_type=operation_type,
            target_filter=str({"count": len(targets)}),
            sql_template="<dynamic>",
            status="running" if not dry_run else "dry_run",
            total_targets=len(targets),
            created_by=created_by,
            started_at=datetime.now() if not dry_run else None,
        )

        if not dry_run:
            db.session.add(task)
            db.session.commit()

        logger.info(f"开始批量任务 '{task_name}': {len(targets)} 个目标"
                   f"{' [DRY RUN]' if dry_run else ''}")

        start_time = time.time()
        results: List[ExecutionResult] = []
        success_count = 0
        fail_count = 0

        # 并行执行
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # 提交所有任务
            future_to_target = {}
            for target in targets:
                sql = sql_generator(target)
                if dry_run:
                    # 干运行模式：不实际执行
                    result = ExecutionResult(
                        target=target,
                        success=True,
                        sql_executed=sql,
                        data=[{"dry_run": True}],
                    )
                    results.append(result)
                    success_count += 1
                else:
                    future = executor.submit(
                        self._execute_on_target,
                        target,
                        sql,
                        is_query,
                    )
                    future_to_target[future] = target

            # 收集结果
            if not dry_run:
                for future in as_completed(future_to_target):
                    result = future.result()
                    results.append(result)

                    if result.success:
                        success_count += 1
                    else:
                        fail_count += 1

                    # 记录详细结果
                    if task.id:
                        detail = BatchTaskDetail(
                            task_id=task.id,
                            instance_name=result.target.instance_name,
                            db_name=result.target.db_name,
                            status="success" if result.success else "failed",
                            sql_executed=result.sql_executed,
                            error_message=result.error_message,
                            execution_time_ms=result.execution_time_ms,
                        )
                        db.session.add(detail)

                        # 每10个提交一次，避免事务过大
                        if (success_count + fail_count) % 10 == 0:
                            db.session.commit()

        elapsed_ms = int((time.time() - start_time) * 1000)

        # 更新任务状态
        if not dry_run and task.id:
            task.status = "completed" if fail_count == 0 else ("partial_failed" if success_count > 0 else "failed")
            task.success_count = success_count
            task.fail_count = fail_count
            task.completed_at = datetime.now()
            db.session.commit()

        summary = {
            "task_id": task.id if not dry_run else None,
            "task_name": task_name,
            "operation_type": operation_type,
            "dry_run": dry_run,
            "total": len(targets),
            "success": success_count,
            "failed": fail_count,
            "elapsed_ms": elapsed_ms,
            "results": [self._result_to_dict(r) for r in results],
        }

        logger.info(f"批量任务完成 '{task_name}': 成功 {success_count}, 失败 {fail_count}, 耗时 {elapsed_ms}ms")
        return summary

    def execute_query_all(
        self,
        task_name: str,
        targets: List[Target],
        sql: str,
        created_by: str = "system",
    ) -> dict:
        """
        在所有目标上执行查询并汇总结果

        Args:
            task_name: 任务名称
            targets: 目标列表
            sql: 查询SQL
            created_by: 创建者

        Returns:
            汇总结果字典，包含每个目标的查询结果
        """
        def sql_generator(target):
            return sql

        return self.execute(
            task_name=task_name,
            operation_type="execute_query",
            targets=targets,
            sql_generator=sql_generator,
            is_query=True,
            created_by=created_by,
        )

    def _result_to_dict(self, result: ExecutionResult) -> dict:
        """将ExecutionResult转为字典"""
        return {
            "instance": result.target.instance_name,
            "database": result.target.db_name,
            "success": result.success,
            "sql": result.sql_executed,
            "data": result.data,
            "error": result.error_message,
            "time_ms": result.execution_time_ms,
        }

    def get_task_history(self, limit: int = 20) -> List[dict]:
        """获取最近的批量任务历史"""
        tasks = BatchTask.query.order_by(BatchTask.created_at.desc()).limit(limit).all()
        return [t.to_dict() for t in tasks]

    def get_task_details(self, task_id: int) -> Optional[dict]:
        """获取任务详情"""
        task = BatchTask.query.get(task_id)
        if not task:
            return None

        details = BatchTaskDetail.query.filter_by(task_id=task_id).all()

        result = task.to_dict()
        result["details"] = [d.to_dict() for d in details]
        return result


# 全局单例
batch_executor = BatchExecutor()
