"""
邮件发送路由 - 模块五：邮件单发/群发 + 发送记录
所有用户可使用
"""
from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.models.email_record import EmailRecord, EmailBatch
from app.models.database import db
from app.middleware.auth import get_current_user
from app.utils.helpers import success_response, error_response, paginate_response, get_request_info
from app.services.email_service import EmailService
from app.models.audit_log import AuditLog

email_bp = Blueprint('email', __name__, url_prefix='/api/v2/email')


@email_bp.route('/send', methods=['POST'])
@jwt_required()
def send_email():
    """发送单封邮件"""
    current_user = get_current_user()
    data = request.get_json()

    to_email = data.get('to_email', '').strip()
    to_name = data.get('to_name', '').strip()
    subject = data.get('subject', '').strip()
    html_content = data.get('html_content', '')
    text_content = data.get('text_content', '')
    template_id = data.get('template_id')
    variables = data.get('variables', {})

    if not to_email or not subject:
        return error_response('收件人邮箱和邮件标题不能为空', 400)

    success, result, code = EmailSendService.send_single_email(
        sender_id=current_user.id,
        to_email=to_email, to_name=to_name,
        subject=subject, html_content=html_content,
        text_content=text_content, template_id=template_id,
        variables=variables,
    )

    if success:
        info = get_request_info()
        AuditLog.create_log(
            user_id=current_user.id, action='send_email', module='email',
            description=f'发送邮件至: {to_email}', target_type='email',
            ip_address=info['ip_address'], browser=info['browser'],
            os=info['os'], device=info['device']
        )
        return success_response(result, '邮件发送成功', code)
    return error_response(result.get('message', '发送失败'), code)


@email_bp.route('/batch', methods=['POST'])
@jwt_required()
def send_batch_email():
    """批量发送邮件"""
    current_user = get_current_user()
    data = request.get_json()

    recipients = data.get('recipients', [])
    subject = data.get('subject', '').strip()
    html_content = data.get('html_content', '')
    text_content = data.get('text_content', '')
    template_id = data.get('template_id')
    variables = data.get('variables', {})

    if not recipients:
        return error_response('收件人列表不能为空', 400)

    if not subject and not template_id:
        return error_response('邮件标题不能为空', 400)

    success, result, code = EmailSendService.send_batch_email(
        sender_id=current_user.id,
        recipients=recipients, subject=subject,
        html_content=html_content, text_content=text_content,
        template_id=template_id, variables_list=variables,
    )

    if success:
        info = get_request_info()
        AuditLog.create_log(
            user_id=current_user.id, action='send_batch_email', module='email',
            description=f'批量发送邮件: {len(recipients)}封', target_type='batch',
            ip_address=info['ip_address'], browser=info['browser'],
            os=info['os'], device=info['device']
        )
        return success_response(result, '批量邮件发送任务已提交', code)
    return error_response(result.get('message', '发送失败'), code)


@email_bp.route('/records', methods=['GET'])
@jwt_required()
def list_records():
    """查询发送记录"""
    current_user = get_current_user()
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    status = request.args.get('status', '').strip()
    send_type = request.args.get('send_type', '').strip()
    to_email = request.args.get('to_email', '').strip()
    start_date = request.args.get('start_date', '').strip()
    end_date = request.args.get('end_date', '').strip()

    query = EmailRecord.query

    # 普通用户只能看自己的记录
    if not current_user.is_admin():
        query = query.filter_by(sender_id=current_user.id)

    if status:
        query = query.filter_by(status=status)
    if send_type:
        query = query.filter_by(send_type=send_type)
    if to_email:
        query = query.filter(EmailRecord.to_email.contains(to_email))
    if start_date:
        from datetime import datetime
        try:
            query = query.filter(EmailRecord.created_at >= datetime.strptime(start_date, '%Y-%m-%d'))
        except ValueError:
            pass
    if end_date:
        from datetime import datetime
        try:
            query = query.filter(EmailRecord.created_at <= datetime.strptime(end_date + ' 23:59:59', '%Y-%m-%d %H:%M:%S'))
        except ValueError:
            pass

    query = query.order_by(EmailRecord.created_at.desc())
    return paginate_response(query, page, per_page)


@email_bp.route('/records/<int:record_id>', methods=['GET'])
@jwt_required()
def get_record(record_id):
    """获取发送记录详情"""
    current_user = get_current_user()
    record = EmailRecord.query.get(record_id)
    if not record:
        return error_response('发送记录不存在', 404)

    if not current_user.is_admin() and record.sender_id != current_user.id:
        return error_response('权限不足', 403)

    return success_response(record.to_dict())


@email_bp.route('/records/<int:record_id>/retry', methods=['POST'])
@jwt_required()
def retry_email(record_id):
    """重试失败的邮件"""
    current_user = get_current_user()
    record = EmailRecord.query.get(record_id)
    if not record:
        return error_response('发送记录不存在', 404)

    if not current_user.is_admin() and record.sender_id != current_user.id:
        return error_response('权限不足', 403)

    success, result, code = EmailSendService.retry_failed_email(record_id)

    if success:
        info = get_request_info()
        AuditLog.create_log(
            user_id=current_user.id, action='retry_email', module='email',
            description=f'重试发送邮件至: {record.to_email}', target_type='email',
            target_id=record_id,
            ip_address=info['ip_address'], browser=info['browser'],
            os=info['os'], device=info['device']
        )
        return success_response(result, '邮件重试成功', code)
    return error_response(result.get('message', '重试失败'), code)


@email_bp.route('/batches', methods=['GET'])
@jwt_required()
def list_batches():
    """查询批量发送批次"""
    current_user = get_current_user()
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)

    query = EmailBatch.query
    if not current_user.is_admin():
        query = query.filter_by(sender_id=current_user.id)

    query = query.order_by(EmailBatch.created_at.desc())
    return paginate_response(query, page, per_page)


@email_bp.route('/stats', methods=['GET'])
@jwt_required()
def get_email_stats():
    """获取邮件统计（管理员可看全系统，普通用户看自己的）"""
    current_user = get_current_user()

    if not current_user.is_admin():
        return error_response('权限不足，仅管理员可查看统计', 403)

    from datetime import datetime, timedelta
    today = datetime.utcnow().date()
    seven_days_ago = today - timedelta(days=7)
    thirty_days_ago = today - timedelta(days=30)

    stats = {
        'today': {
            'total': EmailRecord.query.filter(
                db.func.date(EmailRecord.created_at) == today
            ).count(),
            'success': EmailRecord.query.filter(
                db.func.date(EmailRecord.created_at) == today,
                EmailRecord.status == 'sent'
            ).count(),
            'failed': EmailRecord.query.filter(
                db.func.date(EmailRecord.created_at) == today,
                EmailRecord.status == 'failed'
            ).count(),
        },
        'week': {
            'total': EmailRecord.query.filter(
                db.func.date(EmailRecord.created_at) >= seven_days_ago
            ).count(),
            'success': EmailRecord.query.filter(
                db.func.date(EmailRecord.created_at) >= seven_days_ago,
                EmailRecord.status == 'sent'
            ).count(),
        },
        'month': {
            'total': EmailRecord.query.filter(
                db.func.date(EmailRecord.created_at) >= thirty_days_ago
            ).count(),
            'success': EmailRecord.query.filter(
                db.func.date(EmailRecord.created_at) >= thirty_days_ago,
                EmailRecord.status == 'sent'
            ).count(),
        },
        'all_time': {
            'total': EmailRecord.query.count(),
            'success': EmailRecord.query.filter_by(status='sent').count(),
            'failed': EmailRecord.query.filter_by(status='failed').count(),
        },
    }

    return success_response(stats)
