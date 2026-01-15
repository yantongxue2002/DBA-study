-- 这里记录常见的sql语法，包括DML/DQL/DDL/DQL

-- DML: 数据操作语言，用于对数据库中的数据进行增删改查
-- DQL: 数据查询语言，用于从数据库中查询数据
-- DDL: 数据定义语言，用于创建和删除数据库对象，如表、索引等
-- DCL: 数据控制语言，用于控制数据库的访问权限


-- DML  
DELETE [LOW_PRIORITY] [QUICK] [IGNORE] FROM tbl_name [[AS] tbl_alias]
    [PARTITION (partition_name [, partition_name] ...)]
    [WHERE where_condition]
    [ORDER BY ...]
    [LIMIT row_count]

-- DQL