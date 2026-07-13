"""
批量操作命令行工具

用法:
    python -m cli.batch_cli <command> [options]

命令:
    sync              同步数据库资产清单
    inventory         显示资产清单
    create-login      在所有实例上创建服务器登录
    create-user       在目标数据库上创建用户
    create-role       在目标数据库上创建角色
    grant             在目标数据库上授权
    add-to-role       将用户添加到角色
    execute           在目标上执行任意SQL
    history           查看批量任务历史
    templates         列出所有可用模板

示例:
    # 同步资产
    python -m cli.batch_cli sync

    # 查看资产
    python -m cli.batch_cli inventory

    # 创建登录账号
    python -m cli.batch_cli create-login --name report_reader --password "P@ssw0rd123"

    # 在所有数据库上创建只读用户
    python -m cli.batch_cli create-user --login report_reader --roles db_datareader --dbs "*"

    # 在指定实例的匹配数据库上创建用户
    python -m cli.batch_cli create-user --login app_user --roles db_datareader,db_datawriter \
        --instances 成都,天门 --db-pattern "*prod*"

    # 执行查询
    python -m cli.batch_cli execute --sql "SELECT COUNT(*) as table_count FROM sys.tables" \
        --instances 成都 --dbs "*"
"""

import argparse
import json
import sys
from datetime import datetime

# 添加项目根目录到路径
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from batch_ops.inventory import inventory_manager
from batch_ops.selector import TargetSelector, build_target_summary
from batch_ops.executor import BatchExecutor
from batch_ops import templates
from core.db import db
from core.mssql import connector


class Colors:
    """终端颜色"""
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    BOLD = "\033[1m"
    END = "\033[0m"


def print_success(msg):
    print(f"{Colors.GREEN}✓ {msg}{Colors.END}")


def print_error(msg):
    print(f"{Colors.RED}✗ {msg}{Colors.END}", file=sys.stderr)


def print_warning(msg):
    print(f"{Colors.YELLOW}⚠ {msg}{Colors.END}")


def print_info(msg):
    print(f"{Colors.BLUE}ℹ {msg}{Colors.END}")


def print_bold(msg):
    print(f"{Colors.BOLD}{msg}{Colors.END}")


def init_db():
    """初始化数据库连接"""
    from config import BASE_DIR, SQLITE_PATH, SQLALCHEMY_DATABASE_URI
    from core.db import db as _db
    import sqlalchemy

    engine = sqlalchemy.create_engine(SQLALCHEMY_DATABASE_URI)
    _db.metadata.create_all(engine)
    return _db


def cmd_sync(args):
    """同步资产"""
    print_bold("正在同步数据库资产清单...")
    stats = inventory_manager.sync_to_db()
    print_success(f"同步完成！")
    print(f"  实例数: {stats['total_instances']}")
    print(f"  数据库数: {stats['total_databases']}")
    if stats['failed_instances']:
        print_warning(f"  失败的实例: {', '.join(stats['failed_instances'])}")


def cmd_inventory(args):
    """显示资产清单"""
    print_bold("数据库资产清单")
    print("-" * 60)

    summary = inventory_manager.get_instances_summary()
    if not summary:
        print_warning("资产清单为空，请先运行 sync 命令")
        return

    total_dbs = 0
    for s in summary:
        print(f"  {s['instance_name']:<15} {s['db_count']:>3} 个数据库  "
              f"({s['total_size_mb']:>8.2f} MB)")
        total_dbs += s['db_count']

    print("-" * 60)
    print(f"  总计: {len(summary)} 个实例, {total_dbs} 个数据库")

    if args.detail:
        print("\n数据库列表:")
        items = inventory_manager.get_inventory()
        current_inst = None
        for item in items:
            if item.instance_name != current_inst:
                current_inst = item.instance_name
                print(f"\n  [{current_inst}]")
            print(f"    {item.db_name:<30} {item.db_state:<10} "
                  f"{item.recovery_model or '':<12} {item.db_size_mb or 0:>8.2f} MB")


def _parse_targets(args) -> list:
    """解析命令行参数为目标列表"""
    selector = TargetSelector()

    instances = None
    if args.instances:
        instances = [i.strip() for i in args.instances.split(",")]

    databases = None
    if args.dbs:
        databases = args.dbs if args.dbs == "*" else [d.strip() for d in args.dbs.split(",")]

    db_pattern = getattr(args, 'db_pattern', None)

    targets = selector.select(
        instances=instances,
        databases=databases,
        db_pattern=db_pattern,
    )

    if not targets:
        print_error("没有匹配的目标，请检查参数")
        sys.exit(1)

    summary = build_target_summary(targets)
    print_info(f"目标: {summary['total_targets']} 个 ({summary['unique_instances']} 个实例, "
               f"{summary['unique_databases']} 个数据库)")

    if args.dry_run:
        print_warning("【干运行模式】SQL 不会实际执行")

    return targets


def cmd_create_login(args):
    """创建服务器登录"""
    targets = _parse_targets(args)
    instance_targets = [t for t in targets if t.db_name is None]
    if not instance_targets:
        instance_targets = [Target(t.instance_name) for t in set(targets)]

    print_bold(f"创建服务器登录: {args.name}")

    executor = BatchExecutor()
    sql = templates.create_login(
        login_name=args.name,
        password=args.password,
        default_database=args.default_db,
        check_policy=not args.no_policy,
    )

    results = executor.execute(
        task_name=f"创建登录 {args.name}",
        operation_type="create_login",
        targets=instance_targets,
        sql_generator=lambda t: sql,
        dry_run=args.dry_run,
    )

    _print_results(results)


def cmd_create_user(args):
    """创建数据库用户"""
    targets = _parse_targets(args)
    db_targets = [t for t in targets if t.db_name]

    if not db_targets:
        print_error("没有选择任何数据库目标")
        sys.exit(1)

    roles = [r.strip() for r in args.roles.split(",")] if args.roles else []

    print_bold(f"创建数据库用户: {args.login} -> {args.user or args.login}")
    if roles:
        print_info(f"角色: {', '.join(roles)}")

    executor = BatchExecutor()

    def sql_gen(target):
        return templates.create_user_with_role(
            login_name=args.login,
            user_name=args.user,
            default_schema=args.schema,
            roles=roles,
        )

    results = executor.execute(
        task_name=f"创建用户 {args.login}",
        operation_type="create_db_user",
        targets=db_targets,
        sql_generator=sql_gen,
        dry_run=args.dry_run,
    )

    _print_results(results)


def cmd_create_role(args):
    """创建数据库角色"""
    targets = _parse_targets(args)
    db_targets = [t for t in targets if t.db_name]

    if not db_targets:
        print_error("没有选择任何数据库目标")
        sys.exit(1)

    print_bold(f"创建数据库角色: {args.name}")

    executor = BatchExecutor()
    sql = templates.create_db_role(role_name=args.name, owner=args.owner)

    results = executor.execute(
        task_name=f"创建角色 {args.name}",
        operation_type="create_db_role",
        targets=db_targets,
        sql_generator=lambda t: sql,
        dry_run=args.dry_run,
    )

    _print_results(results)


def cmd_grant(args):
    """授权"""
    targets = _parse_targets(args)
    db_targets = [t for t in targets if t.db_name]

    if not db_targets:
        print_error("没有选择任何数据库目标")
        sys.exit(1)

    print_bold(f"授权: {args.permission} TO {args.user}")

    executor = BatchExecutor()

    def sql_gen(target):
        return templates.grant_permission(
            user_or_role=args.user,
            permission=args.permission,
            securable=args.securable,
            securable_type=args.securable_type,
        )

    results = executor.execute(
        task_name=f"授权 {args.permission} 给 {args.user}",
        operation_type="grant_permission",
        targets=db_targets,
        sql_generator=sql_gen,
        dry_run=args.dry_run,
    )

    _print_results(results)


def cmd_add_to_role(args):
    """添加用户到角色"""
    targets = _parse_targets(args)
    db_targets = [t for t in targets if t.db_name]

    if not db_targets:
        print_error("没有选择任何数据库目标")
        sys.exit(1)

    print_bold(f"添加用户到角色: {args.user} -> {args.role}")

    executor = BatchExecutor()
    sql = templates.add_user_to_role(user_name=args.user, role_name=args.role)

    results = executor.execute(
        task_name=f"添加 {args.user} 到 {args.role}",
        operation_type="add_user_to_role",
        targets=db_targets,
        sql_generator=lambda t: sql,
        dry_run=args.dry_run,
    )

    _print_results(results)


def cmd_execute(args):
    """执行任意SQL"""
    targets = _parse_targets(args)

    print_bold(f"执行 SQL:")
    print(f"  {args.sql}")

    executor = BatchExecutor()

    is_query = not args.no_query
    if is_query:
        print_info("模式: 查询（返回结果集）")
    else:
        print_info("模式: 执行（不返回结果集）")

    results = executor.execute(
        task_name="执行SQL",
        operation_type="execute_sql",
        targets=targets,
        sql_generator=lambda t: args.sql,
        is_query=is_query,
        dry_run=args.dry_run,
    )

    _print_results(results, show_data=is_query)


def cmd_history(args):
    """查看历史"""
    print_bold("批量任务历史")
    print("-" * 80)

    executor = BatchExecutor()
    tasks = executor.get_task_history(limit=args.limit)

    if not tasks:
        print_warning("暂无历史记录")
        return

    print(f"{'ID':<5} {'状态':<12} {'操作类型':<18} {'成功':<5} {'失败':<5} {'任务名称'}")
    print("-" * 80)
    for t in tasks:
        status_color = Colors.GREEN if t['status'] == 'completed' else (
            Colors.YELLOW if t['status'] == 'partial_failed' else Colors.RED)
        print(f"{t['id']:<5} "
              f"{status_color}{t['status']:<12}{Colors.END} "
              f"{t['operation_type']:<18} "
              f"{t['success_count']:<5} "
              f"{t['fail_count']:<5} "
              f"{t['task_name']}")


def cmd_templates(args):
    """列出模板"""
    print_bold("可用 SQL 模板")
    print("-" * 60)
    for name, desc in templates.list_templates().items():
        print(f"  {name:<30} {desc}")


def _print_results(results: dict, show_data: bool = False):
    """打印执行结果"""
    print("\n" + "=" * 60)
    print_bold("执行结果汇总")
    print("=" * 60)

    total = results['total']
    success = results['success']
    failed = results['failed']

    print(f"  总目标: {total}")
    print(f"  {Colors.GREEN}成功: {success}{Colors.END}")
    if failed > 0:
        print(f"  {Colors.RED}失败: {failed}{Colors.END}")
    print(f"  耗时: {results['elapsed_ms']}ms")

    if failed > 0:
        print("\n失败详情:")
        for r in results['results']:
            if not r['success']:
                target = f"{r['instance']}"
                if r['database']:
                    target += f"/{r['database']}"
                print(f"  {Colors.RED}{target}{Colors.END}: {r['error']}")

    if show_data and success > 0:
        print("\n查询结果:")
        for r in results['results']:
            if r['success'] and r['data']:
                target = f"{r['instance']}"
                if r['database']:
                    target += f"/{r['database']}"
                print(f"\n  [{target}]")
                for row in r['data']:
                    print(f"    {json.dumps(row, ensure_ascii=False, default=str)}")


def main():
    parser = argparse.ArgumentParser(
        description="SQL Server 批量操作工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--dry-run", action="store_true", help="干运行模式，只预览SQL不执行")

    subparsers = parser.add_subparsers(dest="command", help="可用命令")

    # sync
    sync_parser = subparsers.add_parser("sync", help="同步数据库资产清单")
    sync_parser.set_defaults(func=cmd_sync)

    # inventory
    inv_parser = subparsers.add_parser("inventory", help="显示资产清单")
    inv_parser.add_argument("--detail", action="store_true", help="显示详细信息")
    inv_parser.set_defaults(func=cmd_inventory)

    # create-login
    login_parser = subparsers.add_parser("create-login", help="创建服务器登录")
    login_parser.add_argument("--name", required=True, help="登录名")
    login_parser.add_argument("--password", required=True, help="密码")
    login_parser.add_argument("--default-db", default="master", help="默认数据库")
    login_parser.add_argument("--no-policy", action="store_true", help="不检查密码策略")
    login_parser.add_argument("--instances", help="目标实例（逗号分隔，*表示所有）")
    login_parser.set_defaults(func=cmd_create_login)

    # create-user
    user_parser = subparsers.add_parser("create-user", help="创建数据库用户")
    user_parser.add_argument("--login", required=True, help="服务器登录名")
    user_parser.add_argument("--user", help="数据库用户名（默认与登录名相同）")
    user_parser.add_argument("--schema", default="dbo", help="默认架构")
    user_parser.add_argument("--roles", help="角色列表（逗号分隔，如 db_datareader,db_datawriter）")
    user_parser.add_argument("--instances", help="目标实例（逗号分隔）")
    user_parser.add_argument("--dbs", help="目标数据库（逗号分隔，*表示所有）")
    user_parser.add_argument("--db-pattern", help="数据库名模糊匹配（如 *_prod）")
    user_parser.set_defaults(func=cmd_create_user)

    # create-role
    role_parser = subparsers.add_parser("create-role", help="创建数据库角色")
    role_parser.add_argument("--name", required=True, help="角色名")
    role_parser.add_argument("--owner", default="dbo", help="所有者")
    role_parser.add_argument("--instances", help="目标实例（逗号分隔）")
    role_parser.add_argument("--dbs", help="目标数据库（逗号分隔，*表示所有）")
    role_parser.add_argument("--db-pattern", help="数据库名模糊匹配")
    role_parser.set_defaults(func=cmd_create_role)

    # grant
    grant_parser = subparsers.add_parser("grant", help="授权")
    grant_parser.add_argument("--user", required=True, help="用户或角色名")
    grant_parser.add_argument("--permission", required=True, help="权限名（如 SELECT, INSERT）")
    grant_parser.add_argument("--securable", help="安全对象名（如表名）")
    grant_parser.add_argument("--securable-type", default="DATABASE", help="安全对象类型")
    grant_parser.add_argument("--instances", help="目标实例（逗号分隔）")
    grant_parser.add_argument("--dbs", help="目标数据库（逗号分隔，*表示所有）")
    grant_parser.add_argument("--db-pattern", help="数据库名模糊匹配")
    grant_parser.set_defaults(func=cmd_grant)

    # add-to-role
    add_parser = subparsers.add_parser("add-to-role", help="添加用户到角色")
    add_parser.add_argument("--user", required=True, help="用户名")
    add_parser.add_argument("--role", required=True, help="角色名")
    add_parser.add_argument("--instances", help="目标实例（逗号分隔）")
    add_parser.add_argument("--dbs", help="目标数据库（逗号分隔，*表示所有）")
    add_parser.add_argument("--db-pattern", help="数据库名模糊匹配")
    add_parser.set_defaults(func=cmd_add_to_role)

    # execute
    exec_parser = subparsers.add_parser("execute", help="执行SQL")
    exec_parser.add_argument("--sql", required=True, help="SQL语句")
    exec_parser.add_argument("--instances", help="目标实例（逗号分隔）")
    exec_parser.add_argument("--dbs", help="目标数据库（逗号分隔，*表示所有）")
    exec_parser.add_argument("--db-pattern", help="数据库名模糊匹配")
    exec_parser.add_argument("--no-query", action="store_true", help="非查询模式（不获取结果集）")
    exec_parser.set_defaults(func=cmd_execute)

    # history
    hist_parser = subparsers.add_parser("history", help="查看任务历史")
    hist_parser.add_argument("--limit", type=int, default=20, help="显示条数")
    hist_parser.set_defaults(func=cmd_history)

    # templates
    tmpl_parser = subparsers.add_parser("templates", help="列出可用模板")
    tmpl_parser.set_defaults(func=cmd_templates)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # 初始化数据库
    init_db()
    connector.load()

    # 执行命令
    args.func(args)


if __name__ == "__main__":
    main()
