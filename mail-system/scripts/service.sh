#!/usr/bin/env bash
# ============================================
# MailSystem 服务管理脚本
# ============================================

APP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PID_DIR="$APP_DIR/storage/cache"
LOG_DIR="$APP_DIR/logs"
PHP_BIN="${PHP_BIN:-/usr/bin/php}"
[ ! -x "$PHP_BIN" ] && PHP_BIN=$(command -v php)

color() { echo -e "\033[0;$1$2\033[0m"; }
GREEN="32"; RED="31"; YELLOW="33"; BLUE="36"

start() {
    color "$GREEN" "启动 MailSystem 邮件服务..."
    if [ ! -f "$APP_DIR/storage/installed.lock" ]; then
        color "$RED" "系统未安装，请先运行 install.sh"
        exit 1
    fi
    nohup "$PHP_BIN" "$APP_DIR/bin/services.php" start > "$LOG_DIR/services-start.log" 2>&1 &
    sleep 2
    status
}

stop() {
    color "$YELLOW" "停止 MailSystem 邮件服务..."
    "$PHP_BIN" "$APP_DIR/bin/services.php" stop
    sleep 1
    color "$GREEN" "已停止"
}

status() {
    "$PHP_BIN" "$APP_DIR/bin/services.php" status
}

test_services() {
    color "$BLUE" "测试邮件服务连接..."
    "$PHP_BIN" "$APP_DIR/bin/services.php" test
}

restart() {
    stop
    sleep 1
    start
}

case "${1:-status}" in
    start)    start ;;
    stop)     stop ;;
    status)   status ;;
    restart)  restart ;;
    test)     test_services ;;
    *)        echo "用法: $0 {start|stop|status|restart|test}"; exit 1 ;;
esac
