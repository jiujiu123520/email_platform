#!/usr/bin/env bash
# MailSystem 卸载脚本

APP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行"
    exit 1
fi

echo "停止服务..."
systemctl stop mailsystem 2>/dev/null
systemctl disable mailsystem 2>/dev/null
rm -f /etc/systemd/system/mailsystem.service
systemctl daemon-reload

echo "停止 PHP 服务进程..."
"$APP_DIR/scripts/service.sh" stop 2>/dev/null || true

echo "删除 Nginx 配置..."
rm -f /etc/nginx/conf.d/mailsystem.conf
rm -f /etc/nginx/sites-enabled/mailsystem
nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null

echo "删除防火墙规则..."
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --remove-port=25/tcp 2>/dev/null
    firewall-cmd --permanent --remove-port=465/tcp 2>/dev/null
    firewall-cmd --permanent --remove-port=587/tcp 2>/dev/null
    firewall-cmd --permanent --remove-port=110/tcp 2>/dev/null
    firewall-cmd --permanent --remove-port=995/tcp 2>/dev/null
    firewall-cmd --permanent --remove-port=143/tcp 2>/dev/null
    firewall-cmd --permanent --remove-port=993/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
fi
if command -v ufw >/dev/null 2>&1; then
    ufw delete allow 25/tcp 2>/dev/null
    ufw delete allow 465/tcp 2>/dev/null
    ufw delete allow 587/tcp 2>/dev/null
    ufw delete allow 110/tcp 2>/dev/null
    ufw delete allow 995/tcp 2>/dev/null
    ufw delete allow 143/tcp 2>/dev/null
    ufw delete allow 993/tcp 2>/dev/null
fi

echo
echo "数据库和数据目录需要手动删除："
echo "  mysql -uroot -e \"DROP DATABASE IF EXISTS mail_system; DROP USER IF EXISTS 'mail_user'@'localhost';\""
echo "  rm -rf $APP_DIR/data/mailboxes  (邮件数据)"
echo "  rm -rf $APP_DIR                (整个项目)"
echo
echo "如需完全卸载请手动执行以上命令。"
