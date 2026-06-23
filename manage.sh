#!/bin/bash
# ============================================================
# 邮件发送平台 - 一键管理脚本（安装/卸载）
# 支持 Docker 部署和普通部署
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ============================================================
# 所有函数定义（放在最前面）
# ============================================================

# 辅助函数
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }

# 自动安装 Docker
function install_docker_auto() {
    info "正在安装 Docker..."
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y yum-utils 2>/dev/null || true
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo 2>/dev/null || \
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    else
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | apt-key add - 2>/dev/null || \
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" 2>/dev/null || \
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
    fi
    systemctl start docker
    systemctl enable docker
    success "Docker 安装完成"
}

# 自动安装基础工具
function install_basics() {
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y epel-release gcc make openssl-devel bzip2-devel libffi-devel wget curl vim unzip git 2>/dev/null || true
    else
        apt-get update
        apt-get install -y wget curl vim unzip git gcc make libssl-dev libbz2-dev libffi-dev
    fi
}

# 自动安装 Python
function install_python39() {
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y python39 python39-devel python39-pip
    else
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
        apt-get update
        apt-get install -y python3.9 python3.9-venv python3.9-dev 2>/dev/null || \
        apt-get install -y python3 python3-venv python3-dev
    fi
}

# 自动安装 MySQL
function install_mysql() {
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y mariadb-server mariadb-devel
        systemctl start mariadb
        systemctl enable mariadb
    else
        apt-get install -y mysql-server mysql-client libmysqlclient-dev
        systemctl start mysql 2>/dev/null || true
        systemctl enable mysql 2>/dev/null || true
    fi
}

# 自动安装 Redis
function install_redis() {
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y redis
    else
        apt-get install -y redis-server
    fi
    systemctl start redis 2>/dev/null || true
    systemctl enable redis 2>/dev/null || true
}

# 自动安装 Nginx
function install_nginx() {
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y nginx
    else
        apt-get install -y nginx
    fi
    systemctl start nginx
    systemctl enable nginx
}

# 自动安装 Supervisor
function install_supervisor() {
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y supervisor
    else
        apt-get install -y supervisor
    fi
    systemctl start supervisord 2>/dev/null || systemctl start supervisor 2>/dev/null || true
    systemctl enable supervisord 2>/dev/null || systemctl enable supervisor 2>/dev/null || true
}

# 安装成功提示
function show_success() {
    local port=$1
    local domain=$2
    local ssl=$3
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo 'your-server-ip')

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║       部署完成！                          ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    if [ -n "$domain" ]; then
        if [ "$ssl" == "true" ]; then
            echo -e "  ${CYAN}HTTPS:${NC}  https://${domain}"
        fi
        echo -e "  ${CYAN}HTTP:${NC}   http://${domain}"
    fi
    echo -e "  ${CYAN}IP访问:${NC}  http://${server_ip}:${port}"
    echo -e "  ${CYAN}账号:${NC}   admin"
    echo -e "  ${CYAN}密码:${NC}   admin123456"
    echo ""
    echo -e "${RED}!!! 请立即修改默认密码 !!!${NC}"
}

# 卸载成功提示
function show_uninstall() {
    local type=$1
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║       ${type}卸载完成！                      ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# Docker 安装
# ============================================================
function install_docker() {
    echo ""
    info "开始 Docker 部署..."
    echo ""

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "无法检测系统类型"
    fi

    if ! command -v docker &> /dev/null; then
        warn "Docker 未安装，正在自动安装..."
        install_docker_auto
    else
        success "Docker 已安装"
    fi

    info "检查 docker-compose..."
    if command -v docker-compose &>/dev/null; then
        if ! docker-compose version &>/dev/null; then
            warn "docker-compose 损坏，重新安装..."
            rm -f $(which docker-compose) 2>/dev/null || true
            pip3 install docker-compose 2>/dev/null || pip install docker-compose
        fi
    else
        info "安装 docker-compose..."
        pip3 install docker-compose 2>/dev/null || pip install docker-compose
    fi
    success "docker-compose 可用"

    if [ ! -f /etc/docker/daemon.json ]; then
        info "配置 Docker 国内镜像加速..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
EOF
        systemctl restart docker
        success "镜像加速配置完成"
    fi

    echo ""
    read -p "  访问端口 [默认: 5200]: " input_port
    NGINX_PORT=${input_port:-5200}
    if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]]; then
        error "端口必须是数字"
    fi

    echo ""
    read -p "  绑定域名 [没有则留空]: " input_domain
    DOMAIN=${input_domain:-}

    ENABLE_SSL="false"
    if [ -n "$DOMAIN" ]; then
        read -p "  申请 SSL 证书? (y/n) [默认: n]: " ssl_input
        if [[ "$ssl_input" =~ ^[Yy]$ ]]; then
            ENABLE_SSL="true"
        fi
    fi

    PROJECT_DIR="/opt/email_platform"
    info "创建项目目录..."
    mkdir -p "$PROJECT_DIR" "$PROJECT_DIR/certbot-data" "$PROJECT_DIR/certbot-www" "$PROJECT_DIR/ssl"
    cd "$PROJECT_DIR"

    if [ ! -f "$PROJECT_DIR/app/app.py" ]; then
        info "下载项目源码..."
        cd /tmp
        rm -f email_platform.zip
        curl -L -o email_platform.zip "https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip" 2>/dev/null || \
        curl -L -o email_platform.zip "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"
        unzip -o email_platform.zip
        cp -r email_platform-main/* "$PROJECT_DIR/"
        cp -r email_platform-main/.* "$PROJECT_DIR/" 2>/dev/null || true
        rm -rf email_platform.zip email_platform-main
        cd "$PROJECT_DIR"
    fi
    success "项目源码准备完成"

    cp nginx-docker.conf nginx.conf

    SECRET_KEY=$(openssl rand -hex 32)
    JWT_SECRET_KEY=$(openssl rand -hex 32)
    cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
NGINX_PORT=${NGINX_PORT}
DOMAIN=${DOMAIN}
ENABLE_SSL=${ENABLE_SSL}
EOF

    info "启动 Docker 服务（首次启动可能需要几分钟）..."
    docker-compose down 2>/dev/null || true
    docker-compose up -d --build --no-cache

    info "等待服务启动..."
    sleep 25

    info "初始化数据库..."
    docker-compose exec -T app python3 -c "
from app.app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库初始化完成')
" 2>/dev/null || warn "数据库初始化可能需要手动执行"

    if [ "$ENABLE_SSL" = "true" ] && [ -n "$DOMAIN" ]; then
        info "申请 SSL 证书..."
        sleep 5
        docker-compose run --rm certbot certonly \
            --webroot --webroot-path /var/www/certbot \
            --email admin@${DOMAIN} --agree-tos --no-eff-email \
            -d ${DOMAIN} || warn "SSL 证书申请失败，请检查域名解析"
        docker-compose restart nginx
    fi

    info "服务状态:"
    docker-compose ps

    show_success "$NGINX_PORT" "$DOMAIN" "$ENABLE_SSL"
}

# ============================================================
# Docker 卸载
# ============================================================
function uninstall_docker() {
    echo ""
    info "开始卸载 Docker 部署..."
    echo ""
    read -p "  确认卸载? (y/n) [默认: n]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warn "已取消"
        exit 0
    fi

    read -p "  删除数据卷? (y/n) [默认: n]: " del_vol
    read -p "  删除项目目录? (y/n) [默认: n]: " del_dir
    read -p "  删除镜像? (y/n) [默认: n]: " del_img
    read -p "  卸载 Docker 软件? (y/n) [默认: n]: " del_docker

    PROJECT_DIR="/opt/email_platform"

    info "停止服务..."
    if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        cd "$PROJECT_DIR"
        docker-compose down 2>/dev/null || true
    else
        docker stop email_platform_app email_platform_mysql email_platform_redis email_platform_nginx email_platform_certbot 2>/dev/null || true
        docker rm -f email_platform_app email_platform_mysql email_platform_redis email_platform_nginx email_platform_certbot 2>/dev/null || true
    fi

    if [[ "$del_vol" =~ ^[Yy]$ ]]; then
        info "删除数据卷..."
        [ -f "$PROJECT_DIR/docker-compose.yml" ] && (cd "$PROJECT_DIR" && docker-compose down -v 2>/dev/null) || true
        docker volume rm email_platform_mysql_data email_platform_redis_data 2>/dev/null || true
    fi

    if [[ "$del_dir" =~ ^[Yy]$ ]]; then
        info "删除项目目录..."
        rm -rf "$PROJECT_DIR"
    fi

    if [[ "$del_img" =~ ^[Yy]$ ]]; then
        info "删除镜像..."
        docker rmi -f email_platform-app 2>/dev/null || true
        docker rmi -f docker.m.daocloud.io/library/mysql:8.0 2>/dev/null || true
        docker rmi -f docker.m.daocloud.io/library/redis:7-alpine 2>/dev/null || true
        docker rmi -f docker.m.daocloud.io/library/nginx:alpine 2>/dev/null || true
        docker rmi -f docker.m.daocloud.io/certbot/certbot:latest 2>/dev/null || true
    fi

    docker system prune -f 2>/dev/null || true

    if [[ "$del_docker" =~ ^[Yy]$ ]]; then
        info "卸载 Docker..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [ "$ID" == "centos" ] || [ "$ID" == "rhel" ]; then
                yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            else
                apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
            fi
        fi
        rm -rf /var/lib/docker
    fi

    show_uninstall "Docker"
}

# ============================================================
# 普通安装
# ============================================================
function install_normal() {
    echo ""
    info "开始普通部署..."
    echo ""

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "无法检测系统类型"
    fi

    read -p "  访问端口 [默认: 5200]: " input_port
    NGINX_PORT=${input_port:-5200}
    if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]]; then
        error "端口必须是数字"
    fi

    read -p "  数据库密码 [默认: EmailPlatform2024!]: " db_pass
    DB_PASS=${db_pass:-EmailPlatform2024!}

    info "检查并安装基础工具..."
    install_basics
    success "基础工具就绪"

    info "检查 Python..."
    PYTHON_CMD=""
    for cmd in python3.9 python3 python; do
        if command -v $cmd &>/dev/null; then
            PYTHON_CMD=$cmd
            break
        fi
    done
    if [ -z "$PYTHON_CMD" ]; then
        warn "Python 未安装，正在安装..."
        install_python39
        PYTHON_CMD="python3.9"
    fi
    success "Python 可用: $PYTHON_CMD"

    info "检查数据库..."
    if ! command -v mysql &>/dev/null; then
        warn "MySQL 未安装，正在安装..."
        install_mysql
    fi
    success "MySQL 可用"

    DB_NAME="email_platform"
    DB_USER="email_user"
    mysql -u root <<DBEOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
DBEOF
    success "数据库配置完成"

    info "检查 Redis..."
    if ! command -v redis-server &>/dev/null; then
        warn "Redis 未安装，正在安装..."
        install_redis
    fi
    success "Redis 可用"

    info "检查 Nginx..."
    if ! command -v nginx &>/dev/null; then
        warn "Nginx 未安装，正在安装..."
        install_nginx
    fi
    success "Nginx 可用"

    info "下载项目源码..."
    PROJECT_DIR="/opt/email_platform"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"

    if [ ! -f "$PROJECT_DIR/app/app.py" ]; then
        cd /tmp
        rm -f email_platform.zip
        curl -L -o email_platform.zip "https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip" 2>/dev/null || \
        curl -L -o email_platform.zip "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"
        unzip -o email_platform.zip
        cp -r email_platform-main/* "$PROJECT_DIR/"
        cp -r email_platform-main/.* "$PROJECT_DIR/" 2>/dev/null || true
        rm -rf email_platform.zip email_platform-main
        cd "$PROJECT_DIR"
    fi

    info "配置 Python 环境..."
    $PYTHON_CMD -m venv venv
    source venv/bin/activate
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple 2>/dev/null || true
    pip install --upgrade pip 2>/dev/null || true
    pip install -r requirements.txt 2>/dev/null || pip install Flask flask-cors flask-jwt-extended flask-limiter pymysql redis gunicorn
    pip install gunicorn 2>/dev/null || true

    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    JWT_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
DATABASE_URL=mysql+pymysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}?charset=utf8mb4
REDIS_URL=redis://localhost:6379/0
FLASK_ENV=production
EOF

    info "配置 Nginx..."
    cat > /etc/nginx/conf.d/email_platform.conf << EOF
upstream email_backend {
    server 127.0.0.1:5000;
    keepalive 64;
}
server {
    listen ${NGINX_PORT};
    server_name _;
    client_max_body_size 20M;
    location / {
        proxy_pass http://email_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    nginx -t && systemctl reload nginx

    info "检查 Supervisor..."
    if ! command -v supervisorctl &>/dev/null; then
        warn "Supervisor 未安装，正在安装..."
        install_supervisor
    fi
    success "Supervisor 可用"

    cat > /etc/supervisord.d/email_platform.ini << EOF
[program:email_platform]
command=${PROJECT_DIR}/venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 wsgi:app
directory=${PROJECT_DIR}
user=root
autostart=true
autorestart=true
stderr_logfile=/var/log/email_platform.err.log
stdout_logfile=/var/log/email_platform.out.log
environment=PATH="${PROJECT_DIR}/venv/bin"
EOF

    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true
    supervisorctl restart email_platform 2>/dev/null || true

    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=${NGINX_PORT}/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi
    if command -v ufw &>/dev/null; then
        ufw allow ${NGINX_PORT}/tcp 2>/dev/null || true
    fi

    show_success "$NGINX_PORT" "" "false"
}

# ============================================================
# 普通卸载
# ============================================================
function uninstall_normal() {
    echo ""
    info "开始卸载普通部署..."
    echo ""
    read -p "  确认卸载? (y/n) [默认: n]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warn "已取消"
        exit 0
    fi

    read -p "  删除数据库? (y/n) [默认: n]: " del_db
    read -p "  卸载软件? (y/n) [默认: n]: " del_sw

    PROJECT_DIR="/opt/email_platform"
    DB_NAME="email_platform"
    DB_USER="email_user"

    info "停止服务..."
    if command -v supervisorctl &>/dev/null; then
        supervisorctl stop email_platform 2>/dev/null || true
        supervisorctl remove email_platform 2>/dev/null || true
        rm -f /etc/supervisord.d/email_platform.ini
        supervisorctl reread && supervisorctl update 2>/dev/null || true
    fi

    rm -f /etc/nginx/conf.d/email_platform.conf
    nginx -t 2>/dev/null && systemctl reload nginx || true

    info "删除项目目录..."
    rm -rf "$PROJECT_DIR" 2>/dev/null
    rm -f /var/log/email_platform.err.log /var/log/email_platform.out.log

    if [[ "$del_db" =~ ^[Yy]$ ]]; then
        info "删除数据库..."
        if command -v mysql &>/dev/null; then
            mysql -u root <<DBEOF
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
DROP USER IF EXISTS '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
DBEOF
        fi
    fi

    if [[ "$del_sw" =~ ^[Yy]$ ]]; then
        info "卸载软件..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [ "$ID" == "centos" ] || [ "$ID" == "rhel" ]; then
                yum remove -y mariadb-server mariadb redis nginx supervisor 2>/dev/null || true
            else
                apt-get purge -y mysql-server redis-server nginx supervisor 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
            fi
        fi
    fi

    show_uninstall "普通"
}

# ============================================================
# 主菜单
# ============================================================

SCRIPT_URL="https://raw.githubusercontent.com/jiujiu123520/email_platform/main/manage.sh"
INSTALL_CMD="curl -fsSL $SCRIPT_URL -o /tmp/manage.sh && chmod +x /tmp/manage.sh && bash /tmp/manage.sh"

clear 2>/dev/null || true
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║      邮件发送平台 - 管理脚本              ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${YELLOW}安装命令:${NC}"
echo -e "  ${GREEN}$INSTALL_CMD${NC}"
echo ""

echo "  请选择："
echo ""
echo "    ${GREEN}1${NC}) Docker 安装（推荐）"
echo "    ${GREEN}2${NC}) 普通安装"
echo "    ${RED}3${NC}) Docker 卸载"
echo "    ${RED}4${NC}) 普通卸载"
echo "    ${YELLOW}0${NC}) 退出"
echo ""
read -p "  输入选项 [1]: " choice
choice=${choice:-1}

case $choice in
    1) install_docker ;;
    2) install_normal ;;
    3) uninstall_docker ;;
    4) uninstall_normal ;;
    0) echo "已退出"; exit 0 ;;
    *) error "无效选项" ;;
esac
