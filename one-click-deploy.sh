#!/bin/bash
# ============================================================
#  邮件发送平台 - 一键部署脚本（本地→远程全自动）
#  在本地执行此脚本，自动完成打包、上传、远程部署
#
#  用法:
#    bash one-click-deploy.sh                          # 交互式输入
#    bash one-click-deploy.sh 124.222.43.74 root pwd   # 命令行参数
#    bash one-click-deploy.sh --local                  # 仅本地打包
# ============================================================

set -e

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✖${NC} $1"; exit 1; }
step()    { echo ""; echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ==================== 配置 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
REMOTE_DIR="/opt/email_platform"
SSH_PORT=22
SSH_KEY=""
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
TAR_FILE="email_platform.tar.gz"

# ==================== 参数解析 ====================
if [[ "$1" == "--local" ]]; then
    info "仅本地打包模式..."
    do_package
    success "打包完成: ${SCRIPT_DIR}/${TAR_FILE}"
    exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo ""
    echo -e "${BOLD}邮件发送平台 - 一键部署脚本${NC}"
    echo ""
    echo "用法:"
    echo "  bash one-click-deploy.sh                              交互式输入"
    echo "  bash one-click-deploy.sh <IP> <用户> <密码>           命令行参数"
    echo "  bash one-click-deploy.sh <IP> <用户> <密码> <端口>    指定SSH端口"
    echo "  bash one-click-deploy.sh --local                      仅本地打包"
    echo ""
    echo "示例:"
    echo "  bash one-click-deploy.sh 124.222.43.74 root 'mypassword'"
    echo "  bash one-click-deploy.sh 124.222.43.74 root 'mypassword' 2222"
    echo ""
    exit 0
fi

SERVER_IP=""
SERVER_USER=""
SERVER_PASS=""

if [ -n "$1" ]; then SERVER_IP="$1"; fi
if [ -n "$2" ]; then SERVER_USER="$2"; fi
if [ -n "$3" ]; then SERVER_PASS="$3"; fi
if [ -n "$4" ]; then SSH_PORT="$4"; fi

# ==================== 交互式输入 ====================
if [ -z "$SERVER_IP" ]; then
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║   邮件发送平台 - 一键部署               ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -p "  请输入服务器 IP 地址: " SERVER_IP
    [ -z "$SERVER_IP" ] && error "IP 地址不能为空"
fi

if [ -z "$SERVER_USER" ]; then
    read -p "  请输入 SSH 用户名 [root]: " SERVER_USER
    SERVER_USER=${SERVER_USER:-root}
fi

if [ -z "$SERVER_PASS" ]; then
    read -sp "  请输入 SSH 密码: " SERVER_PASS
    echo ""
    [ -z "$SERVER_PASS" ] && error "密码不能为空"
fi

# ==================== 安装 sshpass ====================
step "检查 SSH 工具"
if ! command -v sshpass &> /dev/null; then
    info "安装 sshpass（用于自动输入密码）..."
    if command -v brew &> /dev/null; then
        brew install hudochenkov/sshpass/sshpass 2>/dev/null || brew install sshpass 2>/dev/null || true
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        warn "macOS 系统，请先安装 sshpass: brew install sshpass"
    else
        apt-get install -y sshpass 2>/dev/null || yum install -y sshpass 2>/dev/null || true
    fi
fi

if ! command -v sshpass &> /dev/null; then
    warn "sshpass 未安装，将使用 expect 作为替代..."
    if ! command -v expect &> /dev/null; then
        error "请先安装 sshpass 或 expect"
    fi
fi

SSH_CMD="sshpass -p '${SERVER_PASS}' ssh ${SSH_OPTS} -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP}"
SCP_CMD="sshpass -p '${SERVER_PASS}' scp ${SSH_OPTS} -P ${SSH_PORT}"

# ==================== 函数 ====================
remote_exec() {
    local cmd="$1"
    if command -v sshpass &> /dev/null; then
        sshpass -p "${SERVER_PASS}" ssh ${SSH_OPTS} -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "$cmd"
    else
        expect -c "
            spawn ssh ${SSH_OPTS} -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} $cmd
            expect {
                \"*password*\" { send \"${SERVER_PASS}\r\"; exp_continue }
                \"*Password*\" { send \"${SERVER_PASS}\r\"; exp_continue }
                eof
            }
        " 2>/dev/null
    fi
}

remote_scp() {
    local src="$1"
    local dst="$2"
    if command -v sshpass &> /dev/null; then
        sshpass -p "${SERVER_PASS}" scp ${SSH_OPTS} -P ${SSH_PORT} "$src" "${SERVER_USER}@${SERVER_IP}:${dst}"
    else
        expect -c "
            spawn scp ${SSH_OPTS} -P ${SSH_PORT} $src ${SERVER_USER}@${SERVER_IP}:$dst
            expect {
                \"*password*\" { send \"${SERVER_PASS}\r\"; exp_continue }
                \"*Password*\" { send \"${SERVER_PASS}\r\"; exp_continue }
                eof
            }
        " 2>/dev/null
    fi
}

do_package() {
    info "打包项目源码..."
    cd "${SCRIPT_DIR}"
    tar -czf "${TAR_FILE}" \
        app.py config.py wsgi.py requirements.txt .env.example \
        deploy.sh remote-deploy.sh \
        app/ static/ 2>/dev/null
    local size=$(du -h "${TAR_FILE}" | awk '{print $1}')
    success "打包完成: ${TAR_FILE} (${size})"
}

# ==================== 开始部署 ====================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   邮件发送平台 - 一键部署               ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo -e "  服务器: ${BOLD}${SERVER_USER}@${SERVER_IP}:${SSH_PORT}${NC}"
echo ""

TIMER_START=$(date +%s)

# ---- 步骤 1: 测试 SSH 连接 ----
step "步骤 1/5: 测试服务器连接"
info "连接 ${SERVER_USER}@${SERVER_IP}:${SSH_PORT} ..."
if remote_exec "echo '连接成功'" > /dev/null 2>&1; then
    success "SSH 连接正常"
else
    error "SSH 连接失败，请检查 IP、端口、密码是否正确"
fi

# ---- 步骤 2: 打包项目 ----
step "步骤 2/5: 打包项目源码"
do_package

# ---- 步骤 3: 上传到服务器 ----
step "步骤 3/5: 上传源码到服务器"
info "上传 ${TAR_FILE} → ${SERVER_IP}:/root/"
remote_scp "${SCRIPT_DIR}/${TAR_FILE}" "/root/"
success "上传完成"

# ---- 步骤 4: 远程解压 ----
step "步骤 4/5: 远程解压和准备"
info "在服务器上解压文件..."
remote_exec "
    mkdir -p ${REMOTE_DIR}
    cd /root
    tar -xzf ${TAR_FILE} -C ${REMOTE_DIR}/
    rm -f ${TAR_FILE}
    chmod +x ${REMOTE_DIR}/deploy.sh
    echo '解压完成'
"

# ---- 步骤 5: 远程执行部署 ----
step "步骤 5/5: 远程执行部署脚本"
info "在服务器上执行自动化部署（约 3-8 分钟）..."
info "正在安装系统依赖、MySQL、Redis、Python 环境..."
info "请耐心等待..."

remote_exec "cd ${REMOTE_DIR} && bash deploy.sh 2>&1"

# ---- 验证 ----
step "部署验证"
info "检查服务状态..."
sleep 3

REMOTE_STATUS=$(remote_exec "
    # 检查各服务
    NGINX_OK=\$(systemctl is-active nginx 2>/dev/null)
    MYSQL_OK=\$(systemctl is-active mysql 2>/dev/null)
    REDIS_OK=\$(systemctl is-active redis-server 2>/dev/null)
    APP_OK=\$(supervisorctl status email_platform 2>/dev/null | grep RUNNING | wc -l)

    echo \"Nginx=\${NGINX_OK}\"
    echo \"MySQL=\${MYSQL_OK}\"
    echo \"Redis=\${REDIS_OK}\"
    echo \"App=\${APP_OK}\"
" 2>/dev/null)

echo ""
echo -e "${BOLD}  服务状态:${NC}"
echo "$REMOTE_STATUS" | while read line; do
    key=$(echo "$line" | cut -d= -f1)
    val=$(echo "$line" | cut -d= -f2)
    if [ "$val" = "active" ] || [ "$val" = "1" ]; then
        echo -e "    ${GREEN}✔${NC} ${key}: 运行中"
    else
        echo -e "    ${RED}✖${NC} ${key}: ${val}"
    fi
done

# ---- 完成 ----
TIMER_END=$(date +%s)
ELAPSED=$(( TIMER_END - TIMER_START ))
MIN=$(( ELAPSED / 60 ))
SEC=$(( ELAPSED % 60 ))

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         部署完成！                       ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}访问地址:${NC}  http://${SERVER_IP}"
echo -e "  ${BOLD}管理账号:${NC}  admin"
echo -e "  ${BOLD}管理密码:${NC}  admin123456"
echo -e "  ${BOLD}部署目录:${NC}  ${REMOTE_DIR}"
echo -e "  ${BOLD}部署耗时:${NC}  ${MIN}分${SEC}秒"
echo ""
echo -e "${YELLOW}--- 常用命令（在服务器上执行）---${NC}"
echo -e "  查看状态:   ssh ${SERVER_USER}@${SERVER_IP} 'cd ${REMOTE_DIR} && bash deploy.sh --status'"
echo -e "  重启服务:   ssh ${SERVER_USER}@${SERVER_IP} 'cd ${REMOTE_DIR} && bash deploy.sh --restart'"
echo -e "  实时日志:   ssh ${SERVER_USER}@${SERVER_IP} 'cd ${REMOTE_DIR} && bash deploy.sh --logs'"
echo -e "  配置SSL:    ssh ${SERVER_USER}@${SERVER_IP} 'cd ${REMOTE_DIR} && bash deploy.sh --ssl yourdomain.com'"
echo -e "  卸载系统:   ssh ${SERVER_USER}@${SERVER_IP} 'cd ${REMOTE_DIR} && bash deploy.sh --uninstall'"
echo ""
echo -e "${RED}${BOLD}!!! 请立即登录系统修改默认管理员密码 !!!${NC}"
echo ""
