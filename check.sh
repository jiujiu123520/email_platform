#!/bin/bash
# ============================================================
# 邮件发送平台 - 服务器环境检查脚本
# 检测系统是否满足安装要求
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0
WARN=0
FAIL=0

check_pass() { echo -e "  ${GREEN}✔${NC} $1"; ((PASS++)); }
check_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; ((WARN++)); }
check_fail() { echo -e "  ${RED}✖${NC} $1"; ((FAIL++)); }

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║   邮件发送平台 - 环境检查                ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ============================================================
# 系统信息
# ============================================================
echo -e "${BLUE}${BOLD}【系统信息】${NC}"

# 操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    check_pass "操作系统: $PRETTY_NAME"
    OS=$ID
    VER=$VERSION_ID
else
    check_fail "无法检测操作系统"
    OS="unknown"
fi

# 内核版本
KERNEL=$(uname -r)
check_pass "内核版本: $KERNEL"

# 架构
ARCH=$(uname -m)
check_pass "系统架构: $ARCH"

# 主机名
HOSTNAME=$(hostname)
check_pass "主机名: $HOSTNAME"

# 运行时间
UPTIME=$(uptime -p 2>/dev/null || uptime)
check_pass "运行时间: $UPTIME"

echo ""

# ============================================================
# 硬件资源
# ============================================================
echo -e "${BLUE}${BOLD}【硬件资源】${NC}"

# CPU
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
if [ "$CPU_CORES" -ge 4 ]; then
    check_pass "CPU 核心: ${CPU_CORES} 核 (推荐 ≥4)"
elif [ "$CPU_CORES" -ge 2 ]; then
    check_warn "CPU 核心: ${CPU_CORES} 核 (建议 ≥4)"
else
    check_warn "CPU 核心: ${CPU_CORES} 核 (Docker 部署可能性能不足)"
fi

# CPU 使用率
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
if [ -n "$CPU_USAGE" ]; then
    if [ "$CPU_USAGE" -lt 80 ]; then
        check_pass "CPU 使用率: ${CPU_USAGE}%"
    else
        check_warn "CPU 使用率: ${CPU_USAGE}% (较高)"
    fi
fi

# 内存
TOTAL_MEM=$(free -m | awk '/^Mem:/ {print $2}')
USED_MEM=$(free -m | awk '/^Mem:/ {print $3}')
MEM_PERCENT=$((USED_MEM * 100 / TOTAL_MEM))

if [ "$TOTAL_MEM" -ge 4096 ]; then
    check_pass "内存: ${TOTAL_MEM}MB (已用 ${USED_MEM}MB, ${MEM_PERCENT}%)"
elif [ "$TOTAL_MEM" -ge 2048 ]; then
    check_warn "内存: ${TOTAL_MEM}MB (建议 ≥4GB)"
else
    check_fail "内存: ${TOTAL_MEM}MB (不足 2GB，普通部署可能失败)"
fi

# 硬盘
DISK_INFO=$(df -h / | tail -1)
DISK_TOTAL=$(echo $DISK_INFO | awk '{print $2}')
DISK_USED=$(echo $DISK_INFO | awk '{print $3}')
DISK_AVAIL=$(echo $DISK_INFO | awk '{print $4}')
DISK_PERCENT=$(echo $DISK_INFO | awk '{print $5}')

# 解析可用空间为数字（GB）
DISK_AVAIL_GB=$(echo $DISK_AVAIL | sed 's/G//' | sed 's/T/*1024/' | bc 2>/dev/null || echo "0")

if [ "$DISK_AVAIL_GB" -ge 20 ] 2>/dev/null; then
    check_pass "硬盘可用: ${DISK_AVAIL} / ${DISK_TOTAL}"
elif [ "$DISK_AVAIL_GB" -ge 10 ] 2>/dev/null; then
    check_warn "硬盘可用: ${DISK_AVAIL} / ${DISK_TOTAL} (建议 ≥20GB)"
else
    check_warn "硬盘可用: ${DISK_AVAIL} / ${DISK_TOTAL} (可能不足)"
fi

# Swap
SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
if [ "$SWAP_TOTAL" -gt 0 ]; then
    check_pass "Swap: ${SWAP_TOTAL}MB"
else
    check_warn "Swap: 未配置"
fi

echo ""

# ============================================================
# 网络检查
# ============================================================
echo -e "${BLUE}${BOLD}【网络】${NC}"

# IP 地址
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "无法获取")
check_pass "公网 IP: $SERVER_IP"

# DNS
DNS_CHECK=$(nslookup github.com 2>&1 | grep -c "Address:" || echo "0")
if [ "$DNS_CHECK" -gt 0 ]; then
    check_pass "DNS 解析: 正常"
else
    check_warn "DNS 解析: 可能异常"
fi

# 网络连通性
if curl -s --max-time 5 -o /dev/null -w "%{http_code}" https://github.com | grep -q "200\|301\|302"; then
    check_pass "GitHub 连通性: 正常"
else
    check_warn "GitHub 连通性: 异常（脚本可能无法下载源码）"
fi

# 国内镜像
if curl -s --max-time 5 -o /dev/null -w "%{http_code}" https://gh.jasonzeng.dev | grep -q "200\|301\|302\|404"; then
    check_pass "国内镜像 gh.jasonzeng.dev: 可访问"
else
    check_warn "国内镜像 gh.jasonzeng.dev: 不可访问"
fi

# 端口检查
PORT_80=$(ss -tlnp 2>/dev/null | grep -c ":80 " || echo "0")
PORT_443=$(ss -tlnp 2>/dev/null | grep -c ":443 " || echo "0")
PORT_5200=$(ss -tlnp 2>/dev/null | grep -c ":5200 " || echo "0")
PORT_3306=$(ss -tlnp 2>/dev/null | grep -c ":3306 " || echo "0")

if [ "$PORT_5200" -eq 0 ]; then
    check_pass "5200 端口: 未占用"
else
    check_warn "5200 端口: 已被占用"
fi

if [ "$PORT_3306" -eq 0 ]; then
    check_pass "3306 端口: 未占用"
else
    check_warn "3306 端口: 已被占用（MySQL 可能会冲突）"
fi

echo ""

# ============================================================
# Docker 环境检查
# ============================================================
echo -e "${BLUE}${BOLD}【Docker 环境】${NC}"

DOCKER_AVAILABLE=false

if command -v docker &> /dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null)
    check_pass "Docker: 已安装 ($DOCKER_VER)"

    # Docker 服务状态
    if systemctl is-active --quiet docker 2>/dev/null; then
        check_pass "Docker 服务: 运行中"
        DOCKER_AVAILABLE=true
    else
        check_warn "Docker 服务: 未运行（尝试启动...）"
        systemctl start docker 2>/dev/null && check_pass "Docker 服务: 启动成功" || check_fail "Docker 服务: 启动失败"
    fi

    # Docker Compose
    if command -v docker-compose &>/dev/null; then
        COMPOSE_VER=$(docker-compose --version 2>/dev/null)
        if [ -n "$COMPOSE_VER" ]; then
            check_pass "Docker Compose: 已安装 ($COMPOSE_VER)"
        else
            check_warn "Docker Compose: 损坏需要重装"
        fi
    else
        check_warn "Docker Compose: 未安装"
    fi

    # Docker 镜像加速
    if [ -f /etc/docker/daemon.json ]; then
        check_pass "镜像加速: 已配置"
    else
        check_warn "镜像加速: 未配置（国内服务器拉取可能慢）"
    fi

    # Docker 测试
    if docker run --rm hello-world &>/dev/null 2>&1; then
        check_pass "Docker 运行测试: 正常"
    else
        check_warn "Docker 运行测试: 失败（可能需要权限）"
    fi
else
    check_warn "Docker: 未安装（无法使用 Docker 部署）"
fi

echo ""

# ============================================================
# 普通部署环境检查
# ============================================================
echo -e "${BLUE}${BOLD}【普通部署环境】${NC}"

# Python
if command -v python3.9 &>/dev/null; then
    PY_VER=$(python3.9 --version 2>&1)
    check_pass "Python 3.9: 已安装 ($PY_VER)"
elif command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    if [[ "$PY_VER" == *"3.9"* ]] || [[ "$PY_VER" == *"3.10"* ]] || [[ "$PY_VER" == *"3.11"* ]]; then
        check_pass "Python: 已安装 ($PY_VER)"
    else
        check_warn "Python: 已安装但版本不匹配 ($PY_VER)，需要 3.9+"
    fi
else
    check_warn "Python 3.9+: 未安装"
fi

# MySQL/MariaDB
if command -v mysql &>/dev/null; then
    DB_VER=$(mysql --version 2>&1)
    check_pass "MySQL/MariaDB: 已安装 ($DB_VER)"
else
    check_warn "MySQL/MariaDB: 未安装"
fi

# Redis
if command -v redis-server &>/dev/null; then
    REDIS_VER=$(redis-server --version 2>&1)
    check_pass "Redis: 已安装 ($REDIS_VER)"
else
    check_warn "Redis: 未安装"
fi

# Nginx
if command -v nginx &>/dev/null; then
    NGINX_VER=$(nginx -v 2>&1)
    check_pass "Nginx: 已安装 ($NGINX_VER)"
else
    check_warn "Nginx: 未安装"
fi

# Supervisor
if command -v supervisorctl &>/dev/null; then
    check_pass "Supervisor: 已安装"
else
    check_warn "Supervisor: 未安装"
fi

# 系统包管理器
if command -v yum &>/dev/null; then
    check_pass "包管理器: yum (CentOS/RHEL)"
elif command -v apt-get &>/dev/null; then
    check_pass "包管理器: apt (Ubuntu/Debian)"
else
    check_fail "包管理器: 未找到"
fi

# curl/unzip
command -v curl &>/dev/null && check_pass "curl: 已安装" || check_fail "curl: 未安装"
command -v unzip &>/dev/null && check_pass "unzip: 已安装" || check_fail "unzip: 未安装"

echo ""

# ============================================================
# 安全检查
# ============================================================
echo -e "${BLUE}${BOLD}【安全】${NC}"

# 防火墙
if command -v firewall-cmd &>/dev/null; then
    FW_STATUS=$(firewall-cmd --state 2>/dev/null)
    if [ "$FW_STATUS" == "running" ]; then
        check_pass "防火墙 (firewalld): 运行中"
    else
        check_warn "防火墙 (firewalld): 未运行"
    fi
elif command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    if [[ "$UFW_STATUS" == *"active"* ]]; then
        check_pass "防火墙 (ufw): 运行中"
    else
        check_warn "防火墙 (ufw): 未运行"
    fi
elif command -v iptables &>/dev/null; then
    check_pass "防火墙 (iptables): 已安装"
else
    check_warn "防火墙: 未检测到"
fi

# SELinux
if [ -f /etc/selinux/config ]; then
    SELINUX=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
    if [ "$SELINUX" == "enforcing" ]; then
        check_warn "SELinux: enforcing (可能影响 Docker)"
    else
        check_pass "SELinux: $SELINUX"
    fi
fi

# SSH 端口
SSH_PORT=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | cut -d: -f2 | head -1)
if [ -n "$SSH_PORT" ]; then
    check_pass "SSH 端口: $SSH_PORT"
fi

echo ""

# ============================================================
# 检查结果总结
# ============================================================
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}检查结果：${NC}"
echo -e "  ${GREEN}通过: $PASS${NC}"
echo -e "  ${YELLOW}警告: $WARN${NC}"
echo -e "  ${RED}失败: $FAIL${NC}"
echo ""

# 部署建议
echo -e "${BOLD}【部署建议】${NC}"
if [ "$DOCKER_AVAILABLE" = true ] && [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}✔ 推荐使用 Docker 部署${NC}"
    echo -e "    命令: bash manage.sh 选择 1"
elif [ "$DOCKER_AVAILABLE" = false ] && [ "$FAIL" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠ 建议使用普通部署（未检测到 Docker）${NC}"
    echo -e "    命令: bash manage.sh 选择 2"
elif [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}✖ 环境不满足要求，请先解决失败项${NC}"
fi

echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}"
