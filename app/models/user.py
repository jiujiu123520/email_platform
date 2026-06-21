"""
用户模型 - 模块二：用户管理与风控
支持多用户权限系统，软删除，登录风控，QQ号绑定
"""
from datetime import datetime
from app.models.database import db
import bcrypt


class User(db.Model):
    """用户模型"""
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    username = db.Column(db.String(50), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(128), nullable=False)
    display_name = db.Column(db.String(100), default='')
    avatar = db.Column(db.String(255), default='')
    phone = db.Column(db.String(20), default='')
    qq_number = db.Column(db.String(20), default='', index=True)  # QQ号
    qq_avatar = db.Column(db.String(500), default='')  # QQ头像URL
    role = db.Column(db.Enum('super_admin', 'admin', 'user'), default='user', nullable=False)
    status = db.Column(db.Enum('active', 'locked', 'disabled'), default='active', nullable=False)
    is_deleted = db.Column(db.Boolean, default=False, index=True)
    daily_quota = db.Column(db.Integer, default=1000)  # 每日发送配额
    used_quota_today = db.Column(db.Integer, default=0)  # 今日已用配额
    quota_reset_date = db.Column(db.Date, default=datetime.utcnow().date)  # 配额重置日期

    # 风控字段
    login_fail_count = db.Column(db.Integer, default=0)  # 连续登录失败次数
    login_lock_until = db.Column(db.DateTime, nullable=True)  # 锁定截止时间
    last_login_ip = db.Column(db.String(45), default='')
    last_login_time = db.Column(db.DateTime, nullable=True)
    last_login_browser = db.Column(db.String(200), default='')
    last_login_os = db.Column(db.String(100), default='')

    # API认证字段
    api_key = db.Column(db.String(64), unique=True, nullable=True, index=True)
    api_secret = db.Column(db.String(128), nullable=True)

    # 关联
    group_id = db.Column(db.Integer, db.ForeignKey('user_groups.id'), nullable=True)
    group = db.relationship('UserGroup', back_populates='members')

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    deleted_at = db.Column(db.DateTime, nullable=True)

    def set_password(self, password):
        """设置密码（bcrypt加密）"""
        password_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
        self.password_hash = password_hash.decode('utf-8')

    def check_password(self, password):
        """验证密码"""
        return bcrypt.checkpw(password.encode('utf-8'), self.password_hash.encode('utf-8'))

    def is_super_admin(self):
        return self.role == 'super_admin'

    def is_admin(self):
        return self.role in ('super_admin', 'admin')

    def reset_daily_quota(self):
        """重置每日配额"""
        today = datetime.utcnow().date()
        if self.quota_reset_date < today:
            self.used_quota_today = 0
            self.quota_reset_date = today

    def check_quota(self, count=1):
        """检查配额是否充足"""
        self.reset_daily_quota()
        return (self.used_quota_today + count) <= self.daily_quota

    def use_quota(self, count=1):
        """使用配额"""
        self.reset_daily_quota()
        self.used_quota_today += count

    def get_avatar_url(self):
        """获取头像URL，优先使用QQ头像"""
        if self.qq_avatar:
            return self.qq_avatar
        if self.avatar:
            return self.avatar
        return ''

    def to_dict(self, include_sensitive=False):
        """序列化为字典"""
        data = {
            'id': self.id,
            'username': self.username,
            'email': self.email,
            'display_name': self.display_name,
            'avatar': self.get_avatar_url(),
            'phone': self.phone,
            'qq_number': self.qq_number,
            'qq_avatar': self.qq_avatar,
            'role': self.role,
            'status': self.status,
            'daily_quota': self.daily_quota,
            'used_quota_today': self.used_quota_today,
            'group_id': self.group_id,
            'last_login_time': self.last_login_time.isoformat() if self.last_login_time else None,
            'last_login_ip': self.last_login_ip,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
        if include_sensitive:
            data['api_key'] = self.api_key
        return data
