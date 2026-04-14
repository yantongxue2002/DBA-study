--- 本文就是简单记录一下自己的sqlserver学习之路用的命令
```bash
# 查看系统信息
cat /etc/*-release
# 查看版本
cat /proc/version
# 查看文件系统
df -Th
# 查看CPU
lscpu
# 查看内存
free -h
```
--- 修改主机IP
vi /etc/sysconfig/network-scripts/ifcfg-ens33
BOOTPROTO=static
ONBOOT=yes
IPADDR=192.168.1.100
NETMASK=255.255.255.0
GATEWAY=192.168.1.2
DNS1=114.114.114.114
DNS2=8.8.8.8

--- 重启网络服务
systemctl restart NetworkManager
--- 修改主机名
vi /etc/hostname
--- 重启主机
reboot

--- 安装sqlserver


-- 备份事务日志，确保日志文件不会无限增长
BACKUP LOG [MOM]
TO DISK = N'D:\SQL_Backup\Log\MOM_log_20260407.trn'
WITH
    INIT,
    NAME = N'MOM-Transaction Log Backup',
    STATS = 10;
GO

-- 备份自上次完整备份后变化的数据
BACKUP DATABASE [MOM]
TO DISK = N'D:\SQL_Backup\Diff\MOM_diff_20260407.bak'
WITH
    DIFFERENTIAL,   -- 指定为差异备份
    INIT,
    NAME = N'MOM-Differential Backup',
    STATS = 10;
GO

-- 备份整个 WMS 数据库到指定路径
BACKUP DATABASE [WMS]
TO DISK = N'D:\SQL_Backup\Full\WMS_full_20260407.bak'
WITH
    INIT,           -- 覆盖同名文件
    NAME = N'WMS-Full Database Backup',
    STATS = 10;     -- 每完成10%显示一次进度
GO
