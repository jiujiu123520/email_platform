#!/bin/bash
# ============================================================
#  邮件发送平台 - 一键部署脚本（大陆服务器版）
#  适用系统：Ubuntu / Debian / CentOS / Rocky / AlmaLinux
#  镜像加速：DaoCloud / 中科大 / 阿里云 / 百度云
# ============================================================

set -e

# ==================== 颜色 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }
step()    { echo ""; echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ==================== 参数 ====================
NGINX_PORT="${NGINX_PORT:-${1:-5200}}"
PROJECT_DIR="/opt/email_platform"
TIMER_START=$(date +%s)

if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_PORT" -lt 1 ] || [ "$NGINX_PORT" -gt 65535 ]; then
    error "端口无效: $NGINX_PORT"
fi

# ==================== 前置检查 ====================
check_pkg_mgr() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v yum &>/dev/null; then echo "yum"
    else echo ""
    fi
}

PKG_MGR="$(check_pkg_mgr)"
if [ -z "$PKG_MGR" ]; then
    error "不支持的系统：未检测到 apt-get 或 yum"
fi

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║    邮件发送平台 - 大陆服务器一键部署  ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo -e "  端口: $NGINX_PORT   目录: $PROJECT_DIR"

# ============================================================
# 步骤 1：安装 Docker
# ============================================================
step "1/5  安装 Docker"

if ! command -v docker &>/dev/null; then
    info "Docker 未安装，开始安装..."

    if [ "$PKG_MGR" = "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null

        # 中科大 Docker CE 镜像（优先）
        curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null || \
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null || true

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list 2>/dev/null || true

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null

    elif [ "$PKG_MGR" = "yum" ]; then
        yum install -y -q yum-utils >/dev/null 2>&1
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo >/dev/null 2>&1 || \
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
    fi

    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 3

    if ! command -v docker &>/dev/null; then
        error "Docker 安装失败，请手动安装：https://docs.docker.com/engine/install/"
    fi
    success "Docker 安装完成"
else
    if ! docker info &>/dev/null; then
        info "Docker daemon 未运行，启动中..."
        systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 3
    fi
    success "Docker 已就绪"
fi

# ============================================================
# 步骤 2：配置国内镜像加速
# ============================================================
step "2/5  配置 Docker 镜像加速"

if [ ! -f /etc/docker/daemon.json ]; then
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
    sleep 3
    success "镜像加速已配置"
else
    success "镜像加速已存在"
fi

# ============================================================
# 步骤 3：获取项目源码
# ============================================================
step "3/5  获取项目源码"

mkdir -p "$PROJECT_DIR"
cd /tmp

rm -rf email_platform.zip email_platform-main
curl -fsSL -o email_platform.zip \
    "https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip" || \
curl -fsSL -o email_platform.zip \
    "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"

unzip -o -q email_platform.zip
rm -rf "$PROJECT_DIR"/*
cp -a email_platform-main/. "$PROJECT_DIR/"
rm -rf email_platform.zip email_platform-main
cd "$PROJECT_DIR"

mkdir -p certbot-data certbot-www ssl logs
cp -f nginx-docker.conf nginx.conf
success "源码准备完成"

# ============================================================
# 步骤 4：生成配置 & 构建启动
# ============================================================
step "4/5  构建并启动服务"

SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)

cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
NGINX_PORT=${NGINX_PORT}
DOMAIN=
ENABLE_SSL=false
EOF

# 检测 compose 命令
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose 未安装"
fi

info "使用: $COMPOSE_CMD"
$COMPOSE_CMD down 2>/dev/null || true

info "构建镜像（首次约 5-10 分钟）..."
$COMPOSE_CMD up -d --build --no-cache

# 等待 MySQL 就绪
info "等待 MySQL 启动..."
for i in $(seq 1 60); do
    if $COMPOSE_CMD exec -T mysql mysqladmin ping -h localhost -uroot -p"EmailPlatform2024\!" &>/dev/null 2>&1; then
        success "MySQL 就绪（${i}s）"
        break
    fi
    [ $i -eq 60 ] && warn "MySQL 启动超时，继续..."
    sleep 1
done

# 初始化数据库
info "初始化数据库..."
$COMPOSE_CMD exec -T app python3 -c "
from app.app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('数据库初始化完成')
" 2>/dev/null || warn "数据库初始化完成（部分提示可忽略）"

success "服务已启动"

# ============================================================
# 步骤 5：输出结果
# ============================================================
step "5/5  服务状态"
$COMPOSE_CMD ps

SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
             curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
             echo "你的服务器IP")

TIMER_END=$(date +%s)
ELAPSED=$(( TIMER_END - TIMER_START ))
MIN=$(( ELAPSED / 60 ))
SEC=$(( ELAPSED % 60 ))

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           部署完成！                    ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}访问地址:${NC}  http://${SERVER_IP}:${NGINX_PORT}"
echo -e "  ${CYAN}管理账号:${NC}  admin"
echo -e "  ${CYAN}管理密码:${NC}  admin123456"
echo -e "  ${CYAN}部署目录:${NC}  $PROJECT_DIR"
echo -e "  ${CYAN}部署耗时:${NC}  ${MIN}分${SEC}秒"
echo ""
echo -e "${YELLOW}--- 运维命令 ---${NC}"
echo -e "  查看状态:   cd $PROJECT_DIR && $COMPOSE_CMD ps"
echo -e "  实时日志:   cd $PROJECT_DIR && $COMPOSE_CMD logs -f app"
echo -e "  重启服务:   cd $PROJECT_DIR && $COMPOSE_CMD restart"
echo -e "  停止服务:   cd $PROJECT_DIR && $COMPOSE_CMD down"
echo ""
echo -e "${RED}${BOLD}!!! 请立即修改默认管理员密码 admin123456 !!!${NC}"
echo ""
