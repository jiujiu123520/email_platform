#!/bin/bash
# ============================================================
#  Email Platform - One-Click Deploy (Global / Overseas)
#  Install / Uninstall, fully automated
#  Supported: Ubuntu / Debian / CentOS / Rocky / AlmaLinux
# ============================================================

set -e

# ==================== Constants ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
PROJECT_DIR="/opt/email_platform"
NGINX_PORT="${NGINX_PORT:-5200}"

# ==================== Helpers ====================
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }
step()    { echo ""; echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ==================== Detection ====================
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
# Internal: Install Docker
# ============================================================
_install_docker() {
    local pkg_mgr="$1"
    info "Docker not found, installing..."

    if [ "$pkg_mgr" = "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>/dev/null | \
            gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null || true

        local codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
            > /etc/apt/sources.list.d/docker.list 2>/dev/null || true

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1

    elif [ "$pkg_mgr" = "yum" ]; then
        yum install -y -q yum-utils >/dev/null 2>&1
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
    fi

    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 3

    if ! command -v docker &>/dev/null; then
        error "Docker install failed: https://docs.docker.com/engine/install/"
    fi
}

# ============================================================
# Internal: Pull base images from Docker Hub
# ============================================================
_pull_images() {
    info "Pulling base images from Docker Hub..."
    for img in \
        "mysql:8.0" \
        "redis:7-alpine" \
        "nginx:alpine" \
        "certbot/certbot:latest"; do
        info "Pulling $img ..."
        docker pull "$img" 2>/dev/null || warn "Failed to pull $img"
    done
    success "Images ready"
}

# ============================================================
# Internal: Init compose command
# ============================================================
_init_compose() {
    COMPOSE_CMD="$(detect_compose)"

    if [ -z "$COMPOSE_CMD" ]; then
        info "Installing Docker Compose..."

        if [ "$PKG_MGR" = "apt" ]; then
            apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 || true
        elif [ "$PKG_MGR" = "yum" ]; then
            yum install -y -q docker-compose-plugin >/dev/null 2>&1 || true
        fi

        if ! docker compose version &>/dev/null 2>&1; then
            pip3 install docker-compose >/dev/null 2>&1 || \
            pip install docker-compose >/dev/null 2>&1 || true
        fi

        COMPOSE_CMD="$(detect_compose)"
        [ -z "$COMPOSE_CMD" ] && error "Docker Compose install failed"
    fi
}

# ============================================================
# Install
# ============================================================
do_install() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║    Email Platform - One-Click Deploy     ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo -e "  Port: $NGINX_PORT   Dir: $PROJECT_DIR"

    PKG_MGR="$(detect_pkg_mgr)"
    [ -z "$PKG_MGR" ] && error "Unsupported OS"

    # Step 1: Docker
    step "1/5  Install Docker"
    if ! check_docker; then
        _install_docker "$PKG_MGR"
        success "Docker installed"
    else
        success "Docker ready"
    fi

    # Step 2: Pull images
    step "2/5  Pull Docker Images"
    _pull_images
    success "Images ready"

    # Step 3: Source
    step "3/5  Fetch Project Source"
    mkdir -p "$PROJECT_DIR"
    cd /tmp
    rm -rf email_platform.zip email_platform-main
    curl -fsSL -o email_platform.zip \
        "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"
    unzip -o -q email_platform.zip
    rm -rf "${PROJECT_DIR:?}"/*
    cp -a email_platform-main/. "$PROJECT_DIR/"
    rm -rf email_platform.zip email_platform-main
    cd "$PROJECT_DIR"

    mkdir -p certbot-data certbot-www ssl logs
    cp -f nginx-docker.conf nginx.conf

    # Replace DaoCloud mirrors with Docker Hub
    sed -i 's|docker\.m\.daocloud\.io|docker.io|g' docker-compose.yml
    sed -i 's|https://mirror\.baidubce\.com||g' docker-compose.yml
    sed -i 's|https://hub-mirror\.c\.163\.com||g' docker-compose.yml
    sed -i 's|https://docker\.mirrors\.ustc\.edu\.cn||g' docker-compose.yml

    success "Source ready"

    # Step 4: Config & Build
    step "4/5  Build & Start"
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
    info "Using: $COMPOSE_CMD"
    $COMPOSE_CMD down 2>/dev/null || true
    info "Building images (first run ~5-10 min)..."
    if [ "$COMPOSE_CMD" = "docker compose" ]; then
        $COMPOSE_CMD up -d --build
    else
        $COMPOSE_CMD up -d --build --no-cache
    fi

    # Wait for MySQL
    info "Waiting for MySQL..."
    local count=0
    while [ $count -lt 60 ]; do
        if $COMPOSE_CMD exec -T mysql mysqladmin ping -h localhost -uroot -p'EmailPlatform2024!' &>/dev/null 2>&1; then
            success "MySQL ready (${count}s)"
            break
        fi
        count=$((count + 1))
        sleep 1
    done
    if [ $count -ge 60 ]; then
        warn "MySQL startup timeout, continuing..."
    fi

    # Init DB
    info "Initializing database..."
    $COMPOSE_CMD exec -T app python3 -c "
from app.app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('DB ready')
" 2>/dev/null || warn "Database initialized"

    success "Services started"

    # Step 5: Status
    step "5/5  Service Status"
    $COMPOSE_CMD ps

    local server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
                      curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
                      echo "YOUR_SERVER_IP")
    local elapsed=$(( $(date +%s) - START_TIME ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║       Deployed Successfully!          ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Access URL:${NC}  http://${server_ip}:${NGINX_PORT}"
    echo -e "  ${CYAN}Admin User:${NC}  admin"
    echo -e "  ${CYAN}Admin Pass:${NC}  admin123456"
    echo -e "  ${CYAN}Time Cost:${NC}  ${mins}m ${secs}s"
    echo ""
    echo -e "${YELLOW}--- Commands ---${NC}"
    echo -e "  Status:    cd $PROJECT_DIR && $COMPOSE_CMD ps"
    echo -e "  Logs:      cd $PROJECT_DIR && $COMPOSE_CMD logs -f app"
    echo -e "  Restart:   cd $PROJECT_DIR && $COMPOSE_CMD restart"
    echo -e "  Stop:      cd $PROJECT_DIR && $COMPOSE_CMD down"
    echo -e "  Uninstall: bash $0 uninstall"
    echo ""
    echo -e "${RED}${BOLD}!!! Change default password admin123456 immediately !!!${NC}"
    echo ""
}

# ============================================================
# Uninstall
# ============================================================
do_uninstall() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       Email Platform - Uninstall       ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""

    read -p "  Confirm uninstall? All data will be deleted! (y/n) [n]: " confirm
    confirm=${confirm:-n}
    [[ ! "$confirm" =~ ^[Yy]$ ]] && info "Cancelled" && exit 0

    PKG_MGR="$(detect_pkg_mgr)"

    step "1/4  Stop & Remove Containers"
    COMPOSE_CMD="$(detect_compose)"
    COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

    if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        cd "$PROJECT_DIR"
        $COMPOSE_CMD down -v 2>/dev/null || true
        info "Containers removed"
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

    step "2/4  Remove Project Directory"
    rm -rf "$PROJECT_DIR"
    success "Project directory removed"

    step "3/4  Remove Docker (optional)"
    read -p "  Remove Docker software? (y/n) [n]: " del_docker
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
        success "Docker removed"
    fi

    step "4/4  Done"
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        Uninstalled Successfully!       ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# Main
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
        [ ! -d "$PROJECT_DIR" ] && error "Project not installed. Run: bash $0 install"
        cd "$PROJECT_DIR"
        info "Restarting services..."
        $COMPOSE_CMD restart
        success "Restarted"
        ;;
    status|s)
        COMPOSE_CMD="$(detect_compose)"
        COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
        [ ! -d "$PROJECT_DIR" ] && error "Project not installed"
        cd "$PROJECT_DIR"
        $COMPOSE_CMD ps
        ;;
    logs|l)
        COMPOSE_CMD="$(detect_compose)"
        COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
        [ ! -d "$PROJECT_DIR" ] && error "Project not installed"
        cd "$PROJECT_DIR"
        if [ -n "$2" ]; then
            $COMPOSE_CMD logs -f --tail=100 "$2"
        else
            $COMPOSE_CMD logs -f
        fi
        ;;
    help|h|-h|--help)
        echo ""
        echo -e "${BOLD}Usage:${NC}  bash $0 <command>"
        echo ""
        echo -e "  ${GREEN}install${NC}     Install (default)"
        echo -e "  ${RED}uninstall${NC}    Uninstall"
        echo -e "  ${YELLOW}restart${NC}     Restart services"
        echo -e "  ${CYAN}status${NC}      Show status"
        echo -e "  ${CYAN}logs${NC}        Show logs"
        echo -e "  ${CYAN}logs app${NC}     Show app logs"
        echo -e "  ${CYAN}logs nginx${NC}   Show nginx logs"
        echo -e "  ${CYAN}help${NC}        Show this help"
        echo ""
        echo -e "${BOLD}Examples:${NC}"
        echo "  bash $0 install                  # Install (port 5200)"
        echo "  NGINX_PORT=8080 bash $0 install  # Install (port 8080)"
        echo "  bash $0 uninstall               # Uninstall"
        echo "  bash $0 restart                 # Restart"
        echo "  bash $0 logs                    # Show all logs"
        echo "  bash $0 logs app                # Show app logs"
        echo ""
        ;;
    *)
        error "Unknown command: $MODE    Usage: bash $0 help"
        ;;
esac
