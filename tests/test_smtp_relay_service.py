import pytest
from datetime import datetime, date, timedelta
from app.services.smtp_service import SmtpRelayService
from app.models.smtp_relay import SmtpRelay


class TestSmtpRelayService:

    def test_get_available_relay(self, test_relay, app):
        with app.app_context():
            relay = SmtpRelayService.get_available_relay()
            assert relay is not None
            assert relay.id == test_relay.id

    def test_get_available_relay_no_active(self, test_relay, session, app):
        test_relay.status = 'paused'
        session.commit()

        with app.app_context():
            relay = SmtpRelayService.get_available_relay()
            assert relay is None

    def test_get_available_relay_not_healthy(self, test_relay, session, app):
        test_relay.is_healthy = False
        session.commit()

        with app.app_context():
            relay = SmtpRelayService.get_available_relay()
            assert relay is None

    def test_get_available_relay_quota_exceeded(self, test_relay, session, app):
        test_relay.daily_sent = 1000
        test_relay.daily_quota = 1000
        session.commit()

        with app.app_context():
            relay = SmtpRelayService.get_available_relay()
            assert relay is None

    def test_reset_daily_stats(self, test_relay, session):
        test_relay.daily_sent = 500
        test_relay.daily_quota_reset_date = date.today() - timedelta(days=1)
        session.commit()

        test_relay.reset_daily_stats()
        session.commit()

        assert test_relay.daily_sent == 0
        assert test_relay.daily_quota_reset_date == date.today()

    def test_check_daily_quota(self, test_relay, session):
        test_relay.daily_sent = 500
        test_relay.daily_quota = 1000
        session.commit()

        assert test_relay.check_daily_quota()

        test_relay.daily_sent = 1000
        session.commit()

        assert not test_relay.check_daily_quota()

    def test_get_success_rate(self, test_relay, session):
        test_relay.total_sent = 100
        test_relay.total_success = 80
        session.commit()

        assert test_relay.get_success_rate() == 80.0

        test_relay.total_sent = 0
        session.commit()

        assert test_relay.get_success_rate() == 0.0

    def test_get_port_presets(self):
        presets = SmtpRelay.get_port_presets()
        assert 587 in presets
        assert 465 in presets
        assert presets[587]['name'] == 'SMTP-TLS (587)'
        assert presets[465]['ssl'] is True

    def test_get_port_suggestion(self):
        suggestion = SmtpRelay.get_port_suggestion(465)
        assert suggestion['use_ssl'] is True
        assert suggestion['use_tls'] is False

        suggestion = SmtpRelay.get_port_suggestion(587)
        assert suggestion['use_ssl'] is False
        assert suggestion['use_tls'] is True

        suggestion = SmtpRelay.get_port_suggestion(9999)
        assert suggestion['use_ssl'] is False
        assert suggestion['use_tls'] is False

    def test_reset_relay_health(self, test_relay, session, app):
        test_relay.is_healthy = False
        test_relay.consecutive_failures = 5
        test_relay.status = 'paused'
        session.commit()

        with app.app_context():
            success, message = SmtpRelayService.reset_relay_health(test_relay.id)
            assert success
            assert message == '健康状态已重置'

            relay = SmtpRelay.query.get(test_relay.id)
            assert relay.is_healthy is True
            assert relay.consecutive_failures == 0
            assert relay.status == 'active'

    def test_reset_relay_health_not_found(self, app):
        with app.app_context():
            success, message = SmtpRelayService.reset_relay_health(999)
            assert not success
            assert message == '中继不存在'

    def test_reset_all_daily_stats(self, test_relay, session, app):
        test_relay.daily_sent = 500
        test_relay.daily_quota_reset_date = date.today() - timedelta(days=1)
        session.commit()

        with app.app_context():
            count = SmtpRelayService.reset_all_daily_stats()
            assert count == 1

            relay = SmtpRelay.query.get(test_relay.id)
            assert relay.daily_sent == 0