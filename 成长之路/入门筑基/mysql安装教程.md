# MySQL 8.0 全平台安装教程

本文详细介绍 MySQL 8.0 在 Windows、Linux 环境下的多种安装方式，包括二进制包、源码编译及 RPM 包安装。

## 一、 Windows 环境安装

### 1. MSI Installer 图形化安装 (适合新手)
**步骤：**
1.  **下载**：访问 [MySQL官网](https://dev.mysql.com/downloads/installer/) 下载 `mysql-installer-community-8.0.x.msi`。
2.  **运行安装程序**：
    -   选择安装类型：`Server only` (仅服务器) 或 `Custom` (自定义)。
    -   `Developer Default` 会安装大量开发工具，服务器部署不建议选此项。
3.  **配置 Check**：点击 Execute 安装必要的 C++ 运行库。
4.  **配置 MySQL Server**：
    -   **Type and Networking**：选择 `Server Computer` (服务器) 或 `Dedicated Computer` (专用数据库服务器)。端口默认 3306。
    -   **Authentication Method**：推荐选择 `Use Legacy Authentication Method` (兼容性好) 或 `Use Strong Password Encryption` (8.0默认，安全性高，但旧版客户端可能连不上)。
    -   **Accounts and Roles**：设置 root 密码，添加管理员用户。
    -   **Windows Service**：设置服务名 (默认 MySQL80)，勾选开机自启。
5.  **执行安装**：点击 Execute 应用配置，完成后 Finish。

### 2. ZIP 压缩包方式安装 (适合老手/生产环境)
**步骤：**
1.  **下载**：在官网下载 `Windows (x86, 64-bit), ZIP Archive`。
2.  **解压**：解压到指定目录，例如 `D:\mysql-8.0`。
3.  **创建配置文件 `my.ini`**：
    在根目录下新建 `my.ini`，内容如下：
    ```ini
    [mysqld]
    # 设置3306端口
    port=3306
    # 设置mysql的安装目录
    basedir=D:\\mysql-8.0
    # 设置mysql数据库的数据的存放目录
    datadir=D:\\mysql-8.0\\data
    # 允许最大连接数
    max_connections=200
    # 允许连接失败的次数
    max_connect_errors=10
    # 服务端使用的字符集默认为UTF8MB4
    character-set-server=utf8mb4
    # 创建新表时将使用的默认存储引擎
    default-storage-engine=INNODB
    # 默认使用“mysql_native_password”插件认证
    default_authentication_plugin=mysql_native_password
    
    [mysql]
    # 设置mysql客户端默认字符集
    default-character-set=utf8mb4
    
    [client]
    # 设置mysql客户端连接服务端时默认使用的端口
    port=3306
    default-character-set=utf8mb4
    ```
4.  **初始化数据**：
    以管理员身份打开 CMD，进入 `bin` 目录：
    ```cmd
    cd /d D:\mysql-8.0\bin
    mysqld --initialize --console
    ```
    *注意：记录控制台输出的临时密码！*
5.  **安装服务**：
    ```cmd
    mysqld --install MySQL80
    ```
6.  **启动服务**：
    ```cmd
    net start MySQL80
    ```
7.  **修改密码**：
    ```cmd
    mysql -u root -p
    # 输入临时密码登录后
    ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'NewPassword123!';
    FLUSH PRIVILEGES;
    ```

---

## 二、 Linux 环境安装

### 1. YUM 源在线安装 (推荐 CentOS/RedHat)
**步骤：**
1.  **下载并安装 YUM 源 RPM 包**：
    ```bash
    wget https://dev.mysql.com/get/mysql80-community-release-el7-7.noarch.rpm
    rpm -ivh mysql80-community-release-el7-7.noarch.rpm
    ```
2.  **安装 MySQL Server**：
    ```bash
    yum update
    yum install mysql-server
    ```
    *(如果是 CentOS 8 或类似系统，可能需要先禁用本地 mysql 模块: `yum module disable mysql`)*
3.  **启动服务**：
    ```bash
    systemctl start mysqld
    systemctl enable mysqld
    ```
4.  **获取临时密码并登录**：
    ```bash
    grep 'temporary password' /var/log/mysqld.log
    mysql -uroot -p
    ```
5.  **安全配置**：
    ```sql
    ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyNewPass4!';
    ```

### 2. RPM 离线包安装 (pnm/RPM Bundle)
适用于无法连接外网的服务器 (如内网环境)。
**步骤：**
1.  **下载 RPM Bundle**：
    在官网下载 `mysql-8.0.xx-1.el7.x86_64.rpm-bundle.tar`。
2.  **解压**：
    ```bash
    tar -xvf mysql-8.0.xx-1.el7.x86_64.rpm-bundle.tar
    ```
3.  **清理旧版本 (如有)**：
    ```bash
    rpm -qa | grep mariadb
    rpm -e --nodeps mariadb-libs # 卸载 mariadb 库以免冲突
    ```
4.  **按顺序安装 RPM 包**：
    必须严格按照依赖顺序安装：
    ```bash
    # 1. common
    rpm -ivh mysql-community-common-8.0.xx.rpm
    # 2. client-plugins
    rpm -ivh mysql-community-client-plugins-8.0.xx.rpm
    # 3. libs
    rpm -ivh mysql-community-libs-8.0.xx.rpm
    # 4. client
    rpm -ivh mysql-community-client-8.0.xx.rpm
    # 5. server
    rpm -ivh mysql-community-server-8.0.xx.rpm
    ```
    *注：如果缺少依赖 (如 `libaio`, `net-tools`)，请先通过 yum 或 rpm 安装这些系统库。*
5.  **启动与初始化**：
    同 YUM 安装方式 (systemctl start mysqld)。

### 3. 通用二进制包 (Generic Binary) 安装
适用于任何 Linux 发行版，解压即用。
**步骤：**
1.  **下载**：`mysql-8.0.xx-linux-glibc2.12-x86_64.tar.xz`
2.  **解压与移动**：
    ```bash
    tar -xvf mysql-8.0.xx-linux-glibc2.12-x86_64.tar.xz
    mv mysql-8.0.xx-linux-glibc2.12-x86_64 /usr/local/mysql
    ```
3.  **创建用户**：
    ```bash
    groupadd mysql
    useradd -r -g mysql -s /bin/false mysql
    ```
4.  **初始化**：
    ```bash
    cd /usr/local/mysql
    mkdir mysql-files
    chown mysql:mysql mysql-files
    chmod 750 mysql-files
    bin/mysqld --initialize --user=mysql
    # 记录临时密码
    ```
5.  **启动**：
    ```bash
    bin/mysqld_safe --user=mysql &
    ```
6.  **配置环境变量**：将 `/usr/local/mysql/bin` 加入 `PATH`。

---

## 三、 源码构建安装 (Source Code)

适用于深度定制 MySQL 功能或研究源码。

### 1. 环境依赖准备
```bash
# CentOS/RedHat
yum install -y cmake gcc-c++ openssl-devel ncurses-devel libtirpc-devel bison
```
*注意：MySQL 8.0 需要高版本的 GCC (5.3+) 和 CMake (3.5+)。*

### 2. 下载源码与 Boost
MySQL 8.0 依赖 Boost C++ 库。
```bash
wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.xx.tar.gz
# 下载对应版本的 boost (例如 1.77.0，具体看源码目录下的 cmake/boost.cmake)
# 或者在 cmake 时允许自动下载 (DDOWNLOAD_BOOST=1)
```

### 3. CMake 编译配置
```bash
mkdir build && cd build
cmake .. \
-DCMAKE_INSTALL_PREFIX=/usr/local/mysql \
-DMYSQL_DATADIR=/usr/local/mysql/data \
-DSYSCONFDIR=/etc \
-DWITH_BOOST=../boost \
-DWITH_INNOBASE_STORAGE_ENGINE=1 \
-DWITH_PARTITION_STORAGE_ENGINE=1 \
-DWITH_FEDERATED_STORAGE_ENGINE=1 \
-DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
-DWITH_MYISAM_STORAGE_ENGINE=1 \
-DENABLED_LOCAL_INFILE=1 \
-DENABLE_DTRACE=0 \
-DDEFAULT_CHARSET=utf8mb4 \
-DDEFAULT_COLLATION=utf8mb4_general_ci \
-DWITH_EMBEDDED_SERVER=1
```

### 4. 编译与安装
```bash
make -j $(nproc)  # 这是一个漫长的过程，根据机器配置可能需要 30分钟-2小时
make install
```

### 5. 后续配置
同“通用二进制包”安装方式：创建用户、初始化数据、配置 my.cnf、启动服务。

---

## 四、 常见问题
1.  **GPG Key 过期**：
    如果 `yum install` 报错 `GPG key retrieval failed`，可以尝试导入新 Key：
    ```bash
    rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
    ```
2.  **依赖缺失**：
    安装 RPM 包时常遇到缺少 `libaio.so.1`，安装 `libaio` 即可：`yum install libaio`。
3.  **端口冲突**：
    确保 3306 端口未被占用：`netstat -tlnp | grep 3306`。
