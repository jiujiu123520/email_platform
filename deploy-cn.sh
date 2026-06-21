#!/bin/bash
# ============================================================
#  邮件发送平台 - 一键部署脚本（大陆服务器版）
#  支持安装 / 卸载，自动处理 Docker 全家桶
#  适用系统：Ubuntu / Debian / CentOS / Rocky / AlmaLinux
# ============================================================

set -e

# ==================== 常量 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
PROJECT_DIR="/opt/email_platform"
NGINX_PORT="${NGINX_PORT:-5200}"

# ==================== 工具函数 ====================
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }
step()    { echo ""; echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ==================== 前置检测 ====================
detect_pkg_mgr() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v yum &>/dev/null; then echo "yum"
    else echo ""
    fi
}

detect_compose() {
    if docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        echo ""
    fi
}

check_docker() {
    if ! command -v docker &>/dev/null; then return 1; fi
    if ! docker info &>/dev/null 2>&1; then return 1; fi
    return 0
}

# ============================================================
# 安装 Docker（内部函数）
# ============================================================
_install_docker() {
    local pkg_mgr="$1"
    info "Docker 未安装，开始安装..."

    if [ "$pkg_mgr" = "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1

        curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg 2>/dev/null | \
            gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null || \
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>/dev/null | \
            gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null || true

        local codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu ${codename} stable" \
            > /etc/apt/sources.list.d/docker.list 2>/dev/null || true

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1

    elif [ "$pkg_mgr" = "yum" ]; then
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
}

# ============================================================
# 配置镜像加速（内部函数）
# ============================================================
_config_mirrors() {
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
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
        systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
        sleep 3
    fi
}

# ============================================================
# 初始化 Compose 命令（内部函数）
# ============================================================
_init_compose() {
    COMPOSE_CMD="$(detect_compose)"

    if [ -z "$COMPOSE_CMD" ]; then
        info "安装 Docker Compose..."

        if [ "$PKG_MGR" = "apt" ]; then
            apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 || true
        elif [ "$PKG_MGR" = "yum" ]; then
            yum install -y -q docker-compose-plugin >/dev/null 2>&1 || true
        fi

        # pip 回退
        if ! docker compose version &>/dev/null 2>&1; then
            pip3 install docker-compose >/dev/null 2>&1 || \
            pip install docker-compose >/dev/null 2>&1 || true
        fi

        COMPOSE_CMD="$(detect_compose)"
        [ -z "$COMPOSE_CMD" ] && error "Docker Compose 安装失败"
    fi
}

# ============================================================
# 安装流程
# ============================================================
do_install() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║    邮件发送平台 - 大陆服务器一键部署  ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo -e "  端口: $NGINX_PORT   目录: $PROJECT_DIR"

    PKG_MGR="$(detect_pkg_mgr)"
    [ -z "$PKG_MGR" ] && error "不支持的系统"

    # 步骤 1：Docker
    step "1/5  安装 Docker"
    if ! check_docker; then
        _install_docker "$PKG_MGR"
        success "Docker 安装完成"
    else
        success "Docker 已就绪"
    fi

    # 步骤 2：镜像加速
    step "2/5  配置镜像加速"
    _config_mirrors
    success "镜像加速已配置"

    # 步骤 3：源码
    step "3/5  获取项目源码"
    mkdir -p "$PROJECT_DIR"
    cd /tmp
    rm -rf email_platform.zip email_platform-main
    curl -fsSL -o email_platform.zip \
        "https://gh.jasonzeng.dev/https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip" || \
    curl -fsSL -o email_platform.zip \
        "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"
    unzip -o -q email_platform.zip
    rm -rf "${PROJECT_DIR:?}"/*
    cp -a email_platform-main/. "$PROJECT_DIR/"
    rm -rf email_platform.zip email_platform-main
    cd "$PROJECT_DIR"
    mkdir -p certbot-data certbot-www ssl logs
    cp -f nginx-docker.conf nginx.conf
    success "源码准备完成"

    # 步骤 4：配置 & 启动
    step "4/5  构建并启动"
    SECRET_KEY=$(openssl rand -hex 32)
    JWT_SECRET_KEY=$(openssl rand -hex 32)
    cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
NGINX_PORT=${NGINX_PORT}
DOMAIN=
ENABLE_SSL=false
EOF

    _init_compose
    info "使用: $COMPOSE_CMD"
    $COMPOSE_CMD down 2>/dev/null || true
    info "构建镜像（首次约 5-10 分钟）..."
    $COMPOSE_CMD up -d --build --no-cache

    # 等待 MySQL
    info "等待 MySQL 启动..."
    local count=0
    while [ $count -lt 60 ]; do
        if $COMPOSE_CMD exec -T mysql mysqladmin ping -h localhost -uroot -p'EmailPlatform2024!' &>/dev/null 2>&1; then
            success "MySQL 就绪（${count}s）"
            break
        fi
        count=$((count + 1))
        sleep 1
    done
    if [ $count -ge 60 ]; then
        warn "MySQL 启动超时，继续..."
    fi

    # 初始化数据库
    info "初始化数据库..."
    $COMPOSE_CMD exec -T app python3 -c "
from app.app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('DB ready')
" 2>/dev/null || warn "数据库初始化完成"

    success "服务已启动"

    # 步骤 5：状态
    step "5/5  服务状态"
    $COMPOSE_CMD ps

    local server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
                      curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
                      echo "你的服务器IP")
    local elapsed=$(( $(date +%s) - START_TIME ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║           部署完成！                    ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}访问地址:${NC}  http://${server_ip}:${NGINX_PORT}"
    echo -e "  ${CYAN}管理账号:${NC}  admin"
    echo -e "  ${CYAN}管理密码:${NC}  admin123456"
    echo -e "  ${CYAN}部署耗时:${NC}  ${mins}分${secs}秒"
    echo ""
    echo -e "${YELLOW}--- 运维命令 ---${NC}"
    echo -e "  查看状态:   cd $PROJECT_DIR && $COMPOSE_CMD ps"
    echo -e "  实时日志:   cd $PROJECT_DIR && $COMPOSE_CMD logs -f app"
    echo -e "  重启服务:   cd $PROJECT_DIR && $COMPOSE_CMD restart"
    echo -e "  停止服务:   cd $PROJECT_DIR && $COMPOSE_CMD down"
    echo -e "  卸载系统:   bash $0 uninstall"
    echo ""
    echo -e "${RED}${BOLD}!!! 请立即修改默认管理员密码 admin123456 !!!${NC}"
    echo ""
}

# ============================================================
# 卸载流程
# ============================================================
do_uninstall() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       邮件发送平台 - 卸载脚本          ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""

    read -p "  确认卸载？此操作将删除所有数据！(y/n) [n]: " confirm
    confirm=${confirm:-n}
    [[ ! "$confirm" =~ ^[Yy]$ ]] && info "已取消" && exit 0

    PKG_MGR="$(detect_pkg_mgr)"

    step "1/4  停止并删除容器"
    COMPOSE_CMD="$(detect_compose)"
    COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

    if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        cd "$PROJECT_DIR"
        $COMPOSE_CMD down -v 2>/dev/null || true
        info "容器已删除"
    fi

    if command -v docker &>/dev/null; then
        docker stop email_platform_app email_platform_mysql email_platform_redis \
            email_platform_nginx email_platform_certbot 2>/dev/null || true
        docker rm -f email_platform_app email_platform_mysql email_platform_redis \
            email_platform_nginx email_platform_certbot 2>/dev/null || true
        docker volume rm email_platform_mysql_data email_platform_redis_data 2>/dev/null || true
        docker network rm email_platform_email_network 2>/dev/null || true
        docker system prune -f 2>/dev/null || true
    fi

    step "2/4  删除项目目录"
    rm -rf "$PROJECT_DIR"
    success "项目目录已删除"

    step "3/4  删除 Docker（可选）"
    read -p "  是否卸载 Docker 软件？(y/n) [n]: " del_docker
    del_docker=${del_docker:-n}
    if [[ "$del_docker" =~ ^[Yy]$ ]]; then
        if [ "$PKG_MGR" = "apt" ]; then
            apt-get purge -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
        elif [ "$PKG_MGR" = "yum" ]; then
            yum remove -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        fi
        rm -rf /var/lib/docker /etc/docker
        success "Docker 已卸载"
    fi

    step "4/4  完成"
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║           卸载完成！                    ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# 主入口
# ============================================================
START_TIME=$(date +%s)
MODE="${1:-install}"

case "$MODE" in
    install|i)
        do_install
        ;;
    uninstall|u)
        do_uninstall
        ;;
    restart|r)
        COMPOSE_CMD="$(detect_compose)"
        COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
        [ ! -d "$PROJECT_DIR" ] && error "项目未安装，请先运行: bash $0 install"
        cd "$PROJECT_DIR"
        info "重启服务..."
        $COMPOSE_CMD restart
        success "重启完成"
        ;;
    status|s)
        COMPOSE_CMD="$(detect_compose)"
        COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
        [ ! -d "$PROJECT_DIR" ] && error "项目未安装"
        cd "$PROJECT_DIR"
        $COMPOSE_CMD ps
        ;;
    logs|l)
        COMPOSE_CMD="$(detect_compose)"
        COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
        [ ! -d "$PROJECT_DIR" ] && error "项目未安装"
        cd "$PROJECT_DIR"
        if [ -n "$2" ]; then
            $COMPOSE_CMD logs -f --tail=100 "$2"
        else
            $COMPOSE_CMD logs -f
        fi
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
        echo -e "  ${CYAN}logs app${NC}    查看应用日志"
        echo -e "  ${CYAN}logs nginx${NC}  查看 Nginx 日志"
        echo -e "  ${CYAN}help${NC}        显示此帮助"
        echo ""
        echo -e "${BOLD}示例:${NC}"
        echo "  bash $0 install              # 安装（端口 5200）"
        echo "  NGINX_PORT=8080 bash $0 install  # 安装（端口 8080）"
        echo "  bash $0 uninstall            # 卸载"
        echo "  bash $0 restart              # 重启"
        echo "  bash $0 logs                 # 查看日志"
        echo ""
        ;;
    *)
        error "未知命令: $MODE    用法: bash $0 help"
        ;;
esac
