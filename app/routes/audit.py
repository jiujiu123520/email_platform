"""
系统日志审计路由 - 模块七
管理员可查看全部日志，普通用户仅查看自己的
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required
from app.models.audit_log import AuditLog
from app.middleware.auth import get_current_user
from app.utils.helpers import success_response, error_response, paginate_response

audit_bp = Blueprint('audit', __name__, url_prefix='/api/v2/audit')


@audit_bp.route('/logs', methods=['GET'])
@jwt_required()
def list_logs():
    """查询审计日志"""
    current_user = get_current_user()
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    module = request.args.get('module', '').strip()
    action = request.args.get('action', '').strip()
    result = request.args.get('result', '').strip()
    user_id = request.args.get('user_id', type=int)
    start_date = request.args.get('start_date', '').strip()
    end_date = request.args.get('end_date', '').strip()

    query = AuditLog.query

    # 普通用户只能看自己的日志
    if not current_user.is_admin():
        query = query.filter_by(user_id=current_user.id)

    if module:
        query = query.filter_by(module=module)
    if action:
        query = query.filter(AuditLog.action.contains(action))
    if result:
        query = query.filter_by(result=result)
    if user_id and current_user.is_admin():
        query = query.filter_by(user_id=user_id)
    if start_date:
        from datetime import datetime
        try:
            query = query.filter(AuditLog.created_at >= datetime.strptime(start_date, '%Y-%m-%d'))
        except ValueError:
            pass
    if end_date:
        from datetime import datetime
        try:
            query = query.filter(AuditLog.created_at <= datetime.strptime(end_date + ' 23:59:59', '%Y-%m-%d %H:%M:%S'))
        except ValueError:
            pass

    query = query.order_by(AuditLog.created_at.desc())
    return paginate_response(query, page, per_page)


@audit_bp.route('/modules', methods=['GET'])
@jwt_required()
def get_modules():
    """获取所有模块名称"""
    modules = db.session.query(AuditLog.module).distinct().all()
    return success_response([m[0] for m in modules])


@audit_bp.route('/actions', methods=['GET'])
@jwt_required()
def get_actions():
    """获取所有操作类型"""
    actions = db.session.query(AuditLog.action).distinct().all()
    return success_response([a[0] for a in actions])


@audit_bp.route('/login-logs', methods=['GET'])
@jwt_required()
def get_login_logs():
    """获取登录日志"""
    current_user = get_current_user()
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)

    query = AuditLog.query.filter(AuditLog.action.in_(['login', 'login_failed_lock', 'logout']))

    if not current_user.is_admin():
        query = query.filter_by(user_id=current_user.id)

    query = query.order_by(AuditLog.created_at.desc())
    return paginate_response(query, page, per_page)


# 需要导入db
from app.models.database import db
