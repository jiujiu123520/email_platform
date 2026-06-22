import pytest
from datetime import datetime, timedelta
from app.app import create_app
from app.models.database import db
from app.models.user import User
from app.models.email_template import EmailTemplate
from app.models.smtp_relay import SmtpRelay
from app.models.email_record import EmailRecord


@pytest.fixture(scope='module')
def app():
    app = create_app('testing')
    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()


@pytest.fixture(scope='function')
def client(app):
    return app.test_client()


@pytest.fixture(scope='function')
def session(app):
    with app.app_context():
        db.session.begin_nested()
        yield db.session
        db.session.rollback()


@pytest.fixture(scope='function')
def db_cleanup(app):
    with app.app_context():
        yield
        db.session.rollback()
        for table in reversed(db.metadata.sorted_tables):
            db.session.execute(table.delete())
        db.session.commit()


@pytest.fixture(scope='function')
def test_user(session, db_cleanup):
    user = User(
        username='testuser',
        email='test@example.com',
        display_name='Test User',
        role='user',
        daily_quota=100,
    )
    user.set_password('password123')
    session.add(user)
    session.commit()
    return user


@pytest.fixture(scope='function')
def test_admin(session, db_cleanup):
    admin = User(
        username='testadmin',
        email='admin@example.com',
        display_name='Test Admin',
        role='admin',
        daily_quota=1000,
    )
    admin.set_password('admin123')
    session.add(admin)
    session.commit()
    return admin


@pytest.fixture(scope='function')
def test_super_admin(session, db_cleanup):
    super_admin = User(
        username='testsuperadmin',
        email='superadmin@example.com',
        display_name='Test Super Admin',
        role='super_admin',
        daily_quota=999999,
    )
    super_admin.set_password('superadmin123')
    session.add(super_admin)
    session.commit()
    return super_admin


@pytest.fixture(scope='function')
def test_template(session, test_user, db_cleanup):
    template = EmailTemplate(
        name='Test Template',
        subject='Hello ${name}',
        html_content='<p>Hello ${name}, welcome to ${company}</p>',
        text_content='Hello ${name}, welcome to ${company}',
        created_by=test_user.id,
    )
    session.add(template)
    session.commit()
    return template


@pytest.fixture(scope='function')
def test_relay(session, db_cleanup):
    relay = SmtpRelay(
        name='Test Relay',
        host='smtp.test.com',
        port=587,
        username='testuser',
        password='testpass',
        use_tls=True,
        use_ssl=False,
        weight=10,
        daily_quota=1000,
    )
    session.add(relay)
    session.commit()
    return relay


@pytest.fixture(scope='function')
def test_email_record(session, test_user, db_cleanup):
    record = EmailRecord(
        to_email='recipient@example.com',
        to_name='Recipient',
        subject='Test Subject',
        body_html='<p>Test Content</p>',
        body_text='Test Content',
        from_email='sender@example.com',
        from_name='Sender',
        sender_id=test_user.id,
        status='failed',
        retry_count=0,
    )
    session.add(record)
    session.commit()
    return record