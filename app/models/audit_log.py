"""
系统日志审计模型 - 模块七：系统日志审计
记录所有操作日志，管理员可查看全部，普通用户仅查看自己的
"""
from datetime import datetime
from app.models.database import db


class AuditLog(db.Model):
    """系统审计日志模型"""
    __tablename__ = 'audit_logs'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True, index=True)
    user = db.relationship('User', foreign_keys=[user_id])

    # 操作信息
    action = db.Column(db.String(100), nullable=False, index=True)  # 操作类型
    module = db.Column(db.String(50), nullable=False, index=True)  # 模块名称
    description = db.Column(db.String(500), default='')  # 操作描述
    target_type = db.Column(db.String(50), default='')  # 操作对象类型
    target_id = db.Column(db.Integer, default=None)  # 操作对象ID

    # 请求信息
    ip_address = db.Column(db.String(45), nullable=False, index=True)
    browser = db.Column(db.String(200), default='')
    os = db.Column(db.String(100), default='')
    device = db.Column(db.String(200), default='')
    request_url = db.Column(db.String(500), default='')
    request_method = db.Column(db.String(10), default='')
    request_params = db.Column(db.Text, default='')  # 请求参数JSON

    # 结果
    result = db.Column(db.Enum('success', 'failure'), default='success')
    error_message = db.Column(db.Text, default='')

    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'username': self.user.username if self.user else 'system',
            'action': self.action,
            'module': self.module,
            'description': self.description,
            'target_type': self.target_type,
            'target_id': self.target_id,
            'ip_address': self.ip_address,
            'browser': self.browser,
            'os': self.os,
            'device': self.device,
            'result': self.result,
            'error_message': self.error_message,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }

    @staticmethod
    def create_log(user_id=None, action='', module='', description='',
                   target_type='', target_id=None, ip_address='',
                   browser='', os='', device='', result='success',
                   error_message='', request_url='', request_method='',
                   request_params=''):
        """创建审计日志的便捷方法"""
        try:
            log = AuditLog(
                user_id=user_id, action=action, module=module,
                description=description, target_type=target_type,
                target_id=target_id, ip_address=ip_address or '0.0.0.0',
                browser=browser, os=os, device=device, result=result,
                error_message=error_message, request_url=request_url,
                request_method=request_method, request_params=request_params,
            )
            db.session.add(log)
            db.session.commit()
            return log
        except Exception:
            db.session.rollback()
            return None
