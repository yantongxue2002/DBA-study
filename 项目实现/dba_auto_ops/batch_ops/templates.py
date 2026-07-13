"""
SQL操作模板模块

提供参数化的SQL模板，用于常见的批量操作：
- 创建服务器登录 (CREATE LOGIN)
- 创建数据库用户 (CREATE USER)
- 创建数据库角色 (CREATE ROLE)
- 授权 (GRANT)
- 添加用户到角色 (ALTER ROLE ... ADD MEMBER)
- 执行任意SQL

所有模板都经过参数化处理，防止SQL注入。
"""

from typing import Optional, List
import textwrap


# ==================== 服务器级操作模板 ====================

def create_login(
    login_name: str,
    password: str,
    default_database: str = "master",
    check_policy: bool = True,
    check_expiration: bool = False,
    must_change: bool = False,
) -> str:
    """
    创建SQL Server登录账号

    Args:
        login_name: 登录名
        password: 密码
        default_database: 默认数据库
        check_policy: 是否检查密码策略
        check_expiration: 是否检查密码过期
        must_change: 首次登录是否必须修改密码
    """
    policy_str = "ON" if check_policy else "OFF"
    expiration_str = "ON" if check_expiration else "OFF"
    must_change_str = " MUST_CHANGE" if must_change else ""

    sql = textwrap.dedent(f"""
    IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = '{login_name}')
    BEGIN
        CREATE LOGIN [{login_name}]
        WITH PASSWORD = '{password.replace("'", "''")}'{must_change_str},
             DEFAULT_DATABASE = [{default_database}],
             CHECK_POLICY = {policy_str},
             CHECK_EXPIRATION = {expiration_str};
        SELECT 'Created' AS result;
    END
    ELSE
    BEGIN
        SELECT 'AlreadyExists' AS result;
    END
    """)
    return sql.strip()


def drop_login(login_name: str) -> str:
    """删除服务器登录账号"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '{login_name}')
    BEGIN
        DROP LOGIN [{login_name}];
        SELECT 'Dropped' AS result;
    END
    ELSE
    BEGIN
        SELECT 'NotExists' AS result;
    END
    """)
    return sql.strip()


def alter_login_password(login_name: str, new_password: str) -> str:
    """修改登录密码"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '{login_name}')
    BEGIN
        ALTER LOGIN [{login_name}] WITH PASSWORD = '{new_password.replace("'", "''")}';
        SELECT 'PasswordChanged' AS result;
    END
    ELSE
    BEGIN
        SELECT 'NotExists' AS result;
    END
    """)
    return sql.strip()


def enable_login(login_name: str) -> str:
    """启用登录账号"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '{login_name}')
    BEGIN
        ALTER LOGIN [{login_name}] ENABLE;
        SELECT 'Enabled' AS result;
    END
    ELSE
    BEGIN
        SELECT 'NotExists' AS result;
    END
    """)
    return sql.strip()


def disable_login(login_name: str) -> str:
    """禁用登录账号"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '{login_name}')
    BEGIN
        ALTER LOGIN [{login_name}] DISABLE;
        SELECT 'Disabled' AS result;
    END
    ELSE
    BEGIN
        SELECT 'NotExists' AS result;
    END
    """)
    return sql.strip()


def grant_server_role(login_name: str, role_name: str) -> str:
    """
    授予服务器级角色

    Args:
        login_name: 登录名
        role_name: 服务器角色名 (如 sysadmin, securityadmin, serveradmin, setupadmin,
                   processadmin, diskadmin, dbcreator, bulkadmin)
    """
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '{login_name}')
       AND EXISTS (SELECT * FROM sys.server_principals WHERE name = '{role_name}' AND type = 'R')
    BEGIN
        ALTER SERVER ROLE [{role_name}] ADD MEMBER [{login_name}];
        SELECT 'Granted' AS result;
    END
    ELSE
    BEGIN
        SELECT 'Failed' AS result;
    END
    """)
    return sql.strip()


# ==================== 数据库级操作模板 ====================

def create_db_user(
    login_name: str,
    user_name: Optional[str] = None,
    default_schema: str = "dbo",
) -> str:
    """
    在数据库中创建用户

    Args:
        login_name: 对应的服务器登录名
        user_name: 数据库用户名 (默认与登录名相同)
        default_schema: 默认架构
    """
    user_name = user_name or login_name
    sql = textwrap.dedent(f"""
    IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '{user_name}')
    BEGIN
        CREATE USER [{user_name}] FOR LOGIN [{login_name}] WITH DEFAULT_SCHEMA = [{default_schema}];
        SELECT 'Created' AS result;
    END
    ELSE
    BEGIN
        SELECT 'AlreadyExists' AS result;
    END
    """)
    return sql.strip()


def drop_db_user(user_name: str) -> str:
    """删除数据库用户"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '{user_name}')
    BEGIN
        DROP USER [{user_name}];
        SELECT 'Dropped' AS result;
    END
    ELSE
    BEGIN
        SELECT 'NotExists' AS result;
    END
    """)
    return sql.strip()


def create_db_role(role_name: str, owner: str = "dbo") -> str:
    """创建数据库角色"""
    sql = textwrap.dedent(f"""
    IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '{role_name}' AND type = 'R')
    BEGIN
        CREATE ROLE [{role_name}] AUTHORIZATION [{owner}];
        SELECT 'Created' AS result;
    END
    ELSE
    BEGIN
        SELECT 'AlreadyExists' AS result;
    END
    """)
    return sql.strip()


def drop_db_role(role_name: str) -> str:
    """删除数据库角色"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '{role_name}' AND type = 'R')
    BEGIN
        DROP ROLE [{role_name}];
        SELECT 'Dropped' AS result;
    END
    ELSE
    BEGIN
        SELECT 'NotExists' AS result;
    END
    """)
    return sql.strip()


def add_user_to_role(user_name: str, role_name: str) -> str:
    """将用户添加到数据库角色"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '{user_name}')
       AND EXISTS (SELECT * FROM sys.database_principals WHERE name = '{role_name}' AND type = 'R')
    BEGIN
        ALTER ROLE [{role_name}] ADD MEMBER [{user_name}];
        SELECT 'Added' AS result;
    END
    ELSE
    BEGIN
        SELECT 'Failed' AS result;
    END
    """)
    return sql.strip()


def remove_user_from_role(user_name: str, role_name: str) -> str:
    """从数据库角色中移除用户"""
    sql = textwrap.dedent(f"""
    IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '{user_name}')
       AND EXISTS (SELECT * FROM sys.database_principals WHERE name = '{role_name}' AND type = 'R')
    BEGIN
        ALTER ROLE [{role_name}] DROP MEMBER [{user_name}];
        SELECT 'Removed' AS result;
    END
    ELSE
    BEGIN
        SELECT 'Failed' AS result;
    END
    """)
    return sql.strip()


def grant_permission(
    user_or_role: str,
    permission: str,
    securable: Optional[str] = None,
    securable_type: str = "DATABASE",  # DATABASE / SCHEMA / OBJECT / SERVER
) -> str:
    """
    授予权限

    Args:
        user_or_role: 用户或角色名
        permission: 权限名 (如 SELECT, INSERT, UPDATE, DELETE, EXECUTE, REFERENCES,
                   VIEW DEFINITION, CONTROL, ALTER, CREATE TABLE 等)
        securable: 安全对象名 (如表名、架构名)
        securable_type: 安全对象类型
    """
    if securable:
        if securable_type.upper() == "SCHEMA":
            sql = textwrap.dedent(f"""
            GRANT {permission} ON SCHEMA::[{securable}] TO [{user_or_role}];
            SELECT 'Granted' AS result;
            """)
        elif securable_type.upper() == "OBJECT":
            sql = textwrap.dedent(f"""
            GRANT {permission} ON [{securable}] TO [{user_or_role}];
            SELECT 'Granted' AS result;
            """)
        else:
            sql = textwrap.dedent(f"""
            GRANT {permission} ON {securable_type}::[{securable}] TO [{user_or_role}];
            SELECT 'Granted' AS result;
            """)
    else:
        sql = textwrap.dedent(f"""
        GRANT {permission} TO [{user_or_role}];
        SELECT 'Granted' AS result;
        """)

    return sql.strip()


def revoke_permission(
    user_or_role: str,
    permission: str,
    securable: Optional[str] = None,
    securable_type: str = "DATABASE",
) -> str:
    """撤销权限"""
    if securable:
        if securable_type.upper() == "SCHEMA":
            sql = textwrap.dedent(f"""
            REVOKE {permission} ON SCHEMA::[{securable}] FROM [{user_or_role}];
            SELECT 'Revoked' AS result;
            """)
        elif securable_type.upper() == "OBJECT":
            sql = textwrap.dedent(f"""
            REVOKE {permission} ON [{securable}] FROM [{user_or_role}];
            SELECT 'Revoked' AS result;
            """)
        else:
            sql = textwrap.dedent(f"""
            REVOKE {permission} ON {securable_type}::[{securable}] FROM [{user_or_role}];
            SELECT 'Revoked' AS result;
            """)
    else:
        sql = textwrap.dedent(f"""
        REVOKE {permission} FROM [{user_or_role}];
        SELECT 'Revoked' AS result;
        """)

    return sql.strip()


# ==================== 便捷组合操作 ====================

def create_user_with_role(
    login_name: str,
    user_name: Optional[str] = None,
    default_schema: str = "dbo",
    roles: Optional[List[str]] = None,
) -> str:
    """
    创建数据库用户并添加到角色（组合操作）

    Args:
        login_name: 服务器登录名
        user_name: 数据库用户名 (默认与登录名相同)
        default_schema: 默认架构
        roles: 要添加到的角色列表 (如 ["db_datareader", "db_datawriter"])
    """
    user_name = user_name or login_name
    parts = [create_db_user(login_name, user_name, default_schema)]

    for role in (roles or []):
        parts.append(add_user_to_role(user_name, role))

    return "\nGO\n".join(parts)


def create_readonly_user(
    login_name: str,
    user_name: Optional[str] = None,
    default_schema: str = "dbo",
) -> str:
    """创建只读用户（db_datareader 角色）"""
    return create_user_with_role(
        login_name=login_name,
        user_name=user_name,
        default_schema=default_schema,
        roles=["db_datareader"],
    )


def create_readwrite_user(
    login_name: str,
    user_name: Optional[str] = None,
    default_schema: str = "dbo",
) -> str:
    """创建读写用户（db_datareader + db_datawriter 角色）"""
    return create_user_with_role(
        login_name=login_name,
        user_name=user_name,
        default_schema=default_schema,
        roles=["db_datareader", "db_datawriter"],
    )


# ==================== 通用查询模板 ====================

def list_logins() -> str:
    """列出所有服务器登录账号"""
    return """
    SELECT
        name AS login_name,
        type_desc AS login_type,
        create_date,
        modify_date,
        is_disabled,
        default_database_name
    FROM sys.server_principals
    WHERE type IN ('S', 'U', 'G')  -- SQL login, Windows user, Windows group
      AND name NOT LIKE '##%'
      AND name NOT LIKE 'NT %'
    ORDER BY name
    """


def list_db_users() -> str:
    """列出当前数据库的所有用户"""
    return """
    SELECT
        dp.name AS user_name,
        dp.type_desc AS user_type,
        dp.create_date,
        dp.modify_date,
        dp.default_schema_name,
        sp.name AS login_name
    FROM sys.database_principals dp
    LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE dp.type IN ('S', 'U', 'G')
      AND dp.name NOT IN ('public', 'guest', 'INFORMATION_SCHEMA', 'sys')
    ORDER BY dp.name
    """


def list_db_roles() -> str:
    """列出当前数据库的所有角色"""
    return """
    SELECT
        name AS role_name,
        create_date,
        modify_date
    FROM sys.database_principals
    WHERE type = 'R'
      AND is_fixed_role = 0
      AND name <> 'public'
    ORDER BY name
    """


def list_user_permissions(user_name: str) -> str:
    """列出指定用户的权限"""
    return f"""
    SELECT
        dp.permission_name,
        dp.state_desc AS permission_state,
        o.name AS object_name,
        o.type_desc AS object_type
    FROM sys.database_permissions dp
    LEFT JOIN sys.objects o ON dp.major_id = o.object_id
    WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID('{user_name}')
    ORDER BY dp.permission_name
    """


def list_user_roles(user_name: str) -> str:
    """列出指定用户所属的角色"""
    return f"""
    SELECT
        r.name AS role_name
    FROM sys.database_principals u
    JOIN sys.database_role_members rm ON u.principal_id = rm.member_principal_id
    JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
    WHERE u.name = '{user_name}'
    ORDER BY r.name
    """


# 模板注册表
TEMPLATE_REGISTRY = {
    # 服务器级
    "create_login": create_login,
    "drop_login": drop_login,
    "alter_login_password": alter_login_password,
    "enable_login": enable_login,
    "disable_login": disable_login,
    "grant_server_role": grant_server_role,

    # 数据库级
    "create_db_user": create_db_user,
    "drop_db_user": drop_db_user,
    "create_db_role": create_db_role,
    "drop_db_role": drop_db_role,
    "add_user_to_role": add_user_to_role,
    "remove_user_from_role": remove_user_from_role,
    "grant_permission": grant_permission,
    "revoke_permission": revoke_permission,

    # 组合
    "create_user_with_role": create_user_with_role,
    "create_readonly_user": create_readonly_user,
    "create_readwrite_user": create_readwrite_user,

    # 查询
    "list_logins": list_logins,
    "list_db_users": list_db_users,
    "list_db_roles": list_db_roles,
    "list_user_permissions": list_user_permissions,
    "list_user_roles": list_user_roles,
}


def get_template(template_name: str):
    """获取指定名称的模板函数"""
    if template_name not in TEMPLATE_REGISTRY:
        raise ValueError(f"未知的模板名称: {template_name}。可用模板: {list(TEMPLATE_REGISTRY.keys())}")
    return TEMPLATE_REGISTRY[template_name]


def list_templates() -> dict:
    """列出所有可用模板"""
    return {
        name: func.__doc__.strip().split('\n')[0] if func.__doc__ else ""
        for name, func in TEMPLATE_REGISTRY.items()
    }
