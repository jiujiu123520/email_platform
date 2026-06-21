#!/bin/bash
# ============================================================
# 邮件发送平台 - 普通一键部署脚本 (无 Docker)
# 适用于 CentOS 7 / Ubuntu 20+
# 自动安装环境 + 部署 + 配置
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    error "无法检测系统类型"
fi

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   邮件发送平台 - 普通一键部署            ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
info "系统: $OS $VER"

# 交互式配置
read -p "请输入访问端口 [默认: 5200]: " input_port
NGINX_PORT=${input_port:-5200}

if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]]; then
    error "端口必须是数字"
fi

# 数据库配置
read -p "数据库密码 [默认: EmailPlatform2024!]: " db_pass
DB_PASS=${db_pass:-EmailPlatform2024!}

# ============================================================
# 步骤 1: 安装基础工具
# ============================================================
info "步骤 1/8: 安装基础工具..."
if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
    yum install -y epel-release
    yum install -y wget curl vim unzip git gcc make openssl-devel bzip2-devel libffi-devel
elif [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
    apt-get update
    apt-get install -y wget curl vim unzip git gcc make libssl-dev libbz2-dev libffi-dev
else
    error "不支持的操作系统: $OS"
fi
success "基础工具安装完成"

# ============================================================
# 步骤 2: 安装 Python 3.9
# ============================================================
info "步骤 2/8: 安装 Python 3.9..."

if command -v python3.9 &>/dev/null; then
    success "Python 3.9 已安装"
else
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y python39 python39-devel python39-pip
    else
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:deadsnakes/ppa
        apt-get update
        apt-get install -y python3.9 python3.9-venv python3.9-dev
    fi
    success "Python 3.9 安装完成"
fi

python3.9 --version

# ============================================================
# 步骤 3: 安装 MySQL/MariaDB
# ============================================================
info "步骤 3/8: 安装 MySQL/MariaDB..."

if command -v mysql &>/dev/null; then
    success "MySQL/MariaDB 已安装"
else
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y mariadb-server mariadb-devel
        systemctl start mariadb
        systemctl enable mariadb
    else
        apt-get install -y mysql-server mysql-client libmysqlclient-dev
        systemctl start mysql
        systemctl enable mysql
    fi
    success "数据库安装完成"
fi

# 配置数据库
info "配置数据库..."
DB_NAME="email_platform"
DB_USER="email_user"

# 兼容 MariaDB 5.5
mysql -u root <<DBEOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
DBEOF

success "数据库配置完成"

# ============================================================
# 步骤 4: 安装 Redis
# ============================================================
info "步骤 4/8: 安装 Redis..."

if command -v redis-server &>/dev/null; then
    success "Redis 已安装"
else
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y redis
    else
        apt-get install -y redis-server
    fi
    systemctl start redis
    systemctl enable redis
    success "Redis 安装完成"
fi

# ============================================================
# 步骤 5: 安装 Nginx
# ============================================================
info "步骤 5/8: 安装 Nginx..."

if command -v nginx &>/dev/null; then
    success "Nginx 已安装"
else
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum install -y nginx
    else
        apt-get install -y nginx
    fi
    systemctl start nginx
    systemctl enable nginx
    success "Nginx 安装完成"
fi

# ============================================================
# 步骤 6: 下载项目源码
# ============================================================
info "步骤 6/8: 下载项目源码..."

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
success "项目源码下载完成"

# ============================================================
# 步骤 7: 配置 Python 虚拟环境
# ============================================================
info "步骤 7/8: 配置 Python 虚拟环境..."

cd "$PROJECT_DIR"
python3.9 -m venv venv
source venv/bin/activate

# 配置 pip 国内源
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# 安装依赖
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn

success "Python 依赖安装完成"

# 生成配置文件
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
JWT_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
DATABASE_URL=mysql+pymysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}?charset=utf8mb4
REDIS_URL=redis://localhost:6379/0
FLASK_ENV=production
EOF

success "配置文件生成完成"

# ============================================================
# 步骤 8: 配置 Nginx 和 Supervisor
# ============================================================
info "步骤 8/8: 配置 Nginx 和 Supervisor..."

# Nginx 配置
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
success "Nginx 配置完成"

# Supervisor 配置
if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
    yum install -y supervisor
fi
systemctl start supervisord || systemctl start supervisor
systemctl enable supervisord || systemctl enable supervisor

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
success "Supervisor 配置完成"

# 配置防火墙
info "配置防火墙..."
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port=${NGINX_PORT}/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi
if command -v ufw &>/dev/null; then
    ufw allow ${NGINX_PORT}/tcp 2>/dev/null || true
fi
success "防火墙配置完成"

# 输出部署信息
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo 'your-server-ip')
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   普通部署完成！                          ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}访问地址:${NC}  http://${SERVER_IP}:${NGINX_PORT}"
echo -e "  ${CYAN}管理账号:${NC}  admin"
echo -e "  ${CYAN}管理密码:${NC}  admin123456"
echo -e "  ${CYAN}项目目录:${NC}  ${PROJECT_DIR}"
echo ""
echo -e "${YELLOW}--- 常用命令 ---${NC}"
echo -e "  查看日志:   tail -f /var/log/email_platform.out.log"
echo -e "  重启应用:   supervisorctl restart email_platform"
echo -e "  重启Nginx:  systemctl restart nginx"
echo -e "  应用状态:   supervisorctl status"
echo ""
echo -e "${RED}!!! 请立即修改默认管理员密码 !!!${NC}"
