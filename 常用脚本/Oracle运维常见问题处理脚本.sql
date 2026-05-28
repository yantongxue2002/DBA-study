-- 一、启动数据库
-- 1.1 启动监听器
lsnrctl START
-- 1.2 重启数据库
sqlplus / as sysdba
STARTUP;
-- 1.3 查看状态
SELECT status FROM v$instance;