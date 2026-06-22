#!/usr/bin/env bash
# ============================================
# MailSystem 一键安装脚本 (CentOS / Debian / Ubuntu)
# ============================================

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_DIR="$SCRIPT_DIR"
WEB_ROOT_DEFAULT="/var/www/mailsystem"
WEB_ROOT="${WEB_ROOT:-$WEB_ROOT_DEFAULT}"

# 标志
SKIP_DEPS=0
SKIP_NGINX=0
SKIP_FIREWALL=0
SKIP_SERVICE=0
SKIP_DB=0
SILENT=0

# 参数
DB_HOST="127.0.0.1"
DB_PORT=3306
DB_NAME="mail_system"
DB_USER="mail_user"
DB_PASS=""
ADMIN_USER="admin"
ADMIN_PASS=""
ADMIN_EMAIL="admin@localhost.com"
ADMIN_PATH="admin"
ADMIN_PORT=8080
MAIL_HOSTNAME="mail.local"

print_banner() {
cat <<'EOF'
 __  __          _ _           ____            _       _
|  \/  | ___  __| (_) ___ ___ / ___|  ___ _ __(_)_   _| |_
| |\/| |/ _ \/ _` | |/ __/ _ \\___ \ / _ \ '__| | | | | __|
| |  | |  __/ (_| | | (_|  __/ ___) |  __/ |  | | |_| | |_
|_|  |_|\___|\__,_|_|\___\___||____/ \___|_|  |_|\__,_|\__|

        Self-hosted Mail System v1.0.0
EOF
}

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[FAIL]${NC} $*"; }

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VER="$VERSION_ID"
        OS_LIKE="$ID_LIKE"
    else
        log_err "无法识别操作系统，请使用 CentOS 7+ / Debian 9+ / Ubuntu 18+"
        exit 1
    fi
    log_info "检测到系统: $PRETTY_NAME"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_err "请使用 root 权限运行: sudo bash $0"
        exit 1
    fi
}

usage() {
cat <<EOF
用法: $0 [选项]

选项:
  --web-root=DIR          Web 部署目录 (默认: $WEB_ROOT_DEFAULT)
  --db-host=HOST          MySQL 主机 (默认: 127.0.0.1)
  --db-port=PORT          MySQL 端口 (默认: 3306)
  --db-name=NAME          数据库名 (默认: mail_system)
  --db-user=USER          数据库用户 (默认: mail_user)
  --db-pass=PASS          数据库密码 (随机生成)
  --admin-user=USER       管理员用户名 (默认: admin)
  --admin-pass=PASS       管理员密码 (随机生成)
  --admin-email=EMAIL     管理员邮箱
  --admin-path=PATH       后台路径 (默认: admin)
  --admin-port=PORT       后台端口 (默认: 8080)
  --mail-hostname=HOST    邮件主机名 (默认: mail.local)
  --skip-deps             跳过依赖安装
  --skip-nginx            跳过 Nginx 配置
  --skip-firewall         跳过防火墙配置
  --skip-service          跳过服务启动
  --skip-db               跳过数据库初始化
  --silent                静默模式 (使用默认值)
  --help                  显示帮助
EOF
}

parse_args() {
    for arg in "$@"; do
        case $arg in
            --web-root=*)    WEB_ROOT="${arg#*=}" ;;
            --db-host=*)     DB_HOST="${arg#*=}" ;;
            --db-port=*)     DB_PORT="${arg#*=}" ;;
            --db-name=*)     DB_NAME="${arg#*=}" ;;
            --db-user=*)     DB_USER="${arg#*=}" ;;
            --db-pass=*)     DB_PASS="${arg#*=}" ;;
            --admin-user=*)  ADMIN_USER="${arg#*=}" ;;
            --admin-pass=*)  ADMIN_PASS="${arg#*=}" ;;
            --admin-email=*) ADMIN_EMAIL="${arg#*=}" ;;
            --admin-path=*)  ADMIN_PATH="${arg#*=}" ;;
            --admin-port=*)  ADMIN_PORT="${arg#*=}" ;;
            --mail-hostname=*) MAIL_HOSTNAME="${arg#*=}" ;;
            --skip-deps)     SKIP_DEPS=1 ;;
            --skip-nginx)    SKIP_NGINX=1 ;;
            --skip-firewall) SKIP_FIREWALL=1 ;;
            --skip-service)  SKIP_SERVICE=1 ;;
            --skip-db)       SKIP_DB=1 ;;
            --silent)        SILENT=1 ;;
            --help|-h)       usage; exit 0 ;;
            *) log_warn "未知参数: $arg" ;;
        esac
    done
}

random_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

confirm_or_assign() {
    if [ -z "$1" ]; then
        eval "$2=$(random_password)"
        log_info "$3 已自动生成"
    fi
}

install_deps_centos() {
    log_info "使用 yum/dnf 安装依赖..."
    local PM="yum"
    command -v dnf >/dev/null 2>&1 && PM="dnf"
    $PM install -y epel-release yum-utils
    $PM install -y https://rpms.remirepo.net/enterprise/remi-release-7.rpm 2>/dev/null || true
    $PM install -y nginx mariadb-server mariadb php php-fpm php-cli \
        php-mysqlnd php-pdo php-mbstring php-iconv php-openssl \
        php-curl php-xml php-zip php-sockets php-pcntl \
        firewalld policycoreutils-python-utils
    $PM install -y --setopt=tsflags=nodocs fail2ban 2>/dev/null || true
    log_ok "依赖安装完成"
}

install_deps_debian() {
    log_info "使用 apt 安装依赖..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        nginx mariadb-server mariadb-client \
        php php-fpm php-cli php-mysql php-mbstring \
        php-xml php-curl php-zip php-sockets php-pcntl \
        php-openssl php-iconv ufw fail2ban
    log_ok "依赖安装完成"
}

configure_db() {
    log_info "初始化数据库..."
    # 启动 MySQL/MariaDB
    if command -v systemctl >/dev/null; then
        systemctl enable --now mariadb || systemctl enable --now mysql || true
    fi
    sleep 2

    # 等待数据库就绪
    for i in 1 2 3 4 5; do
        if mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" 2>/dev/null; then break; fi
        sleep 2
    done

    # 创建数据库与用户
    mysql -h "$DB_HOST" -P "$DB_PORT" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
    log_ok "数据库 $DB_NAME 已创建"
}

deploy_files() {
    log_info "部署文件到 $WEB_ROOT ..."
    mkdir -p "$WEB_ROOT"
    # 复制文件
    rsync -a --delete \
        --exclude='.git' \
        --exclude='.env' \
        --exclude='storage/installed.lock' \
        --exclude='storage/cache' \
        --exclude='storage/sessions' \
        --exclude='logs' \
        --exclude='data' \
        "$APP_DIR/" "$WEB_ROOT/"

    # 目录权限
    mkdir -p "$WEB_ROOT/storage/cache" "$WEB_ROOT/storage/sessions" \
             "$WEB_ROOT/data/mailboxes" "$WEB_ROOT/logs"
    chown -R nginx:nginx "$WEB_ROOT" 2>/dev/null || chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || true
    chmod -R 755 "$WEB_ROOT"
    chmod -R 770 "$WEB_ROOT/storage" "$WEB_ROOT/data" "$WEB_ROOT/logs"
    log_ok "文件已部署"
}

write_env() {
    log_info "生成 .env 配置..."
    local APP_KEY=$(random_password | md5sum | cut -c1-32)
    cat > "$WEB_ROOT/.env" <<EOF
# MailSystem Config
APP_NAME=MailSystem
APP_ENV=production
APP_DEBUG=false
APP_URL=http://localhost
APP_TIMEZONE=Asia/Shanghai
APP_KEY=$APP_KEY

DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS
DB_CHARSET=utf8mb4

ADMIN_PATH=$ADMIN_PATH
ADMIN_PORT=$ADMIN_PORT
WEB_PORT=80

MAIL_HOSTNAME=$MAIL_HOSTNAME
LOG_PATH=$WEB_ROOT/logs
MAIL_STORAGE_PATH=$WEB_ROOT/data/mailboxes
EOF
    chmod 600 "$WEB_ROOT/.env"
    log_ok ".env 已生成"
}

run_installer() {
    log_info "运行 Web 安装程序..."
    # 通过 CLI 模拟安装
    php "$WEB_ROOT/bin/install-cli.php" \
        --db-host="$DB_HOST" --db-port="$DB_PORT" --db-name="$DB_NAME" \
        --db-user="$DB_USER" --db-pass="$DB_PASS" \
        --admin-user="$ADMIN_USER" --admin-pass="$ADMIN_PASS" --admin-email="$ADMIN_EMAIL" \
        --admin-path="$ADMIN_PATH" --admin-port="$ADMIN_PORT" \
        --mail-hostname="$MAIL_HOSTNAME" --app-url="http://localhost"
    log_ok "系统已安装"
}

configure_php_fpm() {
    log_info "配置 PHP-FPM..."
    local POOL="/etc/php-fpm.d/www.conf"
    [ -f "$POOL" ] || POOL="/etc/php/7.4/fpm/pool.d/www.conf"
    [ -f "$POOL" ] || POOL="/etc/php-fpm.d/www.conf"
    if [ -f "$POOL" ]; then
        sed -i "s/^user = .*/user = nginx/" "$POOL" 2>/dev/null || sed -i "s/^user = .*/user = www-data/" "$POOL"
        sed -i "s/^group = .*/group = nginx/" "$POOL" 2>/dev/null || sed -i "s/^group = .*/group = www-data/" "$POOL"
        sed -i "s/^listen.owner = .*/listen.owner = nginx/" "$POOL" 2>/dev/null || sed -i "s/^listen.owner = .*/listen.owner = www-data/" "$POOL"
        sed -i "s/^listen.group = .*/listen.group = nginx/" "$POOL" 2>/dev/null || sed -i "s/^listen.group = .*/listen.group = www-data/" "$POOL"
        sed -i "s|^listen = .*|listen = 127.0.0.1:9000|" "$POOL"
    fi
    systemctl enable --now php-fpm 2>/dev/null || true
    log_ok "PHP-FPM 已配置"
}

configure_nginx() {
    log_info "配置 Nginx..."
    local NGINX_CONF="/etc/nginx/conf.d/mailsystem.conf"
    [ -d /etc/nginx/sites-enabled ] && NGINX_CONF="/etc/nginx/sites-available/mailsystem"
    local SERVER_NAME=$(hostname -f 2>/dev/null || hostname)
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root $WEB_ROOT/public;
    index index.php index.html;

    client_max_body_size 50M;

    # 前台
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # 后台
    location /$ADMIN_PATH/ {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # 静态资源
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|map)\$ {
        expires 30d;
        access_log off;
    }

    # PHP 处理
    location ~ \.php\$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    # 安全
    location ~ /\.(git|env) { deny all; }
    location ~ /(storage|data|logs)/ { deny all; }
}
EOF
    # 如果有 sites-enabled 目录，启用
    [ -d /etc/nginx/sites-enabled ] && ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/mailsystem && rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx
    log_ok "Nginx 已配置"
}

configure_firewall() {
    log_info "配置防火墙..."
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=25/tcp
        firewall-cmd --permanent --add-port=465/tcp
        firewall-cmd --permanent --add-port=587/tcp
        firewall-cmd --permanent --add-port=110/tcp
        firewall-cmd --permanent --add-port=995/tcp
        firewall-cmd --permanent --add-port=143/tcp
        firewall-cmd --permanent --add-port=993/tcp
        firewall-cmd --reload
        log_ok "firewalld 已配置"
    elif command -v ufw >/dev/null; then
        ufw allow http
        ufw allow https
        ufw allow 25/tcp
        ufw allow 465/tcp
        ufw allow 587/tcp
        ufw allow 110/tcp
        ufw allow 995/tcp
        ufw allow 143/tcp
        ufw allow 993/tcp
        ufw --force enable
        log_ok "ufw 已配置"
    else
        log_warn "未找到防火墙工具，请手动开放 80/25/465/587/110/995/143/993 端口"
    fi
}

configure_service() {
    log_info "配置 systemd 服务..."
    local SVC_FILE="/etc/systemd/system/mailsystem.service"
    cat > "$SVC_FILE" <<EOF
[Unit]
Description=MailSystem Mail Services (SMTP/POP3/IMAP)
After=network.target mysql.service mariadb.service php-fpm.service

[Service]
Type=simple
User=root
WorkingDirectory=$WEB_ROOT
ExecStart=/usr/bin/php $WEB_ROOT/bin/services.php start
ExecStop=/usr/bin/php $WEB_ROOT/bin/services.php stop
Restart=always
RestartSec=5
StandardOutput=append:$WEB_ROOT/logs/services.log
StandardError=append:$WEB_ROOT/logs/services.log

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable mailsystem
    systemctl restart mailsystem
    log_ok "服务已配置并启动"
}

print_summary() {
cat <<EOF

${GREEN}=================================================================${NC}
${GREEN}        MailSystem 安装完成！${NC}
${GREEN}=================================================================${NC}

  后台地址:    http://服务器IP/$ADMIN_PATH/
  默认账号:    $ADMIN_USER
  默认密码:    $ADMIN_PASS

  邮件协议端口:
    SMTP:    25  (明文) / 465 (SSL) / 587 (STARTTLS)
    POP3:    110 (明文) / 995 (SSL)
    IMAP:    143 (STARTTLS) / 993 (SSL)

  数据库信息:
    主机: $DB_HOST:$DB_PORT
    数据库: $DB_NAME
    用户: $DB_USER
    密码: $DB_PASS

  文件目录:
    项目:  $WEB_ROOT
    邮件:  $WEB_ROOT/data/mailboxes
    日志:  $WEB_ROOT/logs
    配置:  $WEB_ROOT/.env

  服务管理:
    systemctl status mailsystem
    systemctl restart mailsystem
    systemctl stop mailsystem

${YELLOW}提示: 邮箱域名需要在 DNS 服务商添加 MX / A / TXT 记录才能外网收发${NC}
${YELLOW}     后台 → 域名管理 → 点击 DNS 按钮查看需要添加的记录${NC}

${GREEN}=================================================================${NC}

EOF
}

# ============================================
# 主流程
# ============================================
main() {
    print_banner
    parse_args "$@"
    check_root
    detect_os

    # 设置默认密码
    [ -z "$DB_PASS" ] && DB_PASS=$(random_password)
    [ -z "$ADMIN_PASS" ] && ADMIN_PASS=$(random_password)
    [ -z "$ADMIN_EMAIL" ] && ADMIN_EMAIL="admin@$(hostname -d 2>/dev/null || echo localhost)"

    # 静默模式确认
    if [ "$SILENT" -eq 0 ] && [ -t 0 ]; then
        echo
        echo "即将开始安装，配置如下："
        echo "  Web 目录:   $WEB_ROOT"
        echo "  数据库:     $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
        echo "  管理员:     $ADMIN_USER / $ADMIN_PASS"
        echo "  后台路径:   /$ADMIN_PATH/"
        echo "  邮件主机名: $MAIL_HOSTNAME"
        echo
        read -p "按 Enter 继续，Ctrl+C 取消..."
    fi

    # 安装依赖
    if [ "$SKIP_DEPS" -eq 0 ]; then
        case "$OS_LIKE" in
            *rhel*|*centos*|*fedora*) install_deps_centos ;;
            *debian*|*ubuntu*)       install_deps_debian ;;
            *) log_err "不支持的系统: $OS_LIKE"; exit 1 ;;
        esac
    fi

    # 部署文件
    deploy_files

    # 初始化数据库
    if [ "$SKIP_DB" -eq 0 ]; then
        configure_db
    fi

    # 写入 .env
    write_env

    # 运行安装
    run_installer

    # 配置 PHP-FPM
    configure_php_fpm

    # 配置 Nginx
    if [ "$SKIP_NGINX" -eq 0 ]; then
        configure_nginx
    fi

    # 配置防火墙
    if [ "$SKIP_FIREWALL" -eq 0 ]; then
        configure_firewall
    fi

    # 启动服务
    if [ "$SKIP_SERVICE" -eq 0 ]; then
        configure_service
    fi

    print_summary
}

main "$@"
