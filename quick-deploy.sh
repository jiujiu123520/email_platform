#!/bin/bash
# ============================================================
#  邮件发送平台 - 一键部署脚本（完全非交互式）
#  适用于：Ubuntu / Debian / CentOS / Rocky / 其他 Linux x86_64
#
#  用法（二选一）：
#    bash quick-deploy.sh                          # 默认端口 5200
#    NGINX_PORT=8080 bash quick-deploy.sh          # 自定义端口
#    bash quick-deploy.sh 8080                     # 自定义端口（位置参数）
# ============================================================

set -e

# ==================== 颜色 & 工具函数 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }
step()    { echo ""; echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ==================== 参数：端口 ====================
NGINX_PORT="${NGINX_PORT:-${1:-5200}}"
if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_PORT" -lt 1 ] || [ "$NGINX_PORT" -gt 65535 ]; then
    error "端口无效: $NGINX_PORT（必须是 1-65535 的数字）"
fi

# ==================== 项目目录 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="/opt/email_platform"
TIMER_START=$(date +%s)

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║      邮件发送平台 - 一键部署             ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo -e "  ${BOLD}端口:${NC} $NGINX_PORT   ${BOLD}目录:${NC} $PROJECT_DIR"

# ============================================================
# 步骤 1：安装 Docker（如未安装）
# ============================================================
step "1/5  检查并安装 Docker"

# 检测包管理器
PKG_MGR=""
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    warn "未检测到 apt-get 或 yum，跳过 Docker 自动安装"
fi

if ! command -v docker &>/dev/null; then
    info "Docker 未安装，开始自动安装..."

    if [ "$PKG_MGR" = "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null

        # 使用国内镜像加速（优先，失败回退官方）
        (curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null) || \
        (curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null) || true

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list 2>/dev/null

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null

    elif [ "$PKG_MGR" = "yum" ]; then
        yum install -y -q yum-utils >/dev/null 2>&1
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo >/dev/null 2>&1 || \
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
    fi

    # 启动 daemon（apt 安装后可能未启动）
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 2

    if ! command -v docker &>/dev/null; then
        error "Docker 安装失败，请手动安装：https://docs.docker.com/engine/install/"
    fi
    success "Docker 安装完成"
else
    # 确保 daemon 运行
    if ! docker info &>/dev/null; then
        info "Docker 已安装但 daemon 未运行，启动中..."
        systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 3
    fi
    success "Docker 已就绪"
fi

# ============================================================
# 步骤 2：确保 compose 可用（兼容 docker-compose / docker compose）
# ============================================================
step "2/5  检查 Docker Compose"

COMPOSE_CMD=""
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
    info "使用 docker compose（插件版）"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    info "使用 docker-compose（独立版）"
else
    info "Compose 未找到，尝试安装 docker-compose-plugin 或 docker-compose..."
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 || true
    elif [ "$PKG_MGR" = "yum" ]; then
        yum install -y -q docker-compose-plugin >/dev/null 2>&1 || true
    fi

    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    else
        pip3 install docker-compose >/dev/null 2>&1 || pip install docker-compose >/dev/null 2>&1 || true
        if command -v docker-compose &>/dev/null; then
            COMPOSE_CMD="docker-compose"
        else
            error "无法安装 Docker Compose，请手动安装后重试"
        fi
    fi
    success "Compose 安装完成"
fi

$COMPOSE_CMD version &>/dev/null || error "Compose 验证失败"
success "Compose 就绪: $COMPOSE_CMD"

# ============================================================
# 步骤 3：准备项目目录与配置
# ============================================================
step "3/5  准备项目文件"

mkdir -p "$PROJECT_DIR"

# 如果当前脚本所在目录已经是项目源码（有 docker-compose.yml），直接复用
if [ -f "$SCRIPT_DIR/docker-compose.yml" ] && [ -f "$SCRIPT_DIR/Dockerfile" ]; then
    info "当前目录为项目源码，复制到 $PROJECT_DIR ..."
    # 先清理旧文件，避免历史资源残留
    find "$PROJECT_DIR" -mindepth 1 -maxdepth 1 ! -name '*.tar.gz' -exec rm -rf {} + 2>/dev/null || true
    cp -a "$SCRIPT_DIR/." "$PROJECT_DIR/"
else
    # 否则尝试从 GitHub 下载
    info "从 GitHub 下载最新源码..."
    cd /tmp
    rm -rf email_platform.zip email_platform-main
    curl -fsSL -o email_platform.zip \
        "https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip" || \
    curl -fsSL -o email_platform.zip \
        "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"
    unzip -o -q email_platform.zip
    find "$PROJECT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    cp -a email_platform-main/. "$PROJECT_DIR/"
    rm -rf email_platform.zip email_platform-main
fi

cd "$PROJECT_DIR"
mkdir -p certbot-data certbot-www ssl logs

# 复制 Nginx 配置
cp -f nginx-docker.conf nginx.conf

# 生成 .env
info "生成 .env 配置..."
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)

cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
NGINX_PORT=${NGINX_PORT}
DOMAIN=
ENABLE_SSL=false
EOF

success "项目准备完成"

# ============================================================
# 步骤 4：构建并启动服务
# ============================================================
step "4/5  构建并启动服务"

$COMPOSE_CMD down 2>/dev/null || true
info "拉取镜像 / 构建镜像（首次需要 3-8 分钟，请耐心等待）..."
$COMPOSE_CMD up -d --build --no-cache

# 等待 MySQL 就绪
info "等待 MySQL 启动..."
for i in $(seq 1 40); do
    if $COMPOSE_CMD exec -T mysql mysqladmin ping -h localhost -uroot -p"EmailPlatform2024!" &>/dev/null; then
        success "MySQL 就绪（${i}s）"
        break
    fi
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
" 2>/dev/null || warn "数据库初始化提示可忽略，请稍后在后台检查"

success "服务启动完成"

# ============================================================
# 步骤 5：状态检查 & 输出结果
# ============================================================
step "5/5  服务状态"
$COMPOSE_CMD ps

# 获取公网 IP
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || echo "你的服务器IP")

TIMER_END=$(date +%s)
ELAPSED=$(( TIMER_END - TIMER_START ))
MIN=$(( ELAPSED / 60 ))
SEC=$(( ELAPSED % 60 ))

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           🎉 部署完成！                  ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}访问地址:${NC}  http://${SERVER_IP}:${NGINX_PORT}"
echo -e "  ${CYAN}管理账号:${NC}  admin"
echo -e "  ${CYAN}管理密码:${NC}  admin123456"
echo -e "  ${CYAN}部署目录:${NC}  $PROJECT_DIR"
echo -e "  ${CYAN}部署耗时:${NC}  ${MIN}分${SEC}秒"
echo ""
echo -e "${YELLOW}--- 常用运维命令 ---${NC}"
echo -e "  查看状态:   cd $PROJECT_DIR && $COMPOSE_CMD ps"
echo -e "  实时日志:   cd $PROJECT_DIR && $COMPOSE_CMD logs -f app"
echo -e "  重启服务:   cd $PROJECT_DIR && $COMPOSE_CMD restart"
echo -e "  停止服务:   cd $PROJECT_DIR && $COMPOSE_CMD down"
echo -e "  进入容器:   cd $PROJECT_DIR && $COMPOSE_CMD exec app bash"
echo -e "  查看菜单:   bash $PROJECT_DIR/manage.sh"
echo ""
echo -e "${RED}${BOLD}!!! 请立即登录并修改默认管理员密码 admin123456 !!!${NC}"
echo ""
