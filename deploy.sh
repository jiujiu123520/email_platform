#!/bin/bash
# ============================================================
#  邮件发送平台 - Ubuntu 一键部署脚本（完整增强版）
#  适用于 Ubuntu 20.04 / 22.04 / 24.04
#
#  用法:
#    sudo bash deploy.sh                    # 默认部署到 /opt/email_platform
#    sudo bash deploy.sh /data/my_project   # 自定义部署目录
#    sudo bash deploy.sh --uninstall        # 卸载
#    sudo bash deploy.sh --status           # 查看运行状态
#    sudo bash deploy.sh --logs              # 查看实时日志
#    sudo bash deploy.sh --restart           # 重启服务
#    sudo bash deploy.sh --ssl yourdomain.com  # 部署并配置SSL
# ============================================================

set -e

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== 常量定义 ====================
APP_NAME="email_platform"
APP_VERSION="V1.0"
DB_NAME="email_platform"
DB_USER="email_user"
DB_PASS="EmailPlatform2024!"
DB_HOST="localhost"
DB_PORT="3306"
REDIS_PORT="6379"
APP_PORT="5000"
WORKERS="4"
DEPLOY_DIR="/opt/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"

# ==================== 工具函数 ====================
info()    { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warn()    { echo -e "${YELLOW}[警告]${NC} $1"; }
error()   { echo -e "${RED}[错误]${NC} $1"; exit 1; }

check_os() {
    if [ ! -f /etc/os-release ]; then
        error "无法检测操作系统版本"
    fi
    . /etc/os-release
    if [[ ! "$ID" =~ ^(ubuntu)$ ]]; then
        warn "此脚本专为 Ubuntu 设计，当前系统: $ID $VERSION"
        read -p "是否继续? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || error "已取消"
    fi
    info "操作系统: $PRETTY_NAME"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 用户或 sudo 运行此脚本\n用法: sudo bash deploy.sh"
    fi
}

check_memory() {
    local mem=$(free -m | awk '/Mem:/ {print $2}')
    info "系统内存: ${mem}MB"
    if [ "$mem" -lt 512 ]; then
        warn "内存不足 512MB，建议至少 1GB"
    fi
}

check_disk() {
    local avail=$(df -m / | awk 'NR==2 {print $4}')
    info "可用磁盘: ${avail}MB"
    if [ "$avail" -lt 1024 ]; then
        warn "磁盘空间不足 1GB，建议至少 5GB"
    fi
}

timer_start() { TIMER_START=$(date +%s); }
timer_end() {
    local elapsed=$(( $(date +%s) - TIMER_START ))
    local min=$(( elapsed / 60 ))
    local sec=$(( elapsed % 60 ))
    info "耗时: ${min}分${sec}秒"
}

# ==================== 快捷命令 ====================
handle_quick_command() {
    case "$1" in
        --uninstall)
            check_root
            echo -e "${RED}============================================================${NC}"
            echo -e "${RED}       卸载邮件发送平台${NC}"
            echo -e "${RED}============================================================${NC}"
            read -p "确定要完全卸载吗？数据库数据将被删除! (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                info "停止服务..."
                supervisorctl stop ${APP_NAME} 2>/dev/null || true
                rm -f /etc/supervisor/conf.d/${APP_NAME}.conf
                supervisorctl reread 2>/dev/null || true
                supervisorctl update 2>/dev/null || true

                info "删除 Nginx 配置..."
                rm -f /etc/nginx/sites-enabled/${APP_NAME}
                rm -f /etc/nginx/sites-available/${APP_NAME}
                nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

                info "删除项目文件..."
                rm -rf "${DEPLOY_DIR}"
                rm -rf "${LOG_DIR}"

                info "删除数据库..."
                mysql -u root -e "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
                mysql -u root -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';" 2>/dev/null || true

                info "删除 Crontab..."
                crontab -l 2>/dev/null | grep -v "${APP_NAME}" | crontab - 2>/dev/null || true

                success "卸载完成！"
            else
                info "已取消卸载"
            fi
            exit 0
            ;;
        --status)
            echo -e "${CYAN}============================================================${NC}"
            echo -e "${CYAN}       邮件发送平台 - 运行状态${NC}"
            echo -e "${CYAN}============================================================${NC}"
            echo ""
            echo -e "${YELLOW}--- 服务状态 ---${NC}"
            systemctl is-active nginx 2>/dev/null && echo -e "  Nginx:       ${GREEN}运行中${NC}" || echo -e "  Nginx:       ${RED}未运行${NC}"
            systemctl is-active mysql 2>/dev/null && echo -e "  MySQL:       ${GREEN}运行中${NC}" || echo -e "  MySQL:       ${RED}未运行${NC}"
            systemctl is-active redis-server 2>/dev/null && echo -e "  Redis:       ${GREEN}运行中${NC}" || echo -e "  Redis:       ${RED}未运行${NC}"
            supervisorctl status ${APP_NAME} 2>/dev/null || echo -e "  应用服务:   ${RED}未运行${NC}"
            echo ""
            echo -e "${YELLOW}--- 系统资源 ---${NC}"
            free -m | awk '/Mem:/ {printf "  内存: %sMB / %sMB\n", $3, $2}'
            df -h / | awk 'NR==2 {printf "  磁盘: %s / %s\n", $3, $2}'
            echo ""
            echo -e "${YELLOW}--- 端口监听 ---${NC}"
            ss -tlnp 2>/dev/null | grep -E ":(80|443|3306|6379|5000) " || echo "  (无相关端口监听)"
            echo ""
            echo -e "${YELLOW}--- 最近日志 (最后10行) ---${NC}"
            tail -10 "${DEPLOY_DIR}/logs/gunicorn.log" 2>/dev/null || echo "  (无日志)"
            exit 0
            ;;
        --logs)
            info "实时查看应用日志 (Ctrl+C 退出)..."
            tail -f "${DEPLOY_DIR}/logs/gunicorn.log" "${DEPLOY_DIR}/logs/gunicorn_error.log" 2>/dev/null
            exit 0
            ;;
        --restart)
            check_root
            info "重启应用服务..."
            supervisorctl restart ${APP_NAME}
            success "服务已重启"
            exit 0
            ;;
        --ssl)
            SSL_DOMAIN="$2"
            if [ -z "$SSL_DOMAIN" ]; then
                error "请指定域名: sudo bash deploy.sh --ssl yourdomain.com"
            fi
            check_root
            install_ssl "$SSL_DOMAIN"
            exit 0
            ;;
    esac
}

# ==================== SSL 证书配置 ====================
install_ssl() {
    local domain="$1"
    info "为域名 ${domain} 配置 SSL 证书..."

    # 安装 certbot
    apt-get install -y certbot python3-certbot-nginx

    # 获取证书
    certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email

    # 设置自动续期
    systemctl enable certbot.timer
    systemctl start certbot.timer

    success "SSL 证书配置完成！"
    info "证书将自动续期"
}

# ==================== 主部署流程 ====================
main_deploy() {
    local custom_dir="$1"

    # 解析参数
    if [[ "$custom_dir" != "--"* ]] && [ -n "$custom_dir" ]; then
        DEPLOY_DIR="$custom_dir"
    fi

    PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
    timer_start

    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}       邮件发送平台 ${APP_VERSION} - 一键部署${NC}"
    echo -e "${CYAN}       部署目录: ${DEPLOY_DIR}${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""

    # ---- 步骤 0: 环境检查 ----
    info "========== [0/12] 环境检查 =========="
    check_os
    check_root
    check_memory
    check_disk
    echo ""

    # ---- 步骤 1: 系统更新 ----
    info "========== [1/12] 更新系统软件包 =========="
    apt-get update -y
    apt-get upgrade -y
    success "系统软件包已更新"
    echo ""

    # ---- 步骤 2: 安装系统基础依赖 ----
    info "========== [2/12] 安装系统基础依赖 =========="
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        libmysqlclient-dev \
        pkg-config \
        libssl-dev \
        libffi-dev \
        nginx \
        supervisor \
        curl \
        wget \
        git \
        unzip \
        htop \
        net-tools \
        vim \
        logrotate
    success "系统基础依赖安装完成"
    echo ""

    # ---- 步骤 3: 安装 MySQL ----
    info "========== [3/12] 安装 MySQL 数据库 =========="
    if ! command -v mysql &> /dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        # Ubuntu 24.04 使用 mysql-server 包
        apt-get install -y mysql-server
        systemctl start mysql
        systemctl enable mysql
        # 优化 MySQL 配置
        cat > /etc/mysql/mysql.conf.d/${APP_NAME}_custom.cnf <<MYEOF
[${APP_NAME}_tuning]
# 邮件平台 MySQL 优化配置
max_connections = 200
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
query_cache_size = 64M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
max_allowed_packet = 64M
MYEOF
        systemctl restart mysql
        success "MySQL 已安装、启动并优化"
    else
        success "MySQL 已存在，跳过安装"
    fi
    echo ""

    # ---- 步骤 4: 安装 Redis ----
    info "========== [4/12] 安装 Redis 缓存 =========="
    if ! command -v redis-server &> /dev/null; then
        apt-get install -y redis-server
        systemctl start redis-server
        systemctl enable redis-server
        # Redis 基础配置
        sed -i 's/^# requirepass foobared/requirepass EmailPlatformRedis2024!/' /etc/redis/redis.conf 2>/dev/null || true
        sed -i 's/^bind 127.0.0.1 ::1/bind 127.0.0.1/' /etc/redis/redis.conf 2>/dev/null || true
        systemctl restart redis-server
        success "Redis 已安装并启动"
    else
        success "Redis 已存在，跳过安装"
    fi
    echo ""

    # ---- 步骤 5: 配置数据库 ----
    info "========== [5/12] 配置数据库 =========="
    mysql -u root <<DBEOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
DBEOF
    success "数据库 ${DB_NAME} 和用户 ${DB_USER} 已创建"
    echo ""

    # ---- 步骤 6: 部署项目文件 ----
    info "========== [6/12] 部署项目文件 =========="
    mkdir -p "${DEPLOY_DIR}"
    mkdir -p "${DEPLOY_DIR}/logs"

    # 复制项目文件
    if [ -d "${PROJECT_DIR}/app" ]; then
        cp -r "${PROJECT_DIR}/"* "${DEPLOY_DIR}/"
        success "项目文件已复制到 ${DEPLOY_DIR}"
    else
        warn "未找到项目源码目录，请手动将源码放入 ${DEPLOY_DIR}"
    fi

    # 创建 Python 虚拟环境
    cd "${DEPLOY_DIR}"
    python3 -m venv venv
    source venv/bin/activate
    success "Python 虚拟环境已创建"
    echo ""

    # ---- 步骤 7: 安装 Python 依赖 ----
    info "========== [7/12] 安装 Python 依赖 =========="
    pip install --upgrade pip setuptools wheel
    if [ -f "${DEPLOY_DIR}/requirements.txt" ]; then
        pip install -r requirements.txt
        success "Python 依赖安装完成"
    else
        warn "未找到 requirements.txt，安装 Flask 基础包"
        pip install flask flask-sqlalchemy flask-jwt-extended flask-cors flask-mail flask-limiter pymysql cryptography python-dotenv gunicorn redis bcrypt requests
    fi
    echo ""

    # ---- 步骤 8: 生成配置文件 ----
    info "========== [8/12] 生成配置文件 =========="
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    JWT_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

    cat > "${DEPLOY_DIR}/.env" <<ENVEOF
# 邮件发送平台 - 生产环境配置（自动生成）
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
DATABASE_URL=mysql+pymysql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?charset=utf8mb4
REDIS_URL=redis://localhost:${REDIS_PORT}/0
MAIL_DEFAULT_SENDER=noreply@example.com
FLASK_ENV=production
ENVEOF

    chmod 600 "${DEPLOY_DIR}/.env"
    success "环境配置文件已生成 (.env)"
    echo ""

    # ---- 步骤 9: 初始化数据库 ----
    info "========== [9/12] 初始化数据库表结构 =========="
    cd "${DEPLOY_DIR}"
    source venv/bin/activate
    export $(cat .env | xargs)

    python3 -c "
import sys
sys.path.insert(0, '${DEPLOY_DIR}')
from app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库表结构初始化完成')
" 2>&1

    success "数据库表结构已创建"
    echo ""

    # ---- 步骤 10: 配置 Nginx ----
    info "========== [10/12] 配置 Nginx 反向代理 =========="
    cat > /etc/nginx/sites-available/${APP_NAME} <<NGXEOF
# 邮件发送平台 Nginx 配置
# 自动生成 - $(date '+%Y-%m-%d %H:%M:%S')

upstream ${APP_NAME}_backend {
    server 127.0.0.1:${APP_PORT};
    keepalive 64;
}

server {
    listen 80;
    server_name _;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # 请求体大小限制
    client_max_body_size 20M;

    # 访问日志
    access_log ${LOG_DIR}/nginx_access.log;
    error_log  ${LOG_DIR}/nginx_error.log;

    # 静态文件（直接由 Nginx 处理，不走后端）
    location /static/ {
        alias ${DEPLOY_DIR}/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # 反向代理到 Flask/Gunicorn
    location / {
        proxy_pass http://${APP_NAME}_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";

        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 120s;

        # WebSocket 支持（如需要）
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # 健康检查端点（不记录日志）
    location /health {
        proxy_pass http://127.0.0.1:${APP_PORT}/;
        access_log off;
    }
}
NGXEOF

    # 创建日志目录
    mkdir -p "${LOG_DIR}"
    chown -R www-data:www-data "${LOG_DIR}"

    # 启用站点
    ln -sf /etc/nginx/sites-available/${APP_NAME} /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # 测试并重载
    nginx -t && systemctl reload nginx
    success "Nginx 反向代理配置完成"
    echo ""

    # ---- 步骤 11: 配置 Supervisor ----
    info "========== [11/12] 配置 Supervisor 进程管理 =========="
    cat > /etc/supervisor/conf.d/${APP_NAME}.conf <<SUPEREOF
[program:${APP_NAME}]
command=${DEPLOY_DIR}/venv/bin/gunicorn \
    --workers ${WORKERS} \
    --bind 0.0.0.0:${APP_PORT} \
    --timeout 120 \
    --keep-alive 5 \
    --max-requests 1000 \
    --max-requests-jitter 50 \
    --access-logfile ${LOG_DIR}/gunicorn_access.log \
    --error-logfile ${LOG_DIR}/gunicorn_error.log \
    --log-level info \
    "app:create_app('production')"

directory=${DEPLOY_DIR}
user=root
autostart=true
autorestart=true
startsecs=5
stopwaitsecs=30
stopasgroup=true
killasgroup=true

stdout_logfile=${LOG_DIR}/supervisor_stdout.log
stderr_logfile=${LOG_DIR}/supervisor_stderr.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10

environment=
    PATH="${DEPLOY_DIR}/venv/bin:/usr/local/bin:/usr/bin:/bin",
    LANG="zh_CN.UTF-8",
    LC_ALL="zh_CN.UTF-8"
SUPEREOF

    # 启动服务
    supervisorctl reread
    supervisorctl update
    supervisorctl start ${APP_NAME}
    success "Supervisor 进程管理配置完成，服务已启动"
    echo ""

    # ---- 步骤 12: 系统优化与定时任务 ----
    info "========== [12/12] 系统优化与定时任务 =========="

    # 配置日志轮转
    cat > /etc/logrotate.d/${APP_NAME} <<LOGEOF
${LOG_DIR}/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        supervisorctl rotate-logs ${APP_NAME} > /dev/null 2>&1 || true
    endscript
}
LOGEOF
    success "日志轮转已配置（保留30天）"

    # 配置 Crontab 定时任务（每日零点重置配额）
    (crontab -l 2>/dev/null | grep -v "${APP_NAME}"; echo "0 0 * * * cd ${DEPLOY_DIR} && ${DEPLOY_DIR}/venv/bin/python -c \"from app import create_app; from app.services.smtp_service import SmtpRelayService; app=create_app('production'); app.app_context().push(); SmtpRelayService.reset_all_daily_stats()\" >> ${LOG_DIR}/cron.log 2>&1") | crontab -
    success "定时任务已配置（每日零点重置SMTP配额）"

    # 配置防火墙（如果可用）
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "active"; then
            ufw allow 80/tcp
            ufw allow 443/tcp
            success "防火墙已放行 80/443 端口"
        else
            info "UFW 防火墙未启用，跳过"
        fi
    fi

    # 设置文件权限
    chmod -R 755 "${DEPLOY_DIR}"
    chmod 600 "${DEPLOY_DIR}/.env"
    chown -R root:root "${DEPLOY_DIR}"
    success "文件权限已设置"
    echo ""

    # ---- 部署完成 ----
    timer_end

    local IP_ADDR=$(hostname -I | awk '{print $1}')

    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}       部署完成!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  ${CYAN}访问地址:${NC}  http://${IP_ADDR}"
    echo -e "  ${CYAN}管理账号:${NC}  admin"
    echo -e "  ${CYAN}管理密码:${NC}  admin123456"
    echo -e "  ${CYAN}部署目录:${NC}  ${DEPLOY_DIR}"
    echo -e "  ${CYAN}日志目录:${NC}  ${LOG_DIR}"
    echo -e "  ${CYAN}配置文件:${NC}  ${DEPLOY_DIR}/.env"
    echo ""
    echo -e "${YELLOW}--- 常用管理命令 ---${NC}"
    echo -e "  查看状态:   sudo bash deploy.sh --status"
    echo -e "  重启服务:   sudo bash deploy.sh --restart"
    echo -e "  实时日志:   sudo bash deploy.sh --logs"
    echo -e "  配置SSL:    sudo bash deploy.sh --ssl yourdomain.com"
    echo -e "  卸载系统:   sudo bash deploy.sh --uninstall"
    echo ""
    echo -e "${YELLOW}--- 手动管理命令 ---${NC}"
    echo -e "  Supervisor:  supervisorctl status|start|stop|restart ${APP_NAME}"
    echo -e "  Nginx:      nginx -t && systemctl reload nginx"
    echo -e "  MySQL:      systemctl status mysql"
    echo -e "  Redis:      systemctl status redis-server"
    echo -e "  数据库:     mysql -u ${DB_USER} -p ${DB_NAME}"
    echo -e "  Python:     ${DEPLOY_DIR}/venv/bin/python"
    echo ""
    echo -e "${YELLOW}--- API 接口 ---${NC}"
    echo -e "  基础地址:   http://${IP_ADDR}/api/v2/"
    echo -e "  登录接口:   POST /api/v2/auth/login"
    echo -e "  模板列表:   GET  /api/v2/templates"
    echo -e "  发送邮件:   POST /api/v2/email/send"
    echo -e "  批量发送:   POST /api/v2/email/batch"
    echo -e "  发送记录:   GET  /api/v2/email/records"
    echo -e "  系统统计:   GET  /api/v2/email/stats"
    echo ""
    echo -e "${RED}!!! 请立即修改默认管理员密码 !!!${NC}"
    echo ""
}

# ==================== 入口 ====================
# 处理快捷命令
handle_quick_command "$1" 2>/dev/null || true

# 主部署流程
main_deploy "$1"
