#!/bin/bash
# ============================================================
#  邮件发送平台 - 腾讯云 CentOS 7.6 一键安装脚本
#  完全非交互式，自动安装所有运行环境
#  适用：腾讯云 CentOS 7.6（其他 CentOS 7 也通用）
# ============================================================

set -e

# ==================== 常量 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
APP_NAME="email_platform"
DEPLOY_DIR="/opt/email_platform"
APP_PORT="${APP_PORT:-5200}"
DB_NAME="${APP_NAME}"
DB_USER="email_user"
DB_PASS="EmailPlatform2024!"
VENV_DIR="${DEPLOY_DIR}/venv"

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

# 下载脚本（支持 raw.githubusercontent.com 受限环境）
download_script() {
    local script_name="$1"
    local output="$2"

    local urls=(
        "https://gh.jasonzeng.dev/https://raw.githubusercontent.com/jiujiu123520/email_platform/main/${script_name}"
        "https://mirror.ghproxy.com/https://raw.githubusercontent.com/jiujiu123520/email_platform/main/${script_name}"
        "https://kgithub.com/jiujiu123520/email_platform/raw/main/${script_name}"
        "https://gitclone.com/gist.github.com/jiujiu123520/email_platform/raw/main/${script_name}"
        "https://raw.githubusercontent.com/jiujiu123520/email_platform/main/${script_name}"
    )

    for u in "${urls[@]}"; do
        info "下载脚本: $u"
        if curl -fsSL --connect-timeout 15 --max-time 60 -o "$output" "$u" 2>/dev/null; then
            if [ -s "$output" ]; then
                success "脚本下载成功"
                return 0
            fi
        fi
    done
    error "脚本下载失败"
}

# ============================================================
# 主流程
# ============================================================
main() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║   邮件发送平台 - 腾讯云 CentOS 一键部署 ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    info "部署目录: $DEPLOY_DIR"
    info "访问端口: $APP_PORT"

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
        python3 python3-pip python3-devel \
        gcc gcc-c++ make \
        openssl-devel libffi-devel bzip2-devel \
        curl wget git unzip \
        net-tools vim htop \
        supervisor \
        logrotate \
        2>/dev/null || true
    success "基础依赖安装完成"

    # ---- 步骤 3: 安装并配置 MariaDB ----
    step "3/8  安装并配置 MariaDB"

    if ! rpm -qa | grep -q mariadb-server; then
        info "安装 MariaDB..."
        yum install -y mariadb-server mariadb mariadb-devel 2>/dev/null || true
    fi

    systemctl start mariadb 2>/dev/null || true
    systemctl enable mariadb 2>/dev/null || true
    sleep 2

    info "配置数据库..."
    mysql -u root << 'SQLEOF' 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS email_platform CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'email_user'@'localhost' IDENTIFIED BY 'EmailPlatform2024!';
GRANT ALL PRIVILEGES ON email_platform.* TO 'email_user'@'localhost';
FLUSH PRIVILEGES;
SQLEOF
    success "数据库配置完成"

    # ---- 步骤 4: 安装 Redis ----
    step "4/8  安装并配置 Redis"
    if ! rpm -qa | grep -q redis; then
        yum install -y redis 2>/dev/null || true
    fi
    systemctl start redis 2>/dev/null || true
    systemctl enable redis 2>/dev/null || true
    success "Redis 安装完成"

    # ---- 步骤 5: 安装 Python 3 和虚拟环境 ----
    step "5/8  配置 Python 环境"

    PYTHON_BIN=$(command -v python3.6 || command -v python3 || command -v python)
    info "使用 Python: $PYTHON_BIN"

    if [ ! -d "$VENV_DIR" ]; then
        info "创建虚拟环境..."
        $PYTHON_BIN -m venv "$VENV_DIR"
    fi

    source "$VENV_DIR/bin/activate"
    info "升级 pip..."
    pip install --upgrade pip setuptools wheel -q 2>/dev/null || true
    success "Python 环境配置完成"

    # ---- 步骤 6: 安装 Python 依赖 ----
    step "6/8  安装 Python 依赖"

    info "安装项目依赖..."
    if [ -f "$DEPLOY_DIR/requirements.txt" ]; then
        pip install -r "$DEPLOY_DIR/requirements.txt" -q 2>/dev/null || \
        pip install flask flask-sqlalchemy flask-jwt-extended flask-cors flask-mail flask-limiter pymysql cryptography python-dotenv gunicorn redis bcrypt requests beautifulsoup4 -q 2>/dev/null || true
    else
        pip install flask flask-sqlalchemy flask-jwt-extended flask-cors flask-mail flask-limiter pymysql cryptography python-dotenv gunicorn redis bcrypt requests beautifulsoup4 -q 2>/dev/null || true
    fi
    pip install gunicorn -q 2>/dev/null || true
    success "Python 依赖安装完成"

    # ---- 步骤 7: 配置应用 ----
    step "7/8  配置应用"

    SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
    JWT_SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")

    cat > "$DEPLOY_DIR/.env" << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
DATABASE_URL=mysql+pymysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}?charset=utf8mb4
REDIS_URL=redis://localhost:6379/0
FLASK_ENV=production
EOF

    mkdir -p /etc/nginx/conf.d
    cat > /etc/nginx/conf.d/email_platform.conf << 'NGINXEOF'
upstream email_backend {
    server 127.0.0.1:5200;
    keepalive 64;
}
server {
    listen 5200;
    server_name _;
    client_max_body_size 20M;
    location / {
        proxy_pass http://email_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXEOF

    nginx -t 2>/dev/null && systemctl reload nginx || true
    success "应用配置完成"

    # ---- 步骤 8: 初始化数据库和启动服务 ----
    step "8/8  初始化数据库并启动服务"

    info "初始化数据库..."
    cd "$DEPLOY_DIR"
    source "$VENV_DIR/bin/activate"
    python3 << 'PYEOF'
import sys
sys.path.insert(0, '/opt/email_platform')
try:
    from app.app import create_app, init_db
    app = create_app('production')
    with app.app_context():
        init_db(app)
    print('数据库初始化完成')
except Exception as e:
    print(f'数据库初始化: {e}')
PYEOF

    cat > /etc/supervisord.d/email_platform.ini << 'SUPERVISOREOF'
[program:email_platform]
command=/opt/email_platform/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:5200 --timeout 120 wsgi:app
directory=/opt/email_platform
user=root
autostart=true
autorestart=true
stderr_logfile=/var/log/email_platform.err.log
stdout_logfile=/var/log/email_platform.out.log
environment=PATH="/opt/email_platform/venv/bin"
SUPERVISOREOF

    supervisord 2>/dev/null || true
    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true
    supervisorctl restart email_platform 2>/dev/null || true

    sleep 3

    if supervisorctl status email_platform 2>/dev/null | grep -q "RUNNING"; then
        success "应用已启动"
    else
        warn "应用可能未正常启动，请检查日志: supervisorctl status"
    fi

    SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
                echo "服务器IP")

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
    echo -e "  查看状态:   supervisorctl status"
    echo -e "  实时日志:   supervisorctl logs -f email_platform"
    echo -e "  重启应用:   supervisorctl restart email_platform"
    echo -e "  停止应用:   supervisorctl stop email_platform"
    echo ""
    echo -e "${RED}${BOLD}!!! 请立即修改默认管理员密码 admin123456 !!!${NC}"
    echo ""
}

# ============================================================
# 卸载
# ============================================================
uninstall() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       邮件发送平台 - 卸载              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""

    read -p "  确认卸载？这将删除所有数据！(y/n) [n]: " confirm
    confirm=${confirm:-n}
    [[ ! "$confirm" =~ ^[Yy]$ ]] && info "已取消" && exit 0

    step "1/3  停止服务"
    supervisorctl stop email_platform 2>/dev/null || true
    supervisorctl remove email_platform 2>/dev/null || true
    rm -f /etc/supervisord.d/email_platform.ini
    supervisorctl reread 2>/dev/null
    supervisorctl update 2>/dev/null
    rm -f /etc/nginx/conf.d/email_platform.conf 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
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
        supervisorctl restart email_platform 2>/dev/null
        echo "服务已重启"
        ;;
    status|s)
        supervisorctl status email_platform
        ;;
    logs|l)
        supervisorctl logs -f email_platform
        ;;
    help|h|-h|--help)
        echo ""
        echo -e "${BOLD}用法:${NC}  bash $0 <命令>"
        echo ""
        echo -e "  ${GREEN}install${NC}     安装（默认）"
        echo -e "  ${RED}uninstall${NC}    卸载"
        echo -e "  ${YELLOW}restart${NC}     重启服务"
        echo -e "  ${CYAN}status${NC}      查看状态"
        echo -e "  ${CYAN}logs${NC}        查看日志"
        echo ""
        ;;
    *)
        echo "用法: bash $0 {install|uninstall|restart|status|logs|help}"
        echo "默认: install"
        ;;
esac
