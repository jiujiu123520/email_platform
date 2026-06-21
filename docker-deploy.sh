#!/bin/bash
# ============================================================
# 邮件发送平台 - Docker 一键部署脚本 (CentOS 7 国内镜像版)
# 使用阿里云镜像，无需访问 Docker Hub
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

# 克隆项目
info "获取项目源码..."
PROJECT_DIR="/opt/email_platform"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

if [ ! -d "$PROJECT_DIR/.git" ]; then
    git clone https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform.git . || \
    git clone https://github.com/jiujiu123520/email_platform.git .
fi

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

# 启动服务（使用国内镜像，无需预拉取）
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

# 验证
info "验证服务状态..."
docker-compose ps

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   Docker 部署完成！                      ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}访问地址:${NC}  http://$(curl -s ifconfig.me 2>/dev/null || echo 'your-server-ip')"
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
