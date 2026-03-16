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
