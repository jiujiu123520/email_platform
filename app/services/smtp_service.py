"""
SMTP智能中继服务 - 模块六
负载均衡、自动切换、健康自检、流量控制
"""
import smtplib
import socket
from datetime import datetime, date
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.utils import formataddr
from app.models.smtp_relay import SmtpRelay
from app.models.database import db
from config import Config


class SmtpRelayService:
    """SMTP中继服务"""

    @staticmethod
    def get_available_relay():
        """
        获取可用的SMTP中继（加权轮询）
        自动跳过不健康和配额用尽的中继
        """
        relays = SmtpRelay.query.filter_by(
            status='active', is_healthy=True
        ).order_by(SmtpRelay.priority.desc(), SmtpRelay.weight.desc()).all()

        for relay in relays:
            relay.reset_daily_stats()
            if relay.check_daily_quota():
                return relay

        return None

    @staticmethod
    def send_email_via_relay(relay, from_email, from_name, to_email, to_name,
                             subject, html_content, text_content=''):
        """
        通过指定中继发送邮件
        返回: (success, error_message)
        """
        try:
            # 创建邮件
            msg = MIMEMultipart('alternative')
            msg['From'] = formataddr((from_name, from_email))
            msg['To'] = formataddr((to_name, to_email))
            msg['Subject'] = subject

            if text_content:
                msg.attach(MIMEText(text_content, 'plain', 'utf-8'))
            if html_content:
                msg.attach(MIMEText(html_content, 'html', 'utf-8'))

            # 连接SMTP服务器
            if relay.use_ssl:
                server = smtplib.SMTP_SSL(relay.host, relay.port, timeout=30)
            else:
                server = smtplib.SMTP(relay.host, relay.port, timeout=30)

            if relay.use_tls and not relay.use_ssl:
                server.starttls()

            if relay.username and relay.password:
                server.login(relay.username, relay.password)

            # 发送
            server.sendmail(from_email, [to_email], msg.as_string())
            server.quit()

            # 更新统计
            relay.total_sent += 1
            relay.total_success += 1
            relay.daily_sent += 1
            relay.consecutive_failures = 0
            relay.is_healthy = True
            relay.last_success_at = datetime.utcnow()
            relay.last_check_at = datetime.utcnow()
            db.session.commit()

            return True, ''

        except smtplib.SMTPException as e:
            SmtpRelayService._handle_relay_failure(relay, str(e))
            return False, str(e)
        except socket.timeout:
            SmtpRelayService._handle_relay_failure(relay, '连接超时')
            return False, '连接SMTP服务器超时'
        except Exception as e:
            SmtpRelayService._handle_relay_failure(relay, str(e))
            return False, str(e)

    @staticmethod
    def _handle_relay_failure(relay, error_message):
        """处理中继发送失败"""
        relay.total_sent += 1
        relay.total_failed += 1
        relay.consecutive_failures += 1
        relay.last_failure_at = datetime.utcnow()
        relay.last_check_at = datetime.utcnow()

        # 连续失败3次 → 标记不健康（下次自动切换到其他中继）
        if relay.consecutive_failures >= Config.SMTP_RELAY_MAX_FAIL_COUNT:
            relay.is_healthy = False

        # 连续失败5次 → 自动暂停
        if relay.consecutive_failures >= Config.SMTP_RELAY_PAUSE_COUNT:
            relay.status = 'paused'

        db.session.commit()

    @staticmethod
    def test_relay_connection(relay_id):
        """
        测试中继连接
        返回: (success, message)
        """
        relay = SmtpRelay.query.get(relay_id)
        if not relay:
            return False, '中继不存在'

        try:
            if relay.use_ssl:
                server = smtplib.SMTP_SSL(relay.host, relay.port, timeout=10)
            else:
                server = smtplib.SMTP(relay.host, relay.port, timeout=10)

            if relay.use_tls and not relay.use_ssl:
                server.starttls()

            if relay.username and relay.password:
                server.login(relay.username, relay.password)

            server.quit()

            # 更新健康状态
            relay.is_healthy = True
            relay.consecutive_failures = 0
            relay.last_check_at = datetime.utcnow()
            relay.last_success_at = datetime.utcnow()
            if relay.status == 'paused':
                relay.status = 'active'
            db.session.commit()

            return True, '连接测试成功'
        except Exception as e:
            relay.last_check_at = datetime.utcnow()
            relay.last_failure_at = datetime.utcnow()
            db.session.commit()
            return False, f'连接测试失败: {str(e)}'

    @staticmethod
    def reset_relay_health(relay_id):
        """重置中继健康状态"""
        relay = SmtpRelay.query.get(relay_id)
        if not relay:
            return False, '中继不存在'

        relay.is_healthy = True
        relay.consecutive_failures = 0
        relay.status = 'active'
        relay.last_check_at = datetime.utcnow()
        db.session.commit()

        return True, '健康状态已重置'

    @staticmethod
    def reset_all_daily_stats():
        """重置所有中继的每日统计（每日零点调用）"""
        today = date.today()
        relays = SmtpRelay.query.filter(SmtpRelay.daily_quota_reset_date < today).all()
        for relay in relays:
            relay.daily_sent = 0
            relay.daily_quota_reset_date = today
        db.session.commit()
        return len(relays)
