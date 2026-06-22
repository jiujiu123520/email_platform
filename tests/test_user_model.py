import pytest
from datetime import datetime, timedelta, date
from app.models.user import User


class TestUserModel:

    def test_password_hashing(self, test_user):
        assert test_user.check_password('password123')
        assert not test_user.check_password('wrongpassword')
        assert not test_user.check_password('PASSWORD123')

    def test_password_not_stored_in_plaintext(self, test_user):
        assert test_user.password_hash != 'password123'
        assert '$2b$' in test_user.password_hash

    def test_role_checks(self, test_user, test_admin, test_super_admin):
        assert not test_user.is_admin()
        assert not test_user.is_super_admin()

        assert test_admin.is_admin()
        assert not test_admin.is_super_admin()

        assert test_super_admin.is_admin()
        assert test_super_admin.is_super_admin()

    def test_quota_management(self, test_user, session):
        user = test_user
        assert user.check_quota(1)
        assert user.check_quota(100)
        assert not user.check_quota(101)

        user.use_quota(50)
        session.commit()

        assert user.used_quota_today == 50
        assert user.check_quota(50)
        assert not user.check_quota(51)

    def test_quota_daily_reset(self, test_user, session):
        user = test_user
        user.used_quota_today = 50
        user.quota_reset_date = date.today() - timedelta(days=1)
        session.commit()

        assert user.check_quota(100)
        assert user.used_quota_today == 0

    def test_to_dict(self, test_user):
        data = test_user.to_dict()
        assert 'id' in data
        assert 'username' in data
        assert 'email' in data
        assert 'role' in data
        assert 'status' in data
        assert 'api_key' not in data

        data_with_sensitive = test_user.to_dict(include_sensitive=True)
        assert 'api_key' in data_with_sensitive

    def test_get_avatar_url(self, test_user, session):
        assert test_user.get_avatar_url() == ''

        test_user.avatar = '/avatar.png'
        session.commit()
        assert test_user.get_avatar_url() == '/avatar.png'

        test_user.qq_avatar = 'https://qq.com/avatar.jpg'
        session.commit()
        assert test_user.get_avatar_url() == 'https://qq.com/avatar.jpg'