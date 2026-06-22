# API 文档

## 基础信息

- **Base URL**：`http://your-server/api/v1`
- **认证方式**：
  - Bearer Token（推荐）
  - API Key（X-API-Key 头）
- **数据格式**：JSON
- **字符编码**：UTF-8

## 响应格式

成功：
```json
{
  "code": 0,
  "msg": "ok",
  "data": { ... }
}
```

失败：
```json
{
  "code": 1001,
  "msg": "Invalid credentials",
  "data": null
}
```

## 错误码

| Code | 含义 |
|------|------|
| 0 | 成功 |
| 400 | 请求参数错误 |
| 401 | 未认证 |
| 403 | 无权限 |
| 404 | 资源不存在 |
| 429 | 请求频率限制 |
| 500 | 服务器内部错误 |
| 1001 | 凭证无效 |
| 1002 | 邮箱不存在 |
| 1003 | 域名已存在 |
| 2001 | 邮件发送失败 |

## 认证接口

### 登录
```
POST /auth/login
Content-Type: application/json

{
  "email": "user@yourdomain.com",
  "password": "your_password"
}
```

返回：
```json
{
  "code": 0,
  "data": {
    "token": "ms_xxxxxxxxxxxxxxxxxxxx",
    "expires_at": 1700000000,
    "user": {
      "id": 1,
      "username": "user",
      "email": "user@yourdomain.com"
    }
  }
}
```

### 登出
```
POST /auth/logout
Authorization: Bearer <token>
```

### 当前用户
```
GET /auth/me
Authorization: Bearer <token>
```

## 域名接口

### 列表
```
GET /domains
GET /domains?status=1
```

### 详情
```
GET /domains/{id}
```

### 创建
```
POST /domains
Authorization: Bearer <token>
Content-Type: application/json

{
  "domain": "yourdomain.com",
  "owner_id": 1
}
```

### 更新
```
PUT /domains/{id}
{
  "status": 1
}
```

### 删除
```
DELETE /domains/{id}
```

## 邮箱接口

### 列表
```
GET /mailboxes
GET /mailboxes?domain_id=1
GET /mailboxes?user_id=1
```

### 创建
```
POST /mailboxes
Authorization: Bearer <token>
{
  "domain_id": 1,
  "local_part": "admin",
  "password": "secret123",
  "display_name": "Admin",
  "quota_mb": 1024
}
```

### 重置密码
```
POST /mailboxes/{id}/password
{
  "new_password": "new_secret123"
}
```

### 删除
```
DELETE /mailboxes/{id}
```

## 邮件接口

### 列表
```
GET /emails?mailbox_id=1
GET /emails?from=sender@example.com
GET /emails?subject=keyword
GET /emails?folder=INBOX
GET /emails?unread=1
GET /emails?limit=20&offset=0
```

### 详情
```
GET /emails/{id}
```

### 发送
```
POST /emails
Authorization: Bearer <token>
{
  "from": "admin@yourdomain.com",
  "to": ["user@example.com"],
  "cc": [],
  "bcc": [],
  "subject": "Hello",
  "text": "Plain text body",
  "html": "<p>HTML body</p>",
  "attachments": [
    {
      "filename": "test.txt",
      "content_type": "text/plain",
      "data": "base64_encoded_data"
    }
  ]
}
```

### 删除
```
DELETE /emails/{id}
```

### 标记已读
```
POST /emails/{id}/read
```

## API Key 接口

### 列表
```
GET /api-keys
```

### 创建
```
POST /api-keys
{
  "name": "My App",
  "scopes": ["read", "send"],
  "expires_at": 1700000000
}
```

### 吊销
```
DELETE /api-keys/{id}
```

## 端口接口

### 列表
```
GET /ports
GET /ports?service=smtp
```

### 启用/禁用
```
POST /ports/{id}/toggle
{
  "enabled": true
}
```

### 添加新端口
```
POST /ports
{
  "service": "smtp",
  "port": 2525,
  "bind_ip": "0.0.0.0",
  "ssl": false,
  "tls": false
}
```

## 速率限制

- 登录：5 次/分钟/IP
- 发送邮件：60 封/小时/用户
- 其他接口：600 次/分钟/Token

## 调用示例

### cURL
```bash
# 登录
TOKEN=$(curl -s -X POST http://localhost/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@yourdomain.com","password":"admin123"}' \
  | jq -r '.data.token')

# 发送邮件
curl -X POST http://localhost/api/v1/emails \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "from": "admin@yourdomain.com",
    "to": ["test@example.com"],
    "subject": "Hello",
    "text": "Hello World"
  }'
```

### PHP
```php
$ch = curl_init('http://localhost/api/v1/emails');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => [
        'Authorization: Bearer ' . $token,
        'Content-Type: application/json',
    ],
    CURLOPT_POSTFIELDS => json_encode([
        'from' => 'admin@yourdomain.com',
        'to' => ['test@example.com'],
        'subject' => 'Hello',
        'text' => 'Hello World',
    ]),
]);
$response = json_decode(curl_exec($ch), true);
```

### Python
```python
import requests

token = requests.post('http://localhost/api/v1/auth/login', json={
    'email': 'admin@yourdomain.com',
    'password': 'admin123'
}).json()['data']['token']

r = requests.post('http://localhost/api/v1/emails',
    headers={'Authorization': f'Bearer {token}'},
    json={
        'from': 'admin@yourdomain.com',
        'to': ['test@example.com'],
        'subject': 'Hello',
        'text': 'Hello World',
    })
print(r.json())
```
