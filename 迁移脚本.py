import pyodbc
import time
import sys
from tqdm import tqdm
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
import queue

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# 数据库连接配置
SOURCE_CONFIG = {
    'server': '10.0.11.213',
    'port': 1433,
    'database': 'wms',
    'username': 'sa',
    'password': 'Admin123456'
}

TARGET_CONFIG = {
    'server': '10.90.178.5',
    'port': 1433,
    'database': 'WMS',
    'username': 'sa',
    'password': 'mes.123()'
}

def create_connection(config):
    """创建数据库连接"""
    try:
        # 获取可用的SQL Server驱动程序
        available_drivers = [d for d in pyodbc.drivers() if 'SQL Server' in d]
        
        # 优先选择较新的驱动程序
        driver_priority = [
            'ODBC Driver 18 for SQL Server',
            'ODBC Driver 17 for SQL Server', 
            'SQL Server'
        ]
        
        selected_driver = None
        for driver in driver_priority:
            if driver in available_drivers:
                selected_driver = driver
                break
        
        if not selected_driver:
            if available_drivers:
                selected_driver = available_drivers[0]  # 使用第一个找到的
            else:
                raise Exception("未找到可用的SQL Server ODBC驱动程序")
        
        logger.info(f"使用驱动程序: {selected_driver}")
        
        # 对于ODBC Driver 18，需要处理加密设置
        if 'ODBC Driver 18' in selected_driver:
            conn_str = (
                f"DRIVER={{{selected_driver}}};"
                f"SERVER={config['server']},{config['port']};"
                f"DATABASE={config['database']};"
                f"UID={config['username']};"
                f"PWD={config['password']};"
                f"Encrypt=no;"  # 禁用加密
                f"TrustServerCertificate=yes;"  # 信任服务器证书
            )
        else:
            conn_str = (
                f"DRIVER={{{selected_driver}}};"
                f"SERVER={config['server']},{config['port']};"
                f"DATABASE={config['database']};"
                f"UID={config['username']};"
                f"PWD={config['password']}"
            )
            
        conn = pyodbc.connect(conn_str)
        logger.info(f"成功连接到数据库 {config['server']}:{config['port']}/{config['database']}")
        return conn
    except Exception as e:
        logger.error(f"连接数据库失败: {e}")
        raise

def disable_foreign_keys(connection):
    """禁用数据库中的所有外键约束"""
    cursor = connection.cursor()
    try:
        cursor.execute("EXEC sp_msforeachtable 'ALTER TABLE ? NOCHECK CONSTRAINT ALL'")
        connection.commit()
        logger.info("已禁用所有外键约束")
    except Exception as e:
        logger.warning(f"禁用外键约束时出现警告（可能某些表没有外键）: {e}")
    finally:
        cursor.close()

def enable_foreign_keys(connection):
    """启用数据库中的所有外键约束"""
    cursor = connection.cursor()
    try:
        cursor.execute("EXEC sp_msforeachtable 'ALTER TABLE ? CHECK CONSTRAINT ALL'")
        connection.commit()
        logger.info("已启用所有外键约束")
    except Exception as e:
        logger.warning(f"启用外键约束时出现警告: {e}")
    finally:
        cursor.close()

def get_all_tables(connection):
    """获取所有用户表"""
    cursor = connection.cursor()
    cursor.execute("""
        SELECT TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_TYPE = 'BASE TABLE' 
        AND TABLE_SCHEMA = 'dbo'
        ORDER BY TABLE_NAME
    """)
    tables = [row[0] for row in cursor.fetchall()]
    cursor.close()
    return tables

def get_table_row_count(connection, table_name):
    """获取表的行数"""
    cursor = connection.cursor()
    cursor.execute(f"SELECT COUNT(*) FROM [{table_name}]")
    count = cursor.fetchone()[0]
    cursor.close()
    return count

def migrate_table_data(source_conn, target_conn, table_name, batch_size=1000):
    """迁移单个表的数据"""
    logger.info(f"开始迁移表: {table_name}")
    
    # 获取表结构信息
    cursor = source_conn.cursor()
    cursor.execute(f"SELECT * FROM [{table_name}] WHERE 1=0")
    columns = [column[0] for column in cursor.description]
    cursor.close()
    
    if not columns:
        logger.warning(f"表 {table_name} 没有列，跳过")
        return 0
    
    # 获取总行数
    total_rows = get_table_row_count(source_conn, table_name)
    if total_rows == 0:
        logger.info(f"表 {table_name} 为空，跳过")
        return 0
    
    # 清空目标表（可选，根据需求决定是否保留）
    target_cursor = target_conn.cursor()
    try:
        target_cursor.execute(f"TRUNCATE TABLE [{table_name}]")
    except:
        # 如果TRUNCATE失败（比如有外键约束），尝试DELETE
        target_cursor.execute(f"DELETE FROM [{table_name}]")
    target_conn.commit()
    target_cursor.close()
    
    # 构建INSERT语句
    placeholders = ', '.join(['?' for _ in columns])
    insert_sql = f"INSERT INTO [{table_name}] ({', '.join([f'[{col}]' for col in columns])}) VALUES ({placeholders})"
    
    # 分批读取和写入数据
    offset = 0
    migrated_count = 0
    
    # 构建明确的列列表用于SELECT
    select_columns = ', '.join([f'[{col}]' for col in columns])
    
    with tqdm(total=total_rows, desc=f"迁移 {table_name}", unit="行") as pbar:
        while offset < total_rows:
            retry_count = 0
            max_retries = 3
            success = False
            
            while retry_count < max_retries and not success:
                try:
                    # 从源数据库读取数据 - 明确指定列名，避免包含rn列
                    source_cursor = source_conn.cursor()
                    source_cursor.execute(f"""
                        SELECT {select_columns} FROM (
                            SELECT {select_columns}, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as rn 
                            FROM [{table_name}]
                        ) t WHERE rn > ? AND rn <= ?
                    """, offset, offset + batch_size)
                    
                    rows = source_cursor.fetchall()
                    source_cursor.close()
                    
                    if not rows:
                        success = True
                        break
                    
                    # 写入目标数据库
                    target_cursor = target_conn.cursor()
                    target_cursor.executemany(insert_sql, rows)
                    target_conn.commit()
                    target_cursor.close()
                    
                    migrated_count += len(rows)
                    offset += batch_size
                    pbar.update(len(rows))
                    success = True
                    
                    # 短暂休眠，避免连接超时
                    time.sleep(0.01)
                    
                except Exception as e:
                    retry_count += 1
                    logger.error(f"迁移表 {table_name} 时出错 (offset={offset}, 尝试 {retry_count}/{max_retries}): {e}")
                    if retry_count >= max_retries:
                        logger.error(f"表 {table_name} 在 offset={offset} 处经过 {max_retries} 次重试后仍失败，跳过该批次")
                        offset += batch_size
                        pbar.update(batch_size)
                        break
                    else:
                        # 尝试重新连接
                        logger.info("尝试重新连接数据库...")
                        try:
                            source_conn = create_connection(SOURCE_CONFIG)
                            target_conn = create_connection(TARGET_CONFIG)
                        except Exception as reconn_error:
                            logger.error(f"重新连接失败: {reconn_error}")
                            break
                        time.sleep(1)  # 等待1秒后重试
    
    logger.info(f"表 {table_name} 迁移完成，共迁移 {migrated_count} 行")
    return migrated_count

def main():
    """主函数"""
    logger.info("开始数据库迁移...")
    
    # 初始化迁移报告
    migration_report = {
        'migrated_tables': [],
        'skipped_tables': []
    }
    
    try:
        # 创建数据库连接
        source_conn = create_connection(SOURCE_CONFIG)
        target_conn = create_connection(TARGET_CONFIG)
        
        # 禁用目标数据库的外键约束
        disable_foreign_keys(target_conn)
        
        # 获取所有表
        tables = get_all_tables(source_conn)
        logger.info(f"发现 {len(tables)} 个表需要迁移")
        
        total_migrated = 0
        
        # 逐个迁移表
        for table_name in tables:
            skip_reason = None
            try:
                # 检查目标表是否已有数据
                target_row_count = get_table_row_count(target_conn, table_name)
                if target_row_count > 0:
                    skip_reason = f"目标表已有 {target_row_count} 行数据"
                    logger.info(f"表 {table_name} {skip_reason}，跳过迁移")
                
                # 检查源表的行数，跳过大于10000行的表
                if skip_reason is None:
                    source_row_count = get_table_row_count(source_conn, table_name)
                    if source_row_count > 10000:
                        skip_reason = f"源表有 {source_row_count} 行数据，超过10000行限制"
                        logger.info(f"表 {table_name} {skip_reason}，跳过迁移")
                
                if skip_reason:
                    migration_report['skipped_tables'].append({
                        'table_name': table_name,
                        'reason': skip_reason
                    })
                    continue
                
                # 执行迁移
                migrated = migrate_table_data(source_conn, target_conn, table_name)
                total_migrated += migrated
                
                if migrated > 0:
                    migration_report['migrated_tables'].append(table_name)
                else:
                    migration_report['skipped_tables'].append({
                        'table_name': table_name,
                        'reason': '源表为空或迁移过程中出现问题'
                    })
                    
            except Exception as e:
                error_msg = f"迁移表 {table_name} 失败: {e}"
                logger.error(error_msg)
                migration_report['skipped_tables'].append({
                    'table_name': table_name,
                    'reason': f'迁移过程中发生错误: {str(e)}'
                })
                continue
        
        logger.info(f"数据库迁移完成！总共迁移了 {total_migrated} 行数据")
        
        # 重新启用外键约束
        enable_foreign_keys(target_conn)
        
        # 输出迁移报告
        print("\n" + "="*60)
        print("数据库迁移报告")
        print("="*60)
        
        print(f"\n✅ 成功迁移的表 ({len(migration_report['migrated_tables'])} 个):")
        if migration_report['migrated_tables']:
            for table in migration_report['migrated_tables']:
                print(f"  - {table}")
        else:
            print("  无")
        
        print(f"\n❌ 跳过的表 ({len(migration_report['skipped_tables'])} 个):")
        if migration_report['skipped_tables']:
            for item in migration_report['skipped_tables']:
                print(f"  - {item['table_name']}: {item['reason']}")
        else:
            print("  无")
        
        print("="*60)
        
    except Exception as e:
        logger.error(f"数据库迁移过程中发生错误: {e}")
    finally:
        # 关闭连接
        if 'source_conn' in locals():
            source_conn.close()
        if 'target_conn' in locals():
            target_conn.close()

if __name__ == "__main__":
    main()