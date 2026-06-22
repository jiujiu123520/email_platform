import pytest
from app.services.email_service import EmailService


class TestEmailService:

    def test_validate_email(self):
        assert EmailService.validate_email('test@example.com')
        assert EmailService.validate_email('user.name@domain.co.uk')
        assert EmailService.validate_email('user+tag@example.org')

        assert not EmailService.validate_email('invalid-email')
        assert not EmailService.validate_email('@example.com')
        assert not EmailService.validate_email('test@')
        assert not EmailService.validate_email('test@.com')
        assert not EmailService.validate_email('')
        assert not EmailService.validate_email(None)

    def test_render_template(self, test_template, app):
        with app.app_context():
            subject, html, text = EmailService.render_template(
                test_template.id, {'name': 'John', 'company': 'ACME'}
            )

            assert subject == 'Hello John'
            assert html == '<p>Hello John, welcome to ACME</p>'
            assert text == 'Hello John, welcome to ACME'

    def test_render_template_not_found(self, app):
        with app.app_context():
            subject, html, error = EmailService.render_template(999, {})
            assert subject is None
            assert html is None
            assert error == '模板不存在'

    def test_render_template_with_none_variables(self, test_template, app):
        with app.app_context():
            subject, html, text = EmailService.render_template(test_template.id, None)
            assert subject == 'Hello ${name}'
            assert html == '<p>Hello ${name}, welcome to ${company}</p>'

    def test_render_template_empty_variables(self, test_template, app):
        with app.app_context():
            subject, html, text = EmailService.render_template(test_template.id, {})
            assert subject == 'Hello ${name}'

    def test_get_executor(self):
        executor = EmailService.get_executor()
        assert executor is not None

        same_executor = EmailService.get_executor()
        assert executor is same_executor