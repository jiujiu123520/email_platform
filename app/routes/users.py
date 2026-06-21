"""
用户管理路由 - 模块二：用户管理与风控
仅超级管理员可操作
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.models.user import User
from app.models.database import db
from app.middleware.auth import super_admin_required, get_current_user
from app.utils.helpers import (
    success_response, error_response, paginate_response,
    get_request_info, generate_api_key, generate_api_secret
)
from app.models.audit_log import AuditLog

user_bp = Blueprint('users', __name__, url_prefix='/api/v2/users')


@user_bp.route('', methods=['GET'])
@jwt_required()
@super_admin_required
def list_users():
    """获取用户列表（超级管理员）"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    keyword = request.args.get('keyword', '').strip()
    role = request.args.get('role', '').strip()
    status = request.args.get('status', '').strip()

    query = User.query.filter_by(is_deleted=False)

    if keyword:
        query = query.filter(
            db.or_(
                User.username.contains(keyword),
                User.email.contains(keyword),
                User.display_name.contains(keyword)
            )
        )
    if role:
        query = query.filter_by(role=role)
    if status:
        query = query.filter_by(status=status)

    query = query.order_by(User.created_at.desc())
    return paginate_response(query, page, per_page)


@user_bp.route('/<int:user_id>', methods=['GET'])
@jwt_required()
def get_user(user_id):
    """获取用户详情"""
    current_user = get_current_user()
    if not current_user.is_super_admin() and current_user.id != user_id:
        return error_response('权限不足', 403)

    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return error_response('用户不存在', 404)
    return success_response(user.to_dict())


@user_bp.route('', methods=['POST'])
@jwt_required()
@super_admin_required
def create_user():
    """创建用户（超级管理员）"""
    data = request.get_json()
    username = data.get('username', '').strip()
    email = data.get('email', '').strip()
    password = data.get('password', '')
    role = data.get('role', 'user')
    display_name = data.get('display_name', '')
    daily_quota = data.get('daily_quota', 1000)
    group_id = data.get('group_id')

    if not username or not email or not password:
        return error_response('用户名、邮箱和密码不能为空', 400)

    if User.query.filter_by(username=username, is_deleted=False).first():
        return error_response('用户名已存在', 400)

    if User.query.filter_by(email=email, is_deleted=False).first():
        return error_response('邮箱已被注册', 400)

    user = User(
        username=username, email=email,
        role=role, display_name=display_name,
        daily_quota=daily_quota, group_id=group_id,
    )
    user.set_password(password)
    db.session.add(user)
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='create_user', module='user_management',
        description=f'创建用户: {username}', target_type='user', target_id=user.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(user.to_dict(), '用户创建成功', 201)


@user_bp.route('/<int:user_id>', methods=['PUT'])
@jwt_required()
@super_admin_required
def update_user(user_id):
    """更新用户信息（超级管理员）"""
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return error_response('用户不存在', 404)

    data = request.get_json()
    if 'role' in data:
        user.role = data['role']
    if 'status' in data:
        user.status = data['status']
    if 'display_name' in data:
        user.display_name = data['display_name']
    if 'daily_quota' in data:
        user.daily_quota = data['daily_quota']
    if 'group_id' in data:
        user.group_id = data['group_id']
    if 'password' in data and data['password']:
        user.set_password(data['password'])

    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='update_user', module='user_management',
        description=f'更新用户: {user.username}', target_type='user', target_id=user.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(user.to_dict(), '用户信息更新成功')


@user_bp.route('/<int:user_id>', methods=['DELETE'])
@jwt_required()
@super_admin_required
def delete_user(user_id):
    """删除用户（软删除，保留日志，禁止重新注册）"""
    current = get_current_user()
    if current.id == user_id:
        return error_response('不能删除自己', 400)

    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return error_response('用户不存在', 404)

    user.is_deleted = True
    user.deleted_at = db.func.now()
    user.status = 'disabled'
    user.username = f"deleted_{user.id}_{user.username}"
    user.email = f"deleted_{user.id}_{user.email}"
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='delete_user', module='user_management',
        description=f'删除用户: {user.username}', target_type='user', target_id=user.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(message='用户已删除（软删除，日志保留，禁止重新注册）')


@user_bp.route('/<int:user_id>/reset-quota', methods=['POST'])
@jwt_required()
@super_admin_required
def reset_user_quota(user_id):
    """重置用户每日配额"""
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return error_response('用户不存在', 404)

    user.used_quota_today = 0
    db.session.commit()
    return success_response(message='用户配额已重置')


@user_bp.route('/<int:user_id>/unlock', methods=['POST'])
@jwt_required()
@super_admin_required
def unlock_user(user_id):
    """解锁用户账户"""
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return error_response('用户不存在', 404)

    user.status = 'active'
    user.login_fail_count = 0
    user.login_lock_until = None
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='unlock_user', module='user_management',
        description=f'解锁用户: {user.username}', target_type='user', target_id=user.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(message='用户已解锁')


@user_bp.route('/<int:user_id>/api-keys', methods=['POST'])
@jwt_required()
@super_admin_required
def generate_api_keys(user_id):
    """为用户生成API Key和Secret"""
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return error_response('用户不存在', 404)

    user.api_key = generate_api_key()
    user.api_secret = generate_api_secret()
    db.session.commit()

    return success_response({
        'api_key': user.api_key,
        'api_secret': user.api_secret,
    }, 'API密钥已生成（请妥善保存Secret，仅显示一次）')
