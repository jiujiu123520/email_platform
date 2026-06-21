#!/bin/bash
# ============================================================
# 邮件发送平台 - 普通一键卸载脚本
# 卸载普通部署（非Docker）的邮件发送平台
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; }

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   邮件发送平台 - 普通一键卸载            ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# 确认卸载
read -p "确认卸载邮件发送平台吗？这将删除所有应用文件 (y/n) [默认: n]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消卸载"
    exit 0
fi

PROJECT_DIR="/opt/email_platform"
DB_NAME="email_platform"
DB_USER="email_user"

# 询问是否删除数据库
read -p "是否同时删除数据库? (y/n) [默认: n]: " delete_db

# 1. 停止并禁用 Supervisor 服务
info "步骤 1/6: 停止 Supervisor 服务..."
if command -v supervisorctl &>/dev/null; then
    supervisorctl stop email_platform 2>/dev/null || true
    supervisorctl remove email_platform 2>/dev/null || true
    rm -f /etc/supervisord.d/email_platform.ini
    supervisorctl reread
    supervisorctl update
    success "Supervisor 服务已停止"
else
    warn "supervisorctl 未安装，跳过"
fi

# 2. 停止并删除 Nginx 配置
info "步骤 2/6: 删除 Nginx 配置..."
if command -v nginx &>/dev/null; then
    rm -f /etc/nginx/conf.d/email_platform.conf
    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] 2>/dev/null; then
        nginx -t 2>/dev/null && systemctl reload nginx || true
    else
        nginx -t 2>/dev/null && systemctl reload nginx || true
    fi
    success "Nginx 配置已删除"
else
    warn "Nginx 未安装，跳过"
fi

# 3. 删除项目目录
info "步骤 3/6: 删除项目目录..."
if [ -d "$PROJECT_DIR" ]; then
    rm -rf "$PROJECT_DIR"
    success "项目目录已删除: $PROJECT_DIR"
else
    warn "项目目录不存在: $PROJECT_DIR"
fi

# 4. 删除日志文件
info "步骤 4/6: 删除日志文件..."
rm -f /var/log/email_platform.err.log
rm -f /var/log/email_platform.out.log
success "日志文件已删除"

# 5. 删除数据库（可选）
if [[ "$delete_db" =~ ^[Yy]$ ]]; then
    info "步骤 5/6: 删除数据库..."
    if command -v mysql &>/dev/null; then
        mysql -u root <<DBEOF
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
DROP USER IF EXISTS '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
DBEOF
        success "数据库已删除"
    else
        warn "MySQL 未安装，跳过"
    fi
else
    info "步骤 5/6: 跳过数据库删除"
fi

# 6. 询问是否卸载服务软件
info "步骤 6/6: 清理服务..."
read -p "是否卸载 MySQL/MariaDB、Redis、Nginx、Python 等软件? (y/n) [默认: n]: " uninstall_software

if [[ "$uninstall_software" =~ ^[Yy]$ ]]; then
    info "卸载服务软件..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi

    if [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum remove -y mariadb-server mariadb redis nginx python39 supervisor 2>/dev/null || true
    else
        apt-get purge -y mysql-server redis-server nginx python3.9 supervisor 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    fi

    success "服务软件已卸载"
else
    info "跳过软件卸载"
fi

# 输出卸载信息
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   普通卸载完成！                          ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "已删除以下内容："
echo "  - 项目目录: $PROJECT_DIR"
echo "  - Supervisor 配置"
echo "  - Nginx 配置"
echo "  - 日志文件"
[ "$delete_db" == "y" ] || [ "$delete_db" == "Y" ] && echo "  - 数据库"
[ "$uninstall_software" == "y" ] || [ "$uninstall_software" == "Y" ] && echo "  - 服务软件"
echo ""
