# 邮件发送平台 V1.0

多用户权限邮件发送平台，支持邮件模板管理、SMTP智能中继、Open API、自服务后台。

## 功能模块

| 模块 | 功能 | 权限 |
|------|------|------|
| 模块一 | 登录 & 全局UI设置 | 所有用户 |
| 模块二 | 用户管理与风控 | 超级管理员 |
| 模块三 | 用户组管理 | 超级管理员 |
| 模块四 | 邮件模板管理 + 变量替换 | 所有用户 |
| 模块五 | 邮件单发/群发 + 发送记录 | 所有用户 |
| 模块六 | SMTP智能中继管理 | 超级管理员 |
| 模块七 | 系统日志审计 | 管理员全量，用户仅自己 |
| 模块八 | API接口管理 | 超级管理员 |
| 模块九 | 个人中心 | 所有用户 |
| 模块十 | 常见问题FAQ | - |
| 模块十一 | API完整调用文档 | - |

## 技术栈

- **后端**: Python 3 + Flask + SQLAlchemy + JWT
- **前端**: HTML5 + CSS3 + JavaScript（原生）
- **数据库**: MySQL 5.7+ / MariaDB 10.3+
- **缓存**: Redis
- **部署**: Nginx + Gunicorn + Supervisor
- **API**: RESTful API `/api/v2/`

## 快速部署

### Ubuntu / Debian

```bash
git clone https://github.com/your-username/email_platform.git /opt/email_platform
cd /opt/email_platform
sudo bash deploy.sh
```

### CentOS / RHEL

```bash
git clone https://github.com/your-username/email_platform.git /opt/email_platform
cd /opt/email_platform
sudo bash deploy-centos.sh
```

### Docker（计划中）

```bash
docker-compose up -d
```

## 部署后

- 访问地址: `http://your-server-ip`
- 管理账号: `admin`
- 管理密码: `admin123456`

> ⚠️ 请立即修改默认密码！

## API 签名算法

```
Sign = MD5(ApiKey + Timestamp + Nonce + ApiSecret)
```

## 项目结构

```
email_platform/
├── app.py                  # 主应用入口
├── config.py               # 配置文件
├── wsgi.py                 # WSGI 入口
├── requirements.txt        # Python 依赖
├── deploy.sh               # Ubuntu 部署脚本
├── deploy-centos.sh        # CentOS 部署脚本
├── one-click-deploy.sh     # 一键远程部署
├── app/
│   ├── models/             # 数据库模型
│   ├── routes/             # API 路由
│   ├── services/           # 业务逻辑
│   ├── middleware/          # 中间件（认证/权限）
│   ├── utils/              # 工具函数
│   └── templates/          # 前端模板
└── static/                 # 静态资源
```

## License

MIT
