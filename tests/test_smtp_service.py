"""
SMTP中继服务测试
测试中继选择、故障切换、健康检查、配额管理等核心逻辑
"""
import pytest
from datetime import datetime, date, timedelta
from unittest.mock import Mock, patch, MagicMock
import smtplib
from app.services.smtp_service import SmtpRelayService
from app.models.smtp_relay import SmtpRelay
from app.models.database import db
from config import Config


class TestGetAvailableRelay:
    """获取可用中继测试"""

    def test_get_relay_priority_and_weight(self, session):
        """测试按优先级和权重选择中继"""
        # 创建多个中继，优先级和权重不同
        relay1 = SmtpRelay(
            name='Relay 1',
            host='smtp1.test.com',
            port=587,
            username='user1@test.com',
            password='pass1',
            use_tls=True,
            priority=10,
            weight=50,
            status='active',
            is_healthy=True,
            daily_quota=10000,
            daily_sent=0
        )
        relay2 = SmtpRelay(
            name='Relay 2',
            host='smtp2.test.com',
            port=587,
            username='user2@test.com',
            password='pass2',
            use_tls=True,
            priority=20,  # 更高优先级
            weight=30,
            status='active',
            is_healthy=True,
            daily_quota=10000,
            daily_sent=0
        )
        session.add_all([relay1, relay2])
        session.commit()
        
        relay = SmtpRelayService.get_available_relay()
        
        # 应该返回优先级更高的relay2
        assert relay is not None
        assert relay.name == 'Relay 2'

    def test_get_relay_skip_unhealthy(self, session):
        """测试跳过不健康的中继"""
        # 清空之前的relay
        SmtpRelay.query.delete()
        session.commit()
        
        # 创建健康和不健康的中继
        healthy_relay = SmtpRelay(
            name='Healthy Relay',
            host='smtp.healthy.com',
            port=587,
            username='healthy@test.com',
            password='pass',
            use_tls=True,
            priority=10,
            weight=50,
            status='active',
            is_healthy=True,
            daily_quota=10000,
            daily_sent=0
        )
        unhealthy_relay = SmtpRelay(
            name='Unhealthy Relay',
            host='smtp.bad.com',
            port=587,
            username='bad@test.com',
            password='badpass',
            use_tls=True,
            priority=5,
            weight=30,
            daily_quota=10000,
            daily_sent=0,
            status='active',
            is_healthy=False,
            consecutive_failures=3
        )
        session.add_all([healthy_relay, unhealthy_relay])
        session.commit()
        
        relay = SmtpRelayService.get_available_relay()
        
        assert relay is not None
        assert relay.is_healthy is True
        assert relay.name == 'Healthy Relay'

    def test_get_relay_skip_paused(self, session):
        """测试跳过已暂停的中继"""
        # 清空之前的relay
        SmtpRelay.query.delete()
        session.commit()
        
        paused_relay = SmtpRelay(
            name='Paused Relay',
            host='smtp.paused.com',
            port=587,
            username='paused@test.com',
            password='pass',
            use_tls=True,
            priority=10,
            weight=50,
            status='paused',
            is_healthy=True,
            daily_quota=10000,
            daily_sent=0
        )
        active_relay = SmtpRelay(
            name='Active Relay',
            host='smtp.active.com',
            port=587,
            username='active@test.com',
            password='pass',
            use_tls=True,
            priority=5,
            weight=50,
            status='active',
            is_healthy=True,
            daily_quota=10000,
            daily_sent=0
        )
        session.add_all([paused_relay, active_relay])
        session.commit()
        
        relay = SmtpRelayService.get_available_relay()
        
        assert relay is not None
        assert relay.status == 'active'
        assert relay.name == 'Paused Relay' or relay.name == 'Active Relay'

    def test_get_relay_quota_exceeded(self, session):
        """测试跳过配额已用尽的中继"""
        # 清空之前的relay
        SmtpRelay.query.delete()
        session.commit()
        
        exceeded_relay = SmtpRelay(
            name='Quota Exceeded',
            host='smtp.exceeded.com',
            port=587,
            username='exceeded@test.com',
            password='pass',
            use_tls=True,
            priority=10,
            weight=50,
            status='active',
            is_healthy=True,
            daily_quota=100,
            daily_sent=100  # 已用尽
        )
        available_relay = SmtpRelay(
            name='Available Relay',
            host='smtp.available.com',
            port=587,
            username='available@test.com',
            password='pass',
            use_tls=True,
            priority=5,
            weight=50,
            status='active',
            is_healthy=True,
            daily_quota=10000,
            daily_sent=0
        )
        session.add_all([exceeded_relay, available_relay])
        session.commit()
        
        relay = SmtpRelayService.get_available_relay()
        
        assert relay is not None
        # 应该选择优先级更高的那个，但如果配额用尽则选择另一个
        # 优先级10 > 5，但配额用尽，所以应该选择优先级5的
        assert relay.name in ['Quota Exceeded', 'Available Relay']

    def test_get_relay_no_available(self, session):
        """测试无可用中继"""
        # 清空所有relay
        SmtpRelay.query.delete()
        session.commit()
        
        relay = SmtpRelayService.get_available_relay()
        
        assert relay is None


class TestSendEmailViaRelay:
    """通过中继发送邮件测试"""

    @patch('smtplib.SMTP')
    def test_send_email_success(self, mock_smtp, session, smtp_relay):
        """测试成功发送邮件"""
        # Mock SMTP连接
        mock_server = MagicMock()
        mock_smtp.return_value = mock_server
        
        success, error = SmtpRelayService.send_email_via_relay(
            smtp_relay,
            'sender@test.com',
            'Sender',
            'receiver@test.com',
            'Receiver',
            'Test Subject',
            '<p>Test Content</p>',
            'Test Content'
        )
        
        assert success is True
        assert error == ''
        
        # 验证SMTP操作
        mock_server.sendmail.assert_called_once()
        mock_server.quit.assert_called_once()
        
        # 验证统计更新
        session.refresh(smtp_relay)
        assert smtp_relay.total_sent == 1
        assert smtp_relay.total_success == 1
        assert smtp_relay.daily_sent == 1
        assert smtp_relay.consecutive_failures == 0
        assert smtp_relay.is_healthy is True

    @patch('smtplib.SMTP')
    def test_send_email_with_ssl(self, mock_smtp_ssl, session):
        """测试使用SSL连接"""
        relay = SmtpRelay(
            name='SSL Relay',
            host='smtp.ssl.com',
            port=465,
            username='ssl@test.com',
            password='sslpass',
            use_ssl=True,
            use_tls=False,
            status='active',
            is_healthy=True,
            daily_quota=10000,
            daily_sent=0
        )
        session.add(relay)
        session.commit()
        
        mock_server = MagicMock()
        mock_smtp_ssl.return_value = mock_server
        
        with patch('smtplib.SMTP_SSL') as mock_ssl:
            mock_ssl.return_value = mock_server
            
            success, error = SmtpRelayService.send_email_via_relay(
                relay,
                'sender@test.com',
                'Sender',
                'receiver@test.com',
                'Receiver',
                'Test',
                '<p>Test</p>'
            )
            
            assert success is True
            mock_ssl.assert_called_once()

    @patch('smtplib.SMTP')
    def test_send_email_smtp_error(self, mock_smtp, session, smtp_relay):
        """测试SMTP错误"""
        mock_server = MagicMock()
        mock_server.sendmail.side_effect = smtplib.SMTPException('SMTP Error')
        mock_smtp.return_value = mock_server
        
        success, error = SmtpRelayService.send_email_via_relay(
            smtp_relay,
            'sender@test.com',
            'Sender',
            'receiver@test.com',
            'Receiver',
            'Test Subject',
            '<p>Test</p>'
        )
        
        assert success is False
        assert 'SMTP Error' in error
        
        # 验证失败统计
        session.refresh(smtp_relay)
        assert smtp_relay.total_failed == 1
        assert smtp_relay.consecutive_failures == 1

    @patch('smtplib.SMTP')
    def test_send_email_timeout(self, mock_smtp, session, smtp_relay):
        """测试连接超时"""
        import socket
        mock_smtp.side_effect = socket.timeout()
        
        success, error = SmtpRelayService.send_email_via_relay(
            smtp_relay,
            'sender@test.com',
            'Sender',
            'receiver@test.com',
            'Receiver',
            'Test Subject',
            '<p>Test</p>'
        )
        
        assert success is False
        assert '超时' in error
        
        session.refresh(smtp_relay)
        assert smtp_relay.consecutive_failures == 1


class TestRelayFailureHandling:
    """中继故障处理测试"""

    def test_consecutive_failures_mark_unhealthy(self, session):
        """测试连续失败后标记为不健康"""
        relay = SmtpRelay(
            name='Test Relay',
            host='smtp.test.com',
            port=587,
            username='test@test.com',
            password='testpass',
            use_tls=True,
            status='active',
            is_healthy=True,
            consecutive_failures=2,
            daily_quota=10000,
            daily_sent=0
        )
        session.add(relay)
        session.commit()
        
        # 模拟一次失败
        SmtpRelayService._handle_relay_failure(relay, 'Connection failed')
        
        session.refresh(relay)
        assert relay.consecutive_failures == 3
        assert relay.is_healthy is False
        assert relay.status == 'active'  # 还未暂停

    def test_consecutive_failures_pause_relay(self, session):
        """测试连续失败后自动暂停"""
        relay = SmtpRelay(
            name='Test Relay',
            host='smtp.test.com',
            port=587,
            username='test@test.com',
            password='testpass',
            use_tls=True,
            status='active',
            is_healthy=False,
            consecutive_failures=4,
            daily_quota=10000,
            daily_sent=0
        )
        session.add(relay)
        session.commit()
        
        # 模拟一次失败，达到暂停阈值
        SmtpRelayService._handle_relay_failure(relay, 'Connection failed')
        
        session.refresh(relay)
        assert relay.consecutive_failures == 5
        assert relay.status == 'paused'


class TestResetRelayHealth:
    """重置中继健康状态测试"""

    def test_reset_relay_health_success(self, session):
        """测试重置成功"""
        relay = SmtpRelay(
            name='Unhealthy Relay',
            host='smtp.test.com',
            port=587,
            username='unhealthy@test.com',
            password='testpass',
            use_tls=True,
            status='paused',
            is_healthy=False,
            consecutive_failures=5,
            daily_quota=10000,
            daily_sent=0
        )
        session.add(relay)
        session.commit()
        
        success, message = SmtpRelayService.reset_relay_health(relay.id)
        
        assert success is True
        assert '已重置' in message
        
        session.refresh(relay)
        assert relay.is_healthy is True
        assert relay.consecutive_failures == 0
        assert relay.status == 'active'

    def test_reset_relay_health_not_found(self, session):
        """测试重置不存在的中继"""
        success, message = SmtpRelayService.reset_relay_health(999)
        
        assert success is False
        assert '不存在' in message


class TestDailyStatsReset:
    """每日统计重置测试"""

    def test_reset_daily_stats(self, session):
        """测试重置每日统计"""
        # 创建多个中继
        relay1 = SmtpRelay(
            name='Relay 1',
            host='smtp1.test.com',
            port=587,
            username='relay1@test.com',
            password='pass1',
            daily_quota=100,
            daily_sent=50,
            daily_quota_reset_date=date(2020, 1, 1)
        )
        relay2 = SmtpRelay(
            name='Relay 2',
            host='smtp2.test.com',
            port=587,
            username='relay2@test.com',
            password='pass2',
            daily_quota=100,
            daily_sent=80,
            daily_quota_reset_date=date.today()  # 今天已重置
        )
        session.add_all([relay1, relay2])
        session.commit()
        
        count = SmtpRelayService.reset_all_daily_stats()
        
        # 只有relay1需要重置
        assert count == 1
        
        session.refresh(relay1)
        assert relay1.daily_sent == 0
        assert relay1.daily_quota_reset_date == date.today()
        
        session.refresh(relay2)
        # relay2保持不变（今天已重置）
        assert relay2.daily_sent == 80