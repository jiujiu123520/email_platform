import pytest
from datetime import datetime, timedelta
from app.middleware.auth import login_user, logout_user
from app.models.user import User


class TestAuth:

    def test_login_success(self, test_user, app):
        with app.app_context():
            success, data, status_code = login_user('testuser', 'password123')
            assert success
            assert status_code == 200
            assert 'access_token' in data
            assert 'refresh_token' in data
            assert 'user' in data

    def test_login_invalid_username(self, app):
        with app.app_context():
            success, data, status_code = login_user('nonexistent', 'password123')
            assert not success
            assert status_code == 401
            assert '用户名或密码错误' in data['message']

    def test_login_invalid_password(self, test_user, app):
        with app.app_context():
            success, data, status_code = login_user('testuser', 'wrongpassword')
            assert not success
            assert status_code == 401

    def test_login_disabled_account(self, test_user, session, app):
        test_user.status = 'disabled'
        session.commit()

        with app.app_context():
            success, data, status_code = login_user('testuser', 'password123')
            assert not success
            assert status_code == 403
            assert '账户已被禁用' in data['message']

    def test_login_locked_account(self, test_user, session, app):
        test_user.status = 'locked'
        test_user.login_lock_until = datetime.now() + timedelta(minutes=30)
        session.commit()

        with app.app_context():
            success, data, status_code = login_user('testuser', 'password123')
            assert not success
            assert status_code == 403
            assert '账户已锁定' in data['message']

    def test_login_lock_expired(self, test_user, session, app):
        test_user.status = 'locked'
        test_user.login_lock_until = datetime.now() - timedelta(minutes=1)
        test_user.login_fail_count = 5
        session.commit()

        with app.app_context():
            success, data, status_code = login_user('testuser', 'password123')
            assert success
            assert status_code == 200

    def test_login_failure_count(self, test_user, app):
        with app.app_context():
            for i in range(4):
                success, data, status_code = login_user('testuser', 'wrongpassword')
                assert not success
                assert status_code == 401

            user = User.query.filter_by(username='testuser').first()
            assert user.login_fail_count == 4

            success, data, status_code = login_user('testuser', 'wrongpassword')
            assert not success
            assert status_code == 403
            assert '账户已锁定' in data['message']

            user = User.query.filter_by(username='testuser').first()
            assert user.status == 'locked'

    def test_logout(self, test_user, app):
        with app.app_context():
            logout_user(test_user.id)