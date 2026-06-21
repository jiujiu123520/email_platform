"""
邮件发送平台 - WSGI入口
用于Gunicorn等WSGI服务器启动
"""
import os

# 设置环境变量
os.environ.setdefault('FLASK_ENV', 'production')

# 导入应用工厂
from app import create_app, init_db

# 创建应用实例
app = create_app('production')

# 初始化数据库
with app.app_context():
    init_db(app)
