"""
邮件发送服务 - 模块五
单发、群发、重试、模板渲染
"""
import uuid
from datetime import datetime
from app.models.email_record import EmailRecord, EmailBatch
from app.models.email_template import EmailTemplate
from app.models.user import User
from app.models.database import db
from app.services.smtp_service import SmtpRelayService


class EmailSendService:
    """邮件发送服务"""

    @staticmethod
    def send_single_email(sender_id, to_email, to_name, subject, html_content,
                          text_content='', template_id=None, variables=None):
        """
        发送单封邮件
        返回: (success, record_or_error, status_code)
        """
        sender = User.query.get(sender_id)
        if not sender:
            return False, {'message': '发送者不存在'}, 404

        # 检查配额
        if not sender.check_quota():
            return False, {'message': '今日发送配额已用完'}, 429

        # 模板渲染
        if template_id:
            template = EmailTemplate.query.get(template_id)
            if template:
                html_content = EmailTemplate.render_template(html_content or template.html_content, variables)
                if not subject:
                    subject = EmailTemplate.render_template(template.subject, variables)

        # 获取可用中继
        relay = SmtpRelayService.get_available_relay()

        # 创建发送记录
        record = EmailRecord(
            to_email=to_email, to_name=to_name or '',
            subject=subject, body_html=html_content,
            body_text=text_content, from_email=sender.email,
            from_name=sender.display_name or sender.username,
            sender_id=sender_id, template_id=template_id,
            relay_id=relay.id if relay else None,
            status='sending', send_type='single',
        )
        db.session.add(record)

        if relay:
            success, error = SmtpRelayService.send_email_via_relay(
                relay=relay,
                from_email=sender.email,
                from_name=sender.display_name or sender.username,
                to_email=to_email,
                to_name=to_name or '',
                subject=subject,
                html_content=html_content,
                text_content=text_content,
            )

            if success:
                record.status = 'sent'
                record.sent_at = datetime.utcnow()
                record.completed_at = datetime.utcnow()
                sender.use_quota()
            else:
                record.status = 'failed'
                record.error_message = error
                record.completed_at = datetime.utcnow()
        else:
            record.status = 'failed'
            record.error_message = '没有可用的SMTP中继'
            record.completed_at = datetime.utcnow()

        db.session.commit()
        return True, record.to_dict(), 200 if record.status == 'sent' else 500

    @staticmethod
    def send_batch_email(sender_id, recipients, subject, html_content,
                         text_content='', template_id=None, variables_list=None):
        """
        批量发送邮件
        recipients: [{'email': '', 'name': '', 'variables': {}}, ...]
        返回: (success, batch_info, status_code)
        """
        sender = User.query.get(sender_id)
        if not sender:
            return False, {'message': '发送者不存在'}, 404

        total_count = len(recipients)
        if total_count == 0:
            return False, {'message': '收件人列表为空'}, 400

        # 检查配额
        if not sender.check_quota(total_count):
            return False, {'message': f'今日配额不足，剩余{sender.daily_quota - sender.used_quota_today}'}, 429

        # 创建批次记录
        batch_id = uuid.uuid4().hex[:16]
        batch = EmailBatch(
            id=batch_id, sender_id=sender_id,
            template_id=template_id,
            total_count=total_count,
            status='processing',
        )
        db.session.add(batch)
        db.session.commit()

        success_count = 0
        failed_count = 0

        for i, recipient in enumerate(recipients):
            to_email = recipient.get('email', '')
            to_name = recipient.get('name', '')
            recipient_vars = recipient.get('variables', {})
            merged_vars = {**(variables_list or {}), **recipient_vars}

            # 模板渲染
            rendered_html = html_content
            rendered_subject = subject
            if template_id:
                template = EmailTemplate.query.get(template_id)
                if template:
                    rendered_html = EmailTemplate.render_template(
                        html_content or template.html_content, merged_vars
                    )
                    rendered_subject = EmailTemplate.render_template(
                        subject or template.subject, merged_vars
                    )

            # 获取中继
            relay = SmtpRelayService.get_available_relay()

            record = EmailRecord(
                to_email=to_email, to_name=to_name,
                subject=rendered_subject, body_html=rendered_html,
                body_text=text_content, from_email=sender.email,
                from_name=sender.display_name or sender.username,
                sender_id=sender_id, template_id=template_id,
                relay_id=relay.id if relay else None,
                status='sending', send_type='batch', batch_id=batch_id,
            )
            db.session.add(record)

            if relay:
                success, error = SmtpRelayService.send_email_via_relay(
                    relay=relay,
                    from_email=sender.email,
                    from_name=sender.display_name or sender.username,
                    to_email=to_email, to_name=to_name,
                    subject=rendered_subject,
                    html_content=rendered_html,
                    text_content=text_content,
                )
                if success:
                    record.status = 'sent'
                    record.sent_at = datetime.utcnow()
                    record.completed_at = datetime.utcnow()
                    success_count += 1
                else:
                    record.status = 'failed'
                    record.error_message = error
                    record.completed_at = datetime.utcnow()
                    failed_count += 1
            else:
                record.status = 'failed'
                record.error_message = '没有可用的SMTP中继'
                record.completed_at = datetime.utcnow()
                failed_count += 1

        # 更新批次统计
        batch.success_count = success_count
        batch.failed_count = failed_count
        batch.pending_count = 0
        batch.status = 'completed'
        batch.completed_at = datetime.utcnow()
        sender.use_quota(success_count)
        db.session.commit()

        return True, batch.to_dict(), 200

    @staticmethod
    def retry_failed_email(record_id):
        """重试失败的邮件"""
        record = EmailRecord.query.get(record_id)
        if not record:
            return False, {'message': '发送记录不存在'}, 404

        if record.status != 'failed':
            return False, {'message': '只能重试失败的邮件'}, 400

        if record.retry_count >= record.max_retries:
            return False, {'message': '已达到最大重试次数'}, 400

        record.retry_count += 1
        record.status = 'sending'
        record.error_message = ''

        relay = SmtpRelayService.get_available_relay()
        if relay:
            record.relay_id = relay.id
            success, error = SmtpRelayService.send_email_via_relay(
                relay=relay,
                from_email=record.from_email,
                from_name=record.from_name,
                to_email=record.to_email,
                to_name=record.to_name,
                subject=record.subject,
                html_content=record.body_html,
                text_content=record.body_text,
            )
            if success:
                record.status = 'sent'
                record.sent_at = datetime.utcnow()
                record.completed_at = datetime.utcnow()
            else:
                record.status = 'failed'
                record.error_message = error
                record.completed_at = datetime.utcnow()
        else:
            record.status = 'failed'
            record.error_message = '没有可用的SMTP中继'
            record.completed_at = datetime.utcnow()

        db.session.commit()
        return True, record.to_dict(), 200
