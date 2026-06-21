"""
个人中心路由 - 模块九
所有用户可访问，支持QQ号绑定和头像获取
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required
from app.models.user import User
from app.models.email_record import EmailRecord
from app.models.database import db
from app.middleware.auth import get_current_user
from app.utils.helpers import success_response, error_response, paginate_response
import requests

profile_bp = Blueprint('profile', __name__, url_prefix='/api/v2/profile')


def get_qq_avatar_url(qq_number):
    """获取QQ头像URL"""
    if not qq_number:
        return ''
    # QQ头像API
    return f'https://q1.qlogo.cn/g?b=qq&nk={qq_number}&s=100'


def get_qq_nickname(qq_number):
    """获取QQ昵称（通过QQ号查询）"""
    if not qq_number:
        return ''
    try:
        # 使用QQ互联接口获取昵称
        url = f'https://r.qzone.qq.com/fcg-bin/cgi_get_portrait.fcg?uins={qq_number}'
        response = requests.get(url, timeout=5)
        if response.status_code == 200:
            # 解析返回数据
            content = response.text
            if 'portraitCallBack' in content:
                import json
                # 提取JSON数据
                json_str = content.replace('portraitCallBack(', '').rstrip(')')
                data = json.loads(json_str)
                if qq_number in data:
                    return data[qq_number][6] if len(data[qq_number]) > 6 else ''
    except Exception:
        pass
    return ''


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


@profile_bp.route('/bind-qq', methods=['POST'])
@jwt_required()
def bind_qq():
    """绑定QQ号"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)

    data = request.get_json()
    qq_number = data.get('qq_number', '').strip()

    if not qq_number:
        return error_response('QQ号不能为空', 400)

    if not qq_number.isdigit():
        return error_response('QQ号必须为数字', 400)

    # 检查QQ号是否已被其他用户绑定
    existing = User.query.filter(
        User.qq_number == qq_number,
        User.id != user.id,
        User.is_deleted == False
    ).first()
    if existing:
        return error_response('该QQ号已被其他用户绑定', 400)

    # 获取QQ头像
    qq_avatar = get_qq_avatar_url(qq_number)

    user.qq_number = qq_number
    user.qq_avatar = qq_avatar

    db.session.commit()
    return success_response({
        'qq_number': qq_number,
        'qq_avatar': qq_avatar,
        'avatar': user.get_avatar_url()
    }, 'QQ号绑定成功')


@profile_bp.route('/unbind-qq', methods=['POST'])
@jwt_required()
def unbind_qq():
    """解绑QQ号"""
    user = get_current_user()
    if not user:
        return error_response('用户不存在', 404)

    user.qq_number = ''
    user.qq_avatar = ''
    db.session.commit()
    return success_response({'avatar': user.get_avatar_url()}, 'QQ号解绑成功')


@profile_bp.route('/qq-avatar/<qq_number>', methods=['GET'])
def get_qq_avatar(qq_number):
    """获取QQ头像（公开接口，无需登录）"""
    if not qq_number or not qq_number.isdigit():
        return error_response('无效的QQ号', 400)

    avatar_url = get_qq_avatar_url(qq_number)
    return success_response({
        'qq_number': qq_number,
        'avatar_url': avatar_url,
        'avatar_size_100': f'https://q1.qlogo.cn/g?b=qq&nk={qq_number}&s=100',
        'avatar_size_640': f'https://q1.qlogo.cn/g?b=qq&nk={qq_number}&s=640',
    })


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
