"""
邮件发送平台 - WSGI入口
用于Gunicorn等WSGI服务器启动
"""
import os
import sys

# 设置环境变量
os.environ.setdefault('FLASK_ENV', 'production')

# 添加项目根目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 直接从 app.app 模块导入（避免循环导入）
from app.app import create_app, init_db

# 创建应用实例
app = create_app('production')

# 初始化数据库
with app.app_context():
    init_db(app)
