"""
WSGI入口文件 - 用于Gunicorn部署
"""
from app import create_app

app = create_app('production')
