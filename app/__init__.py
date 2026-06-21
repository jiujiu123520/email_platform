"""
邮件发送平台 - 应用包初始化
导出 create_app 和 init_db 供 WSGI 使用
"""
from app import create_app, init_db

__all__ = ['create_app', 'init_db']
