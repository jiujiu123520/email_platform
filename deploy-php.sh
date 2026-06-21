#!/bin/bash
# ============================================================
#  邮件发送平台 - PHP 版本一键部署脚本
#  适用：腾讯云 CentOS 7.6
#  技术栈：PHP 8.0 + ThinkPHP 6 + SQL Server + Nginx
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
APP_NAME="email_platform"
DEPLOY_DIR="/opt/email_platform"
APP_PORT="${APP_PORT:-8080}"
DB_NAME="${APP_NAME}"
DB_USER="sa"
DB_PASS="${DB_PASS:-EmailPlatform2024!}"
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "服务器IP")

info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }
step()    { echo ""; echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

START_TIME=$(date +%s)

# 下载文件（多代理回退）
download_file() {
    local github_file="$1"
    local output="$2"

    local urls=(
        "https://gh.jasonzeng.dev/https://github.com/${github_file}"
        "https://mirror.ghproxy.com/https://github.com/${github_file}"
        "https://kgithub.com/${github_file}"
        "https://gitclone.com/github.com/${github_file}"
        "https://ghproxy.com/https://github.com/${github_file}"
        "https://github.com/${github_file}"
    )

    for u in "${urls[@]}"; do
        info "下载: $u"
        if curl -fsSL --connect-timeout 15 --max-time 120 -o "$output" "$u" 2>/dev/null; then
            if [ -s "$output" ]; then
                success "下载成功"
                return 0
            fi
        fi
    done
    return 1
}

# ============================================================
# 主流程
# ============================================================
main() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║   邮件发送平台 PHP 版 - 一键部署      ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    info "部署目录: $DEPLOY_DIR"
    info "访问端口: $APP_PORT"
    info "数据库: SQL Server"

    # ---- 步骤 1: 下载项目源码 ----
    step "1/8  下载项目源码"
    mkdir -p "$DEPLOY_DIR"
    cd /tmp

    info "正在下载项目源码..."
    if ! download_file "jiujiu123520/email_platform/archive/refs/heads/main.zip" "/tmp/email_platform.zip"; then
        error "源码下载失败，请检查网络连接"
    fi

    unzip -o -q /tmp/email_platform.zip
    rm -rf "${DEPLOY_DIR:?}"/*
    cp -a /tmp/email_platform-main/. "$DEPLOY_DIR/"
    rm -rf /tmp/email_platform.zip /tmp/email_platform-main
    cd "$DEPLOY_DIR"
    success "源码准备完成"

    # ---- 步骤 2: 安装 EPEL 和基础依赖 ----
    step "2/8  安装 EPEL 和基础依赖"
    yum install -y epel-release 2>/dev/null
    yum install -y \
        wget curl git unzip \
        net-tools vim htop \
        supervisor \
        logrotate \
        2>/dev/null || true
    success "基础依赖安装完成"

    # ---- 步骤 3: 安装 PHP 8.0 ----
    step "3/8  安装 PHP 8.0"

    if ! command -v php &>/dev/null || [[ "$(php -r 'echo PHP_MAJOR_VERSION;')" -lt 8 ]]; then
        info "安装 Remi 源..."
        yum install -y yum-utils 2>/dev/null || true
        rpm -Uvh https://mirrors.cloud.tencent.com/remi/enterprise/remi-release-7.rpm 2>/dev/null || \
        rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 2>/dev/null || true
        yum-config-manager --enable remi-php80 2>/dev/null || true

        info "安装 PHP 8.0 及扩展..."
        yum install -y php php-cli php-fpm php-mysqlnd php-xml php-xmlrpc php-mbstring \
            php-curl php-sqlsrv php-pdo_sqlsrv php-json php-gd php-bcmath \
            2>/dev/null || true
    fi

    PHP_BIN=$(command -v php)
    info "PHP 版本: $($PHP_BIN -v | head -1)"
    success "PHP 安装完成"

    # ---- 步骤 4: 安装 SQL Server ----
    step "4/8  安装 SQL Server"

    if ! command -v sqlcmd &>/dev/null; then
        info "安装 SQL Server 驱动..."
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | rpm --import - 2>/dev/null || true
        curl -fsSL https://packages.microsoft.com/config/rhel/7/prod.repo -o /etc/yum.repos.d/mssql-release.repo 2>/dev/null || true
        yum install -y mssql-tools unixODBC-devel 2>/dev/null || true
        export PATH="$PATH:/opt/mssql-tools/bin"
    fi

    success "SQL Server 驱动安装完成"

    # ---- 步骤 5: 配置 Nginx + PHP-FPM ----
    step "5/8  配置 Nginx 和 PHP-FPM"

    # 创建 PHP-FPM 配置
    cat > /etc/php-fpm.d/www.conf << 'PHPFPMEOF'
[www]
user = nginx
group = nginx
listen = /var/run/php-fpm/php-fpm.sock
listen.owner = nginx
listen.group = nginx
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500
PHPFPMEOF

    mkdir -p /var/run/php-fpm
    systemctl enable php-fpm 2>/dev/null || true
    systemctl start php-fpm 2>/dev/null || true

    # 创建 Nginx 配置
    mkdir -p /etc/nginx/conf.d
    cat > /etc/nginx/conf.d/email_platform.conf << 'NGINXEOF'
server {
    listen 8080;
    server_name _;
    root /opt/email_platform/public;
    index index.php index.html;

    client_max_body_size 20M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXEOF

    nginx -t 2>/dev/null && systemctl reload nginx || true
    success "Nginx 和 PHP-FPM 配置完成"

    # ---- 步骤 6: 安装 Composer 和项目依赖 ----
    step "6/8  安装 Composer 和 PHP 依赖"

    # 安装 Composer
    if [ ! -f /usr/local/bin/composer ]; then
        info "安装 Composer..."
        curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php 2>/dev/null || true
        php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer 2>/dev/null || true
        rm -f /tmp/composer-setup.php
    fi

    cd "$DEPLOY_DIR"
    info "安装 PHP 依赖..."
    composer install --no-dev --optimize-autoloader 2>/dev/null || true
    success "Composer 依赖安装完成"

    # ---- 步骤 7: 配置应用 ----
    step "7/8  配置应用"

    # 创建环境配置文件
    cat > "$DEPLOY_DIR/.env" << EOF
APP_DEBUG=false
APP_TRACE=false

DB_TYPE=sqlsrv
DB_HOSTNAME=127.0.0.1
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}
DB_HOSTPORT=1433

CACHE_DRIVER=file
SESSION_DRIVER=file

JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
JWT_EXPIRE=7200
EOF

    # 创建 runtime 目录
    mkdir -p "$DEPLOY_DIR/runtime"
    chmod -R 777 "$DEPLOY_DIR/runtime"

    # 初始化数据库
    info "初始化数据库..."
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$DB_PASS" -Q "
        IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '${DB_NAME}')
        BEGIN
            CREATE DATABASE ${DB_NAME};
        END
    " 2>/dev/null || true

    # 创建数据表
    create_tables

    success "应用配置完成"

    # ---- 步骤 8: 启动服务 ----
    step "8/8  启动服务"

    # 确保 php-fpm 运行
    systemctl restart php-fpm 2>/dev/null || true

    # 确保 nginx 运行
    systemctl restart nginx 2>/dev/null || true

    # 配置Supervisor
    configure_supervisor

    sleep 3

    ELAPSED=$(( $(date +%s) - START_TIME ))
    MINS=$(( ELAPSED / 60 ))
    SECS=$(( ELAPSED % 60 ))

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║           部署完成！                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}访问地址:${NC}  http://${SERVER_IP}:${APP_PORT}"
    echo -e "  ${CYAN}管理账号:${NC}  admin"
    echo -e "  ${CYAN}管理密码:${NC}  admin123456"
    echo -e "  ${CYAN}部署目录:${NC}  $DEPLOY_DIR"
    echo -e "  ${CYAN}部署耗时:${NC}  ${MINS}分${SECS}秒"
    echo ""
    echo -e "${YELLOW}--- 运维命令 ---${NC}"
    echo -e "  重启应用:   systemctl restart php-fpm && systemctl restart nginx"
    echo -e "  查看状态:   systemctl status php-fpm nginx"
    echo -e "  查看日志:   tail -f /var/log/nginx/error.log"
    echo ""
    echo -e "${RED}${BOLD}!!! 请立即修改默认管理员密码 admin123456 !!!${NC}"
    echo ""
}

# 创建数据库表
create_tables() {
    info "创建数据库表..."
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$DB_PASS" -d "$DB_NAME" -Q "
        IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'users')
        BEGIN
            CREATE TABLE users (
                id INT IDENTITY(1,1) PRIMARY KEY,
                username NVARCHAR(50) NOT NULL UNIQUE,
                password NVARCHAR(255) NOT NULL,
                email NVARCHAR(100) NOT NULL,
                display_name NVARCHAR(100),
                role NVARCHAR(20) DEFAULT 'user',
                group_id INT,
                daily_quota INT DEFAULT 100,
                used_quota INT DEFAULT 0,
                total_sent INT DEFAULT 0,
                is_deleted INT DEFAULT 0,
                created_at DATETIME DEFAULT GETDATE(),
                updated_at DATETIME DEFAULT GETDATE(),
                deleted_at DATETIME NULL
            );

            CREATE TABLE user_groups (
                id INT IDENTITY(1,1) PRIMARY KEY,
                name NVARCHAR(100) NOT NULL,
                description NVARCHAR(500),
                created_at DATETIME DEFAULT GETDATE(),
                updated_at DATETIME DEFAULT GETDATE()
            );

            CREATE TABLE email_templates (
                id INT IDENTITY(1,1) PRIMARY KEY,
                name NVARCHAR(100) NOT NULL,
                subject NVARCHAR(255),
                html_content NVARCHAR(MAX),
                text_content NVARCHAR(MAX),
                is_default INT DEFAULT 0,
                created_by INT,
                is_deleted INT DEFAULT 0,
                created_at DATETIME DEFAULT GETDATE(),
                updated_at DATETIME DEFAULT GETDATE(),
                deleted_at DATETIME NULL
            );

            CREATE TABLE email_records (
                id INT IDENTITY(1,1) PRIMARY KEY,
                sender_id INT NOT NULL,
                from_email NVARCHAR(100),
                from_name NVARCHAR(100),
                to_email NVARCHAR(100) NOT NULL,
                to_name NVARCHAR(100),
                subject NVARCHAR(255),
                html_content NVARCHAR(MAX),
                text_content NVARCHAR(MAX),
                template_id INT,
                smtp_relay_id INT,
                status NVARCHAR(20) DEFAULT 'pending',
                error_message NVARCHAR(500),
                retry_count INT DEFAULT 0,
                sent_at DATETIME NULL,
                is_deleted INT DEFAULT 0,
                created_at DATETIME DEFAULT GETDATE(),
                updated_at DATETIME DEFAULT GETDATE(),
                deleted_at DATETIME NULL
            );

            CREATE TABLE smtp_relays (
                id INT IDENTITY(1,1) PRIMARY KEY,
                name NVARCHAR(100) NOT NULL,
                host NVARCHAR(255) NOT NULL,
                port INT DEFAULT 25,
                username NVARCHAR(100),
                password NVARCHAR(255),
                from_email NVARCHAR(100),
                from_name NVARCHAR(100),
                is_active INT DEFAULT 1,
                is_global INT DEFAULT 0,
                priority INT DEFAULT 1,
                max_daily_quota INT DEFAULT 1000,
                used_today INT DEFAULT 0,
                consecutive_failures INT DEFAULT 0,
                is_paused INT DEFAULT 0,
                last_used_at DATETIME NULL,
                is_deleted INT DEFAULT 0,
                created_at DATETIME DEFAULT GETDATE(),
                updated_at DATETIME DEFAULT GETDATE(),
                deleted_at DATETIME NULL
            );

            CREATE TABLE audit_logs (
                id INT IDENTITY(1,1) PRIMARY KEY,
                user_id INT,
                action NVARCHAR(50) NOT NULL,
                ip NVARCHAR(50),
                user_agent NVARCHAR(500),
                details NVARCHAR(MAX),
                is_deleted INT DEFAULT 0,
                created_at DATETIME DEFAULT GETDATE(),
                deleted_at DATETIME NULL
            );

            CREATE TABLE api_configs (
                id INT IDENTITY(1,1) PRIMARY KEY,
                name NVARCHAR(100) NOT NULL,
                description NVARCHAR(500),
                base_url NVARCHAR(255),
                api_key NVARCHAR(255),
                enabled INT DEFAULT 1,
                is_deleted INT DEFAULT 0,
                created_at DATETIME DEFAULT GETDATE(),
                updated_at DATETIME DEFAULT GETDATE(),
                deleted_at DATETIME NULL
            );

            -- 创建默认管理员
            INSERT INTO users (username, password, email, display_name, role, daily_quota)
            VALUES ('admin', '\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin@example.com', '系统管理员', 'super_admin', 999999);

            -- 创建默认 SMTP 中继
            INSERT INTO smtp_relays (name, host, port, username, password, from_email, from_name, is_global, priority)
            VALUES ('默认本地SMTP', 'localhost', 25, '', '', 'noreply@example.com', '邮件平台', 1, 1);
        END
    " 2>/dev/null || warn "数据库表创建可能需要手动完成"
}

# 配置Supervisor
configure_supervisor() {
    cat > /etc/supervisord.d/email_platform.ini << 'SUPERVISOREOF'
[program:php-fpm]
command=/usr/sbin/php-fpm --nodaemonize
autostart=true
autorestart=true
stdout_logfile=/var/log/email_platform.out.log
stderr_logfile=/var/log/email_platform.err.log
SUPERVISOREOF

    if [ ! -f /etc/supervisord.conf ]; then
        echo -e "[supervisord]\nlogfile=/var/log/supervisord.log\npidfile=/var/run/supervisord.pid\nchildlogdir=/var/log" > /etc/supervisord.conf
    fi
    if ! grep -q "supervisord.d" /etc/supervisord.conf 2>/dev/null; then
        echo -e "\n[include]\nfiles = /etc/supervisord.d/*.ini" >> /etc/supervisord.conf
    fi

    supervisord -c /etc/supervisord.conf 2>/dev/null || true
}

# ============================================================
# 卸载
# ============================================================
uninstall() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       邮件发送平台 PHP 版 - 卸载      ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""

    read -p "  确认卸载？这将删除所有数据！(y/n) [n]: " confirm
    confirm=${confirm:-n}
    [[ ! "$confirm" =~ ^[Yy]$ ]] && info "已取消" && exit 0

    step "1/3  停止服务"
    systemctl stop php-fpm nginx 2>/dev/null || true
    supervisorctl -c /etc/supervisord.conf stop email_platform 2>/dev/null || true
    rm -f /etc/supervisord.d/email_platform.ini
    rm -f /etc/nginx/conf.d/email_platform.conf
    systemctl reload nginx 2>/dev/null || true
    success "服务已停止"

    step "2/3  删除项目目录"
    rm -rf "$DEPLOY_DIR"
    success "项目目录已删除"

    step "3/3  完成"
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║           卸载完成！                  ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# 主入口
# ============================================================
case "${1:-install}" in
    install|i)
        main
        ;;
    uninstall|u)
        uninstall
        ;;
    restart|r)
        systemctl restart php-fpm nginx 2>/dev/null
        echo "服务已重启"
        ;;
    status|s)
        systemctl status php-fpm nginx --no-pager 2>/dev/null || echo "检查失败"
        ;;
    help|h|-h|--help)
        echo ""
        echo -e "${BOLD}用法:${NC}  bash $0 <命令>"
        echo ""
        echo -e "  ${GREEN}install${NC}     安装（默认）"
        echo -e "  ${RED}uninstall${NC}    卸载"
        echo -e "  ${YELLOW}restart${NC}     重启服务"
        echo -e "  ${CYAN}status${NC}      查看状态"
        echo ""
        ;;
    *)
        echo "用法: bash $0 {install|uninstall|restart|status|help}"
        echo "默认: install"
        ;;
esac
