#!/bin/bash
# ============================================================
# 邮件发送平台 - Docker 一键部署脚本 (域名+SSL版)
# 支持自定义端口、域名绑定、Let's Encrypt 免费 SSL 证书
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   邮件发送平台 - Docker 一键部署        ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# 交互式选择端口
read -p "请输入访问端口 [默认: 5200]: " input_port
NGINX_PORT=${input_port:-5200}

# 验证端口是否为数字
if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]]; then
    error "端口必须是数字"
fi

# 检查端口范围
if [ "$NGINX_PORT" -lt 1 ] || [ "$NGINX_PORT" -gt 65535 ]; then
    error "端口范围必须在 1-65535 之间"
fi

info "使用端口: $NGINX_PORT"

# 交互式输入域名
read -p "请输入绑定域名 [没有则留空]: " input_domain
DOMAIN=${input_domain:-}

if [ -n "$DOMAIN" ]; then
    info "绑定域名: $DOMAIN"
    
    # 询问是否启用SSL
    read -p "是否申请 Let's Encrypt 免费 SSL 证书? (y/n) [默认: n]: " enable_ssl_input
    if [[ "$enable_ssl_input" =~ ^[Yy]$ ]]; then
        ENABLE_SSL="true"
        info "将自动申请 SSL 证书"
    else
        ENABLE_SSL="false"
        info "不启用 SSL"
    fi
else
    ENABLE_SSL="false"
    info "无域名绑定"
fi

# 检查 Docker
if ! command -v docker &> /dev/null; then
    error "Docker 未安装，请先安装 Docker"
fi

# 修复 docker-compose
info "检查并修复 docker-compose..."
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

if ! docker-compose version &>/dev/null; then
    error "docker-compose 安装失败，请手动安装"
fi
success "docker-compose 可用"

# 创建项目目录并进入
PROJECT_DIR="/opt/email_platform"
info "创建项目目录 $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# 创建 Certbot 目录
mkdir -p certbot-data certbot-www ssl

# 获取项目源码（使用 curl 下载 zip，无需 git）
info "获取项目源码..."
if [ ! -f "$PROJECT_DIR/app.py" ]; then
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

# 复制 Nginx 配置
cp nginx-docker.conf nginx.conf

# 生成配置文件
info "生成配置文件..."
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
info "启动 Docker 服务..."
docker-compose down 2>/dev/null || true
docker-compose up -d --build

# 等待 MySQL 启动
info "等待数据库启动..."
sleep 25

# 初始化数据库
info "初始化数据库..."
docker-compose exec -T app python3 -c "
from app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库初始化完成')
" || warn "数据库初始化可能需要手动执行"

# 如果启用SSL且配置了域名，申请证书
if [ "$ENABLE_SSL" = "true" ] && [ -n "$DOMAIN" ]; then
    info "申请 Let's Encrypt SSL 证书..."
    
    # 等待Nginx启动
    sleep 5
    
    # 使用certbot申请证书
    docker-compose run --rm certbot certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --email admin@${DOMAIN} \
        --agree-tos \
        --no-eff-email \
        -d ${DOMAIN} || warn "SSL证书申请失败，请检查域名解析是否正确"
    
    # 重启Nginx加载证书
    docker-compose restart nginx
    success "SSL 证书申请完成"
fi

# 验证
info "验证服务状态..."
docker-compose ps

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   Docker 部署完成！                      ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

if [ -n "$DOMAIN" ]; then
    if [ "$ENABLE_SSL" = "true" ]; then
        echo -e "  ${CYAN}HTTPS访问:${NC}  https://${DOMAIN}"
        echo -e "  ${CYAN}HTTP访问:${NC}   http://${DOMAIN} (自动跳转HTTPS)"
    else
        echo -e "  ${CYAN}域名访问:${NC}   http://${DOMAIN}"
    fi
fi

echo -e "  ${CYAN}IP访问:${NC}     http://$(curl -s ifconfig.me 2>/dev/null || echo 'your-server-ip'):${NGINX_PORT}"
echo -e "  ${CYAN}管理账号:${NC}  admin"
echo -e "  ${CYAN}管理密码:${NC}  admin123456"
echo ""

if [ "$ENABLE_SSL" = "true" ]; then
    echo -e "${YELLOW}--- SSL证书管理 ---${NC}"
    echo -e "  证书路径:   ./certbot-data/live/${DOMAIN}/"
    echo -e "  手动续期:   docker-compose run --rm certbot renew"
    echo -e "  自动续期:   Certbot容器每12小时自动检查续期"
    echo ""
fi

echo -e "${YELLOW}--- 常用命令 ---${NC}"
echo -e "  查看日志:   docker-compose logs -f"
echo -e "  重启服务:   docker-compose restart"
echo -e "  停止服务:   docker-compose down"
echo -e "  进入容器:   docker-compose exec app bash"
echo ""
echo -e "${RED}!!! 请立即修改默认管理员密码 !!!${NC}"
