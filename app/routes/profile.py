"""
个人中心路由 - 模块九
所有用户可访问
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required
from app.models.user import User
from app.models.email_record import EmailRecord
from app.models.database import db
from app.middleware.auth import get_current_user
from app.utils.helpers import success_response, error_response, paginate_response

profile_bp = Blueprint('profile', __name__, url_prefix='/api/v2/profile')


@profile_bp.route('/info', methods=['GET'])
@jwt_required()
def get_info():
    """获取个人信息"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)
    return success_response(user.to_dict())


@profile_bp.route('/info', methods=['PUT'])
@jwt_required()
def update_info():
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


@profile_bp.route('/quota', methods=['GET'])
@jwt_required()
def get_quota():
    """获取配额信息"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)

    user.reset_daily_quota()
    return success_response({
        'daily_quota': user.daily_quota,
        'used_quota_today': user.used_quota_today,
        'remaining_quota': user.daily_quota - user.used_quota_today,
    })


@profile_bp.route('/api-keys', methods=['GET'])
@jwt_required()
def get_api_keys():
    """获取API密钥信息"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)

    return success_response({
        'api_key': user.api_key,
        'has_secret': bool(user.api_secret),
    })


@profile_bp.route('/statistics', methods=['GET'])
@jwt_required()
def get_personal_statistics():
    """获取个人统计"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)

    from datetime import datetime, timedelta
    today = datetime.utcnow().date()
    seven_days_ago = today - timedelta(days=7)

    stats = {
        'today_sent': EmailRecord.query.filter(
            EmailRecord.sender_id == user.id,
            db.func.date(EmailRecord.created_at) == today
        ).count(),
        'today_success': EmailRecord.query.filter(
            EmailRecord.sender_id == user.id,
            db.func.date(EmailRecord.created_at) == today,
            EmailRecord.status == 'sent'
        ).count(),
        'week_sent': EmailRecord.query.filter(
            EmailRecord.sender_id == user.id,
            db.func.date(EmailRecord.created_at) >= seven_days_ago
        ).count(),
        'week_success': EmailRecord.query.filter(
            EmailRecord.sender_id == user.id,
            db.func.date(EmailRecord.created_at) >= seven_days_ago,
            EmailRecord.status == 'sent'
        ).count(),
        'total_sent': EmailRecord.query.filter_by(sender_id=user.id).count(),
        'total_success': EmailRecord.query.filter_by(
            sender_id=user.id, status='sent'
        ).count(),
    }

    return success_response(stats)
