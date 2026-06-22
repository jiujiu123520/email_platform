# 更新日志

## [1.0.0] - 2026-06-22

### 新增
- ✨ 完整的 SMTP / POP3 / IMAP 协议服务端（原生 PHP socket 实现）
- ✨ 自定义端口支持：SMTP 25/465/587，POP3 110/995，IMAP 143/993
- ✨ SSL/TLS 加密支持（SMTPS/POP3S/IMAPS + STARTTLS）
- ✨ 美观的 Vue 3 + Element Plus 后台管理 SPA
- ✨ 独立的 Web 邮件端（类 Foxmail 风格）
- ✨ 域名绑定与多域名管理
- ✨ RESTful API（v1），支持 Bearer Token 与 API Key
- ✨ Maildir 邮件存储格式
- ✨ 自实现 MIME 解析（multipart, base64, quoted-printable）
- ✨ 前后端分离，后台路径与端口可自定义
- ✨ Linux 一键安装脚本（CentOS / Debian / Ubuntu）
- ✨ systemd 服务管理
- ✨ 完整的命令行工具（CLI 安装、服务启停、状态监控）
- ✨ Web 安装向导
- ✨ 单元测试 + 集成测试

### 技术栈
- **后端**：原生 PHP 7.4+，PDO，pdo_mysql，sockets，pcntl，openssl
- **前端**：Vue 3，Element Plus（CDN 引入）
- **数据库**：MySQL 5.7+ / MariaDB 10.x
- **Web 服务器**：Nginx + PHP-FPM

### 修复
- 修复 MimeParser 中 content-type 小写化导致 boundary 匹配失败的问题
- 修复中文显示名无法被 `iconv_mime_decode` 正确处理的 bug
- 修复 BaseServer 中 foreach 迭代时修改数组导致未定义键警告的问题
- 修复 fork 后子进程共享父进程数据库连接导致的 "MySQL server has gone away" 问题
- 修复 POP3 客户端初次连接时 state 未初始化的 bug
- 修复 closeClient 中对 null socket 调 fclose 抛错的 bug
- 修复 schema.sql 中 `ssl` 字段（MySQL 保留字）需要反引号的问题
- 修复 MailStorage 中新投递的邮件被错误写入 cur/ 而非 new/ 的问题
- 修复 install-cli.php 中 `getOpt` 与 PHP 内置函数冲突的问题
- 修复 .env.example 缺少 MAIL_HOSTNAME 默认值的问题
