"""
工具函数模块
包含：响应格式化、API签名验证、请求信息获取等
"""
import hashlib
import time
import uuid
import json
from functools import wraps
from flask import jsonify, request, g
from app.models.user import User
from app.models.api_config import ApiCallLog
from app.models.audit_log import AuditLog
from app.models.database import db
from config import Config


def success_response(data=None, message='操作成功', code=200):
    """成功响应"""
    response = {'code': code, 'message': message}
    if data is not None:
        response['data'] = data
    return jsonify(response), code


def error_response(message='操作失败', code=400, data=None):
    """错误响应"""
    response = {'code': code, 'message': message}
    if data is not None:
        response['data'] = data
    return jsonify(response), code


def paginate_response(query, page, per_page, serializer=None):
    """分页响应"""
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    items = []
    for item in pagination.items:
        if serializer:
            items.append(serializer(item))
        elif hasattr(item, 'to_dict'):
            items.append(item.to_dict())
        else:
            items.append(str(item))

    return success_response({
        'items': items,
        'total': pagination.total,
        'page': page,
        'per_page': per_page,
        'pages': pagination.pages,
        'has_next': pagination.has_next,
        'has_prev': pagination.has_prev,
    })


def get_request_info():
    """获取请求信息"""
    return {
        'ip_address': request.headers.get('X-Real-IP', request.remote_addr),
        'browser': request.headers.get('User-Agent', ''),
        'os': request.headers.get('X-OS', ''),
        'device': request.headers.get('X-Device', ''),
    }


def generate_api_key():
    """生成API Key"""
    return uuid.uuid4().hex + uuid.uuid4().hex


def generate_api_secret():
    """生成API Secret"""
    return uuid.uuid4().hex + uuid.uuid4().hex


def verify_api_sign(api_key, timestamp, nonce, sign, api_secret):
    """
    验证API签名
    Sign = MD5(Key + Timestamp + Nonce + Secret)
    """
    # 检查时间戳是否过期（5分钟）
    current_time = int(time.time() * 1000)
    if abs(current_time - int(timestamp)) > Config.API_SIGN_EXPIRE_SECONDS * 1000:
        return False, '请求已过期'

    # 计算签名
    sign_str = f"{api_key}{timestamp}{nonce}{api_secret}"
    expected_sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()

    if sign != expected_sign:
        return False, '签名验证失败'

    return True, '验证成功'


def log_api_call(user_id, endpoint, method, response_code, duration_ms):
    """记录API调用日志"""
    try:
        log = ApiCallLog(
            user_id=user_id,
            endpoint=endpoint,
            method=method,
            request_params=json.dumps(request.args.to_dict()) if request.args else '',
            request_body=request.get_data(as_text=True)[:2000] if request.data else '',
            response_code=response_code,
            ip_address=request.headers.get('X-Real-IP', request.remote_addr),
            user_agent=request.headers.get('User-Agent', ''),
            duration_ms=duration_ms,
        )
        db.session.add(log)
        db.session.commit()
    except Exception:
        db.session.rollback()


def api_sign_required(fn):
    """API签名验证装饰器"""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        api_key = request.headers.get('ApiKey') or request.args.get('ApiKey')
        timestamp = request.headers.get('Timestamp') or request.args.get('Timestamp')
        nonce = request.headers.get('Nonce') or request.args.get('Nonce')
        sign = request.headers.get('Sign') or request.args.get('Sign')

        if not all([api_key, timestamp, nonce, sign]):
            return error_response('缺少必要的认证参数（ApiKey, Timestamp, Nonce, Sign）', 401)

        # 查找用户
        user = User.query.filter_by(api_key=api_key, is_deleted=False).first()
        if not user:
            return error_response('无效的ApiKey', 401)

        if user.status != 'active':
            return error_response('账户已被禁用或锁定', 403)

        # 验证签名
        valid, msg = verify_api_sign(api_key, timestamp, nonce, sign, user.api_secret)
        if not valid:
            return error_response(msg, 401)

        # 检查IP白名单
        if Config.IP_WHITELIST_ENABLED:
            client_ip = request.headers.get('X-Real-IP', request.remote_addr)
            api_config = ApiConfig.query.filter_by(enabled=True).first()
            if api_config and api_config.ip_whitelist_enabled:
                whitelist = [ip.strip() for ip in api_config.ip_whitelist.split(',') if ip.strip()]
                if whitelist and client_ip not in whitelist:
                    return error_response('IP地址不在白名单中', 403)

        g.current_user = user
        g.api_auth = True
        return fn(*args, **kwargs)
    return wrapper


# 导入ApiConfig（延迟导入避免循环引用）
from app.models.api_config import ApiConfig
