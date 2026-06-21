#!/bin/bash
# ============================================================
#  Email Platform - One-Click Deploy (Global / Overseas)
#  Supported: Ubuntu / Debian / CentOS / Rocky / AlmaLinux
#  Registry: Docker Hub (Official)
# ============================================================

set -e

# ==================== Colors ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }
step()    { echo ""; echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ==================== Config ====================
NGINX_PORT="${NGINX_PORT:-${1:-5200}}"
PROJECT_DIR="/opt/email_platform"
TIMER_START=$(date +%s)

if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_PORT" -lt 1 ] || [ "$NGINX_PORT" -gt 65535 ]; then
    error "Invalid port: $NGINX_PORT"
fi

# ==================== Detect Package Manager ====================
check_pkg_mgr() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v yum &>/dev/null; then echo "yum"
    else echo ""
    fi
}

PKG_MGR="$(check_pkg_mgr)"
if [ -z "$PKG_MGR" ]; then
    error "Unsupported OS: apt-get or yum not found"
fi

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║    Email Platform - One-Click Deploy     ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo -e "  Port: $NGINX_PORT   Dir: $PROJECT_DIR"

# ============================================================
# Step 1: Install Docker
# ============================================================
step "1/5  Install Docker"

if ! command -v docker &>/dev/null; then
    info "Docker not found, installing..."

    if [ "$PKG_MGR" = "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null

        # Official Docker CE (stable)
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>/dev/null | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg --yes 2>/dev/null || true
        DISTRIB_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu ${DISTRIB_CODENAME} stable" \
            > /etc/apt/sources.list.d/docker.list 2>/dev/null || true

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null

    elif [ "$PKG_MGR" = "yum" ]; then
        yum install -y -q yum-utils >/dev/null 2>&1
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
    fi

    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 3

    if ! command -v docker &>/dev/null; then
        error "Docker install failed: https://docs.docker.com/engine/install/"
    fi
    success "Docker installed"
else
    if ! docker info &>/dev/null; then
        info "Docker daemon not running, starting..."
        systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 3
    fi
    success "Docker ready"
fi

# ============================================================
# Step 2: Pull Images (Docker Hub - Official)
# ============================================================
step "2/5  Pull Docker Images"

# Pull base images from Docker Hub
for image in \
    "mysql:8.0" \
    "redis:7-alpine" \
    "nginx:alpine" \
    "certbot/certbot:latest"; do
    info "Pulling $image ..."
    docker pull "$image" 2>/dev/null || warn "Failed to pull $image"
done
success "Images ready"

# ============================================================
# Step 3: Fetch Project Source
# ============================================================
step "3/5  Fetch Project Source"

mkdir -p "$PROJECT_DIR"
cd /tmp

rm -rf email_platform.zip email_platform-main
curl -fsSL -o email_platform.zip \
    "https://github.com/jiujiu123520/email_platform/archive/refs/heads/main.zip"

unzip -o -q email_platform.zip
rm -rf "$PROJECT_DIR"/*
cp -a email_platform-main/. "$PROJECT_DIR/"
rm -rf email_platform.zip email_platform-main
cd "$PROJECT_DIR"

mkdir -p certbot-data certbot-www ssl logs
cp -f nginx-docker.conf nginx.conf

# Update docker-compose.yml to use Docker Hub images
sed -i 's|docker\.m\.daocloud\.io/library/|docker.io/library/|g' docker-compose.yml
sed -i 's|docker\.m\.daocloud\.io/certbot/|docker.io/certbot/|g' docker-compose.yml
sed -i 's|docker\.m\.daocloud\.io/library/nginx:alpine|docker.io/library/nginx:alpine|g' docker-compose.yml

success "Source ready"

# ============================================================
# Step 4: Config & Build
# ============================================================
step "4/5  Build & Start Services"

SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)

cat > .env << EOF
SECRET_KEY=${SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
NGINX_PORT=${NGINX_PORT}
DOMAIN=
ENABLE_SSL=false
EOF

# Detect compose command
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose not installed"
fi

info "Using: $COMPOSE_CMD"
$COMPOSE_CMD down 2>/dev/null || true

info "Building images (first run ~5-10 min)..."
$COMPOSE_CMD up -d --build --no-cache

# Wait for MySQL
info "Waiting for MySQL..."
for i in $(seq 1 60); do
    if $COMPOSE_CMD exec -T mysql mysqladmin ping -h localhost -uroot -p"EmailPlatform2024\!" &>/dev/null 2>&1; then
        success "MySQL ready (${i}s)"
        break
    fi
    [ $i -eq 60 ] && warn "MySQL startup timeout, continuing..."
    sleep 1
done

# Init DB
info "Initializing database..."
$COMPOSE_CMD exec -T app python3 -c "
from app.app import create_app, init_db
app = create_app('production')
with app.app_context():
    init_db(app)
print('Database initialized')
" 2>/dev/null || warn "DB init may need manual check"

success "Services started"

# ============================================================
# Step 5: Output
# ============================================================
step "5/5  Service Status"
$COMPOSE_CMD ps

SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
             curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
             echo "YOUR_SERVER_IP")

TIMER_END=$(date +%s)
ELAPSED=$(( TIMER_END - TIMER_START ))
MIN=$(( ELAPSED / 60 ))
SEC=$(( ELAPSED % 60 ))

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           Deployed Successfully!       ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Access URL:${NC}  http://${SERVER_IP}:${NGINX_PORT}"
echo -e "  ${CYAN}Admin User:${NC}  admin"
echo -e "  ${CYAN}Admin Pass:${NC}  admin123456"
echo -e "  ${CYAN}Project Dir:${NC}  $PROJECT_DIR"
echo -e "  ${CYAN}Time Cost:${NC}  ${MIN}m ${SEC}s"
echo ""
echo -e "${YELLOW}--- Common Commands ---${NC}"
echo -e "  Status:   cd $PROJECT_DIR && $COMPOSE_CMD ps"
echo -e "  Logs:    cd $PROJECT_DIR && $COMPOSE_CMD logs -f app"
echo -e "  Restart: cd $PROJECT_DIR && $COMPOSE_CMD restart"
echo -e "  Stop:    cd $PROJECT_DIR && $COMPOSE_CMD down"
echo ""
echo -e "${RED}${BOLD}!!! Please change the default password admin123456 immediately !!!${NC}"
echo ""
