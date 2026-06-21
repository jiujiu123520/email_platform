"""
用户组管理路由 - 模块三
仅超级管理员可操作
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required
from app.models.user_group import UserGroup
from app.models.database import db
from app.middleware.auth import super_admin_required
from app.utils.helpers import success_response, error_response, paginate_response, get_request_info
from app.models.audit_log import AuditLog

group_bp = Blueprint('groups', __name__, url_prefix='/api/v2/groups')


@group_bp.route('', methods=['GET'])
@jwt_required()
@super_admin_required
def list_groups():
    """获取用户组列表"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    keyword = request.args.get('keyword', '').strip()

    query = UserGroup.query.filter_by(is_deleted=False)
    if keyword:
        query = query.filter(UserGroup.name.contains(keyword))

    query = query.order_by(UserGroup.created_at.desc())
    return paginate_response(query, page, per_page)


@group_bp.route('/<int:group_id>', methods=['GET'])
@jwt_required()
@super_admin_required
def get_group(group_id):
    """获取用户组详情"""
    group = UserGroup.query.filter_by(id=group_id, is_deleted=False).first()
    if not group:
        return error_response('用户组不存在', 404)
    return success_response(group.to_dict())


@group_bp.route('', methods=['POST'])
@jwt_required()
@super_admin_required
def create_group():
    """创建用户组"""
    data = request.get_json()
    name = data.get('name', '').strip()
    description = data.get('description', '')
    max_daily_quota = data.get('max_daily_quota', 5000)
    allowed_relay_ids = data.get('allowed_relay_ids', '')

    if not name:
        return error_response('组名不能为空', 400)

    if UserGroup.query.filter_by(name=name, is_deleted=False).first():
        return error_response('组名已存在', 400)

    group = UserGroup(
        name=name, description=description,
        max_daily_quota=max_daily_quota,
        allowed_relay_ids=allowed_relay_ids,
    )
    db.session.add(group)
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='create_group', module='group_management',
        description=f'创建用户组: {name}', target_type='group', target_id=group.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(group.to_dict(), '用户组创建成功', 201)


@group_bp.route('/<int:group_id>', methods=['PUT'])
@jwt_required()
@super_admin_required
def update_group(group_id):
    """更新用户组"""
    group = UserGroup.query.filter_by(id=group_id, is_deleted=False).first()
    if not group:
        return error_response('用户组不存在', 404)

    data = request.get_json()
    if 'name' in data:
        group.name = data['name']
    if 'description' in data:
        group.description = data['description']
    if 'max_daily_quota' in data:
        group.max_daily_quota = data['max_daily_quota']
    if 'allowed_relay_ids' in data:
        group.allowed_relay_ids = data['allowed_relay_ids']

    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='update_group', module='group_management',
        description=f'更新用户组: {group.name}', target_type='group', target_id=group.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(group.to_dict(), '用户组更新成功')


@group_bp.route('/<int:group_id>', methods=['DELETE'])
@jwt_required()
@super_admin_required
def delete_group(group_id):
    """删除用户组"""
    group = UserGroup.query.filter_by(id=group_id, is_deleted=False).first()
    if not group:
        return error_response('用户组不存在', 404)

    group.is_deleted = True
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='delete_group', module='group_management',
        description=f'删除用户组: {group.name}', target_type='group', target_id=group.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(message='用户组已删除')
