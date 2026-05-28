# Linux 常用命令大全

## 一、文件和目录操作

### 1.1 目录导航

```bash
# 查看当前所在目录
pwd

# 列出目录内容
ls                  # 简单列出文件
ls -l               # 详细列表（ll）
ls -a               # 显示所有文件（包括隐藏文件）
ls -lh              # 人类可读的文件大小
ls -R               # 递归列出子目录
ls -t               # 按修改时间排序
ls -ltr             # 按时间逆序排列

# 切换目录
cd /path/to/dir     # 进入指定目录
cd ..               # 返回上级目录
cd ~                # 返回家目录
cd -                # 返回上一个目录

# 查看目录结构
tree                # 树状显示目录结构
tree -L 2           # 显示 2 层深度
tree -d             # 只显示目录
```

### 1.2 文件操作

```bash
# 创建文件
touch filename              # 创建空文件
touch file1 file2 file3     # 创建多个文件

# 创建目录
mkdir dirname               # 创建单个目录
mkdir -p dir1/dir2/dir3     # 递归创建多级目录
mkdir dir1 dir2 dir3        # 创建多个目录

# 复制文件/目录
cp source dest              # 复制文件
cp -r source_dir dest_dir   # 递归复制目录
cp -i source dest           # 覆盖前询问
cp -v source dest           # 显示复制过程

# 移动/重命名文件
mv oldname newname          # 重命名
mv file /path/to/dir        # 移动文件
mv -i file dest             # 覆盖前询问
mv -v file dest             # 显示移动过程

# 删除文件/目录
rm filename                 # 删除文件
rm -f filename              # 强制删除，不提示
rm -i filename              # 删除前询问
rm -r dirname               # 递归删除目录
rm -rf dirname              # 强制递归删除（危险！）

# 查看文件内容
cat filename                # 显示整个文件
cat -n filename             # 显示行号
less filename               # 分页查看（可上下翻页）
more filename               # 分页查看（只能向下）
head filename               # 查看前 10 行
head -n 20 filename         # 查看前 20 行
tail filename               # 查看后 10 行
tail -n 20 filename         # 查看后 20 行
tail -f filename            # 实时跟踪文件变化（日志监控）
tail -100f filename         # 实时跟踪最后 100 行
```

### 1.3 查找文件

```bash
# find - 强大的文件查找工具
find /path -name "filename"         # 按文件名查找
find /path -name "*.txt"            # 按通配符查找
find /path -type f                  # 查找文件
find /path -type d                  # 查找目录
find /path -size +100M              # 查找大于 100M 的文件
find /path -size -1M                # 查找小于 1M 的文件
find /path -mtime -7                # 查找 7 天内修改的文件
find /path -mtime +30               # 查找 30 天前修改的文件
find /path -perm 755                # 查找权限为 755 的文件
find /path -user username           # 查找属于某用户的文件
find /path -exec command {} \;      # 对查找结果执行命令

# locate - 快速查找（基于数据库）
locate filename                     # 快速查找文件
updatedb                            # 更新 locate 数据库

# which - 查找可执行文件路径
which command                       # 显示命令的完整路径
which -a command                    # 显示所有匹配的路径

# whereis - 查找二进制、源码和手册页
whereis command                     # 查找命令的相关文件
```

## 二、文件权限管理

### 2.1 查看权限

```bash
ls -l filename                      # 查看文件权限
ls -ld dirname                      # 查看目录权限
stat filename                       # 查看详细信息
```

### 2.2 修改权限

```bash
# chmod - 修改文件权限
chmod 755 filename                  # 数字方式设置权限
chmod +x filename                   # 添加执行权限
chmod -x filename                   # 移除执行权限
chmod u+x filename                  # 给所有者添加执行权限
chmod g+w filename                  # 给组添加写权限
chmod o-w filename                  # 移除其他人的写权限
chmod a+r filename                  # 给所有人添加读权限
chmod -R 755 dirname                # 递归修改目录权限

# 权限数字说明：
# 4 = read (r)
# 2 = write (w)
# 1 = execute (x)
# 755 = rwxr-xr-x
# 644 = rw-r--r--
```

### 2.3 修改所有者

```bash
# chown - 修改文件所有者
chown user filename                 # 修改所有者
chown user:group filename           # 修改所有者和组
chown -R user:group dirname         # 递归修改

# chgrp - 修改文件所属组
chgrp group filename                # 修改所属组
chgrp -R group dirname              # 递归修改
```

## 三、文本处理

### 3.1 grep - 文本搜索

```bash
grep "pattern" filename             # 搜索包含 pattern 的行
grep -i "pattern" filename          # 忽略大小写
grep -v "pattern" filename          # 反向匹配
grep -n "pattern" filename          # 显示行号
grep -c "pattern" filename          # 统计匹配行数
grep -r "pattern" /path             # 递归搜索
grep -l "pattern" *.txt             # 只显示文件名
grep -E "pattern1|pattern2" file    # 扩展正则表达式
grep -w "word" filename             # 匹配整个单词
grep -A 3 "pattern" file            # 显示匹配行及后 3 行
grep -B 3 "pattern" file            # 显示匹配行及前 3 行
grep -C 3 "pattern" file            # 显示匹配行及前后 3 行
```

### 3.2 sed - 流编辑器

```bash
# 替换操作
sed 's/old/new/' file               # 替换每行第一个匹配
sed 's/old/new/g' file              # 替换所有匹配
sed -i 's/old/new/g' file           # 直接修改文件
sed '1,10s/old/new/g' file          # 替换 1-10 行

# 删除操作
sed '2d' file                       # 删除第 2 行
sed '1,5d' file                     # 删除 1-5 行
sed '/pattern/d' file               # 删除匹配行
sed '/^$/d' file                    # 删除空行

# 插入和追加
sed '2i\new line' file              # 在第 2 行前插入
sed '2a\new line' file              # 在第 2 行后追加
```

### 3.3 awk - 文本分析

```bash
# 基本用法
awk '{print $0}' file               # 打印所有行
awk '{print $1}' file               # 打印第一列
awk '{print $1, $3}' file           # 打印第 1 和 3 列
awk -F: '{print $1}' /etc/passwd    # 指定分隔符

# 条件过滤
awk '$1 > 100' file                 # 第一列大于 100 的行
awk '/pattern/ {print $0}' file     # 匹配 pattern 的行
awk 'NR==1 {print}' file            # 打印第一行
awk 'NR>1 && NR<10' file            # 打印 2-9 行

# 内置变量
awk '{print NR, $0}' file           # 显示行号和内容
awk 'END {print NR}' file           # 统计总行数
awk '{sum+=$1} END {print sum}' file  # 求和
```

### 3.4 cut - 列切割

```bash
cut -d: -f1 /etc/passwd             # 以:分隔，取第 1 列
cut -d: -f1,3 /etc/passwd           # 取第 1 和 3 列
cut -d: -f1-3 /etc/passwd           # 取第 1 到 3 列
cut -c1-5 file                      # 取每行前 5 个字符
```

### 3.5 sort - 排序

```bash
sort file                           # 基本排序
sort -r file                        # 逆序排序
sort -n file                        # 数值排序
sort -t: -k3 -n /etc/passwd         # 指定分隔符和排序列
sort -u file                        # 去重排序
sort -o output file                 # 输出到文件
```

### 3.6 uniq - 去重

```bash
uniq file                           # 去除相邻重复行
sort file | uniq                    # 完全去重
uniq -c file                        # 显示重复次数
uniq -d file                        # 只显示重复行
uniq -u file                        # 只显示不重复行
```

### 3.7 wc - 统计

```bash
wc file                             # 统计行数、词数、字节数
wc -l file                          # 只统计行数
wc -w file                          # 只统计词数
wc -c file                          # 只统计字节数
wc -m file                          # 只统计字符数
```

## 四、压缩和归档

### 4.1 tar - 打包压缩

```bash
# 创建压缩包
tar -cvf archive.tar file1 file2    # 只打包不压缩
tar -czvf archive.tar.gz file1      # gzip 压缩
tar -cjvf archive.tar.bz2 file1     # bzip2 压缩
tar -cJvf archive.tar.xz file1      # xz 压缩

# 解压压缩包
tar -xvf archive.tar                # 解压 tar
tar -xzvf archive.tar.gz            # 解压 tar.gz
tar -xjvf archive.tar.bz2           # 解压 tar.bz2
tar -xJvf archive.tar.xz            # 解压 tar.xz

# 查看压缩包内容
tar -tvf archive.tar                # 查看 tar 包内容
tar -tzvf archive.tar.gz            # 查看 tar.gz 内容

# 解压到指定目录
tar -xzvf archive.tar.gz -C /path   # 解压到指定目录

# 参数说明：
# -c: 创建新的归档文件
# -x: 从归档文件中提取文件
# -v: 显示详细过程
# -f: 指定归档文件名
# -z: 使用 gzip 压缩/解压
# -j: 使用 bzip2 压缩/解压
# -J: 使用 xz 压缩/解压
# -t: 查看归档内容
```

### 4.2 gzip - gzip 压缩

```bash
gzip filename                       # 压缩文件（生成.gz）
gzip -d filename.gz                 # 解压文件
gzip -9 filename                    # 最高压缩比
gzip -r dirname                     # 递归压缩目录
```

### 4.3 zip/unzip - zip 压缩

```bash
# 压缩
zip archive.zip file1 file2         # 压缩文件
zip -r archive.zip dirname          # 递归压缩目录
zip -9 archive.zip file             # 最高压缩比

# 解压
unzip archive.zip                   # 解压到当前目录
unzip archive.zip -d /path          # 解压到指定目录
unzip -l archive.zip                # 查看压缩包内容
unzip -o archive.zip                # 覆盖已有文件
```

## 五、系统信息

### 5.1 系统基本信息

```bash
uname -a                            # 显示所有系统信息
uname -r                            # 显示内核版本
uname -n                            # 显示主机名
hostname                            # 显示/设置主机名
uptime                              # 显示系统运行时间
date                                # 显示/设置日期时间
cal                                 # 显示日历
```

### 5.2 硬件信息

```bash
lscpu                               # 显示 CPU 信息
free -h                             # 显示内存使用（人类可读）
free -m                             # 显示内存使用（MB）
df -h                               # 显示磁盘空间（人类可读）
df -i                               # 显示 inode 使用情况
du -sh dirname                      # 显示目录总大小
du -h --max-depth=1 dirname         # 显示一级子目录大小
du -ah | sort -rh | head -10        # 显示最大的 10 个文件
lsblk                               # 显示块设备信息
fdisk -l                            # 显示磁盘分区
```

### 5.3 进程信息

```bash
ps aux                              # 显示所有进程
ps -ef                              # 显示所有进程（另一种格式）
ps aux | grep process_name          # 查找特定进程
top                                 # 实时显示进程状态
htop                                # top 的增强版
pstree                              # 树状显示进程
pgrep process_name                  # 查找进程 PID
```

### 5.4 系统负载

```bash
w                                   # 显示登录用户和负载
who                                 # 显示登录用户
last                                # 显示最近登录记录
dmesg                               # 显示启动信息
vmstat 1                            # 每秒显示系统状态
iostat -x 1                         # 每秒显示 IO 状态
netstat -tuln                       # 显示监听端口
ss -tuln                            # netstat 的替代工具
```

## 六、网络命令

### 6.1 网络配置

```bash
ip addr                             # 显示 IP 地址（推荐）
ifconfig                            # 显示网络接口（旧版）
ip route                            # 显示路由表
route -n                            # 显示路由表（旧版）
ip link                             # 显示网络接口状态
netstat -i                          # 显示网络接口统计
```

### 6.2 网络测试

```bash
ping hostname                       # 测试网络连通性
ping -c 4 hostname                  # 发送 4 个包
traceroute hostname                 # 跟踪路由路径
tracepath hostname                  # 跟踪路径（无需 root）
mtr hostname                        # 结合 ping 和 traceroute
nslookup domain                     # DNS 查询
dig domain                          # DNS 查询（更详细）
host domain                         # DNS 查询（简洁）
```

### 6.3 网络下载

```bash
wget url                            # 下载文件
wget -O filename url                # 下载并重命名
wget -c url                         # 断点续传
wget -r url                         # 递归下载

curl url                            # 传输数据
curl -O url                         # 下载文件
curl -o filename url                # 下载并重命名
curl -I url                         # 只显示响应头
curl -X POST -d "data" url          # POST 请求
```

### 6.4 端口和连接

```bash
netstat -tuln                       # 显示监听端口
netstat -an | grep ESTABLISHED      # 显示已建立的连接
ss -tuln                            # 显示监听端口（更快）
lsof -i :80                         # 查看 80 端口的进程
lsof -i                             # 显示所有网络连接
```

### 6.5 防火墙

```bash
# iptables（旧版）
iptables -L                         # 查看规则
iptables -L -n -v                   # 详细查看
iptables -A INPUT -p tcp --dport 80 -j ACCEPT  # 允许 80 端口

# firewalld（CentOS 7+）
firewall-cmd --list-all             # 查看所有规则
firewall-cmd --add-port=80/tcp      # 添加端口
firewall-cmd --reload               # 重载规则

# ufw（Ubuntu）
ufw status                          # 查看状态
ufw allow 80                        # 允许 80 端口
ufw enable                          # 启用防火墙
```

## 七、用户和组管理

### 7.1 用户管理

```bash
# 查看用户
whoami                              # 显示当前用户
id                                  # 显示用户 ID 和组 ID
id username                         # 显示指定用户信息
w                                   # 显示登录用户
who                                 # 显示登录用户
last                                # 显示登录历史

# 添加/删除用户
useradd username                    # 创建用户
useradd -m username                 # 创建用户并创建家目录
useradd -s /bin/bash username       # 指定 shell
useradd -G sudo username            # 添加到 sudo 组
userdel username                    # 删除用户
userdel -r username                 # 删除用户及家目录

# 修改用户
usermod -aG groupname username      # 添加到组
usermod -s /bin/bash username       # 修改 shell
usermod -L username                 # 锁定用户
usermod -U username                 # 解锁用户

# 密码管理
passwd username                     # 修改用户密码
passwd -d username                  # 删除密码
passwd -l username                  # 锁定密码
passwd -u username                  # 解锁密码
```

### 7.2 组管理

```bash
# 查看组
groups                              # 显示当前用户所在组
groups username                     # 显示用户所在组
getent group                        # 查看所有组
getent group groupname              # 查看指定组

# 添加/删除组
groupadd groupname                  # 创建组
groupdel groupname                  # 删除组

# 修改组
groupmod -n newname oldname         # 重命名组
gpasswd -a user group               # 添加用户到组
gpasswd -d user group               # 从组中删除用户
```

### 7.3 切换用户

```bash
su - username                       # 切换到其他用户
su -                                # 切换到 root
sudo command                        # 以 root 权限执行命令
sudo -i                             # 切换到 root shell
sudo -u user command                # 以指定用户执行
```

## 八、软件包管理

### 8.1 CentOS/RHEL (yum/dnf)

```bash
# yum（CentOS 7 及之前）
yum install package                 # 安装包
yum remove package                  # 卸载包
yum update package                  # 更新包
yum search keyword                  # 搜索包
yum info package                    # 查看包信息
yum list installed                  # 列出已安装包
yum clean all                       # 清理缓存

# dnf（CentOS 8+）
dnf install package                 # 安装包
dnf remove package                  # 卸载包
dnf update                          # 更新所有包
dnf search keyword                  # 搜索包
dnf info package                    # 查看包信息
dnf list installed                  # 列出已安装包
dnf clean all                       # 清理缓存
```

### 8.2 Ubuntu/Debian (apt)

```bash
apt update                          # 更新包索引
apt upgrade                         # 更新所有包
apt install package                 # 安装包
apt remove package                  # 卸载包
apt purge package                   # 卸载包并删除配置
apt search keyword                  # 搜索包
apt show package                    # 查看包信息
apt list --installed                # 列出已安装包
apt autoremove                      # 删除不需要的包
apt clean                           # 清理缓存
```

### 8.3 源码编译安装

```bash
./configure                         # 配置编译选项
make                                # 编译
make install                        # 安装
make uninstall                      # 卸载
```

## 九、服务管理

### 9.1 systemd（CentOS 7+/Ubuntu 16.04+）

```bash
systemctl start service             # 启动服务
systemctl stop service              # 停止服务
systemctl restart service           # 重启服务
systemctl reload service            # 重载配置
systemctl status service            # 查看服务状态
systemctl enable service            # 开机自启
systemctl disable service           # 禁用开机自启
systemctl is-enabled service        # 检查是否开机自启
systemctl list-units --type=service # 列出所有服务
systemctl daemon-reload             # 重载 systemd 配置
```

### 9.2 service（旧版）

```bash
service name start                  # 启动服务
service name stop                   # 停止服务
service name restart                # 重启服务
service name status                 # 查看状态
service name reload                 # 重载配置
```

### 9.3  chkconfig（旧版）

```bash
chkconfig --list                    # 列出所有服务
chkconfig name on                   # 启用开机自启
chkconfig name off                  # 禁用开机自启
chkconfig --level 35 name on        # 指定运行级别
```

## 十、磁盘管理

### 10.1 磁盘查看

```bash
df -h                               # 查看磁盘使用情况
df -i                               # 查看 inode 使用
du -sh dirname                      # 查看目录大小
du -ah | sort -rh | head -20        # 查看最大的 20 个文件
lsblk                               # 查看块设备
fdisk -l                            # 查看磁盘分区
parted -l                           # 查看分区表
```

### 10.2 磁盘挂载

```bash
mount                               # 查看所有挂载
mount /dev/sdb1 /mnt                # 挂载设备
umount /mnt                         # 卸载设备
umount /dev/sdb1                    # 卸载设备
mount -a                            # 挂载 fstab 中所有设备
blkid                               # 查看设备 UUID
```

### 10.3 磁盘格式化

```bash
mkfs.ext4 /dev/sdb1                 # 格式化为 ext4
mkfs.xfs /dev/sdb1                  # 格式化为 xfs
mkfs.vfat /dev/sdb1                 # 格式化为 fat32
mkswap /dev/sdb1                    # 创建 swap 分区
swapon /dev/sdb1                    # 启用 swap
swapoff /dev/sdb1                   # 禁用 swap
```

### 10.4 磁盘检查

```bash
fsck /dev/sdb1                      # 检查并修复文件系统
fsck -y /dev/sdb1                   # 自动修复
badblocks -s /dev/sdb1              # 检查坏道
smartctl -a /dev/sda                # 查看 SMART 信息
```

## 十一、性能监控

### 11.1 CPU 监控

```bash
top                                 # 实时进程监控
htop                                # top 增强版
mpstat 1                            # 每秒显示 CPU 统计
vmstat 1                            # 每秒显示系统状态
sar -u 1 3                          # 收集 CPU 信息
```

### 11.2 内存监控

```bash
free -h                             # 内存使用
vmstat 1                            # 虚拟内存统计
sar -r 1 3                          # 收集内存信息
```

### 11.3 磁盘 IO 监控

```bash
iostat -x 1                         # 每秒显示 IO 统计
iotop                               # IO 监控（类似 top）
dstat                               # 综合统计工具
```

### 11.4 网络监控

```bash
iftop                               # 网络流量监控
nethogs                             # 按进程显示网络使用
sar -n DEV 1 3                      # 收集网络统计
```

## 十二、日志管理

### 12.1 查看日志

```bash
# 系统日志
tail -f /var/log/messages           # 系统消息（CentOS）
tail -f /var/log/syslog             # 系统日志（Ubuntu）
tail -f /var/log/secure             # 安全日志（CentOS）
tail -f /var/log/auth.log           # 认证日志（Ubuntu）

# 服务日志
tail -f /var/log/nginx/error.log    # Nginx 错误日志
tail -f /var/log/httpd/error_log    # Apache 错误日志
tail -f /var/log/mysql/error.log    # MySQL 错误日志

# journalctl（systemd 系统）
journalctl                          # 查看所有日志
journalctl -f                       # 实时跟踪日志
journalctl -u service               # 查看服务日志
journalctl -xe                      # 查看详细错误
journalctl --since "2024-01-01"     # 查看指定时间后的日志
journalctl --since "1 hour ago"     # 查看 1 小时内的日志
```

### 12.2 日志轮转

```bash
logrotate -f /etc/logrotate.conf    # 强制轮转日志
logrotate -d /etc/logrotate.conf    # 调试模式
```

## 十三、常用快捷键

### 13.1 命令行编辑

```bash
Ctrl + A        # 移动到行首
Ctrl + E        # 移动到行尾
Ctrl + U        # 删除到行首
Ctrl + K        # 删除到行尾
Ctrl + W        # 删除前一个单词
Ctrl + L        # 清屏
Ctrl + C        # 终止当前命令
Ctrl + Z        # 挂起进程
Ctrl + D        # 退出 shell
Ctrl + R        # 搜索历史命令
!!              # 执行上一条命令
!$              # 上一条命令的最后一个参数
```

### 13.2 命令历史

```bash
history                           # 显示历史命令
history 100                       # 显示最近 100 条
!123                              # 执行第 123 条历史命令
!:gs/old/new/                     # 替换上一条命令
Ctrl + R                          # 搜索历史
Ctrl + G                          # 退出搜索
```

## 十四、其他实用命令

### 14.1 别名

```bash
alias                               # 显示所有别名
alias ll='ls -l'                    # 创建别名
unalias ll                          # 删除别名
```

### 14.2 后台任务

```bash
command &                           # 后台运行
jobs                                # 查看后台任务
fg %1                               # 将任务 1 调到前台
bg %1                               # 将任务 1 在后台运行
kill %1                             # 杀死后台任务 1
```

### 14.3 计划任务

```bash
# cron
crontab -e                          # 编辑定时任务
crontab -l                          # 查看定时任务
crontab -r                          # 删除定时任务

# at
at now + 5 minutes                  # 5 分钟后执行
at -l                               # 查看待执行任务
```

### 14.4 管道和重定向

```bash
command1 | command2                 # 管道
command > file                      # 标准输出重定向（覆盖）
command >> file                     # 标准输出重定向（追加）
command 2> file                     # 标准错误重定向
command > file 2>&1                 # 所有输出重定向
command < file                      # 标准输入重定向
```

### 14.5 其他

```bash
which command                       # 显示命令路径
man command                         # 查看帮助文档
command --help                      # 查看简要帮助
type command                        # 显示命令类型
echo $PATH                          # 显示 PATH 环境变量
export VAR=value                    # 设置环境变量
source file                         # 执行脚本并影响当前 shell
```

## 十五、实战示例

### 15.1 日志分析

```bash
# 统计访问最多的 IP
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10

# 统计 404 错误
grep "404" access.log | wc -l

# 统计每小时访问量
awk -F: '{print $2}' access.log | cut -d' ' -f1 | sort | uniq -c
```

### 15.2 文件批量操作

```bash
# 批量修改文件扩展名
for file in *.txt; do mv "$file" "${file%.txt}.md"; done

# 批量删除空文件
find . -type f -empty -delete

# 查找并删除 30 天前的日志
find /var/log -name "*.log" -mtime +30 -delete
```

### 15.3 系统监控脚本

```bash
#!/bin/bash
echo "=== 系统信息 ==="
uname -a
echo ""
echo "=== CPU 使用率 ==="
top -bn1 | grep "Cpu(s)"
echo ""
echo "=== 内存使用率 ==="
free -h
echo ""
echo "=== 磁盘使用率 ==="
df -h
```

---

**提示**：
- 使用 `man command` 查看命令的详细手册
- 使用 `command --help` 查看简要帮助
- 危险操作（如 rm -rf）前务必确认
- 生产环境执行重要操作前先测试
