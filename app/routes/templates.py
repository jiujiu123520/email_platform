"""
邮件模板路由 - 模块四：邮件模板管理 + 变量替换
所有用户可创建和管理自己的模板，管理员可管理所有模板
"""
import re
from flask import Blueprint, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.models.email_template import EmailTemplate
from app.models.database import db
from app.middleware.auth import get_current_user
from app.utils.helpers import success_response, error_response, paginate_response, get_request_info
from app.models.audit_log import AuditLog

template_bp = Blueprint('templates', __name__, url_prefix='/api/v2/templates')


@template_bp.route('', methods=['GET'])
@jwt_required()
def list_templates():
    """获取模板列表"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    keyword = request.args.get('keyword', '').strip()
    category = request.args.get('category', '').strip()

    current_user = get_current_user()
    query = EmailTemplate.query.filter_by(is_deleted=False)

    # 普通用户只能看自己的模板，管理员可看所有
    if not current_user.is_admin():
        query = query.filter_by(created_by=current_user.id)

    if keyword:
        query = query.filter(
            db.or_(
                EmailTemplate.name.contains(keyword),
                EmailTemplate.subject.contains(keyword)
            )
        )
    if category:
        query = query.filter_by(category=category)

    query = query.order_by(EmailTemplate.created_at.desc())
    return paginate_response(query, page, per_page)


@template_bp.route('/<int:template_id>', methods=['GET'])
@jwt_required()
def get_template(template_id):
    """获取模板详情"""
    current_user = get_current_user()
    template = EmailTemplate.query.filter_by(id=template_id, is_deleted=False).first()
    if not template:
        return error_response('模板不存在', 404)

    # 普通用户只能看自己的模板
    if not current_user.is_admin() and template.created_by != current_user.id:
        return error_response('权限不足', 403)

    return success_response(template.to_dict())


@template_bp.route('', methods=['POST'])
@jwt_required()
def create_template():
    """创建模板"""
    current_user = get_current_user()
    data = request.get_json()

    name = data.get('name', '').strip()
    subject = data.get('subject', '').strip()
    html_content = data.get('html_content', '')
    text_content = data.get('text_content', '')
    category = data.get('category', 'general')

    if not name or not subject:
        return error_response('模板名称和标题不能为空', 400)

    if not html_content:
        return error_response('模板HTML内容不能为空', 400)

    # 提取变量
    variables = re.findall(r'\{(\w+)\}', html_content + subject)
    variables = list(set(variables))
    import json
    variables_json = json.dumps(variables, ensure_ascii=False)

    template = EmailTemplate(
        name=name, subject=subject,
        html_content=html_content, text_content=text_content,
        variables=variables_json, category=category,
        created_by=current_user.id,
    )
    db.session.add(template)
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=current_user.id, action='create_template', module='template',
        description=f'创建模板: {name}', target_type='template', target_id=template.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(template.to_dict(), '模板创建成功', 201)


@template_bp.route('/<int:template_id>', methods=['PUT'])
@jwt_required()
def update_template(template_id):
    """更新模板"""
    current_user = get_current_user()
    template = EmailTemplate.query.filter_by(id=template_id, is_deleted=False).first()
    if not template:
        return error_response('模板不存在', 404)

    if not current_user.is_admin() and template.created_by != current_user.id:
        return error_response('权限不足', 403)

    data = request.get_json()
    if 'name' in data:
        template.name = data['name']
    if 'subject' in data:
        template.subject = data['subject']
    if 'html_content' in data:
        template.html_content = data['html_content']
    if 'text_content' in data:
        template.text_content = data['text_content']
    if 'category' in data:
        template.category = data['category']

    # 重新提取变量
    all_text = template.html_content + template.subject
    variables = list(set(re.findall(r'\{(\w+)\}', all_text)))
    import json
    template.variables = json.dumps(variables, ensure_ascii=False)

    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=current_user.id, action='update_template', module='template',
        description=f'更新模板: {template.name}', target_type='template', target_id=template.id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(template.to_dict(), '模板更新成功')


@template_bp.route('/<int:template_id>', methods=['DELETE'])
@jwt_required()
def delete_template(template_id):
    """删除模板（硬删除，不可恢复）"""
    current_user = get_current_user()
    template = EmailTemplate.query.filter_by(id=template_id, is_deleted=False).first()
    if not template:
        return error_response('模板不存在', 404)

    if not current_user.is_admin() and template.created_by != current_user.id:
        return error_response('权限不足', 403)

    db.session.delete(template)
    db.session.commit()

    info = get_request_info()
    AuditLog.create_log(
        user_id=current_user.id, action='delete_template', module='template',
        description=f'删除模板: {template.name}（硬删除）', target_type='template',
        target_id=template_id,
        ip_address=info['ip_address'], browser=info['browser'],
        os=info['os'], device=info['device']
    )

    return success_response(message='模板已删除（硬删除，不可恢复）')


@template_bp.route('/<int:template_id>/preview', methods=['POST'])
@jwt_required()
def preview_template(template_id):
    """预览模板（变量替换后的效果）"""
    current_user = get_current_user()
    template = EmailTemplate.query.filter_by(id=template_id, is_deleted=False).first()
    if not template:
        return error_response('模板不存在', 404)

    data = request.get_json()
    variables = data.get('variables', {})

    rendered_html = EmailTemplate.render_template(template.html_content, variables)
    rendered_subject = EmailTemplate.render_template(template.subject, variables)

    return success_response({
        'subject': rendered_subject,
        'html_content': rendered_html,
    })


@template_bp.route('/variables', methods=['GET'])
@jwt_required()
def get_available_variables():
    """获取可用变量列表"""
    variables = [
        {'name': 'username', 'description': '发送者用户名'},
        {'name': 'toEmail', 'description': '收件人邮箱'},
        {'name': 'sendTime', 'description': '发送时间'},
        {'name': 'today', 'description': '当前日期'},
        {'name': 'subject', 'description': '邮件标题'},
    ]
    return success_response(variables)
