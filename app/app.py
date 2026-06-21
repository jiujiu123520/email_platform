"""
邮件发送平台 - 主应用入口
包含：Flask应用工厂、蓝图注册、错误处理、初始化数据
"""
import os
import sys
from datetime import datetime
from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

from config import config
from app.models.database import db


def create_app(config_name='default'):
    """Flask应用工厂"""
    app = Flask(
        __name__,
        static_folder=os.path.join(os.path.dirname(__file__), '..', 'static'),
        template_folder=os.path.join(os.path.dirname(__file__), 'templates'),
        static_url_path='/static'
    )

    # 加载配置
    app.config.from_object(config[config_name])

    # 初始化扩展
    db.init_app(app)
    CORS(app, supports_credentials=True)
    JWTManager(app)

    # 限流
    limiter = Limiter(
        app=app,
        key_func=get_remote_address,
        default_limits=["200 per minute"],
        storage_uri=os.environ.get('REDIS_URL', 'memory://')
    )

    # 注册蓝图
    register_blueprints(app)

    # 注册错误处理
    register_error_handlers(app)

    # 静态文件服务
    register_static_routes(app)

    return app


def register_blueprints(app):
    """注册所有蓝图"""
    from app.routes.auth import auth_bp
    from app.routes.users import user_bp
    from app.routes.groups import group_bp
    from app.routes.templates import template_bp
    from app.routes.email import email_bp
    from app.routes.relays import relay_bp
    from app.routes.audit import audit_bp
    from app.routes.api_config import api_config_bp
    from app.routes.profile import profile_bp
    from app.routes.faq import faq_bp

    blueprints = [
        auth_bp,       # 模块一：认证
        user_bp,       # 模块二：用户管理
        group_bp,      # 模块三：用户组管理
        template_bp,   # 模块四：模板管理
        email_bp,      # 模块五：邮件发送
        relay_bp,      # 模块六：SMTP中继
        audit_bp,      # 模块七：审计日志
        api_config_bp, # 模块八：API配置
        profile_bp,    # 模块九：个人中心
        faq_bp,        # 模块十：FAQ
    ]

    for bp in blueprints:
        app.register_blueprint(bp)


def register_error_handlers(app):
    """注册错误处理"""
    @app.errorhandler(400)
    def bad_request(e):
        return jsonify({'code': 400, 'message': '请求参数错误'}), 400

    @app.errorhandler(401)
    def unauthorized(e):
        return jsonify({'code': 401, 'message': '未授权，请先登录'}), 401

    @app.errorhandler(403)
    def forbidden(e):
        return jsonify({'code': 403, 'message': '权限不足'}), 403

    @app.errorhandler(404)
    def not_found(e):
        return jsonify({'code': 404, 'message': '资源不存在'}), 404

    @app.errorhandler(429)
    def rate_limited(e):
        return jsonify({'code': 429, 'message': '请求过于频繁，请稍后再试'}), 429

    @app.errorhandler(500)
    def internal_error(e):
        return jsonify({'code': 500, 'message': '服务器内部错误'}), 500


def register_static_routes(app):
    """注册静态文件路由"""
    @app.route('/')
    def index():
        return send_from_directory(
            os.path.join(os.path.dirname(__file__), 'templates'),
            'index.html'
        )

    @app.route('/<path:path>')
    def static_proxy(path):
        return send_from_directory(
            os.path.join(os.path.dirname(__file__), 'templates'),
            path
        )


def init_db(app):
    """初始化数据库"""
    with app.app_context():
        db.create_all()
        # 创建初始超级管理员
        from app.models.user import User
        admin = User.query.filter_by(username='admin', is_deleted=False).first()
        if not admin:
            admin = User(
                username='admin',
                email='admin@example.com',
                display_name='系统管理员',
                role='super_admin',
                daily_quota=999999,
            )
            admin.set_password('admin123456')
            db.session.add(admin)
            db.session.commit()
            print('[初始化] 超级管理员已创建 - 用户名: admin, 密码: admin123456')

        # 创建默认API配置
        from app.models.api_config import ApiConfig
        if not ApiConfig.query.first():
            api_config = ApiConfig(
                name='默认API配置',
                description='系统默认API配置',
                base_url='/api/v2',
                enabled=True,
            )
            db.session.add(api_config)
            db.session.commit()
            print('[初始化] 默认API配置已创建')
