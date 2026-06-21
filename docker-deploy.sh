#!/bin/bash
# ============================================================
# 邮件发送平台 - Docker 一键部署脚本
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

# 检查 Docker
if ! command -v docker &> /dev/null; then
    info "安装 Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl start docker
    systemctl enable docker
    success "Docker 安装完成"
fi

# 检查 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    info "安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    success "Docker Compose 安装完成"
fi

# 克隆项目
info "获取项目源码..."
if [ ! -d "email_platform" ]; then
    git clone https://github.com/jiujiu123520/email_platform.git || \
    git clone https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform.git
fi
cd email_platform

# 复制 Nginx 配置
cp nginx-docker.conf nginx.conf

# 生成密钥
info "生成配置文件..."
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)
cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
EOF

# 启动服务
info "启动 Docker 服务..."
docker-compose up -d --build

# 等待 MySQL 启动
info "等待数据库启动..."
sleep 15

# 初始化数据库
info "初始化数据库..."
docker-compose exec -T app python3 -c "
from app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库初始化完成')
" || warn "数据库初始化可能需要手动执行"

# 验证
info "验证服务状态..."
docker-compose ps

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   Docker 部署完成！                      ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}访问地址:${NC}  http://$(curl -s ifconfig.me || echo 'your-server-ip')"
echo -e "  ${CYAN}管理账号:${NC}  admin"
echo -e "  ${CYAN}管理密码:${NC}  admin123456"
echo ""
echo -e "${YELLOW}--- 常用命令 ---${NC}"
echo -e "  查看日志:   docker-compose logs -f"
echo -e "  重启服务:   docker-compose restart"
echo -e "  停止服务:   docker-compose down"
echo -e "  进入容器:   docker-compose exec app bash"
echo ""
echo -e "${RED}!!! 请立即修改默认管理员密码 !!!${NC}"
