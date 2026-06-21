"""
邮件模板模型 - 模块四：邮件模板管理 + 变量替换
支持富文本编辑、HTML源码、变量替换、垃圾邮件评分
"""
from datetime import datetime
from app.models.database import db


class EmailTemplate(db.Model):
    """邮件模板模型"""
    __tablename__ = 'email_templates'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(200), nullable=False)
    subject = db.Column(db.String(500), nullable=False)
    html_content = db.Column(db.Text, nullable=False)  # HTML内容
    text_content = db.Column(db.Text, default='')  # 纯文本备选
    variables = db.Column(db.Text, default='')  # 使用的变量列表，JSON格式
    spam_score = db.Column(db.Float, default=0.0)  # 垃圾邮件评分
    category = db.Column(db.String(50), default='general')  # 模板分类

    # 所有用户可创建，但只能管理自己的模板（管理员可管理所有）
    created_by = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    creator = db.relationship('User', foreign_keys=[created_by])

    is_system = db.Column(db.Boolean, default=False)  # 是否为系统模板
    is_deleted = db.Column(db.Boolean, default=False)  # 硬删除标记

    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'subject': self.subject,
            'html_content': self.html_content,
            'text_content': self.text_content,
            'variables': self.variables,
            'spam_score': self.spam_score,
            'category': self.category,
            'created_by': self.created_by,
            'creator_name': self.creator.display_name or self.creator.username,
            'is_system': self.is_system,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }

    @staticmethod
    def render_template(html_content, variables_dict):
        """
        变量替换
        支持变量: {username}, {toEmail}, {sendTime}, {today}, {subject}
        """
        import re
        from datetime import datetime

        default_vars = {
            'today': datetime.utcnow().strftime('%Y-%m-%d'),
            'sendTime': datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S'),
        }
        # 合并默认变量和传入变量
        all_vars = {**default_vars, **(variables_dict or {})}

        def replace_var(match):
            var_name = match.group(1)
            return str(all_vars.get(var_name, match.group(0)))

        return re.sub(r'\{(\w+)\}', replace_var, html_content)
