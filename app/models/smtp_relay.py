"""
SMTP智能中继模型 - 模块六：SMTP智能中继管理
支持负载均衡、自动切换、健康自检、流量控制、多端口支持
"""
from datetime import datetime, date
from app.models.database import db


class SmtpRelay(db.Model):
    """SMTP中继模型"""
    __tablename__ = 'smtp_relays'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(200), nullable=False)
    host = db.Column(db.String(200), nullable=False)
    port = db.Column(db.Integer, default=587)
    username = db.Column(db.String(200), nullable=False)
    password = db.Column(db.String(500), nullable=False)  # 加密存储
    use_tls = db.Column(db.Boolean, default=True)
    use_ssl = db.Column(db.Boolean, default=False)

    # 权重和状态
    weight = db.Column(db.Integer, default=10)  # 负载均衡权重
    status = db.Column(
        db.Enum('active', 'paused', 'disabled'),
        default='active', nullable=False
    )

    # 健康检查
    is_healthy = db.Column(db.Boolean, default=True)
    consecutive_failures = db.Column(db.Integer, default=0)  # 连续失败次数
    last_check_at = db.Column(db.DateTime, nullable=True)
    last_success_at = db.Column(db.DateTime, nullable=True)
    last_failure_at = db.Column(db.DateTime, nullable=True)

    # 统计
    total_sent = db.Column(db.Integer, default=0)  # 总发送数
    total_success = db.Column(db.Integer, default=0)  # 总成功数
    total_failed = db.Column(db.Integer, default=0)  # 总失败数
    daily_sent = db.Column(db.Integer, default=0)  # 今日发送数
    daily_quota = db.Column(db.Integer, default=10000)  # 每日配额
    daily_quota_reset_date = db.Column(db.Date, default=date.today)

    # 备注
    description = db.Column(db.String(500), default='')
    priority = db.Column(db.Integer, default=0)  # 优先级，数字越大优先级越高

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # 常用SMTP端口配置建议
    PORT_PRESETS = {
        25: {'name': 'SMTP (25)', 'ssl': False, 'tls': False, 'desc': '标准SMTP端口，无加密'},
        109: {'name': 'POP2 (109)', 'ssl': False, 'tls': False, 'desc': 'POP2协议端口'},
        110: {'name': 'POP3 (110)', 'ssl': False, 'tls': False, 'desc': 'POP3协议端口'},
        143: {'name': 'IMAP (143)', 'ssl': False, 'tls': False, 'desc': 'IMAP协议端口'},
        465: {'name': 'SMTPS (465)', 'ssl': True, 'tls': False, 'desc': 'SSL加密SMTP'},
        587: {'name': 'SMTP-TLS (587)', 'ssl': False, 'tls': True, 'desc': 'TLS加密SMTP（推荐）'},
        995: {'name': 'POP3S (995)', 'ssl': True, 'tls': False, 'desc': 'SSL加密POP3'},
        993: {'name': 'IMAPS (993)', 'ssl': True, 'tls': False, 'desc': 'SSL加密IMAP'},
        994: {'name': 'IMAPS旧 (994)', 'ssl': True, 'tls': False, 'desc': '旧版IMAPS端口'},
    }

    def reset_daily_stats(self):
        """重置每日统计"""
        today = date.today()
        if self.daily_quota_reset_date < today:
            self.daily_sent = 0
            self.daily_quota_reset_date = today

    def check_daily_quota(self):
        """检查每日配额"""
        self.reset_daily_stats()
        return self.daily_sent < self.daily_quota

    def get_success_rate(self):
        """获取成功率"""
        if self.total_sent == 0:
            return 0.0
        return round(self.total_success / self.total_sent * 100, 2)

    @classmethod
    def get_port_presets(cls):
        """获取端口预设配置"""
        return cls.PORT_PRESETS

    @classmethod
    def get_port_suggestion(cls, port):
        """根据端口获取建议配置"""
        preset = cls.PORT_PRESETS.get(port, {})
        return {
            'use_ssl': preset.get('ssl', False),
            'use_tls': preset.get('tls', False),
            'description': preset.get('desc', '')
        }

    def to_dict(self, include_password=False):
        data = {
            'id': self.id,
            'name': self.name,
            'host': self.host,
            'port': self.port,
            'username': self.username,
            'use_tls': self.use_tls,
            'use_ssl': self.use_ssl,
            'weight': self.weight,
            'status': self.status,
            'is_healthy': self.is_healthy,
            'consecutive_failures': self.consecutive_failures,
            'total_sent': self.total_sent,
            'total_success': self.total_success,
            'total_failed': self.total_failed,
            'daily_sent': self.daily_sent,
            'daily_quota': self.daily_quota,
            'success_rate': self.get_success_rate(),
            'description': self.description,
            'priority': self.priority,
            'last_check_at': self.last_check_at.isoformat() if self.last_check_at else None,
            'last_success_at': self.last_success_at.isoformat() if self.last_success_at else None,
            'last_failure_at': self.last_failure_at.isoformat() if self.last_failure_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
        if include_password:
            data['password'] = self.password
        return data
