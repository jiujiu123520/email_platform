"""
邮件发送记录模型 - 模块五：邮件发送 + 发送记录
支持单发、群发、发送状态追踪
"""
from datetime import datetime
from app.models.database import db


class EmailRecord(db.Model):
    """邮件发送记录模型"""
    __tablename__ = 'email_records'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    # 发送信息
    to_email = db.Column(db.String(120), nullable=False, index=True)
    to_name = db.Column(db.String(200), default='')
    subject = db.Column(db.String(500), nullable=False)
    body_html = db.Column(db.Text, nullable=False)
    body_text = db.Column(db.Text, default='')

    # 发送者
    from_email = db.Column(db.String(120), nullable=False)
    from_name = db.Column(db.String(200), default='')
    sender_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    sender = db.relationship('User', foreign_keys=[sender_id])

    # 模板
    template_id = db.Column(db.Integer, db.ForeignKey('email_templates.id'), nullable=True)
    template = db.relationship('EmailTemplate')

    # 发送状态
    status = db.Column(
        db.Enum('pending', 'sending', 'sent', 'failed', 'queued'),
        default='pending', nullable=False, index=True
    )
    send_type = db.Column(db.Enum('single', 'batch'), default='single')  # 单发/群发
    batch_id = db.Column(db.String(64), nullable=True, index=True)  # 批量发送批次ID

    # SMTP中继
    relay_id = db.Column(db.Integer, db.ForeignKey('smtp_relays.id'), nullable=True)
    relay = db.relationship('SmtpRelay')

    # 结果信息
    error_message = db.Column(db.Text, default='')
    retry_count = db.Column(db.Integer, default=0)
    max_retries = db.Column(db.Integer, default=3)

    # 时间
    sent_at = db.Column(db.DateTime, nullable=True)
    completed_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'to_email': self.to_email,
            'to_name': self.to_name,
            'subject': self.subject,
            'from_email': self.from_email,
            'from_name': self.from_name,
            'sender_id': self.sender_id,
            'template_id': self.template_id,
            'status': self.status,
            'send_type': self.send_type,
            'batch_id': self.batch_id,
            'relay_id': self.relay_id,
            'error_message': self.error_message,
            'retry_count': self.retry_count,
            'sent_at': self.sent_at.isoformat() if self.sent_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


class EmailBatch(db.Model):
    """批量发送批次模型"""
    __tablename__ = 'email_batches'

    id = db.Column(db.String(64), primary_key=True)
    sender_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    sender = db.relationship('User', foreign_keys=[sender_id])
    template_id = db.Column(db.Integer, db.ForeignKey('email_templates.id'), nullable=True)
    template = db.relationship('EmailTemplate')

    total_count = db.Column(db.Integer, default=0)  # 总数
    success_count = db.Column(db.Integer, default=0)  # 成功数
    failed_count = db.Column(db.Integer, default=0)  # 失败数
    pending_count = db.Column(db.Integer, default=0)  # 待发送数

    status = db.Column(
        db.Enum('pending', 'processing', 'completed', 'failed'),
        default='pending', nullable=False
    )

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    completed_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        return {
            'id': self.id,
            'sender_id': self.sender_id,
            'template_id': self.template_id,
            'total_count': self.total_count,
            'success_count': self.success_count,
            'failed_count': self.failed_count,
            'pending_count': self.pending_count,
            'status': self.status,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
        }
