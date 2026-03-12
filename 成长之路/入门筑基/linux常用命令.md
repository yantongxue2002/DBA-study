# Linux常用命令大全

## 目录
- [系统信息](#系统信息)
- [文件和目录操作](#文件和目录操作)
- [文件查看和编辑](#文件查看和编辑)
- [文件权限和属性](#文件权限和属性)
- [进程管理](#进程管理)
- [网络相关](#网络相关)
- [磁盘和存储](#磁盘和存储)
- [用户和组管理](#用户和组管理)
- [压缩和解压](#压缩和解压)
- [文本处理](#文本处理)
- [系统监控](#系统监控)
- [软件包管理](#软件包管理)
- [定时任务](#定时任务)
- [Shell脚本相关](#shell脚本相关)

## 系统信息

### 基本系统信息
```bash
# 查看内核版本
uname -a

# 查看操作系统版本
cat /etc/os-release
lsb_release -a  # Ubuntu/Debian
cat /etc/redhat-release  # RHEL/CentOS

# 查看主机名
hostname
hostnamectl

# 查看系统启动时间
uptime

# 查看系统架构
arch
getconf LONG_BIT  # 查看系统位数

# 查看CPU信息
lscpu
cat /proc/cpuinfo

# 查看内存信息
free -h
cat /proc/meminfo

# 查看系统负载
top
htop  # 需要安装
```

### 硬件信息
```bash
# 查看PCI设备
lspci

# 查看USB设备
lsusb

# 查看硬盘信息
lsblk
fdisk -l
df -h

# 查看网络接口
ip addr show
ifconfig  # 较老的命令
```

## 文件和目录操作

### 基本操作
```bash
# 列出目录内容
ls
ls -l          # 详细信息
ls -a          # 显示隐藏文件
ls -lh         # 人性化显示文件大小
ls -lt         # 按修改时间排序
ls -lrth       # 组合使用

# 切换目录
cd /path/to/directory
cd ..          # 返回上一级
cd ~           # 返回家目录
cd -           # 返回上次目录

# 创建目录
mkdir directory_name
mkdir -p path/to/directory  # 递归创建

# 删除目录
rmdir directory_name        # 删除空目录
rm -rf directory_name       # 强制递归删除

# 创建文件
touch filename
echo "content" > filename

# 复制文件/目录
cp source destination
cp -r source_directory destination_directory  # 递归复制
cp -i source destination                      # 交互式（覆盖前询问）

# 移动/重命名文件
mv old_name new_name
mv file /path/to/destination

# 删除文件
rm filename
rm -f filename              # 强制删除
rm -i filename              # 交互式删除
```

### 文件查找
```bash
# 查找文件
find /path -name "filename"
find . -type f -name "*.txt"    # 查找当前目录下所有.txt文件
find . -mtime -7                # 查找7天内修改的文件
find . -size +100M              # 查找大于100MB的文件

# 快速查找（需要updatedb）
locate filename

# 在文件中搜索内容
grep "pattern" filename
grep -r "pattern" /path         # 递归搜索
grep -i "pattern" filename      # 忽略大小写
grep -v "pattern" filename      # 反向匹配
grep -n "pattern" filename      # 显示行号
```

## 文件查看和编辑

### 查看文件
```bash
# 查看整个文件
cat filename

# 分页查看
less filename
more filename

# 查看文件开头/结尾
head filename           # 默认前10行
head -n 20 filename     # 前20行
tail filename           # 默认后10行
tail -n 20 filename     # 后20行
tail -f filename        # 实时跟踪文件变化（常用于日志）

# 查看文件类型
file filename

# 查看二进制文件
hexdump -C filename
xxd filename
```

### 编辑文件
```bash
# 使用vim编辑
vim filename

# 使用nano编辑（更简单）
nano filename

# 使用sed进行流编辑
sed 's/old/new/g' filename          # 替换
sed -i 's/old/new/g' filename       # 直接修改文件
```

## 文件权限和属性

### 权限管理
```bash
# 查看文件权限
ls -l filename

# 修改文件权限
chmod 755 filename                  # 数字模式
chmod u+x,g+w,o-r filename          # 符号模式
chmod -R 755 directory              # 递归修改

# 修改文件所有者
chown user:group filename
chown -R user:group directory

# 修改文件所属组
chgrp group filename
```

### 特殊权限
```bash
# 设置SUID（4）
chmod 4755 filename     # 执行时以文件所有者身份运行

# 设置SGID（2）
chmod 2755 directory    # 在此目录创建的文件继承目录的组

# 设置sticky bit（1）
chmod 1755 directory    # 只有文件所有者才能删除文件
```

## 进程管理

### 查看进程
```bash
# 查看所有进程
ps aux
ps -ef

# 实时查看进程
top
htop

# 查看进程树
pstree

# 根据名称查找进程
pgrep process_name
pidof process_name
```

### 控制进程
```bash
# 终止进程
kill PID
kill -9 PID             # 强制终止
killall process_name    # 根据名称终止

# 后台运行
command &               # 后台运行
nohup command &         # 后台运行且忽略挂起信号

# 作业控制
jobs                    # 查看后台作业
fg %job_number          # 将作业移到前台
bg %job_number          # 继续后台运行

# 进程优先级
nice -n 10 command      # 以较低优先级运行
renice -n 5 PID         # 修改现有进程优先级
```

## 网络相关

### 网络配置
```bash
# 查看网络接口
ip addr show
ifconfig

# 查看路由表
ip route show
route -n

# 查看网络连接
netstat -tuln
ss -tuln                # 更现代的替代品

# 测试网络连通性
ping hostname
ping -c 4 hostname      # 发送4个包后停止

# 跟踪路由
traceroute hostname
mtr hostname            # 结合ping和traceroute
```

### 网络工具
```bash
# DNS查询
nslookup hostname
dig hostname
host hostname

# 下载文件
wget url
curl url

# 端口扫描
nmap hostname

# 网络抓包
tcpdump -i interface
```

### 防火墙
```bash
# iptables（传统）
iptables -L             # 查看规则
iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# firewalld（现代）
firewall-cmd --list-all
firewall-cmd --add-port=80/tcp --permanent
```

## 磁盘和存储

### 磁盘信息
```bash
# 查看磁盘使用情况
df -h
du -sh /path            # 查看目录大小
du -h --max-depth=1     # 查看当前目录下各子目录大小

# 查看分区信息
fdisk -l
lsblk

# 挂载/卸载
mount /dev/sda1 /mnt
umount /mnt
```

### 磁盘管理
```bash
# 创建文件系统
mkfs.ext4 /dev/sda1

# 检查文件系统
fsck /dev/sda1

# 调整分区大小
resize2fs /dev/sda1

# 创建交换分区
mkswap /dev/sda2
swapon /dev/sda2
```

## 用户和组管理

### 用户管理
```bash
# 创建用户
useradd username
adduser username        # 交互式（Debian系）

# 设置密码
passwd username

# 删除用户
userdel username
userdel -r username     # 同时删除家目录

# 修改用户信息
usermod -aG groupname username  # 添加到组
```

### 组管理
```bash
# 创建组
groupadd groupname

# 删除组
groupdel groupname

# 修改组
groupmod -n newname oldname
```

### 用户信息
```bash
# 查看当前用户
whoami
id

# 查看登录用户
who
w

# 查看用户列表
cat /etc/passwd
getent passwd
```

## 压缩和解压

### tar命令
```bash
# 创建压缩包
tar -czvf archive.tar.gz directory/      # gzip压缩
tar -cjvf archive.tar.bz2 directory/     # bzip2压缩
tar -cJvf archive.tar.xz directory/      # xz压缩

# 解压
tar -xzvf archive.tar.gz                 # 解压gzip
tar -xjvf archive.tar.bz2                # 解压bzip2
tar -xJvf archive.tar.xz                 # 解压xz

# 查看压缩包内容
tar -tzvf archive.tar.gz
```

### 其他压缩格式
```bash
# zip/unzip
zip -r archive.zip directory/
unzip archive.zip

# gzip/gunzip
gzip file
gunzip file.gz

# bzip2/bunzip2
bzip2 file
bunzip2 file.bz2
```

## 文本处理

### 文本操作
```bash
# 排序
sort filename

# 去重
uniq filename

# 统计
wc filename             # 行数、单词数、字符数
wc -l filename          # 只统计行数

# 切割文本
cut -d':' -f1 /etc/passwd   # 以:分隔，取第1字段
awk -F':' '{print $1}' /etc/passwd

# 合并文件
paste file1 file2
join file1 file2
```

### 流编辑
```bash
# sed示例
sed 's/old/new/g' file          # 全局替换
sed '1,10d' file                # 删除1-10行
sed -n '5p' file                # 打印第5行

# awk示例
awk '{print $1}' file           # 打印第一列
awk '$3 > 100 {print $0}' file  # 条件打印
```

## 系统监控

### 性能监控
```bash
# CPU和内存
top
htop
vmstat 1                        # 每秒更新
iostat 1                        # I/O统计

# 内存详细信息
free -h
cat /proc/meminfo

# 磁盘I/O
iotop                           # 需要安装
iostat -x 1

# 网络监控
iftop                           # 需要安装
nethogs                         # 按进程显示网络使用
```

### 日志查看
```bash
# 系统日志
journalctl                      # systemd日志
journalctl -u service_name      # 查看特定服务日志
journalctl -f                   # 实时跟踪

# 传统日志
tail -f /var/log/messages
tail -f /var/log/syslog
```

## 软件包管理

### Debian/Ubuntu (APT)
```bash
# 更新包列表
apt update

# 升级已安装的包
apt upgrade
apt full-upgrade

# 安装/删除包
apt install package_name
apt remove package_name
apt purge package_name          # 完全删除（包括配置）

# 搜索包
apt search keyword

# 查看包信息
apt show package_name
```

### RHEL/CentOS (YUM/DNF)
```bash
# 更新
yum update
dnf update                      # CentOS 8+

# 安装/删除
yum install package_name
yum remove package_name

# 搜索
yum search keyword

# 查看包信息
yum info package_name
```

## 定时任务

### crontab
```bash
# 编辑定时任务
crontab -e

# 查看定时任务
crontab -l

# 删除定时任务
crontab -r

# crontab格式：分 时 日 月 周 命令
# 示例：
# 0 2 * * * /backup.sh        # 每天凌晨2点执行
# */5 * * * * /check.sh       # 每5分钟执行一次
```

### at命令（一次性任务）
```bash
# 执行一次性任务
at 2:00 PM tomorrow
at> echo "Hello" > /tmp/test
at> <Ctrl+D>

# 查看待执行任务
atq

# 删除任务
atrm job_number
```

## Shell脚本相关

### 变量和环境
```bash
# 查看环境变量
env
printenv

# 设置环境变量
export VAR=value

# 查看Shell变量
set

# 特殊变量
$$          # 当前进程PID
$?          # 上一条命令退出状态
$0          # 脚本名称
$1, $2...   # 参数
$#          # 参数个数
$*          # 所有参数
```

### 条件判断
```bash
# 文件测试
[ -f file ]     # 文件存在且为普通文件
[ -d dir ]      # 目录存在
[ -r file ]     # 文件可读
[ -w file ]     # 文件可写
[ -x file ]     # 文件可执行

# 字符串比较
[ "$str1" = "$str2" ]   # 相等
[ "$str1" != "$str2" ]  # 不相等
[ -z "$str" ]           # 字符串为空
[ -n "$str" ]           # 字符串非空

# 数值比较
[ $num1 -eq $num2 ]     # 等于
[ $num1 -ne $num2 ]     # 不等于
[ $num1 -gt $num2 ]     # 大于
[ $num1 -lt $num2 ]     # 小于
```

### 常用快捷键
```bash
Ctrl+C      # 终止当前命令
Ctrl+Z      # 挂起当前命令
Ctrl+D      # 退出当前Shell（EOF）
Ctrl+A      # 移动到行首
Ctrl+E      # 移动到行尾
Ctrl+U      # 删除从光标到行首的内容
Ctrl+K      # 删除从光标到行尾的内容
Ctrl+R      # 历史命令搜索
Tab         # 自动补全
```

## 实用技巧

### 命令组合
```bash
# 管道
command1 | command2

# 重定向
command > file          # 输出重定向（覆盖）
command >> file         # 输出重定向（追加）
command 2> file         # 错误重定向
command &> file         # 标准输出和错误都重定向

# 后台执行
command &
nohup command &         # 忽略挂起信号

# 条件执行
command1 && command2    # command1成功才执行command2
command1 || command2    # command1失败才执行command2
```

### 历史命令
```bash
history                 # 查看历史命令
!number                 # 执行历史命令编号
!!                      # 执行上一条命令
!string                 # 执行最近以string开头的命令
```

### 别名设置
```bash
# 临时别名
alias ll='ls -l'
alias la='ls -la'

# 永久别名（添加到~/.bashrc）
echo "alias ll='ls -l'" >> ~/.bashrc
source ~/.bashrc
```

## 数据库相关命令（DBA专用）

### MySQL/MariaDB
```bash
# 连接数据库
mysql -u username -p
mysql -h hostname -u username -p database_name

# 备份数据库
mysqldump -u username -p database_name > backup.sql
mysqldump -u username -p --all-databases > all_backup.sql

# 恢复数据库
mysql -u username -p database_name < backup.sql

# 查看MySQL状态
mysqladmin -u username -p status
mysqladmin -u username -p processlist
```

### PostgreSQL
```bash
# 连接数据库
psql -U username -d database_name

# 备份
pg_dump -U username database_name > backup.sql
pg_dumpall -U username > all_backup.sql

# 恢复
psql -U username -d database_name < backup.sql
```

### Redis
```bash
# 连接Redis
redis-cli
redis-cli -h hostname -p port

# 基本操作
redis-cli ping
redis-cli info
redis-cli keys "*"
```

## 故障排查常用命令

### 系统问题
```bash
# 查看系统日志
dmesg | tail -20
journalctl -xe

# 检查磁盘空间
df -h
du -sh /var/log/*

# 检查内存使用
free -h
cat /proc/meminfo

# 检查CPU负载
uptime
top
```

### 网络问题
```bash
# 检查端口监听
netstat -tulnp
ss -tulnp

# 检查防火墙
iptables -L
firewall-cmd --list-all

# 测试DNS解析
nslookup google.com
dig google.com
```

### 进程问题
```bash
# 查找占用资源最多的进程
ps aux --sort=-%cpu | head -10
ps aux --sort=-%mem | head -10

# 查看进程打开的文件
lsof -p PID
lsof /path/to/file

# 查看进程的网络连接
lsof -i -P -n | grep :port
```

---
**注意：**
- 在生产环境中执行删除、修改等危险操作前，请务必确认命令的正确性
- 使用 `man command` 可以查看任何命令的详细帮助文档
- 不同Linux发行版可能有些命令的选项略有差异
- 建议在执行重要操作前先在测试环境中验证