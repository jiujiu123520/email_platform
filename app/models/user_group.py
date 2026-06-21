"""
用户组模型 - 模块三：用户组管理
仅超级管理员可操作
"""
from datetime import datetime
from app.models.database import db


class UserGroup(db.Model):
    """用户组模型"""
    __tablename__ = 'user_groups'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    description = db.Column(db.String(500), default='')
    max_daily_quota = db.Column(db.Integer, default=5000)  # 组级每日配额上限
    allowed_relay_ids = db.Column(db.Text, default='')  # 允许使用的SMTP中继ID，逗号分隔
    is_deleted = db.Column(db.Boolean, default=False)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # 关联
    members = db.relationship('User', back_populates='group', lazy='dynamic')

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'max_daily_quota': self.max_daily_quota,
            'allowed_relay_ids': self.allowed_relay_ids,
            'member_count': self.members.filter_by(is_deleted=False).count(),
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
