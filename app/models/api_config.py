"""
API接口管理模型 - 模块八：API接口管理
仅超级管理员可操作
"""
from datetime import datetime
from app.models.database import db


class ApiConfig(db.Model):
    """API配置模型"""
    __tablename__ = 'api_configs'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(100), nullable=False)
    description = db.Column(db.String(500), default='')

    # API认证
    base_url = db.Column(db.String(255), default='/api/v2')
    enabled = db.Column(db.Boolean, default=True)

    # 限流配置
    rate_limit_per_hour = db.Column(db.Integer, default=100)
    rate_limit_per_day = db.Column(db.Integer, default=1000)
    concurrent_limit = db.Column(db.Integer, default=50)

    # IP白名单
    ip_whitelist_enabled = db.Column(db.Boolean, default=False)
    ip_whitelist = db.Column(db.Text, default='')  # 逗号分隔的IP列表

    # 签名配置
    sign_enabled = db.Column(db.Boolean, default=True)
    sign_expire_seconds = db.Column(db.Integer, default=300)  # 签名过期时间（秒）

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'base_url': self.base_url,
            'enabled': self.enabled,
            'rate_limit_per_hour': self.rate_limit_per_hour,
            'rate_limit_per_day': self.rate_limit_per_day,
            'concurrent_limit': self.concurrent_limit,
            'ip_whitelist_enabled': self.ip_whitelist_enabled,
            'ip_whitelist': self.ip_whitelist,
            'sign_enabled': self.sign_enabled,
            'sign_expire_seconds': self.sign_expire_seconds,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }


class ApiCallLog(db.Model):
    """API调用日志模型"""
    __tablename__ = 'api_call_logs'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True, index=True)
    user = db.relationship('User', foreign_keys=[user_id])

    endpoint = db.Column(db.String(255), nullable=False, index=True)
    method = db.Column(db.String(10), nullable=False)
    request_params = db.Column(db.Text, default='')
    request_body = db.Column(db.Text, default='')
    response_code = db.Column(db.Integer, default=200)
    response_body = db.Column(db.Text, default='')
    ip_address = db.Column(db.String(45), default='')
    user_agent = db.Column(db.String(500), default='')
    duration_ms = db.Column(db.Integer, default=0)  # 请求耗时（毫秒）

    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'username': self.user.username if self.user else None,
            'endpoint': self.endpoint,
            'method': self.method,
            'response_code': self.response_code,
            'ip_address': self.ip_address,
            'duration_ms': self.duration_ms,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
