#!/bin/bash
# ============================================================
# 邮件发送平台 - Docker 一键卸载脚本
# 卸载 Docker 部署的邮件发送平台
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; }

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   邮件发送平台 - Docker 一键卸载        ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# 确认卸载
read -p "确认卸载 Docker 部署的邮件发送平台吗? (y/n) [默认: n]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消卸载"
    exit 0
fi

PROJECT_DIR="/opt/email_platform"

# 询问是否删除数据
read -p "是否同时删除数据卷（数据库、Redis 数据等）? (y/n) [默认: n]: " delete_volumes
read -p "是否同时删除项目目录? (y/n) [默认: n]: " delete_project
read -p "是否同时删除 Docker 镜像? (y/n) [默认: n]: " delete_images
read -p "是否同时卸载 Docker 软件? (y/n) [默认: n]: " uninstall_docker

# 1. 停止并删除容器
info "步骤 1/6: 停止并删除容器..."
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    cd "$PROJECT_DIR"
    docker-compose down 2>/dev/null || true
    success "容器已停止并删除"
else
    warn "docker-compose.yml 不存在，尝试直接删除容器..."
    docker stop email_platform_app email_platform_mysql email_platform_redis email_platform_nginx email_platform_certbot 2>/dev/null || true
    docker rm -f email_platform_app email_platform_mysql email_platform_redis email_platform_nginx email_platform_certbot 2>/dev/null || true
    success "容器已停止并删除"
fi

# 2. 删除数据卷
if [[ "$delete_volumes" =~ ^[Yy]$ ]]; then
    info "步骤 2/6: 删除数据卷..."
    if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        cd "$PROJECT_DIR"
        docker-compose down -v 2>/dev/null || true
    fi
    docker volume rm email_platform_mysql_data email_platform_redis_data 2>/dev/null || true
    success "数据卷已删除"
else
    info "步骤 2/6: 跳过数据卷删除"
fi

# 3. 删除项目目录
if [[ "$delete_project" =~ ^[Yy]$ ]]; then
    info "步骤 3/6: 删除项目目录..."
    if [ -d "$PROJECT_DIR" ]; then
        rm -rf "$PROJECT_DIR"
        success "项目目录已删除: $PROJECT_DIR"
    else
        warn "项目目录不存在: $PROJECT_DIR"
    fi
else
    info "步骤 3/6: 跳过项目目录删除"
fi

# 4. 删除 Docker 镜像
if [[ "$delete_images" =~ ^[Yy]$ ]]; then
    info "步骤 4/6: 删除 Docker 镜像..."
    docker rmi -f email_platform-app 2>/dev/null || true
    docker rmi -f docker.m.daocloud.io/library/mysql:8.0 2>/dev/null || true
    docker rmi -f docker.m.daocloud.io/library/redis:7-alpine 2>/dev/null || true
    docker rmi -f docker.m.daocloud.io/library/nginx:alpine 2>/dev/null || true
    docker rmi -f docker.m.daocloud.io/certbot/certbot:latest 2>/dev/null || true
    docker rmi -f docker.m.daocloud.io/library/python:3.9-slim 2>/dev/null || true
    success "Docker 镜像已删除"
else
    info "步骤 4/6: 跳过镜像删除"
fi

# 5. 清理 Docker 资源
info "步骤 5/6: 清理 Docker 缓存..."
docker system prune -f 2>/dev/null || true
docker network rm email_platform_email_network 2>/dev/null || true
success "Docker 缓存已清理"

# 6. 卸载 Docker 软件
if [[ "$uninstall_docker" =~ ^[Yy]$ ]]; then
    info "步骤 6/6: 卸载 Docker..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi

    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum remove -y docker docker-client docker-client-latest docker-common \
            docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
        rm -rf /var/lib/docker
    else
        apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        rm -rf /var/lib/docker
    fi

    success "Docker 已卸载"
else
    info "步骤 6/6: 跳过 Docker 卸载"
fi

# 输出卸载信息
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   Docker 卸载完成！                      ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "已删除以下内容："
echo "  - 所有容器（app、mysql、redis、nginx、certbot）"
[ "$delete_volumes" == "y" ] || [ "$delete_volumes" == "Y" ] && echo "  - 数据卷（数据库、Redis 数据）"
[ "$delete_project" == "y" ] || [ "$delete_project" == "Y" ] && echo "  - 项目目录: $PROJECT_DIR"
[ "$delete_images" == "y" ] || [ "$delete_images" == "Y" ] && echo "  - Docker 镜像"
[ "$uninstall_docker" == "y" ] || [ "$uninstall_docker" == "Y" ] && echo "  - Docker 软件"
echo ""
