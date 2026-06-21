"""
认证与权限控制模块 - 模块一：登录 & 全局UI设置
JWT认证 + RBAC权限控制 + 登录风控
"""
from functools import wraps
from datetime import datetime, timedelta
from flask import jsonify, request, g
from flask_jwt_extended import (
    create_access_token, create_refresh_token,
    jwt_required, get_jwt_identity, verify_jwt_in_request
)
from app.models.user import User
from app.models.audit_log import AuditLog
from app.models.database import db
from config import Config


def login_user(username, password, ip_address='', browser='', os='', device=''):
    """
    用户登录
    返回: (success, data_or_error, status_code)
    """
    user = User.query.filter_by(username=username, is_deleted=False).first()

    if not user:
        return False, {'message': '用户名或密码错误'}, 401

    # 检查账户状态
    if user.status == 'disabled':
        return False, {'message': '账户已被禁用，请联系管理员'}, 403

    if user.status == 'locked':
        if user.login_lock_until and user.login_lock_until > datetime.utcnow():
            remaining = (user.login_lock_until - datetime.utcnow()).seconds
            return False, {'message': f'账户已锁定，请{remaining}秒后再试'}, 403
        else:
            # 锁定已过期，解锁
            user.status = 'active'
            user.login_fail_count = 0
            user.login_lock_until = None

    # 验证密码
    if not user.check_password(password):
        user.login_fail_count += 1

        # 检查是否达到锁定阈值
        if user.login_fail_count >= Config.LOGIN_FAIL_LOCK_COUNT:
            user.status = 'locked'
            user.login_lock_until = datetime.utcnow() + timedelta(minutes=Config.LOGIN_FAIL_LOCK_MINUTES)
            db.session.commit()

            # 记录审计日志
            AuditLog.create_log(
                user_id=user.id, action='login_failed_lock',
                module='auth', description=f'账户因连续{user.login_fail_count}次登录失败被锁定',
                ip_address=ip_address, browser=browser, os=os, device=device,
                result='failure'
            )
            return False, {'message': f'连续登录失败{user.login_fail_count}次，账户已锁定{Config.LOGIN_FAIL_LOCK_MINUTES}分钟'}, 403

        db.session.commit()
        return False, {'message': f'用户名或密码错误，还剩{Config.LOGIN_FAIL_LOCK_COUNT - user.login_fail_count}次尝试机会'}, 401

    # 登录成功
    user.login_fail_count = 0
    user.login_lock_until = None
    user.status = 'active'
    user.last_login_ip = ip_address
    user.last_login_time = datetime.utcnow()
    user.last_login_browser = browser
    user.last_login_os = os
    db.session.commit()

    # 生成JWT令牌
    access_token = create_access_token(identity=user.id)
    refresh_token = create_refresh_token(identity=user.id)

    # 记录审计日志
    AuditLog.create_log(
        user_id=user.id, action='login', module='auth',
        description='用户登录成功', ip_address=ip_address,
        browser=browser, os=os, device=device, result='success'
    )

    return True, {
        'access_token': access_token,
        'refresh_token': refresh_token,
        'user': user.to_dict(),
        'message': '登录成功'
    }, 200


def logout_user(user_id, ip_address='', browser='', os='', device=''):
    """用户登出"""
    AuditLog.create_log(
        user_id=user_id, action='logout', module='auth',
        description='用户登出', ip_address=ip_address,
        browser=browser, os=os, device=device, result='success'
    )


def admin_required(fn):
    """管理员权限装饰器 - 超级管理员和普通管理员可访问"""
    @wraps(fn)
    @jwt_required()
    def wrapper(*args, **kwargs):
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        if not user or not user.is_admin():
            return jsonify({'code': 403, 'message': '权限不足，需要管理员权限'}), 403
        g.current_user = user
        return fn(*args, **kwargs)
    return wrapper


def super_admin_required(fn):
    """超级管理员权限装饰器"""
    @wraps(fn)
    @jwt_required()
    def wrapper(*args, **kwargs):
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        if not user or not user.is_super_admin():
            return jsonify({'code': 403, 'message': '权限不足，需要超级管理员权限'}), 403
        g.current_user = user
        return fn(*args, **kwargs)
    return wrapper


def get_current_user():
    """获取当前登录用户"""
    try:
        verify_jwt_in_request()
        user_id = get_jwt_identity()
        return User.query.get(user_id)
    except Exception:
        return None
