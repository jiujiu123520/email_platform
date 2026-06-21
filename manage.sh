#!/bin/bash
# ============================================================
# 邮件发送平台 - 一键管理脚本（安装/卸载）
# 支持 Docker 部署和普通部署
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }

show_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════╗"
    echo "║     邮件发送平台 - 一键管理脚本         ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_banner
echo ""
echo "  请选择操作："
echo ""
echo "    ${GREEN}1) 安装 - Docker 部署（推荐）${NC}"
echo "    ${GREEN}2) 安装 - 普通部署（无 Docker）${NC}"
echo "    ${RED}3) 卸载 - Docker 部署${NC}"
echo "    ${RED}4) 卸载 - 普通部署${NC}"
echo "    ${YELLOW}0) 退出${NC}"
echo ""
read -p "  请输入选项 (0-4) [默认: 1]: " choice
choice=${choice:-1}

case $choice in
    1) install_docker ;;
    2) install_normal ;;
    3) uninstall_docker ;;
    4) uninstall_normal ;;
    0) echo "已退出"; exit 0 ;;
    *) error "无效选项" ;;
esac

# ============================================================
# Docker 安装
# ============================================================
install_docker() {
    echo ""
    info "开始 Docker 部署..."
    echo ""

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker"
    fi

    # 修复 docker-compose
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

    # 交互式配置
    echo ""
    read -p "  请输入访问端口 [默认: 5200]: " input_port
    NGINX_PORT=${input_port:-5200}
    if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]]; then
        error "端口必须是数字"
    fi

    echo ""
    read -p "  请输入绑定域名 [没有则留空]: " input_domain
    DOMAIN=${input_domain:-}

    ENABLE_SSL="false"
    if [ -n "$DOMAIN" ]; then
        read -p "  是否申请 Let's Encrypt 免费 SSL 证书? (y/n) [默认: n]: " ssl_input
        if [[ "$ssl_input" =~ ^[Yy]$ ]]; then
            ENABLE_SSL="true"
        fi
    fi

    # 创建项目目录
    PROJECT_DIR="/opt/email_platform"
    info "创建项目目录..."
    mkdir -p "$PROJECT_DIR" "$PROJECT_DIR/certbot-data" "$PROJECT_DIR/certbot-www" "$PROJECT_DIR/ssl"
    cd "$PROJECT_DIR"

    # 获取项目源码
    if [ ! -f "$PROJECT_DIR/app/app.py" ]; then
        info "下载项目源码..."
        cd /tmp
        rm -f email_platform.zip
        curl -L -o email_platform.zip "https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip" || \
        curl -L -o email_platform.zip "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"
        unzip -o email_platform.zip
        cp -r email_platform-main/* "$PROJECT_DIR/"
        cp -r email_platform-main/.* "$PROJECT_DIR/" 2>/dev/null || true
        rm -rf email_platform.zip email_platform-main
        cd "$PROJECT_DIR"
    fi
    success "项目源码准备完成"

    # 复制 Nginx 配置
    cp nginx-docker.conf nginx.conf

    # 生成配置文件
    SECRET_KEY=$(openssl rand -hex 32)
    JWT_SECRET_KEY=$(openssl rand -hex 32)
    cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
NGINX_PORT=${NGINX_PORT}
DOMAIN=${DOMAIN}
ENABLE_SSL=${ENABLE_SSL}
EOF

    # 启动服务
    info "启动 Docker 服务（首次启动可能需要几分钟构建）..."
    docker-compose down 2>/dev/null || true
    docker-compose up -d --build --no-cache

    # 等待 MySQL 启动
    info "等待数据库启动..."
    sleep 25

    # 初始化数据库
    info "初始化数据库..."
    docker-compose exec -T app python3 -c "
from app.app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库初始化完成')
" 2>/dev/null || warn "数据库初始化可能需要手动执行"

    # 申请 SSL 证书
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
uninstall_docker() {
    echo ""
    info "开始卸载 Docker 部署..."
    echo ""
    read -p "  确认卸载吗? (y/n) [默认: n]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warn "已取消"
        exit 0
    fi

    read -p "  删除数据卷（数据库、Redis）? (y/n) [默认: n]: " del_vol
    read -p "  删除项目目录? (y/n) [默认: n]: " del_dir
    read -p "  删除 Docker 镜像? (y/n) [默认: n]: " del_img
    read -p "  卸载 Docker 软件? (y/n) [默认: n]: " del_docker

    PROJECT_DIR="/opt/email_platform"

    info "停止并删除容器..."
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
    docker network rm email_platform_email_network 2>/dev/null || true

    if [[ "$del_docker" =~ ^[Yy]$ ]]; then
        info "卸载 Docker 软件..."
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
install_normal() {
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
    DB_PASS=${db_pass:-EmailPlatform2024!'}

    # 安装基础工具
    info "安装基础工具..."
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y epel-release gcc make openssl-devel bzip2-devel libffi-devel wget curl vim unzip
    else
        apt-get update
        apt-get install -y wget curl vim unzip git gcc make libssl-dev libbz2-dev libffi-dev
    fi

    # 安装 Python 3.9
    info "安装 Python 3.9..."
    if ! command -v python3.9 &>/dev/null; then
        if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
            yum install -y python39 python39-devel python39-pip
        else
            apt-get install -y software-properties-common
            add-apt-repository -y ppa:deadsnakes/ppa
            apt-get update
            apt-get install -y python3.9 python3.9-venv python3.9-dev
        fi
    fi

    # 安装数据库
    info "安装数据库..."
    if ! command -v mysql &>/dev/null; then
        if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
            yum install -y mariadb-server mariadb-devel
            systemctl start mariadb
            systemctl enable mariadb
        else
            apt-get install -y mysql-server mysql-client libmysqlclient-dev
            systemctl start mysql
            systemctl enable mysql
        fi
    fi

    DB_NAME="email_platform"
    DB_USER="email_user"
    mysql -u root <<DBEOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
DBEOF

    # 安装 Redis
    info "安装 Redis..."
    if ! command -v redis-server &>/dev/null; then
        if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
            yum install -y redis
        else
            apt-get install -y redis-server
        fi
        systemctl start redis
        systemctl enable redis
    fi

    # 安装 Nginx
    info "安装 Nginx..."
    if ! command -v nginx &>/dev/null; then
        if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
            yum install -y nginx
        else
            apt-get install -y nginx
        fi
        systemctl start nginx
        systemctl enable nginx
    fi

    # 下载项目
    info "下载项目源码..."
    PROJECT_DIR="/opt/email_platform"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"

    if [ ! -f "$PROJECT_DIR/app/app.py" ]; then
        cd /tmp
        rm -f email_platform.zip
        curl -L -o email_platform.zip "https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip" || \
        curl -L -o email_platform.zip "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"
        unzip -o email_platform.zip
        cp -r email_platform-main/* "$PROJECT_DIR/"
        cp -r email_platform-main/.* "$PROJECT_DIR/" 2>/dev/null || true
        rm -rf email_platform.zip email_platform-main
        cd "$PROJECT_DIR"
    fi

    # 配置虚拟环境
    info "配置 Python 虚拟环境..."
    python3.9 -m venv venv
    source venv/bin/activate
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    pip install --upgrade pip
    pip install -r requirements.txt
    pip install gunicorn

    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    JWT_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
DATABASE_URL=mysql+pymysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}?charset=utf8mb4
REDIS_URL=redis://localhost:6379/0
FLASK_ENV=production
EOF

    # 配置 Nginx
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
    location /static/ {
        alias ${PROJECT_DIR}/app/templates/;
        expires 30d;
    }
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

    # 配置 Supervisor
    info "配置 Supervisor..."
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y supervisor
    fi
    systemctl start supervisord 2>/dev/null || systemctl start supervisor 2>/dev/null
    systemctl enable supervisord 2>/dev/null || systemctl enable supervisor 2>/dev/null

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

    supervisorctl reread
    supervisorctl update
    supervisorctl restart email_platform

    # 配置防火墙
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
uninstall_normal() {
    echo ""
    info "开始卸载普通部署..."
    echo ""
    read -p "  确认卸载吗? (y/n) [默认: n]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warn "已取消"
        exit 0
    fi

    read -p "  删除数据库? (y/n) [默认: n]: " del_db
    read -p "  卸载 MySQL/Redis/Nginx 等软件? (y/n) [默认: n]: " del_sw

    PROJECT_DIR="/opt/email_platform"
    DB_NAME="email_platform"
    DB_USER="email_user"

    info "停止 Supervisor..."
    if command -v supervisorctl &>/dev/null; then
        supervisorctl stop email_platform 2>/dev/null || true
        supervisorctl remove email_platform 2>/dev/null || true
        rm -f /etc/supervisord.d/email_platform.ini
        supervisorctl reread && supervisorctl update
    fi

    info "删除 Nginx 配置..."
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
                yum remove -y mariadb-server mariadb redis nginx python39 supervisor 2>/dev/null || true
            else
                apt-get purge -y mysql-server redis-server nginx python3.9 supervisor 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
            fi
        fi
    fi

    show_uninstall "普通"
}

# ============================================================
# 公共函数
# ============================================================
show_success() {
    local port=$1
    local domain=$2
    local ssl=$3
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo 'your-server-ip')

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   部署完成！                              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    if [ -n "$domain" ]; then
        if [ "$ssl" == "true" ]; then
            echo -e "  ${CYAN}HTTPS:${NC}  https://${domain}"
            echo -e "  ${CYAN}HTTP:${NC}   http://${domain}"
        else
            echo -e "  ${CYAN}域名:${NC}   http://${domain}"
        fi
    fi
    echo -e "  ${CYAN}IP访问:${NC}  http://${server_ip}:${port}"
    echo -e "  ${CYAN}账号:${NC}   admin"
    echo -e "  ${CYAN}密码:${NC}   admin123456"
    echo ""
    echo -e "${RED}!!! 请立即修改默认密码 !!!${NC}"
}

show_uninstall() {
    local type=$1
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ${type} 卸载完成！                          ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}
