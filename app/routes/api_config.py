"""
API接口管理路由 - 模块八
仅超级管理员可操作
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required
from app.models.api_config import ApiConfig, ApiCallLog
from app.models.database import db
from app.middleware.auth import super_admin_required
from app.utils.helpers import success_response, error_response, paginate_response, get_request_info
from app.models.audit_log import AuditLog

api_config_bp = Blueprint('api_config', __name__, url_prefix='/api/v2/api-config')


@api_config_bp.route('', methods=['GET'])
@jwt_required()
@super_admin_required
def list_configs():
    """获取API配置列表"""
    configs = ApiConfig.query.all()
    return success_response([c.to_dict() for c in configs])


@api_config_bp.route('/<int:config_id>', methods=['PUT'])
@jwt_required()
@super_admin_required
def update_config(config_id):
    """更新API配置"""
    config = ApiConfig.query.get(config_id)
    if not config:
        return error_response('配置不存在', 404)

    data = request.get_json()
    updatable_fields = ['name', 'description', 'base_url', 'enabled',
                         'rate_limit_per_hour', 'rate_limit_per_day',
                         'concurrent_limit', 'ip_whitelist_enabled',
                         'ip_whitelist', 'sign_enabled', 'sign_expire_seconds']

    for field in updatable_fields:
        if field in data:
            setattr(config, field, data[field])

    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=get_jwt_identity(), action='update_api_config', module='api_config',
        description=f'更新API配置: {config.name}', target_type='api_config',
        target_id=config.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(config.to_dict(), 'API配置更新成功')


@api_config_bp.route('/call-logs', methods=['GET'])
@jwt_required()
@super_admin_required
def list_call_logs():
    """获取API调用日志"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    endpoint = request.args.get('endpoint', '').strip()
    user_id = request.args.get('user_id', type=int)
    response_code = request.args.get('response_code', type=int)

    query = ApiCallLog.query

    if endpoint:
        query = query.filter(ApiCallLog.endpoint.contains(endpoint))
    if user_id:
        query = query.filter_by(user_id=user_id)
    if response_code:
        query = query.filter_by(response_code=response_code)

    query = query.order_by(ApiCallLog.created_at.desc())
    return paginate_response(query, page, per_page)


@api_config_bp.route('/call-stats', methods=['GET'])
@jwt_required()
@super_admin_required
def get_call_stats():
    """获取API调用统计"""
    from datetime import datetime, timedelta
    today = datetime.utcnow().date()

    stats = {
        'today_total': ApiCallLog.query.filter(
            db.func.date(ApiCallLog.created_at) == today
        ).count(),
        'today_success': ApiCallLog.query.filter(
            db.func.date(ApiCallLog.created_at) == today,
            ApiCallLog.response_code == 200
        ).count(),
        'today_failed': ApiCallLog.query.filter(
            db.func.date(ApiCallLog.created_at) == today,
            ApiCallLog.response_code != 200
        ).count(),
        'avg_duration_ms': db.session.query(
            db.func.avg(ApiCallLog.duration_ms)
        ).scalar() or 0,
    }

    return success_response(stats)
