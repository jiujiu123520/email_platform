"""
SMTP中继管理路由 - 模块六
超级管理员和核心高级用户可操作
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.models.smtp_relay import SmtpRelay
from app.models.database import db
from app.middleware.auth import admin_required, get_current_user
from app.utils.helpers import success_response, error_response, paginate_response, get_request_info
from app.services.smtp_service import SmtpRelayService
from app.models.audit_log import AuditLog

relay_bp = Blueprint('relays', __name__, url_prefix='/api/v2/relays')


@relay_bp.route('', methods=['GET'])
@jwt_required()
@admin_required
def list_relays():
    """获取SMTP中继列表"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    status = request.args.get('status', '').strip()

    query = SmtpRelay.query
    if status:
        query = query.filter_by(status=status)

    query = query.order_by(SmtpRelay.priority.desc(), SmtpRelay.created_at.desc())
    return paginate_response(query, page, per_page)


@relay_bp.route('/<int:relay_id>', methods=['GET'])
@jwt_required()
@admin_required
def get_relay(relay_id):
    """获取中继详情"""
    relay = SmtpRelay.query.get(relay_id)
    if not relay:
        return error_response('中继不存在', 404)
    return success_response(relay.to_dict())


@relay_bp.route('', methods=['POST'])
@jwt_required()
@admin_required
def create_relay():
    """创建SMTP中继"""
    data = request.get_json()
    name = data.get('name', '').strip()
    host = data.get('host', '').strip()
    port = data.get('port', 587)
    username = data.get('username', '').strip()
    password = data.get('password', '')
    use_tls = data.get('use_tls', True)
    use_ssl = data.get('use_ssl', False)
    weight = data.get('weight', 10)
    daily_quota = data.get('daily_quota', 10000)
    priority = data.get('priority', 0)
    description = data.get('description', '')

    if not name or not host or not username:
        return error_response('名称、主机和用户名不能为空', 400)

    relay = SmtpRelay(
        name=name, host=host, port=port,
        username=username, password=password,
        use_tls=use_tls, use_ssl=use_ssl,
        weight=weight, daily_quota=daily_quota,
        priority=priority, description=description,
    )
    db.session.add(relay)
    db.session.commit()

    current_user = get_current_user()
    info = get_request_info()
    AuditLog.create_log(
        user_id=current_user.id, action='create_relay', module='smtp_relay',
        description=f'创建SMTP中继: {name}', target_type='relay', target_id=relay.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(relay.to_dict(), 'SMTP中继创建成功', 201)


@relay_bp.route('/<int:relay_id>', methods=['PUT'])
@jwt_required()
@admin_required
def update_relay(relay_id):
    """更新SMTP中继"""
    relay = SmtpRelay.query.get(relay_id)
    if not relay:
        return error_response('中继不存在', 404)

    data = request.get_json()
    updatable_fields = ['name', 'host', 'port', 'username', 'password',
                        'use_tls', 'use_ssl', 'weight', 'daily_quota',
                        'priority', 'description', 'status']

    for field in updatable_fields:
        if field in data:
            setattr(relay, field, data[field])

    db.session.commit()

    current_user = get_current_user()
    info = get_request_info()
    AuditLog.create_log(
        user_id=current_user.id, action='update_relay', module='smtp_relay',
        description=f'更新SMTP中继: {relay.name}', target_type='relay', target_id=relay.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(relay.to_dict(), 'SMTP中继更新成功')


@relay_bp.route('/<int:relay_id>', methods=['DELETE'])
@jwt_required()
@admin_required
def delete_relay(relay_id):
    """删除SMTP中继"""
    relay = SmtpRelay.query.get(relay_id)
    if not relay:
        return error_response('中继不存在', 404)

    db.session.delete(relay)
    db.session.commit()

    current_user = get_current_user()
    info = get_request_info()
    AuditLog.create_log(
        user_id=current_user.id, action='delete_relay', module='smtp_relay',
        description=f'删除SMTP中继: {relay.name}', target_type='relay',
        target_id=relay_id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(message='SMTP中继已删除')


@relay_bp.route('/<int:relay_id>/test', methods=['POST'])
@jwt_required()
@admin_required
def test_relay(relay_id):
    """测试中继连接"""
    success, message = SmtpRelayService.test_relay_connection(relay_id)

    current_user = get_current_user()
    info = get_request_info()
    AuditLog.create_log(
        user_id=current_user.id, action='test_relay', module='smtp_relay',
        description=f'测试中继连接: ID={relay_id}, 结果={"成功" if success else "失败"}',
        target_type='relay', target_id=relay_id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device'],
        result='success' if success else 'failure',
        error_message='' if success else message
    )

    if success:
        return success_response(message=message)
    return error_response(message, 500)


@relay_bp.route('/<int:relay_id>/reset-health', methods=['POST'])
@jwt_required()
@admin_required
def reset_relay_health(relay_id):
    """重置中继健康状态"""
    success, message = SmtpRelayService.reset_relay_health(relay_id)

    if success:
        return success_response(message=message)
    return error_response(message, 404)


@relay_bp.route('/dashboard', methods=['GET'])
@jwt_required()
@admin_required
def relay_dashboard():
    """SMTP中继仪表盘"""
    relays = SmtpRelay.query.all()
    dashboard = {
        'total': len(relays),
        'active': len([r for r in relays if r.status == 'active']),
        'paused': len([r for r in relays if r.status == 'paused']),
        'disabled': len([r for r in relays if r.status == 'disabled']),
        'healthy': len([r for r in relays if r.is_healthy]),
        'unhealthy': len([r for r in relays if not r.is_healthy]),
        'relays': [r.to_dict() for r in relays],
    }
    return success_response(dashboard)
