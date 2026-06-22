"""
邮件发送服务 - 模块五
支持单发、批量发送、模板渲染、变量替换、高并发无限发送模式
"""
import re
import random
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from app.models.email_template import EmailTemplate
from app.models.email_record import EmailRecord
from app.models.user import User
from app.models.database import db
from app.services.smtp_service import SmtpRelayService
from config import Config


class EmailService:
    """邮件发送服务"""

    # 线程池（用于批量发送）
    _executor = None
    _lock = threading.Lock()

    @classmethod
    def get_executor(cls):
        """获取线程池"""
        if cls._executor is None or cls._executor._shutdown:
            with cls._lock:
                if cls._executor is None or cls._executor._shutdown:
                    max_workers = Config.SMTP_RELAY_CONCURRENT_LIMIT
                    cls._executor = ThreadPoolExecutor(max_workers=max_workers)
        return cls._executor

    @staticmethod
    def render_template(template_id, variables):
        """渲染邮件模板，替换变量"""
        template = EmailTemplate.query.get(template_id)
        if not template:
            return None, None, '模板不存在'

        subject = template.subject
        html_content = template.html_content
        text_content = template.text_content or ''

        # 替换变量 ${variable_name}
        if variables:
            for key, value in variables.items():
                placeholder = f'${{{key}}}'
                subject = subject.replace(placeholder, str(value))
                html_content = html_content.replace(placeholder, str(value))
                text_content = text_content.replace(placeholder, str(value))

        return subject, html_content, text_content

    @staticmethod
    def validate_email(email):
        """验证邮箱格式"""
        if email is None:
            return False
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None

    @classmethod
    def send_single_email(cls, sender_id, from_email, from_name,
                          to_email, to_name, subject, html_content,
                          template_id=None, variables=None, text_content=''):
        """
        发送单封邮件
        返回: (success, record_id, message)
        """
        # 验证邮箱
        if not cls.validate_email(to_email):
            return False, None, '收件人邮箱格式不正确'

        # 检查用户配额
        user = User.query.get(sender_id)
        if not user:
            return False, None, '用户不存在'

        if not user.check_quota(1):
            return False, None, '今日发送配额已用完'

        # 渲染模板
        if template_id:
            rendered = cls.render_template(template_id, variables or {})
            if rendered[0] is None:
                return False, None, rendered[2]
            subject, html_content, text_content = rendered

        # 创建发送记录
        record = EmailRecord(
            sender_id=sender_id,
            from_email=from_email,
            from_name=from_name,
            to_email=to_email,
            to_name=to_name,
            subject=subject,
            html_content=html_content,
            template_id=template_id,
            status='sending',
        )
        db.session.add(record)
        db.session.commit()

        # 获取可用中继
        relay = SmtpRelayService.get_available_relay()
        if not relay:
            record.status = 'failed'
            record.error_message = '没有可用的SMTP中继'
            db.session.commit()
            return False, record.id, '没有可用的SMTP中继，请检查SMTP配置'

        # 发送邮件
        success, error = SmtpRelayService.send_email_via_relay(
            relay, from_email, from_name, to_email, to_name,
            subject, html_content, text_content
        )

        # 更新记录
        if success:
            record.status = 'sent'
            record.sent_at = datetime.utcnow()
            record.smtp_relay_id = relay.id
            user.use_quota(1)
            db.session.commit()

            # 无限发送模式：随机延迟
            if Config.UNLIMITED_MODE:
                delay = random.uniform(Config.SEND_DELAY_MIN, Config.SEND_DELAY_MAX)
                time.sleep(delay)

            return True, record.id, '邮件发送成功'
        else:
            record.status = 'failed'
            record.error_message = error
            db.session.commit()
            return False, record.id, f'邮件发送失败: {error}'

    @classmethod
    def send_batch_emails(cls, sender_id, from_email, from_name,
                          recipients, subject, html_content,
                          template_id=None, variables_list=None, text_content=''):
        """
        批量发送邮件（使用线程池并发发送）
        recipients: [(to_email, to_name), ...]
        返回: {'success_count': int, 'failed_count': int, 'records': [record_id, ...]}
        """
        results = {
            'success_count': 0,
            'failed_count': 0,
            'records': [],
            'errors': []
        }

        if not recipients:
            return results

        # 检查总配额
        user = User.query.get(sender_id)
        if not user:
            results['errors'].append('用户不存在')
            return results

        if not user.check_quota(len(recipients)):
            results['errors'].append('发送配额不足')
            return results

        # 使用线程池并发发送
        executor = cls.get_executor()
        futures = []

        for i, (to_email, to_name) in enumerate(recipients):
            # 每个收件人使用不同的变量
            vars_item = variables_list[i] if variables_list and i < len(variables_list) else {}

            future = executor.submit(
                cls._send_single_email_worker,
                sender_id, from_email, from_name,
                to_email, to_name, subject, html_content,
                template_id, vars_item, text_content
            )
            futures.append(future)

        # 收集结果
        for future in as_completed(futures):
            try:
                success, record_id, message = future.result()
                results['records'].append(record_id)
                if success:
                    results['success_count'] += 1
                else:
                    results['failed_count'] += 1
                    results['errors'].append(message)
            except Exception as e:
                results['failed_count'] += 1
                results['errors'].append(str(e))

        return results

    @classmethod
    def _send_single_email_worker(cls, sender_id, from_email, from_name,
                                   to_email, to_name, subject, html_content,
                                   template_id, variables, text_content):
        """工作线程：发送单封邮件"""
        # 每个线程需要独立的应用上下文
        from app import create_app
        app = create_app('production')
        with app.app_context():
            return cls.send_single_email(
                sender_id, from_email, from_name,
                to_email, to_name, subject, html_content,
                template_id, variables, text_content
            )

    @classmethod
    def retry_failed_email(cls, record_id):
        """重试发送失败的邮件"""
        record = EmailRecord.query.get(record_id)
        if not record:
            return False, '记录不存在'

        if record.status != 'failed':
            return False, '只能重试失败的邮件'

        if record.retry_count >= 3:
            return False, '已超过最大重试次数'

        # 更新状态
        record.status = 'sending'
        record.retry_count += 1
        db.session.commit()

        # 重新发送
        success, error = SmtpRelayService.send_email_via_relay(
            SmtpRelayService.get_available_relay(),
            record.from_email, record.from_name,
            record.to_email, record.to_name,
            record.subject, record.html_content
        )

        if success:
            record.status = 'sent'
            record.sent_at = datetime.utcnow()
            db.session.commit()
            return True, '重试成功'
        else:
            record.status = 'failed'
            record.error_message = error
            db.session.commit()
            return False, f'重试失败: {error}'
