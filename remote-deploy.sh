#!/bin/bash
# ============================================================
#  邮件发送平台 - 远程服务器自动化部署脚本
#  在目标服务器上直接执行此脚本即可完成全部部署
#  用法: curl -fsSL https://your-cdn/remote-deploy.sh | sudo bash
#  或:   wget -qO- https://your-cdn/remote-deploy.sh | sudo bash
# ============================================================

set -e

APP_NAME="email_platform"
DEPLOY_DIR="/opt/${APP_NAME}"
PROJECT_URL="https://github.com/your-repo/email_platform.git"  # 可替换为您的仓库地址

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; exit 1; }

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  邮件发送平台 - 远程自动化部署${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# 检查 root
if [ "$EUID" -ne 0 ]; then error "请使用 root 或 sudo 运行"; fi

# 步骤1: 安装基础环境
info "[1/5] 安装基础环境..."
apt-get update -y
apt-get install -y git curl wget python3 python3-pip python3-venv python3-dev build-essential \
    libmysqlclient-dev pkg-config libssl-dev libffi-dev nginx supervisor mysql-server redis-server \
    logrotate net-tools

# 启动服务
systemctl start mysql redis-server nginx
systemctl enable mysql redis-server nginx
success "基础环境安装完成"

# 步骤2: 克隆/下载项目
info "[2/5] 获取项目源码..."
mkdir -p "${DEPLOY_DIR}"
cd "${DEPLOY_DIR}"

if [ -d ".git" ]; then
    git pull
elif command -v git &> /dev/null; then
    # 尝试从 git 拉取，失败则创建基础结构
    git clone "${PROJECT_URL}" . 2>/dev/null || true
fi

# 如果没有源码，提示用户上传
if [ ! -f "app.py" ]; then
    warn "未找到项目源码，请确保已将源码上传到 ${DEPLOY_DIR}"
    warn "您可以通过以下方式上传:"
    warn "  scp -r ./email_platform root@124.222.43.74:/opt/"
    error "项目源码缺失，部署中止"
fi
success "项目源码已就位"

# 步骤3: 安装 Python 依赖
info "[3/5] 安装 Python 依赖..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install flask flask-sqlalchemy flask-jwt-extended flask-cors flask-mail flask-limiter \
    pymysql cryptography python-dotenv gunicorn redis bcrypt requests beautifulsoup4
success "Python 依赖安装完成"

# 步骤4: 配置数据库和环境
info "[4/5] 配置数据库..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS email_platform CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -e "CREATE USER IF NOT EXISTS 'email_user'@'localhost' IDENTIFIED BY 'EmailPlatform2024!';"
mysql -u root -e "GRANT ALL PRIVILEGES ON email_platform.* TO 'email_user'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# 生成 .env
cat > "${DEPLOY_DIR}/.env" <<EOF
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
JWT_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
DATABASE_URL=mysql+pymysql://email_user:EmailPlatform2024!@localhost:3306/email_platform?charset=utf8mb4
REDIS_URL=redis://localhost:6379/0
MAIL_DEFAULT_SENDER=noreply@example.com
FLASK_ENV=production
EOF
chmod 600 "${DEPLOY_DIR}/.env"
success "数据库和环境配置完成"

# 步骤5: 初始化数据并启动服务
info "[5/5] 初始化数据库并启动服务..."
export $(cat "${DEPLOY_DIR}/.env" | xargs)
python3 -c "
import sys
sys.path.insert(0, '${DEPLOY_DIR}')
from app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库初始化完成')
"

# Nginx 配置
cat > /etc/nginx/sites-available/email_platform <<'NGX'
upstream email_platform_backend {
    server 127.0.0.1:5000;
    keepalive 64;
}
server {
    listen 80;
    server_name _;
    client_max_body_size 20M;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    location / {
        proxy_pass http://email_platform_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 120s;
    }
    location /static/ {
        alias /opt/email_platform/static/;
        expires 30d;
        access_log off;
    }
}
NGX
ln -sf /etc/nginx/sites-available/email_platform /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Supervisor 配置
mkdir -p /var/log/email_platform
cat > /etc/supervisor/conf.d/email_platform.conf <<'SUPER'
[program:email_platform]
command=/opt/email_platform/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 --timeout 120 --max-requests 1000 "app:create_app('production')"
directory=/opt/email_platform
user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/email_platform/gunicorn.log
stderr_logfile=/var/log/email_platform/gunicorn_error.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
SUPER

supervisorctl reread
supervisorctl update
supervisorctl start email_platform

# 防火墙
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true

# 日志轮转
cat > /etc/logrotate.d/email_platform <<'LOGR'
/var/log/email_platform/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 root root
}
LOGR

IP_ADDR=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  部署完成!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  访问地址: http://${IP_ADDR}"
echo -e "  管理账号: admin"
echo -e "  管理密码: admin123456"
echo -e "  部署目录: ${DEPLOY_DIR}"
echo ""
echo -e "${RED}!!! 请立即修改默认管理员密码 !!!${NC}"
