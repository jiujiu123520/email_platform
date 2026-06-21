#!/bin/bash
# ============================================================
#  邮件发送平台 - CentOS 一键部署脚本（完整版）
#  适用于 CentOS 7 / 8 / 9 Stream
#
#  用法:
#    sudo bash deploy-centos.sh                    # 默认部署
#    sudo bash deploy-centos.sh /data/my_project   # 自定义目录
#    sudo bash deploy-centos.sh --uninstall        # 卸载
#    sudo bash deploy-centos.sh --status           # 查看状态
#    sudo bash deploy-centos.sh --logs              # 查看日志
#    sudo bash deploy-centos.sh --restart           # 重启
#    sudo bash deploy-centos.sh --ssl yourdomain.com # 配置SSL
# ============================================================

set -e

# ==================== 颜色 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }

# ==================== 常量 ====================
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

# ==================== 系统检测 ====================
detect_pkg_manager() {
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
    else
        error "未找到 yum 或 dnf 包管理器"
    fi
    info "包管理器: ${PKG_MANAGER}"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        info "操作系统: ${PRETTY_NAME}"
        OS_VERSION="${VERSION_ID%%.*}"
    elif [ -f /etc/redhat-release ]; then
        info "操作系统: $(cat /etc/redhat-release)"
        OS_VERSION=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
    else
        warn "无法检测操作系统版本"
        OS_VERSION="7"
    fi
}

check_selinux() {
    if command -v getenforce &> /dev/null; then
        local selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
        if [ "$selinux_status" = "Enforcing" ]; then
            warn "SELinux 处于 Enforcing 模式，临时设为 Permissive"
            setenforce 0 2>/dev/null || true
            # 持久化
            sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
        fi
    fi
}

check_firewall() {
    # CentOS 7 使用 firewalld，CentOS 8/9 可能使用 nftables
    if systemctl is-active firewalld &> /dev/null; then
        info "检测到 firewalld 防火墙，放行端口..."
        firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=443/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        success "防火墙已放行 80/443"
    elif command -v iptables &> /dev/null; then
        info "检测到 iptables，放行端口..."
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        service iptables save 2>/dev/null || true
        success "防火墙已放行 80/443"
    fi
}

# ==================== 快捷命令 ====================
handle_quick_command() {
    case "$1" in
        --uninstall)
            if [ "$EUID" -ne 0 ]; then error "请使用 root 运行"; fi
            echo -e "${RED}============================================================${NC}"
            echo -e "${RED}       卸载邮件发送平台${NC}"
            echo -e "${RED}============================================================${NC}"
            read -p "确定完全卸载？数据库将被删除 (yes/no): " confirm
            [ "$confirm" = "yes" ] || { info "已取消"; exit 0; }

            supervisorctl stop ${APP_NAME} 2>/dev/null || true
            rm -f /etc/supervisord.d/${APP_NAME}.ini 2>/dev/null || true
            rm -f /etc/supervisor/conf.d/${APP_NAME}.conf 2>/dev/null || true
            supervisorctl reread 2>/dev/null; supervisorctl update 2>/dev/null

            rm -f /etc/nginx/conf.d/${APP_NAME}.conf 2>/dev/null
            nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

            rm -rf "${DEPLOY_DIR}" "${LOG_DIR}"

            mysql -u root -e "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
            mysql -u root -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';" 2>/dev/null || true

            crontab -l 2>/dev/null | grep -v "${APP_NAME}" | crontab - 2>/dev/null || true
            success "卸载完成"; exit 0
            ;;
        --status)
            echo -e "${CYAN}============================================================${NC}"
            echo -e "${CYAN}       邮件发送平台 - 运行状态${NC}"
            echo -e "${CYAN}============================================================${NC}"
            echo ""
            echo -e "${YELLOW}--- 服务状态 ---${NC}"
            systemctl is-active nginx 2>/dev/null && echo -e "  Nginx:       ${GREEN}运行中${NC}" || echo -e "  Nginx:       ${RED}未运行${NC}"
            systemctl is-active mysqld 2>/dev/null && echo -e "  MySQL:       ${GREEN}运行中${NC}" || echo -e "  MySQL:       ${RED}未运行${NC}"
            systemctl is-active redis 2>/dev/null && echo -e "  Redis:       ${GREEN}运行中${NC}" || echo -e "  Redis:       ${RED}未运行${NC}"
            supervisorctl status ${APP_NAME} 2>/dev/null || echo -e "  应用服务:   ${RED}未运行${NC}"
            echo ""
            echo -e "${YELLOW}--- 系统资源 ---${NC}"
            free -m | awk '/Mem:/ {printf "  内存: %sMB / %sMB\n", $3, $2}'
            df -h / | awk 'NR==2 {printf "  磁盘: %s / %s\n", $3, $2}'
            echo ""
            echo -e "${YELLOW}--- 端口监听 ---${NC}"
            ss -tlnp 2>/dev/null | grep -E ":(80|443|3306|6379|5000) " || echo "  (无相关端口)"
            echo ""
            echo -e "${YELLOW}--- 最近日志 ---${NC}"
            tail -5 "${DEPLOY_DIR}/logs/gunicorn.log" 2>/dev/null || echo "  (无日志)"
            exit 0
            ;;
        --logs)
            info "实时日志 (Ctrl+C 退出)..."
            tail -f "${DEPLOY_DIR}/logs/gunicorn.log" "${DEPLOY_DIR}/logs/gunicorn_error.log" 2>/dev/null
            exit 0
            ;;
        --restart)
            [ "$EUID" -ne 0 ] && error "请使用 root 运行"
            supervisorctl restart ${APP_NAME}
            success "服务已重启"; exit 0
            ;;
        --ssl)
            [ "$EUID" -ne 0 ] && error "请使用 root 运行"
            [ -z "$2" ] && error "请指定域名: sudo bash deploy-centos.sh --ssl yourdomain.com"
            $PKG_INSTALL certbot python3-certbot-nginx 2>/dev/null || $PKG_INSTALL certbot 2>/dev/null
            certbot --nginx -d "$2" --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null
            systemctl enable certbot-renew.timer 2>/dev/null || true
            success "SSL 配置完成"; exit 0
            ;;
    esac
}

# ==================== SSL ====================
install_ssl() {
    local domain="$1"
    info "配置 SSL: ${domain}"
    $PKG_INSTALL certbot python3-certbot-nginx 2>/dev/null || $PKG_INSTALL certbot
    certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email
    systemctl enable certbot-renew.timer 2>/dev/null || true
    success "SSL 证书配置完成"
}

# ==================== 主部署 ====================
main_deploy() {
    local custom_dir="$1"
    [[ "$custom_dir" != "--"* ]] && [ -n "$custom_dir" ] && DEPLOY_DIR="$custom_dir"

    PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
    TIMER_START=$(date +%s)

    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  邮件发送平台 ${APP_VERSION} - CentOS 一键部署${NC}"
    echo -e "${CYAN}  部署目录: ${DEPLOY_DIR}${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""

    [ "$EUID" -ne 0 ] && error "请使用 root 或 sudo 运行"

    # ---- 0: 系统检测 ----
    info "========== [0/12] 系统环境检测 =========="
    detect_os
    detect_pkg_manager
    check_selinux

    local mem=$(free -m | awk '/Mem:/ {print $2}')
    info "系统内存: ${mem}MB"
    [ "$mem" -lt 512 ] && warn "内存不足 512MB，建议至少 1GB"

    local avail=$(df -m / | awk 'NR==2 {print $4}')
    info "可用磁盘: ${avail}MB"
    [ "$avail" -lt 1024 ] && warn "磁盘不足 1GB"
    echo ""

    # ---- 1: EPEL 源 ----
    info "========== [1/12] 配置 EPEL 和系统更新 =========="
    $PKG_INSTALL epel-release 2>/dev/null || true
    $PKG_MANAGER update -y
    success "系统已更新"
    echo ""

    # ---- 2: 安装基础依赖 ----
    info "========== [2/12] 安装系统基础依赖 =========="
    $PKG_INSTALL \
        python3 \
        python3-pip \
        python3-devel \
        gcc \
        gcc-c++ \
        make \
        mariadb-devel \
        openssl-devel \
        libffi-devel \
        nginx \
        supervisor \
        curl \
        wget \
        git \
        unzip \
        logrotate \
        net-tools \
        vim \
        htop 2>/dev/null || true

    # CentOS 7 可能需要单独安装 python36
    if ! command -v python3 &> /dev/null; then
        $PKG_INSTALL python36 python36-pip python36-devel 2>/dev/null || true
        if command -v python3.6 &> /dev/null && ! command -v python3 &> /dev/null; then
            ln -sf /usr/bin/python3.6 /usr/bin/python3
            ln -sf /usr/bin/pip3.6 /usr/bin/pip3
        fi
    fi

    # 确保 pip 可用
    if ! command -v pip3 &> /dev/null; then
        curl -sS https://bootstrap.pypa.io/get-pip.py | python3
    fi

    success "基础依赖安装完成"
    echo ""

    # ---- 3: 安装 MySQL (MariaDB) ----
    info "========== [3/12] 安装 MySQL 数据库 =========="
    if ! command -v mysql &> /dev/null && ! rpm -qa | grep -q mariadb; then
        # CentOS 7 使用 MariaDB
        if [ "${OS_VERSION}" = "7" ]; then
            $PKG_INSTALL mariadb-server mariadb
            systemctl start mariadb
            systemctl enable mariadb
            # 安全初始化
            mysql_secure_installation <<SECURE
n
Y
Y
Y
Y
Y
SECURE
        else
            # CentOS 8/9 使用 mysql-server
            $PKG_INSTALL mysql-server
            systemctl start mysqld
            systemctl enable mysqld
        fi

        # 优化配置
        local my_cnf="/etc/my.cnf.d/${APP_NAME}_custom.cnf"
        cat > "$my_cnf" <<MYEOF
[${APP_NAME}_tuning]
max_connections = 200
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
max_allowed_packet = 64M
MYEOF

        systemctl restart mariadb 2>/dev/null || systemctl restart mysqld 2>/dev/null
        success "MySQL 已安装并优化"
    else
        systemctl start mariadb 2>/dev/null || systemctl start mysqld 2>/dev/null
        systemctl enable mariadb 2>/dev/null || systemctl enable mysqld 2>/dev/null
        success "MySQL 已存在，跳过安装"
    fi
    echo ""

    # ---- 4: 安装 Redis ----
    info "========== [4/12] 安装 Redis =========="
    if ! command -v redis-server &> /dev/null && ! command -v redis-cli &> /dev/null; then
        $PKG_INSTALL redis
        systemctl start redis
        systemctl enable redis
        # 配置
        sed -i 's/^# requirepass foobared/requirepass EmailPlatformRedis2024!/' /etc/redis.conf 2>/dev/null || true
        sed -i 's/^bind 127.0.0.1 ::1/bind 127.0.0.1/' /etc/redis.conf 2>/dev/null || true
        systemctl restart redis
        success "Redis 已安装"
    else
        systemctl start redis 2>/dev/null || systemctl start redis-server 2>/dev/null
        systemctl enable redis 2>/dev/null || systemctl enable redis-server 2>/dev/null
        success "Redis 已存在"
    fi
    echo ""

    # ---- 5: 配置数据库 ----
    info "========== [5/12] 配置数据库 =========="
    mysql -u root <<DBEOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
DBEOF
    success "数据库已创建"
    echo ""

    # ---- 6: 部署项目 ----
    info "========== [6/12] 部署项目文件 =========="
    mkdir -p "${DEPLOY_DIR}" "${DEPLOY_DIR}/logs"

    if [ -d "${PROJECT_DIR}/app" ]; then
        cp -r "${PROJECT_DIR}/"* "${DEPLOY_DIR}/"
        success "项目文件已复制"
    else
        warn "未找到源码，请手动放入 ${DEPLOY_DIR}"
    fi

    cd "${DEPLOY_DIR}"
    python3 -m venv venv 2>/dev/null || python3 -m venv --without-pip venv && source venv/bin/activate && curl -sS https://bootstrap.pypa.io/get-pip.py | python3
    source venv/bin/activate
    success "Python 虚拟环境已创建"
    echo ""

    # ---- 7: 安装 Python 依赖 ----
    info "========== [7/12] 安装 Python 依赖 =========="
    pip install --upgrade pip setuptools wheel
    if [ -f requirements.txt ]; then
        pip install -r requirements.txt
    else
        pip install flask flask-sqlalchemy flask-jwt-extended flask-cors flask-mail flask-limiter \
            pymysql cryptography python-dotenv gunicorn redis bcrypt requests beautifulsoup4
    fi
    success "Python 依赖安装完成"
    echo ""

    # ---- 8: 生成配置 ----
    info "========== [8/12] 生成配置文件 =========="
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    JWT_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

    cat > "${DEPLOY_DIR}/.env" <<EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
DATABASE_URL=mysql+pymysql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?charset=utf8mb4
REDIS_URL=redis://localhost:${REDIS_PORT}/0
MAIL_DEFAULT_SENDER=noreply@example.com
FLASK_ENV=production
EOF
    chmod 600 "${DEPLOY_DIR}/.env"
    success "配置文件已生成"
    echo ""

    # ---- 9: 初始化数据库 ----
    info "========== [9/12] 初始化数据库表 =========="
    export $(cat .env | xargs)
    python3 -c "
import sys
sys.path.insert(0, '${DEPLOY_DIR}')
from app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库初始化完成')
" 2>&1
    success "数据库表已创建"
    echo ""

    # ---- 10: Nginx ----
    info "========== [10/12] 配置 Nginx =========="
    cat > /etc/nginx/conf.d/${APP_NAME}.conf <<NGXEOF
upstream ${APP_NAME}_backend {
    server 127.0.0.1:${APP_PORT};
    keepalive 64;
}

server {
    listen 80;
    server_name _;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    client_max_body_size 20M;

    access_log ${LOG_DIR}/nginx_access.log;
    error_log  ${LOG_DIR}/nginx_error.log;

    location /static/ {
        alias ${DEPLOY_DIR}/static/;
        expires 30d;
        access_log off;
    }

    location / {
        proxy_pass http://${APP_NAME}_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 120s;
    }
}
NGXEOF

    mkdir -p "${LOG_DIR}"
    nginx -t && systemctl reload nginx
    success "Nginx 配置完成"
    echo ""

    # ---- 11: Supervisor ----
    info "========== [11/12] 配置 Supervisor =========="
    # CentOS 的 supervisor 配置目录可能不同
    local supervisor_conf=""
    if [ -d /etc/supervisord.d ]; then
        supervisor_conf="/etc/supervisord.d/${APP_NAME}.ini"
    elif [ -d /etc/supervisor/conf.d ]; then
        supervisor_conf="/etc/supervisor/conf.d/${APP_NAME}.conf"
    else
        mkdir -p /etc/supervisor/conf.d
        supervisor_conf="/etc/supervisor/conf.d/${APP_NAME}.conf"
        # 确保 supervisor 配置包含 conf.d
        grep -q "include /etc/supervisor/conf.d" /etc/supervisord.conf 2>/dev/null || \
            echo "[include]" >> /etc/supervisord.conf && \
            echo "files = /etc/supervisor/conf.d/*.conf" >> /etc/supervisord.conf
    fi

    cat > "${supervisor_conf}" <<SUPEREOF
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

    # 确保 supervisord 服务启动
    systemctl enable supervisord 2>/dev/null || systemctl enable supervisor 2>/dev/null || true
    systemctl start supervisord 2>/dev/null || systemctl start supervisor 2>/dev/null || true

    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true
    supervisorctl start ${APP_NAME} 2>/dev/null || true
    success "Supervisor 配置完成"
    echo ""

    # ---- 12: 系统优化 ----
    info "========== [12/12] 系统优化 =========="

    # 日志轮转
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
    success "日志轮转已配置"

    # 定时任务
    (crontab -l 2>/dev/null | grep -v "${APP_NAME}"; echo "0 0 * * * cd ${DEPLOY_DIR} && ${DEPLOY_DIR}/venv/bin/python -c \"from app import create_app; from app.services.smtp_service import SmtpRelayService; app=create_app('production'); app.app_context().push(); SmtpRelayService.reset_all_daily_stats()\" >> ${LOG_DIR}/cron.log 2>&1") | crontab -
    success "定时任务已配置"

    # 防火墙
    check_firewall

    # 文件权限
    chmod -R 755 "${DEPLOY_DIR}"
    chmod 600 "${DEPLOY_DIR}/.env"
    success "文件权限已设置"
    echo ""

    # ---- 完成 ----
    local elapsed=$(( $(date +%s) - TIMER_START ))
    local min=$(( elapsed / 60 ))
    local sec=$(( elapsed % 60 ))
    local ip=$(hostname -I | awk '{print $1}')

    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}       部署完成! (耗时 ${min}分${sec}秒)${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  ${CYAN}访问地址:${NC}  http://${ip}"
    echo -e "  ${CYAN}管理账号:${NC}  admin"
    echo -e "  ${CYAN}管理密码:${NC}  admin123456"
    echo -e "  ${CYAN}部署目录:${NC}  ${DEPLOY_DIR}"
    echo -e "  ${CYAN}日志目录:${NC}  ${LOG_DIR}"
    echo ""
    echo -e "${YELLOW}--- 常用命令 ---${NC}"
    echo -e "  查看状态:   sudo bash deploy-centos.sh --status"
    echo -e "  重启服务:   sudo bash deploy-centos.sh --restart"
    echo -e "  实时日志:   sudo bash deploy-centos.sh --logs"
    echo -e "  配置SSL:    sudo bash deploy-centos.sh --ssl yourdomain.com"
    echo -e "  卸载系统:   sudo bash deploy-centos.sh --uninstall"
    echo ""
    echo -e "${YELLOW}--- 手动管理 ---${NC}"
    echo -e "  supervisorctl status|restart|stop ${APP_NAME}"
    echo -e "  nginx -t && systemctl reload nginx"
    echo -e "  systemctl status mariadb  (或 mysqld)"
    echo -e "  systemctl status redis"
    echo -e "  mysql -u ${DB_USER} -p ${DB_NAME}"
    echo ""
    echo -e "${RED}!!! 请立即修改默认管理员密码 !!!${NC}"
    echo ""
}

# ==================== 入口 ====================
handle_quick_command "$1" 2>/dev/null || true
main_deploy "$1"
