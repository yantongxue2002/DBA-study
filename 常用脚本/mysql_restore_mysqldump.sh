#!/bin/bash
# mysqldump 备份恢复脚本
# 说明：对应 mysql_backup_mysqldump.sh 的反向恢复操作
# 功能：交互式或参数化选择备份文件，并恢复到指定数据库实例

# ================= 配置部分 =================
# 备份根目录 (需与备份脚本保持一致)
BASEDIR="/datacfs/mysqlbak"
# mysql 命令路径
MYSQL="mysql"

# 预定义连接配置 (格式 ["IP:Port"]="User Password")
# 如果恢复的目标在列表里，会自动匹配密码；否则需要手动输入
declare -A MYSQL_CONFIGS=(
    ["127.0.0.1:3306"]="backup_user aaa123456"
    ["devmysql.fixpng.top:3306"]="backup aaa123456b"
)
# ===========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo -e "${RED}[ERROR] $*${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $*${NC}"
}

# 检查依赖
if ! command -v gunzip &> /dev/null; then
    error "未找到 gunzip 命令，请先安装 gzip"
    exit 1
fi

# 交互式选择函数
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=""
    
    echo -e "${GREEN}${prompt}${NC}"
    select opt in "${options[@]}"; do
        if [ -n "$opt" ]; then
            selected="$opt"
            break
        else
            echo "无效选择，请重试。"
        fi
    done
    echo "$selected"
}

# ================= 主流程 =================

# 1. 选择备份源实例 (Source Instance)
if [ ! -d "$BASEDIR" ]; then
    error "备份目录不存在: $BASEDIR"
    exit 1
fi

echo "正在扫描备份目录: $BASEDIR ..."
INSTANCES=($(ls "$BASEDIR" | grep ":")) # 假设目录名包含冒号，如 IP:Port

if [ ${#INSTANCES[@]} -eq 0 ]; then
    error "未找到任何备份实例目录 (格式如 IP:Port)"
    exit 1
fi

SELECTED_INSTANCE=$(select_option "请选择备份源实例:" "${INSTANCES[@]}")
log "已选择源实例: $SELECTED_INSTANCE"

# 2. 选择备份日期
INSTANCE_DIR="${BASEDIR}/${SELECTED_INSTANCE}"
DATES=($(ls "$INSTANCE_DIR" | grep -E "^[0-9]{8}$" | sort -r))

if [ ${#DATES[@]} -eq 0 ]; then
    error "该实例下未找到日期格式的备份目录"
    exit 1
fi

SELECTED_DATE=$(select_option "请选择备份日期:" "${DATES[@]}")
BACKUP_PATH="${INSTANCE_DIR}/${SELECTED_DATE}"
log "已选择备份路径: $BACKUP_PATH"

# 3. 选择要恢复的数据库 (Database)
FILES=($(ls "$BACKUP_PATH"/*.sql.gz 2>/dev/null))
if [ ${#FILES[@]} -eq 0 ]; then
    error "该日期下未找到 .sql.gz 备份文件"
    exit 1
fi

# 提取文件名中的数据库名 (去除路径和后缀)
DB_NAMES=()
for f in "${FILES[@]}"; do
    filename=$(basename "$f")
    dbname="${filename%.sql.gz}"
    DB_NAMES+=("$dbname")
done
# 添加"全部恢复"选项 (可选)
# DB_NAMES+=("ALL_DATABASES")

SELECTED_DB=$(select_option "请选择要恢复的数据库:" "${DB_NAMES[@]}")
TARGET_FILE="${BACKUP_PATH}/${SELECTED_DB}.sql.gz"
log "准备恢复文件: $TARGET_FILE"

# 4. 确认恢复目标 (Target Instance)
echo -e "\n${YELLOW}请配置恢复目标数据库连接:${NC}"
read -p "目标主机 (IP) [默认从源实例解析]: " TARGET_HOST
read -p "目标端口 [默认从源实例解析]: " TARGET_PORT

# 如果未输入，尝试从 SELECTED_INSTANCE 解析
if [ -z "$TARGET_HOST" ]; then
    IFS=':' read -r H P <<< "$SELECTED_INSTANCE"
    TARGET_HOST="$H"
    [ -z "$TARGET_PORT" ] && TARGET_PORT="$P"
fi
[ -z "$TARGET_PORT" ] && TARGET_PORT=3306

TARGET_HOST_PORT="${TARGET_HOST}:${TARGET_PORT}"
echo "目标实例: $TARGET_HOST_PORT"

# 尝试自动匹配密码
TARGET_USER=""
TARGET_PASS=""

if [ -n "${MYSQL_CONFIGS[$TARGET_HOST_PORT]}" ]; then
    CREDENTIAL="${MYSQL_CONFIGS[$TARGET_HOST_PORT]}"
    USERPASS=(${CREDENTIAL})
    TARGET_USER=${USERPASS[0]}
    TARGET_PASS=${USERPASS[1]}
    log "已自动匹配到配置中的凭据 (用户: $TARGET_USER)"
else
    read -p "请输入目标数据库用户名 [root]: " INPUT_USER
    TARGET_USER="${INPUT_USER:-root}"
    read -s -p "请输入目标数据库密码: " TARGET_PASS
    echo ""
fi

# 5. 二次确认
echo -e "\n${RED}================== 警告 ==================${NC}"
echo -e "即将执行以下操作:"
echo -e "1. 来源文件: $TARGET_FILE"
echo -e "2. 目标实例: $TARGET_HOST:$TARGET_PORT"
echo -e "3. 目标数据库: $SELECTED_DB (若不存在将尝试创建)"
echo -e "${RED}此操作可能会覆盖目标数据库中的现有数据！${NC}"
echo -e "${RED}==========================================${NC}"
read -p "确认执行恢复吗? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "操作已取消。"
    exit 0
fi

# 6. 执行恢复
log "开始恢复..."

# 检查并创建数据库
CREATE_DB_CMD="$MYSQL -h$TARGET_HOST -P$TARGET_PORT -u$TARGET_USER -p$TARGET_PASS -e 'CREATE DATABASE IF NOT EXISTS \`$SELECTED_DB\` DEFAULT CHARACTER SET utf8mb4;'"
eval "$CREATE_DB_CMD"
if [ $? -ne 0 ]; then
    error "连接数据库失败或创建数据库失败，请检查凭据和网络。"
    exit 1
fi

# 解压并导入
# 注意：pv 命令可以显示进度，如果系统有的话最好加上，这里用基础管道
CMD="gunzip < \"$TARGET_FILE\" | $MYSQL -h$TARGET_HOST -P$TARGET_PORT -u$TARGET_USER -p$TARGET_PASS \"$SELECTED_DB\""

log "Executing: gunzip < ... | mysql -h$TARGET_HOST -P$TARGET_PORT -u$TARGET_USER -p... $SELECTED_DB"
eval "$CMD"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}恢复成功！${NC}"
else
    error "恢复过程中发生错误，请检查输出。"
    exit 1
fi