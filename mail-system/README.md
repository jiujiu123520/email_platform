# MailSystem - 轻量级自托管邮件系统

一个基于 PHP + MySQL 的完整自托管邮件系统，支持自定义 SMTP 发送端口（25/465/587）与 POP3/IMAP 接收端口（110/995/143/993），提供美观的可视化后台管理、域名绑定、API 对接、Linux 一键部署。

## ✨ 核心特性

- 📬 **完整邮件协议**：自实现 SMTP / POP3 / IMAP 服务端（基于 PHP socket），无依赖外部 MTA
- 🔒 **多端口 SSL 支持**：SMTP 465/587（STARTTLS）、POP3 995、IMAP 993
- 🌐 **域名绑定**：支持绑定多个域名，独立管理邮件账户
- 🎨 **前后端分离**：Vue 3 + Element Plus 后台 SPA + 独立 Web 邮件端
- 🔧 **后台管理可定制**：管理路径、访问端口可自定义
- 🔌 **API 对接**：RESTful API，支持 API Key 认证
- 🚀 **一键安装**：自动检测系统、自动安装依赖（PHP / MariaDB / Nginx）
- 🐧 **Linux 部署**：支持 CentOS / Debian / Ubuntu，提供 systemd 服务管理

## 📋 系统要求

- **PHP** 7.4+ (推荐 8.0+)
- **PHP 扩展**：pdo_mysql, sockets, openssl, mbstring, iconv, pcntl, posix
- **MySQL / MariaDB** 5.7+
- **Linux** 内核 3.10+（CentOS 7+/Debian 10+/Ubuntu 18.04+）
- **Web 服务器**（可选）：Nginx / Apache

## 🚀 一键安装

### 方式一：一键安装脚本（推荐）

```bash
# 下载代码
git clone https://github.com/yourname/mail-system.git /opt/mail-system
cd /opt/mail-system

# 一键安装（自动安装 PHP、MariaDB、Nginx，配置数据库与服务）
sudo bash scripts/install.sh
```

`install.sh` 会自动完成：
1. 检测系统类型（CentOS / Debian / Ubuntu）
2. 安装 PHP 8.x、MariaDB 10.x、Nginx（含必需 PHP 扩展）
3. 创建数据库与用户
4. 导入数据库 Schema
5. 生成 APP_KEY 与 .env 配置文件
6. 配置 Nginx 反向代理
7. 注册 systemd 服务，开机自启

安装过程中会交互询问：
- 数据库密码
- 管理员账号/密码
- 默认域名
- 管理后台路径（默认 `admin`）
- 后台访问端口（默认 `8080`）

### 方式二：手动安装

```bash
# 1. 安装系统依赖
# CentOS / RHEL
sudo yum install -y php php-fpm php-pdo php-mysqlnd php-sockets php-openssl php-mbstring php-iconv php-pcntl mariadb-server nginx

# Debian / Ubuntu
sudo apt install -y php php-fpm php-mysql php-sockets php-openssl php-mbstring php-iconv php-pcntl mariadb-server nginx

# 2. 启动服务
sudo systemctl enable --now php-fpm mariadb nginx

# 3. 创建数据库
mysql -u root -p
> CREATE DATABASE mail_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
> CREATE USER 'mail_user'@'localhost' IDENTIFIED BY 'your_password';
> GRANT ALL ON mail_system.* TO 'mail_user'@'localhost';
> FLUSH PRIVILEGES;

# 4. 复制配置并修改
cp .env.example .env
vim .env   # 修改数据库连接、域名、管理员账号等

# 5. 运行安装程序
php bin/install-cli.php \
  --db-host=127.0.0.1 \
  --db-name=mail_system \
  --db-user=mail_user \
  --db-pass=your_password \
  --admin-user=admin \
  --admin-pass=admin123 \
  --admin-email=admin@yourdomain.com \
  --default-domain=yourdomain.com \
  --admin-path=admin \
  --mail-hostname=mail.yourdomain.com

# 6. 启动邮件服务（守护进程）
php bin/services.php start
php bin/services.php status   # 查看状态

# 7. 配置 Nginx
sudo cp config/nginx.conf.example /etc/nginx/conf.d/mail.conf
sudo vim /etc/nginx/conf.d/mail.conf  # 调整 server_name 与 root
sudo systemctl reload nginx
```

## 🎯 端口规划

| 服务 | 端口 | 加密 | 说明 |
|------|------|------|------|
| SMTP | 25 | 无 | 标准 SMTP 发送 |
| SMTP | 465 | SSL | SMTPS（隐式 TLS） |
| SMTP | 587 | STARTTLS | 提交端口（推荐） |
| POP3 | 110 | 无 | 标准 POP3 |
| POP3 | 995 | SSL | POP3S |
| IMAP | 143 | 无 | 标准 IMAP |
| IMAP | 993 | SSL | IMAPS |

所有端口都可以在后台管理界面里**动态启用/禁用/修改**（后台 → 端口管理）。

## 🖥️ 后台管理

访问：`http://your-server:8080/admin/`（路径与端口可在安装时自定义）

### 功能模块
- **仪表盘**：系统状态、流量统计
- **域名管理**：添加/删除/启停域名，DNS 记录指引
- **邮箱管理**：创建/删除/重置密码邮箱，容量限制
- **端口管理**：自定义 SMTP/POP3/IMAP 端口与 SSL 设置
- **邮件列表**：查看所有邮件（按用户/域筛选）
- **API 密钥管理**：生成/吊销 API Key
- **系统设置**：网站名称、Logo、Maildir 路径
- **用户管理**：管理员与普通用户 CRUD
- **系统日志**：操作日志与系统日志
- **系统信息**：PHP 版本、扩展检测、磁盘空间

## 🌐 Web 邮件端

访问：`http://your-server/`（普通端口）

类似 Foxmail 风格的多标签邮件界面，支持：
- 登录 / 退出
- 收件箱 / 草稿 / 发送 / 垃圾箱
- 撰写邮件（支持 HTML）
- 邮件详情查看（text/html 双视图）
- 删除邮件

## 🔌 API 对接

所有 API 端点位于 `/api/v1/`，支持两种认证方式：

### 1. Bearer Token
```bash
curl -X POST http://localhost/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"your_password"}'

# 返回
{"code":0,"data":{"token":"...","expires_at":"..."}}
```

### 2. API Key
```bash
curl http://localhost/api/v1/emails \
  -H "X-API-Key: ms_live_xxxxxxxxxxxxxxxx"
```

### 主要端点
| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/auth/login` | 登录获取 Token |
| GET  | `/api/v1/auth/me` | 当前用户信息 |
| GET  | `/api/v1/domains` | 域名列表 |
| POST | `/api/v1/domains` | 添加域名 |
| GET  | `/api/v1/mailboxes` | 邮箱列表 |
| POST | `/api/v1/mailboxes` | 创建邮箱 |
| GET  | `/api/v1/emails` | 邮件列表 |
| POST | `/api/v1/emails` | 发送邮件 |
| GET  | `/api/v1/emails/{id}` | 邮件详情 |
| DELETE | `/api/v1/emails/{id}` | 删除邮件 |

详细 API 文档参见 `docs/API.md`。

## 📂 项目结构

```
mail-system/
├── app/                       # 核心代码
│   ├── Core/                  # 框架核心（Database/Request/Response/Auth/MimeParser...）
│   ├── Controllers/           # HTTP 控制器
│   ├── Models/                # 数据模型
│   └── Services/              # 协议服务端 (SMTP/POP3/IMAP)
├── public/                    # Web 入口
│   ├── admin/                 # 后台管理前端
│   ├── web/                   # Web 邮件前端
│   ├── api.php                # API 路由
│   └── index.php              # 统一入口
├── config/                    # 配置文件
├── database/                  # 数据库 Schema
├── scripts/                   # 部署脚本
│   ├── install.sh             # 一键安装
│   ├── service.sh             # 服务管理
│   └── uninstall.sh           # 卸载
├── bin/                       # CLI 工具
│   ├── install-cli.php        # CLI 安装程序
│   └── services.php           # 邮件服务启停
├── storage/                   # 运行时数据
├── logs/                      # 日志
├── data/                      # 邮件存储（Maildir）
├── tests/                     # 测试
└── install/                   # Web 安装向导
```

## 🔧 服务管理

```bash
# 启动 / 停止 / 重启 / 状态
php bin/services.php start
php bin/services.php stop
php bin/services.php restart
php bin/services.php status

# 或通过 systemd（安装脚本会注册）
sudo systemctl start  mail-system
sudo systemctl stop   mail-system
sudo systemctl status mail-system
sudo journalctl -u mail-system -f
```

## 🧪 测试

```bash
# 单元 + 集成测试
php tests/test.php

# 端到端集成测试（需要 MySQL 已配置）
php tests/integration_test.php
```

## 🔐 安全建议

1. **生产环境务必启用 HTTPS**（后台与 Web 端）
2. **修改默认管理员密码**（`admin/admin123` 仅为演示）
3. **配置防火墙**仅开放必要端口
4. **定期备份** `data/mailboxes/` 与 MySQL
5. **API Key 妥善保管**（泄露后可吊销重发）
6. **配置 SPF/DKIM/DMARC** 提升投递率

## 🌐 域名 DNS 配置

要让其他服务器接收您域名发出的邮件，请配置以下 DNS 记录：

```
A     mail.yourdomain.com     <your-server-ip>
MX    yourdomain.com          mail.yourdomain.com (优先级 10)
TXT   yourdomain.com          v=spf1 mx ~all
TXT   _dmarc.yourdomain.com   v=DMARC1; p=quarantine; rua=mailto:admin@yourdomain.com
```

## 🐛 故障排查

| 现象 | 检查 |
|------|------|
| 端口未监听 | `php bin/services.php status` / `ss -tlnp \| grep 25` |
| 邮件无法发送 | 检查 `logs/smtp-*.log` |
| 邮件无法接收 | 检查 `logs/pop3-*.log` 和 `data/mailboxes/` 权限 |
| 后台无法访问 | 检查 `.env` 中 `ADMIN_PATH`、`ADMIN_PORT` 与 Nginx 配置 |
| 数据库连接失败 | 确认 MariaDB 已启动：`systemctl status mariadb` |

## 📜 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 与 Pull Request！

## 📮 联系方式

- Issues: [GitHub Issues](https://github.com/yourname/mail-system/issues)
- Email: support@example.com
