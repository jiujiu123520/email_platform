"""
邮件服务测试
测试配额管理、模板渲染、邮箱验证、批量发送等核心功能
"""
import pytest
from datetime import datetime, date
from app.services.email_service import EmailService
from app.models.user import User
from app.models.email_template import EmailTemplate
from app.models.email_record import EmailRecord
from app.models.smtp_relay import SmtpRelay
from app.models.database import db


class TestEmailValidation:
    """邮箱验证测试"""

    def test_valid_email(self):
        """测试有效的邮箱格式"""
        valid_emails = [
            'test@example.com',
            'user.name@example.com',
            'user+tag@example.com',
            'user@subdomain.example.com',
            'user123@test.co.uk'
        ]
        
        for email in valid_emails:
            assert EmailService.validate_email(email) is True

    def test_invalid_email(self):
        """测试无效的邮箱格式"""
        invalid_emails = [
            'invalid',
            '@example.com',
            'user@',
            'user @example.com',
            'user@example',
            '',
            'user@example.'
        ]
        
        for email in invalid_emails:
            assert EmailService.validate_email(email) is False


class TestTemplateRendering:
    """模板渲染测试"""

    def test_render_template_success(self, session, email_template):
        """测试成功渲染模板"""
        variables = {
            'name': '张三',
            'company': '测试公司'
        }
        
        subject, html, text = EmailService.render_template(
            email_template.id,
            variables
        )
        
        assert subject == 'Hello 张三'
        assert 'Hello 张三' in html
        assert 'Welcome to 测试公司!' in html
        assert 'Hello 张三' in text
        assert 'Welcome to 测试公司!' in text

    def test_render_template_not_found(self, session):
        """测试模板不存在"""
        subject, html, text = EmailService.render_template(999, {})
        
        assert subject is None
        assert html is None
        assert '模板不存在' in text

    def test_render_template_no_variables(self, session, email_template):
        """测试无变量时渲染模板"""
        subject, html, text = EmailService.render_template(
            email_template.id,
            None
        )
        
        # 变量未被替换
        assert '${name}' in subject
        assert '${company}' in html

    def test_render_template_partial_variables(self, session, email_template):
        """测试部分变量渲染"""
        variables = {'name': '李四'}
        
        subject, html, text = EmailService.render_template(
            email_template.id,
            variables
        )
        
        assert '李四' in subject
        assert '${company}' in html  # 未提供的变量保持原样


class TestQuotaManagement:
    """配额管理测试"""

    def test_check_quota_sufficient(self, session, normal_user):
        """测试配额充足"""
        normal_user.daily_quota = 100
        normal_user.used_quota_today = 50
        session.commit()
        
        assert normal_user.check_quota(10) is True
        assert normal_user.check_quota(50) is True

    def test_check_quota_insufficient(self, session, normal_user):
        """测试配额不足"""
        normal_user.daily_quota = 100
        normal_user.used_quota_today = 95
        session.commit()
        
        assert normal_user.check_quota(10) is False
        assert normal_user.check_quota(5) is True

    def test_use_quota(self, session, normal_user):
        """测试使用配额"""
        normal_user.daily_quota = 100
        normal_user.used_quota_today = 10
        session.commit()
        
        normal_user.use_quota(5)
        assert normal_user.used_quota_today == 15

    def test_quota_reset_daily(self, session, normal_user):
        """测试每日配额重置"""
        # 设置为昨天的日期
        normal_user.quota_reset_date = date(2020, 1, 1)
        normal_user.used_quota_today = 100
        session.commit()
        
        # 检查配额时会自动重置
        normal_user.check_quota(1)
        assert normal_user.used_quota_today == 0
        assert normal_user.quota_reset_date == date.today()


class TestSendSingleEmail:
    """单封邮件发送测试"""

    def test_send_email_invalid_email(self, session, normal_user):
        """测试发送到无效邮箱"""
        success, record_id, message = EmailService.send_single_email(
            sender_id=normal_user.id,
            from_email='sender@test.com',
            from_name='Sender',
            to_email='invalid-email',
            to_name='Receiver',
            subject='Test',
            html_content='<p>Test</p>'
        )
        
        assert success is False
        assert record_id is None
        assert '邮箱格式不正确' in message

    def test_send_email_user_not_found(self, session):
        """测试用户不存在"""
        success, record_id, message = EmailService.send_single_email(
            sender_id=999,
            from_email='sender@test.com',
            from_name='Sender',
            to_email='receiver@test.com',
            to_name='Receiver',
            subject='Test',
            html_content='<p>Test</p>'
        )
        
        assert success is False
        assert record_id is None
        assert '用户不存在' in message

    def test_send_email_quota_exceeded(self, session, normal_user):
        """测试配额不足"""
        normal_user.daily_quota = 10
        normal_user.used_quota_today = 10
        session.commit()
        
        success, record_id, message = EmailService.send_single_email(
            sender_id=normal_user.id,
            from_email='sender@test.com',
            from_name='Sender',
            to_email='receiver@test.com',
            to_name='Receiver',
            subject='Test',
            html_content='<p>Test</p>'
        )
        
        assert success is False
        assert record_id is None
        assert '配额已用完' in message

    def test_send_email_no_relay_available(self, session, normal_user):
        """测试无可用的SMTP中继"""
        # 先清空所有relay
        SmtpRelay.query.delete()
        session.commit()
        
        success, record_id, message = EmailService.send_single_email(
            sender_id=normal_user.id,
            from_email='sender@test.com',
            from_name='Sender',
            to_email='receiver@test.com',
            to_name='Receiver',
            subject='Test',
            html_content='<p>Test</p>'
        )
        
        assert success is False
        assert '没有可用的SMTP中继' in message


class TestRetryFailedEmail:
    """重试失败邮件测试"""

    def test_retry_nonexistent_record(self, session):
        """测试重试不存在的记录"""
        success, message = EmailService.retry_failed_email(999)
        
        assert success is False
        assert '记录不存在' in message

    def test_retry_non_failed_email(self, session, normal_user):
        """测试重试非失败状态的邮件"""
        record = EmailRecord(
            sender_id=normal_user.id,
            from_email='sender@test.com',
            from_name='Sender',
            to_email='receiver@test.com',
            to_name='Receiver',
            subject='Test',
            body_html='<p>Test</p>',
            status='sent'
        )
        session.add(record)
        session.commit()
        
        success, message = EmailService.retry_failed_email(record.id)
        
        assert success is False
        assert '只能重试失败的邮件' in message

    def test_retry_max_attempts_exceeded(self, session, normal_user):
        """测试超过最大重试次数"""
        record = EmailRecord(
            sender_id=normal_user.id,
            from_email='sender@test.com',
            from_name='Sender',
            to_email='receiver@test.com',
            to_name='Receiver',
            subject='Test',
            body_html='<p>Test</p>',
            status='failed',
            retry_count=3
        )
        session.add(record)
        session.commit()
        
        success, message = EmailService.retry_failed_email(record.id)
        
        assert success is False
        assert '已超过最大重试次数' in message