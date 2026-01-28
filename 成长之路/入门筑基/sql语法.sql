-- =================================================================================================
-- SQL语法详解 - 数据库管理员(DBA)入门筑基
-- =================================================================================================

-- 一、SQL语言概述
-- SQL (Structured Query Language) 是结构化查询语言的缩写，是一种用于管理关系型数据库的标准语言
-- SQL语言主要分为四大类：
--   1. DML (Data Manipulation Language) - 数据操作语言
--   2. DQL (Data Query Language) - 数据查询语言
--   3. DDL (Data Definition Language) - 数据定义语言
--   4. DCL (Data Control Language) - 数据控制语言

-- =================================================================================================
-- 二、DML (Data Manipulation Language) - 数据操作语言
-- =================================================================================================
-- DML用于对数据库表中的数据进行增、删、改操作，主要包括以下语句：
--   INSERT - 插入新数据
--   UPDATE - 更新现有数据
--   DELETE - 删除数据

-- 2.1 INSERT语句 - 插入数据
-- 基本语法：插入单行数据
INSERT INTO table_name (column1, column2, column3, ...)
VALUES (value1, value2, value3, ...);

-- 插入多行数据
INSERT INTO table_name (column1, column2, column3, ...)
VALUES 
    (value1_1, value2_1, value3_1, ...),
    (value1_2, value2_2, value3_2, ...),
    (value1_3, value2_3, value3_3, ...);

-- 从其他表插入数据
INSERT INTO table_name (column1, column2, ...)
SELECT column1, column2, ...
FROM source_table
WHERE condition;

-- MySQL特定语法：插入时忽略重复错误
INSERT IGNORE INTO table_name (column1, column2, ...)
VALUES (value1, value2, ...);

-- MySQL特定语法：插入时更新重复数据
INSERT INTO table_name (column1, column2, ...)
VALUES (value1, value2, ...)
ON DUPLICATE KEY UPDATE 
    column1 = VALUES(column1),
    column2 = VALUES(column2);

-- 2.2 UPDATE语句 - 更新数据
-- 基本语法
UPDATE table_name
SET column1 = value1, column2 = value2, ...
WHERE condition;

-- 多表更新（MySQL语法）
UPDATE table1
INNER JOIN table2 ON table1.id = table2.id
SET table1.column1 = value1, table2.column2 = value2
WHERE condition;

-- 带排序的更新（MySQL语法）
UPDATE table_name
SET column = value
WHERE condition
ORDER BY column
LIMIT row_count;

-- 低优先级更新（MySQL语法）
UPDATE [LOW_PRIORITY] [IGNORE] table_name
SET column1 = value1, column2 = value2, ...
WHERE condition;

-- 2.3 DELETE语句 - 删除数据
-- 基本语法
DELETE FROM table_name
WHERE condition;

-- MySQL完整语法
DELETE [LOW_PRIORITY] [QUICK] [IGNORE] 
FROM tbl_name [[AS] tbl_alias]
    [PARTITION (partition_name [, partition_name] ...)]
    [WHERE where_condition]
    [ORDER BY ...]
    [LIMIT row_count];

-- 多表删除（MySQL语法）
DELETE t1, t2 FROM table1 AS t1
INNER JOIN table2 AS t2 ON t1.id = t2.id
WHERE condition;

-- 使用子查询删除
DELETE FROM table_name
WHERE id IN (SELECT id FROM other_table WHERE condition);

-- TRUNCATE TABLE - 快速删除表中所有数据（DDL语句，但功能类似DML）
TRUNCATE TABLE table_name;

-- =================================================================================================
-- 三、DQL (Data Query Language) - 数据查询语言
-- =================================================================================================
-- DQL用于从数据库中检索数据，主要使用SELECT语句

-- 3.1 基本SELECT语句
-- 基本语法
SELECT column1, column2, ...
FROM table_name
WHERE condition
GROUP BY column1, column2, ...
HAVING condition
ORDER BY column1, column2, ...
LIMIT offset, count;

-- 选择所有列
SELECT * FROM table_name;

-- 使用别名
SELECT column1 AS alias1, column2 AS alias2
FROM table_name AS t;

-- 去除重复行
SELECT DISTINCT column1, column2
FROM table_name;

-- 3.2 WHERE子句 - 条件过滤
-- 比较运算符
SELECT * FROM table_name WHERE column = value;
SELECT * FROM table_name WHERE column <> value;  -- 不等于
SELECT * FROM table_name WHERE column != value;  -- 不等于
SELECT * FROM table_name WHERE column > value;
SELECT * FROM table_name WHERE column >= value;
SELECT * FROM table_name WHERE column < value;
SELECT * FROM table_name WHERE column <= value;

-- 逻辑运算符
SELECT * FROM table_name WHERE condition1 AND condition2;
SELECT * FROM table_name WHERE condition1 OR condition2;
SELECT * FROM table_name WHERE NOT condition;

-- 范围查询
SELECT * FROM table_name WHERE column BETWEEN value1 AND value2;
SELECT * FROM table_name WHERE column IN (value1, value2, value3);

-- 模糊查询
SELECT * FROM table_name WHERE column LIKE 'pattern';
SELECT * FROM table_name WHERE column LIKE 'abc%';   -- 以abc开头
SELECT * FROM table_name WHERE column LIKE '%abc';   -- 以abc结尾
SELECT * FROM table_name WHERE column LIKE '%abc%';  -- 包含abc
SELECT * FROM table_name WHERE column LIKE '_abc';   -- _代表单个字符

-- 空值判断
SELECT * FROM table_name WHERE column IS NULL;
SELECT * FROM table_name WHERE column IS NOT NULL;

-- 3.3 聚合函数
SELECT COUNT(*) FROM table_name;
SELECT COUNT(column) FROM table_name;
SELECT SUM(column) FROM table_name;
SELECT AVG(column) FROM table_name;
SELECT MIN(column) FROM table_name;
SELECT MAX(column) FROM table_name;

-- 3.4 GROUP BY和HAVING子句
-- 分组统计
SELECT column1, COUNT(*), SUM(column2)
FROM table_name
GROUP BY column1;

-- 多列分组
SELECT column1, column2, COUNT(*)
FROM table_name
GROUP BY column1, column2;

-- 分组后过滤
SELECT column1, COUNT(*)
FROM table_name
GROUP BY column1
HAVING COUNT(*) > 10;

-- 3.5 ORDER BY子句 - 排序
SELECT * FROM table_name ORDER BY column1 ASC;   -- 升序
SELECT * FROM table_name ORDER BY column1 DESC;  -- 降序
SELECT * FROM table_name ORDER BY column1 ASC, column2 DESC;  -- 多列排序

-- 3.6 LIMIT子句 - 限制结果集
SELECT * FROM table_name LIMIT 10;           -- 前10行
SELECT * FROM table_name LIMIT 10, 20;       -- 从第10行开始的20行（MySQL语法）
SELECT * FROM table_name OFFSET 10 FETCH NEXT 20 ROWS ONLY;  -- 标准SQL语法

-- 3.7 JOIN操作 - 表连接
-- 内连接
SELECT * FROM table1
INNER JOIN table2 ON table1.id = table2.id;

-- 左连接
SELECT * FROM table1
LEFT JOIN table2 ON table1.id = table2.id;

-- 右连接
SELECT * FROM table1
RIGHT JOIN table2 ON table1.id = table2.id;

-- 全外连接（MySQL不支持，使用UNION模拟）
SELECT * FROM table1
LEFT JOIN table2 ON table1.id = table2.id
UNION
SELECT * FROM table1
RIGHT JOIN table2 ON table1.id = table2.id;

-- 交叉连接
SELECT * FROM table1
CROSS JOIN table2;

-- 自连接
SELECT t1.column1, t2.column2
FROM table AS t1
INNER JOIN table AS t2 ON t1.id = t2.parent_id;

-- 3.8 子查询
-- 标量子查询
SELECT * FROM table1
WHERE column1 = (SELECT MAX(column2) FROM table2);

-- 列表子查询
SELECT * FROM table1
WHERE id IN (SELECT id FROM table2 WHERE condition);

-- 表子查询
SELECT * FROM (SELECT column1, column2 FROM table1) AS t
WHERE condition;

-- EXISTS子查询
SELECT * FROM table1
WHERE EXISTS (SELECT 1 FROM table2 WHERE table1.id = table2.id);

-- 3.9 集合操作
-- UNION - 合并结果集，去除重复行
SELECT column1, column2 FROM table1
UNION
SELECT column1, column2 FROM table2;

-- UNION ALL - 合并结果集，保留所有行
SELECT column1, column2 FROM table1
UNION ALL
SELECT column1, column2 FROM table2;

-- INTERSECT - 返回两个结果集的交集（MySQL不支持）
SELECT column1, column2 FROM table1
INTERSECT
SELECT column1, column2 FROM table2;

-- EXCEPT - 返回第一个结果集中不在第二个结果集中的行（MySQL不支持）
SELECT column1, column2 FROM table1
EXCEPT
SELECT column1, column2 FROM table2;

-- 3.10 窗口函数（MySQL 8.0+支持）
-- 基本语法
SELECT column1, column2,
       ROW_NUMBER() OVER (PARTITION BY column1 ORDER BY column2) AS row_num
FROM table_name;

-- 常用窗口函数
-- ROW_NUMBER() - 行号
-- RANK() - 排名，相同值排名相同，后续排名跳过
-- DENSE_RANK() - 排名，相同值排名相同，后续排名不跳过
-- LAG() - 获取前一行的值
-- LEAD() - 获取后一行的值
-- FIRST_VALUE() - 获取分区第一个值
-- LAST_VALUE() - 获取分区最后一个值
-- SUM()/AVG()/COUNT() OVER() - 窗口聚合函数

-- 3.11 CASE表达式
-- 简单CASE表达式
SELECT column1,
       CASE column2
           WHEN value1 THEN result1
           WHEN value2 THEN result2
           ELSE default_result
       END AS new_column
FROM table_name;

-- 搜索CASE表达式
SELECT column1,
       CASE
           WHEN condition1 THEN result1
           WHEN condition2 THEN result2
           ELSE default_result
       END AS new_column
FROM table_name;

-- =================================================================================================
-- 四、DDL (Data Definition Language) - 数据定义语言
-- =================================================================================================
-- DDL用于定义和管理数据库对象，包括数据库、表、索引、视图、存储过程等

-- 4.1 数据库操作
-- 创建数据库
CREATE DATABASE database_name;

-- 创建数据库（指定字符集和排序规则）
CREATE DATABASE database_name
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- 查看数据库
SHOW DATABASES;

-- 选择数据库
USE database_name;

-- 修改数据库
ALTER DATABASE database_name
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- 删除数据库
DROP DATABASE database_name;

-- 4.2 表操作
-- 创建表
CREATE TABLE table_name (
    column1 data_type [NOT NULL | NULL] [DEFAULT default_value] [AUTO_INCREMENT],
    column2 data_type [NOT NULL | NULL] [DEFAULT default_value],
    column3 data_type [NOT NULL | NULL] [DEFAULT default_value],
    ...
    PRIMARY KEY (column1),
    INDEX index_name (column2),
    UNIQUE KEY unique_key_name (column3),
    FOREIGN KEY (column1) REFERENCES other_table(column1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 从其他表创建表
CREATE TABLE new_table AS
SELECT * FROM old_table
WHERE condition;

-- 查看表结构
DESC table_name;
DESCRIBE table_name;
SHOW COLUMNS FROM table_name;

-- 查看建表语句
SHOW CREATE TABLE table_name;

-- 修改表 - 添加列
ALTER TABLE table_name
ADD COLUMN column_name data_type [NOT NULL | NULL] [DEFAULT default_value];

-- 修改表 - 修改列
ALTER TABLE table_name
MODIFY COLUMN column_name new_data_type [NOT NULL | NULL] [DEFAULT default_value];

-- 修改表 - 重命名列
ALTER TABLE table_name
CHANGE COLUMN old_column_name new_column_name data_type [NOT NULL | NULL] [DEFAULT default_value];

-- 修改表 - 删除列
ALTER TABLE table_name
DROP COLUMN column_name;

-- 修改表 - 添加主键
ALTER TABLE table_name
ADD PRIMARY KEY (column_name);

-- 修改表 - 删除主键
ALTER TABLE table_name
DROP PRIMARY KEY;

-- 修改表 - 添加外键
ALTER TABLE table_name
ADD CONSTRAINT fk_name
FOREIGN KEY (column_name) REFERENCES other_table(column_name)
[ON DELETE CASCADE | SET NULL | NO ACTION | RESTRICT]
[ON UPDATE CASCADE | SET NULL | NO ACTION | RESTRICT];

-- 修改表 - 删除外键
ALTER TABLE table_name
DROP FOREIGN KEY fk_name;

-- 修改表 - 添加索引
ALTER TABLE table_name
ADD INDEX index_name (column_name);

-- 修改表 - 添加唯一索引
ALTER TABLE table_name
ADD UNIQUE INDEX index_name (column_name);

-- 修改表 - 删除索引
ALTER TABLE table_name
DROP INDEX index_name;

-- 重命名表
RENAME TABLE old_table_name TO new_table_name;
ALTER TABLE old_table_name RENAME TO new_table_name;

-- 删除表
DROP TABLE [IF EXISTS] table_name;

-- 清空表（保留表结构）
TRUNCATE TABLE table_name;

-- 4.3 视图操作
-- 创建视图
CREATE VIEW view_name AS
SELECT column1, column2, ...
FROM table_name
WHERE condition;

-- 创建或替换视图
CREATE OR REPLACE VIEW view_name AS
SELECT column1, column2, ...
FROM table_name
WHERE condition;

-- 查看视图
SHOW CREATE VIEW view_name;

-- 删除视图
DROP VIEW [IF EXISTS] view_name;

-- 4.4 索引操作
-- 创建普通索引
CREATE INDEX index_name ON table_name (column_name);

-- 创建唯一索引
CREATE UNIQUE INDEX index_name ON table_name (column_name);

-- 创建复合索引
CREATE INDEX index_name ON table_name (column1, column2, column3);

-- 创建全文索引
CREATE FULLTEXT INDEX index_name ON table_name (column_name);

-- 删除索引
DROP INDEX index_name ON table_name;

-- 4.5 存储过程和函数
-- 创建存储过程
DELIMITER //
CREATE PROCEDURE procedure_name(IN param1 data_type, OUT param2 data_type)
BEGIN
    -- SQL语句
    SELECT * FROM table_name WHERE column = param1;
    SET param2 = value;
END //
DELIMITER ;

-- 调用存储过程
CALL procedure_name(value, @output_variable);
SELECT @output_variable;

-- 删除存储过程
DROP PROCEDURE [IF EXISTS] procedure_name;

-- 创建函数
DELIMITER //
CREATE FUNCTION function_name(param1 data_type) RETURNS return_data_type
BEGIN
    DECLARE variable data_type;
    -- SQL语句
    RETURN value;
END //
DELIMITER ;

-- 删除函数
DROP FUNCTION [IF EXISTS] function_name;

-- 4.6 触发器
-- 创建触发器
DELIMITER //
CREATE TRIGGER trigger_name
BEFORE INSERT ON table_name
FOR EACH ROW
BEGIN
    -- 触发器执行的SQL语句
    SET NEW.column = value;
END //
DELIMITER ;

-- 删除触发器
DROP TRIGGER [IF EXISTS] trigger_name;

-- 4.7 事件（定时任务）
-- 创建事件
CREATE EVENT event_name
ON SCHEDULE EVERY 1 DAY
STARTS '2023-01-01 00:00:00'
DO
BEGIN
    -- 定时执行的SQL语句
    CALL procedure_name();
END;

-- 启用事件调度器
SET GLOBAL event_scheduler = ON;

-- 删除事件
DROP EVENT [IF EXISTS] event_name;

-- =================================================================================================
-- 五、DCL (Data Control Language) - 数据控制语言
-- =================================================================================================
-- DCL用于控制数据库的访问权限和事务处理

-- 5.1 用户管理
-- 创建用户
CREATE USER 'username'@'host' IDENTIFIED BY 'password';

-- 修改用户密码
ALTER USER 'username'@'host' IDENTIFIED BY 'new_password';
SET PASSWORD FOR 'username'@'host' = PASSWORD('new_password');

-- 删除用户
DROP USER 'username'@'host';

-- 查看用户
SELECT user, host FROM mysql.user;

-- 5.2 权限管理
-- 授予权限
GRANT ALL PRIVILEGES ON database_name.* TO 'username'@'host';
GRANT SELECT, INSERT, UPDATE ON database_name.table_name TO 'username'@'host';
GRANT CREATE, ALTER, DROP ON database_name.* TO 'username'@'host';
GRANT ALL PRIVILEGES ON *.* TO 'username'@'host' WITH GRANT OPTION;

-- 查看权限
SHOW GRANTS FOR 'username'@'host';

-- 撤销权限
REVOKE ALL PRIVILEGES ON database_name.* FROM 'username'@'host';
REVOKE SELECT, INSERT, UPDATE ON database_name.table_name FROM 'username'@'host';
REVOKE GRANT OPTION ON *.* FROM 'username'@'host';

-- 刷新权限
FLUSH PRIVILEGES;

-- 5.3 事务控制
-- 开始事务
START TRANSACTION;
BEGIN;

-- 提交事务
COMMIT;

-- 回滚事务
ROLLBACK;

-- 设置保存点
SAVEPOINT savepoint_name;

-- 回滚到保存点
ROLLBACK TO SAVEPOINT savepoint_name;

-- 释放保存点
RELEASE SAVEPOINT savepoint_name;

-- 设置事务隔离级别
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 5.4 锁表
-- 锁定表
LOCK TABLES table_name READ;
LOCK TABLES table_name WRITE;
LOCK TABLES table1 READ, table2 WRITE;

-- 解锁表
UNLOCK TABLES;

-- =================================================================================================
-- 六、其他常用SQL语句
-- =================================================================================================

-- 6.1 数据导出导入
-- 导出数据
SELECT * FROM table_name
INTO OUTFILE '/path/to/file.csv'
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

-- 导入数据
LOAD DATA INFILE '/path/to/file.csv'
INTO TABLE table_name
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 6.2 数据分析
-- EXPLAIN - 分析查询执行计划
EXPLAIN SELECT * FROM table_name WHERE condition;

-- EXPLAIN ANALYZE - 执行并分析查询（MySQL 8.0+）
EXPLAIN ANALYZE SELECT * FROM table_name WHERE condition;

-- 6.3 表维护
-- 分析表
ANALYZE TABLE table_name;

-- 检查表
CHECK TABLE table_name;

-- 优化表
OPTIMIZE TABLE table_name;

-- 修复表
REPAIR TABLE table_name;

-- 6.4 变量设置
-- 会话变量
SET @variable_name = value;
SELECT @variable_name;

-- 系统变量
SHOW VARIABLES LIKE 'variable_name';
SET GLOBAL variable_name = value;
SET SESSION variable_name = value;

-- 6.5 注释
-- 单行注释
# 单行注释
-- 单行注释

-- 多行注释
/*
多行注释
多行注释
