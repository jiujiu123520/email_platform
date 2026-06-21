"""
邮件发送平台 - 配置文件
支持高并发无限发送模式
"""
import os
from datetime import timedelta

BASE_DIR = os.path.abspath(os.path.dirname(__file__))


class BaseConfig:
    """基础配置"""
    SECRET_KEY = os.environ.get('SECRET_KEY', 'your-secret-key-change-in-production')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY', 'jwt-secret-key-change-in-production')
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=2)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=7)
    JSON_AS_ASCII = False

    # 邮件发送配置
    MAIL_DEFAULT_SENDER = os.environ.get('MAIL_DEFAULT_SENDER', 'noreply@example.com')

    # API签名配置
    API_SIGN_EXPIRE_SECONDS = 300  # 5分钟过期
    API_RATE_LIMIT = '1000 per hour'  # API限流（高并发模式）

    # SMTP中继配置
    SMTP_RELAY_MAX_FAIL_COUNT = 3      # 连续失败3次自动切换
    SMTP_RELAY_PAUSE_COUNT = 5         # 连续失败5次自动暂停
    SMTP_RELAY_DAILY_QUOTA = 100000    # 每日配额（高并发模式）
    SMTP_RELAY_CONCURRENT_LIMIT = 200  # 并发限制（高并发模式）

    # 安全配置
    LOGIN_FAIL_LOCK_COUNT = 5          # 登录失败5次锁定
    LOGIN_FAIL_LOCK_MINUTES = 30       # 锁定30分钟
    IP_WHITELIST_ENABLED = False       # IP白名单开关

    # 主题配置
    THEME_LIGHT_START_HOUR = 7         # 亮色主题开始时间
    THEME_LIGHT_END_HOUR = 19          # 亮色主题结束时间

    # 无限发送模式配置
    UNLIMITED_MODE = os.environ.get('UNLIMITED_MODE', 'false').lower() == 'true'
    SEND_DELAY_MIN = 0.5               # 最小发送间隔（秒）
    SEND_DELAY_MAX = 3.0               # 最大发送间隔（秒）
    AUTO_ROTATE_IP = False             # 自动轮换IP
    PROXY_POOL_URL = ''                # 代理池地址


class DevelopmentConfig(BaseConfig):
    """开发环境配置"""
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        'DATABASE_URL',
        'mysql+pymysql://root:password@localhost:3306/email_platform?charset=utf8mb4'
    )
    REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')


class ProductionConfig(BaseConfig):
    """生产环境配置"""
    DEBUG = False
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL')
    REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')


class UnlimitedConfig(ProductionConfig):
    """无限发送模式配置"""
    UNLIMITED_MODE = True
    SMTP_RELAY_DAILY_QUOTA = 999999    # 无限配额
    SMTP_RELAY_CONCURRENT_LIMIT = 500  # 高并发
    API_RATE_LIMIT = '10000 per hour'  # 高限流
    SEND_DELAY_MIN = 0.1               # 最小延迟
    SEND_DELAY_MAX = 1.0               # 最大延迟
    AUTO_ROTATE_IP = True              # 启用IP轮换


class TestingConfig(BaseConfig):
    """测试环境配置"""
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'


# 配置映射
config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'unlimited': UnlimitedConfig,      # 无限发送模式
    'testing': TestingConfig,
    'default': DevelopmentConfig
}
