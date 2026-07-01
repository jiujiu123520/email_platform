"""
Pytest配置文件 - 提供测试fixtures和共享配置
"""
import pytest
import bcrypt
from datetime import datetime, timedelta
from app.app import create_app
from app.models.database import db
from app.models.user import User
from app.models.smtp_relay import SmtpRelay
from app.models.email_template import EmailTemplate
from app.models.email_record import EmailRecord
from app.models.user_group import UserGroup
from app.models.api_config import ApiConfig
from config import TestingConfig


@pytest.fixture(scope='session')
def app():
    """创建测试应用"""
    test_app = create_app('testing')
    with test_app.app_context():
        db.create_all()
        yield test_app
        db.drop_all()


@pytest.fixture(scope='function')
def client(app):
    """创建测试客户端"""
    return app.test_client()


@pytest.fixture(scope='function')
def session(app):
    """创建数据库会话"""
    connection = db.engine.connect()
    transaction = connection.begin()
    session = db.session

    yield session

    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture
def super_admin_user(session):
    """创建超级管理员用户"""
    user = User(
        username='superadmin',
        email='superadmin@test.com',
        role='super_admin',
        status='active',
        daily_quota=1000
    )
    user.set_password('password123')
    session.add(user)
    session.commit()
    return user


@pytest.fixture
def admin_user(session):
    """创建管理员用户"""
    user = User(
        username='admin',
        email='admin@test.com',
        role='admin',
        status='active',
        daily_quota=1000
    )
    user.set_password('password123')
    session.add(user)
    session.commit()
    return user


@pytest.fixture
def normal_user(session):
    """创建普通用户"""
    # 使用唯一用户名避免冲突
    import uuid
    unique_id = str(uuid.uuid4())[:8]
    user = User(
        username=f'testuser_{unique_id}',
        email=f'testuser_{unique_id}@test.com',
        role='user',
        status='active',
        daily_quota=100
    )
    user.set_password('password123')
    session.add(user)
    session.commit()
    return user


@pytest.fixture
def locked_user(session):
    """创建被锁定的用户"""
    import uuid
    unique_id = str(uuid.uuid4())[:8]
    user = User(
        username=f'lockeduser_{unique_id}',
        email=f'locked_{unique_id}@test.com',
        role='user',
        status='locked',
        login_lock_until=datetime.utcnow() + timedelta(minutes=30),
        login_fail_count=5,
        daily_quota=100
    )
    user.set_password('password123')
    session.add(user)
    session.commit()
    return user


@pytest.fixture
def disabled_user(session):
    """创建被禁用的用户"""
    import uuid
    unique_id = str(uuid.uuid4())[:8]
    user = User(
        username=f'disableduser_{unique_id}',
        email=f'disabled_{unique_id}@test.com',
        role='user',
        status='disabled',
        daily_quota=100
    )
    user.set_password('password123')
    session.add(user)
    session.commit()
    return user


@pytest.fixture
def smtp_relay(session):
    """创建SMTP中继配置"""
    relay = SmtpRelay(
        name='Test SMTP Relay',
        host='smtp.test.com',
        port=587,
        username='test@test.com',
        password='testpass',
        use_tls=True,
        use_ssl=False,
        priority=10,
        weight=50,
        daily_quota=10000,
        daily_sent=0,
        status='active',
        is_healthy=True
    )
    session.add(relay)
    session.commit()
    return relay


@pytest.fixture
def unhealthy_relay(session):
    """创建不健康的SMTP中继"""
    relay = SmtpRelay(
        name='Unhealthy SMTP Relay',
        host='smtp.bad.com',
        port=587,
        username='bad@test.com',
        password='badpass',
        use_tls=True,
        use_ssl=False,
        priority=5,
        weight=30,
        daily_quota=10000,
        daily_sent=0,
        status='active',
        is_healthy=False,
        consecutive_failures=3
    )
    session.add(relay)
    session.commit()
    return relay


@pytest.fixture
def email_template(session):
    """创建邮件模板"""
    template = EmailTemplate(
        name='Test Template',
        subject='Hello ${name}',
        html_content='<h1>Hello ${name}</h1><p>Welcome to ${company}!</p>',
        text_content='Hello ${name}, Welcome to ${company}!',
        created_by=1
    )
    session.add(template)
    session.commit()
    return template


@pytest.fixture
def api_config(session):
    """创建API配置"""
    config = ApiConfig(
        enabled=True,
        ip_whitelist_enabled=False,
        ip_whitelist='',
        rate_limit=1000
    )
    session.add(config)
    session.commit()
    return config


@pytest.fixture
def auth_header(super_admin_user):
    """生成JWT认证头"""
    from flask_jwt_extended import create_access_token
    token = create_access_token(identity=super_admin_user.id)
    return {'Authorization': f'Bearer {token}'}


@pytest.fixture
def api_auth_headers(normal_user):
    """生成API签名认证头"""
    import time
    import hashlib
    from app.utils.helpers import generate_api_key, generate_api_secret

    if not normal_user.api_key:
        normal_user.api_key = generate_api_key()
        normal_user.api_secret = generate_api_secret()
        db.session.commit()

    timestamp = str(int(time.time() * 1000))
    nonce = 'testnonce123456'
    sign_str = f"{normal_user.api_key}{timestamp}{nonce}{normal_user.api_secret}"
    sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()

    return {
        'ApiKey': normal_user.api_key,
        'Timestamp': timestamp,
        'Nonce': nonce,
        'Sign': sign
    }