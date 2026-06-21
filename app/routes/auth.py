"""
认证路由 - 模块一：登录 & 全局UI设置
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity, create_access_token, create_refresh_token
from app.models.user import User
from app.middleware.auth import login_user, logout_user, get_current_user
from app.utils.helpers import success_response, error_response, get_request_info
from app.models.audit_log import AuditLog
from app.models.database import db

auth_bp = Blueprint('auth', __name__, url_prefix='/api/v2/auth')


@auth_bp.route('/login', methods=['POST'])
def login():
    """用户登录"""
    data = request.get_json()
    username = data.get('username', '').strip()
    password = data.get('password', '')

    if not username or not password:
        return error_response('用户名和密码不能为空', 400)

    info = get_request_info()
    success, result, code = login_user(
        username=username, password=password,
        ip_address=info['ip_address'],
        browser=info['browser'],
        os=info['os'],
        device=info['device']
    )

    if success:
        return jsonify({'code': code, **result}), code
    return jsonify({'code': code, **result}), code


@auth_bp.route('/logout', methods=['POST'])
@jwt_required()
def logout():
    """用户登出"""
    user_id = get_jwt_identity()
    info = get_request_info()
    logout_user(
        user_id=user_id,
        ip_address=info['ip_address'],
        browser=info['browser'],
        os=info['os'],
        device=info['device']
    )
    return success_response(message='登出成功')


@auth_bp.route('/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh_token():
    """刷新访问令牌"""
    user_id = get_jwt_identity()
    access_token = create_access_token(identity=user_id)
    return success_response({'access_token': access_token}, '令牌刷新成功')


@auth_bp.route('/profile', methods=['GET'])
@jwt_required()
def get_profile():
    """获取当前用户信息"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)
    return success_response(user.to_dict())


@auth_bp.route('/profile', methods=['PUT'])
@jwt_required()
def update_profile():
    """更新个人信息"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)

    data = request.get_json()
    if 'display_name' in data:
        user.display_name = data['display_name']
    if 'avatar' in data:
        user.avatar = data['avatar']
    if 'phone' in data:
        user.phone = data['phone']

    db.session.commit()
    return success_response(user.to_dict(), '个人信息更新成功')


@auth_bp.route('/change-password', methods=['POST'])
@jwt_required()
def change_password():
    """修改密码"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)

    data = request.get_json()
    old_password = data.get('old_password', '')
    new_password = data.get('new_password', '')
    confirm_password = data.get('confirm_password', '')

    if not old_password or not new_password:
        return error_response('旧密码和新密码不能为空', 400)

    if not user.check_password(old_password):
        return error_response('旧密码错误', 400)

    if new_password != confirm_password:
        return error_response('两次输入的新密码不一致', 400)

    if len(new_password) < 8:
        return error_response('新密码长度不能少于8位', 400)

    user.set_password(new_password)
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=user.id, action='change_password', module='auth',
        description='用户修改密码', ip_address=info['ip_address'],
        browser=info['browser'], os=info['os'], device=info['device']
    )

    return success_response(message='密码修改成功')
