"""
SQL Server 连接管理 — pyodbc 连接 + 多实例查询封装
"""

import time
import logging
from contextlib import contextmanager
from typing import Optional

import pyodbc
import yaml

from config import INSTANCES_CONFIG, ODBC_DRIVER, QUERY_TIMEOUT, CONNECT_RETRY

logger = logging.getLogger(__name__)


class InstanceConfig:
    """单个实例的连接配置"""

    def __init__(self, name: str, host: str, port: int, user: str,
                 password: str, description: str = "", enabled: bool = True):
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.description = description
        self.enabled = enabled

    @property
    def connection_string(self) -> str:
        return (
            f"DRIVER={{{ODBC_DRIVER}}};"
            f"SERVER={self.host},{self.port};"
            f"DATABASE=master;"
            f"UID={self.user};"
            f"PWD={self.password};"
            f"TrustServerCertificate=yes;"
            f"Encrypt=yes;"
        )

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "host": self.host,
            "port": self.port,
            "description": self.description,
            "enabled": self.enabled,
        }


def load_instances(config_path: str = None) -> list:
    """从 YAML 加载实例配置"""
    path = config_path or INSTANCES_CONFIG
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    instances = []
    for item in data.get("instances", []):
        if not item.get("enabled", True):
            continue
        instances.append(InstanceConfig(
            name=item["name"],
            host=item["host"],
            port=item.get("port", 1433),
            user=item["user"],
            password=item.get("password", ""),
            description=item.get("description", ""),
            enabled=item.get("enabled", True),
        ))
    return instances


class MssqlConnector:
    """SQL Server 连接管理器"""

    def __init__(self):
        self._instances: dict[str, InstanceConfig] = {}
        self._connections: dict[str, pyodbc.Connection] = {}

    def load(self, config_path: str = None):
        """加载所有实例配置"""
        self._instances = {
            inst.name: inst for inst in load_instances(config_path)
        }
        logger.info(f"已加载 {len(self._instances)} 个 SQL Server 实例")

    def get_instance(self, name: str) -> Optional[InstanceConfig]:
        return self._instances.get(name)

    def list_instances(self) -> list[InstanceConfig]:
        return list(self._instances.values())

    @contextmanager
    def connect(self, instance_name: str):
        """
        获取实例连接 — 上下文管理器, 自动释放连接
        用法: with connector.connect("SRV-01") as conn: ...
        """
        inst = self._instances.get(instance_name)
        if not inst:
            raise ValueError(f"实例 '{instance_name}' 未配置")

        conn = None
        last_error = None
        for attempt in range(CONNECT_RETRY + 1):
            try:
                conn = pyodbc.connect(
                    inst.connection_string,
                    timeout=QUERY_TIMEOUT,
                    autocommit=True,
                )
                break
            except pyodbc.Error as e:
                last_error = e
                logger.warning(f"连接 {instance_name} 失败 (第{attempt+1}次): {e}")
                if attempt < CONNECT_RETRY:
                    time.sleep(2)
        if not conn:
            raise ConnectionError(f"无法连接到 {instance_name}: {last_error}")

        try:
            yield conn
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def execute_query(self, instance_name: str, sql: str,
                      params: tuple = None, timeout: int = None) -> list[dict]:
        """
        在指定实例上执行查询，返回字典列表
        """
        timeout = timeout or QUERY_TIMEOUT
        results = []

        with self.connect(instance_name) as conn:
            conn.timeout = timeout
            cursor = conn.cursor()
            cursor.execute(sql, params or ())

            # 判断是否是返回结果集的查询
            if cursor.description:
                columns = [col[0] for col in cursor.description]
                for row in cursor.fetchall():
                    results.append(dict(zip(columns, row)))

            cursor.close()

        return results

    def execute_query_all(self, instance_name: str, sql: str,
                          timeout: int = None) -> list[list[dict]]:
        """
        执行包含多个 SELECT 的 SQL，返回多个结果集。
        每个结果集是 list[dict]。
        """
        timeout = timeout or QUERY_TIMEOUT
        all_results = []

        with self.connect(instance_name) as conn:
            conn.timeout = timeout
            cursor = conn.cursor()

            # 使用 SET NOCOUNT ON 避免行计数干扰
            cursor.execute("SET NOCOUNT ON;")
            cursor.execute(sql)

            # 遍历所有结果集
            while True:
                if cursor.description:
                    columns = [col[0] for col in cursor.description]
                    result_set = []
                    for row in cursor.fetchall():
                        result_set.append(dict(zip(columns, row)))
                    all_results.append(result_set)
                if not cursor.nextset():
                    break

            cursor.close()

        return all_results

    def test_connection(self, instance_name: str) -> dict:
        """测试实例连接是否正常"""
        try:
            sql = "SELECT @@VERSION AS version, @@SERVERNAME AS server_name, DB_NAME() AS db_name"
            rows = self.execute_query(instance_name, sql)
            return {
                "success": True,
                "data": rows[0] if rows else {},
                "error": None,
            }
        except Exception as e:
            return {
                "success": False,
                "data": None,
                "error": str(e),
            }


# 全局单例
connector = MssqlConnector()
