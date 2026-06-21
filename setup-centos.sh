#!/bin/bash
# ============================================================
#  邮件发送平台 - CentOS 环境一键安装脚本
#  仅安装系统环境（Python/MySQL/Redis/Nginx/Supervisor）
#  不部署项目代码
#
#  用法:
#    sudo bash setup-centos.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && error "请使用 root 或 sudo 运行"

detect_pkg_manager() {
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"; PKG_INSTALL="dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"; PKG_INSTALL="yum install -y"
    else
        error "未找到 yum 或 dnf"
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_VERSION="${VERSION_ID%%.*}"
        info "系统: ${PRETTY_NAME}"
    else
        OS_VERSION="7"
    fi
}

echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   邮件发送平台 - CentOS 环境一键安装    ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

detect_os
detect_pkg_manager

# 1. 更新系统
info "[1/8] 更新系统..."
$PKG_INSTALL epel-release 2>/dev/null || true
$PKG_MANAGER update -y
success "系统更新完成"

# 2. 安装基础工具
info "[2/8] 安装基础工具..."
$PKG_INSTALL wget curl vim net-tools htop git unzip tar logrotate ntpdate
success "基础工具安装完成"

# 3. 配置时区
info "[3/8] 配置时区..."
timedatectl set-timezone Asia/Shanghai
ntpdate -u pool.ntp.org 2>/dev/null || true
date
success "时区配置完成"

# 4. 关闭 SELinux
info "[4/8] 关闭 SELinux..."
setenforce 0 2>/dev/null || true
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
success "SELinux 已关闭"

# 5. 配置防火墙
info "[5/8] 配置防火墙..."
$PKG_INSTALL firewalld 2>/dev/null || true
systemctl start firewalld 2>/dev/null || true
systemctl enable firewalld 2>/dev/null || true
firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
firewall-cmd --permanent --add-port=443/tcp 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true
success "防火墙已放行 80/443"

# 6. 安装 Python 3
info "[6/8] 安装 Python 3..."
if [ "${OS_VERSION}" = "7" ]; then
    $PKG_INSTALL python36 python36-pip python36-devel 2>/dev/null || true
    if command -v python3.6 &> /dev/null && ! command -v python3 &> /dev/null; then
        ln -sf /usr/bin/python3.6 /usr/bin/python3
        ln -sf /usr/bin/pip3.6 /usr/bin/pip3
    fi
else
    $PKG_INSTALL python3 python3-pip python3-devel
fi
if ! command -v pip3 &> /dev/null; then
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3
fi
pip3 install --upgrade pip setuptools wheel
python3 --version
pip3 --version
success "Python 3 安装完成"

# 7. 安装 MySQL
info "[7/8] 安装 MySQL..."
if [ "${OS_VERSION}" = "7" ]; then
    $PKG_INSTALL mariadb-server mariadb
    systemctl start mariadb
    systemctl enable mariadb
    # 安全初始化
    mysql_secure_installation <<'SECURE' 2>/dev/null || true
n
Y
Y
Y
Y
Y
SECURE
else
    $PKG_INSTALL mysql-server
    systemctl start mysqld
    systemctl enable mysqld
fi

# 创建数据库
mysql -u root -e "CREATE DATABASE IF NOT EXISTS email_platform CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
mysql -u root -e "CREATE USER IF NOT EXISTS 'email_user'@'localhost' IDENTIFIED BY 'EmailPlatform2024!';" 2>/dev/null || true
mysql -u root -e "GRANT ALL PRIVILEGES ON email_platform.* TO 'email_user'@'localhost';" 2>/dev/null || true
mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
success "MySQL 安装并配置完成"

# 8. 安装 Redis + Nginx + Supervisor
info "[8/8] 安装 Redis、Nginx、Supervisor..."
$PKG_INSTALL redis nginx supervisor

# Redis
systemctl start redis
systemctl enable redis
sed -i 's/^# requirepass foobared/requirepass EmailPlatformRedis2024!/' /etc/redis.conf 2>/dev/null || true
sed -i 's/^bind 127.0.0.1 ::1/bind 127.0.0.1/' /etc/redis.conf 2>/dev/null || true
systemctl restart redis

# Nginx
systemctl start nginx
systemctl enable nginx

# Supervisor
systemctl start supervisord 2>/dev/null || systemctl start supervisor 2>/dev/null || true
systemctl enable supervisord 2>/dev/null || systemctl enable supervisor 2>/dev/null || true

success "Redis、Nginx、Supervisor 安装完成"

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   环境安装完成！                         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}已安装:${NC}"
echo -e "    ✔ Python 3 + pip"
echo -e "    ✔ MySQL/MariaDB"
echo -e "    ✔ Redis"
echo -e "    ✔ Nginx"
echo -e "    ✔ Supervisor"
echo -e "    ✔ 防火墙 (80/443 已放行)"
echo -e "    ✔ SELinux (已关闭)"
echo ""
echo -e "  ${CYAN}数据库信息:${NC}"
echo -e "    数据库: email_platform"
echo -e "    用户名: email_user"
echo -e "    密码:   EmailPlatform2024!"
echo ""
echo -e "  ${YELLOW}下一步:${NC}"
echo -e "    1. 上传项目源码到 /opt/email_platform"
echo -e "    2. cd /opt/email_platform && bash deploy-centos.sh"
echo ""
