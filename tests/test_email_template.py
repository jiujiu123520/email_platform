import pytest
from datetime import datetime
from app.models.email_template import EmailTemplate


class TestEmailTemplate:

    def test_render_template_basic(self):
        html = '<p>Hello {username}, welcome to our service!</p>'
        variables = {'username': 'John'}
        result = EmailTemplate.render_template(html, variables)
        assert result == '<p>Hello John, welcome to our service!</p>'

    def test_render_template_multiple_variables(self):
        html = '<p>Hello {first} {last}, your email is {email}</p>'
        variables = {'first': 'John', 'last': 'Doe', 'email': 'john@example.com'}
        result = EmailTemplate.render_template(html, variables)
        assert result == '<p>Hello John Doe, your email is john@example.com</p>'

    def test_render_template_default_variables(self):
        html = '<p>Today is {today}, sent at {sendTime}</p>'
        result = EmailTemplate.render_template(html, {})

        today_str = datetime.utcnow().strftime('%Y-%m-%d')
        assert today_str in result
        assert 'sent at' in result

    def test_render_template_missing_variable(self):
        html = '<p>Hello {username}, your role is {role}</p>'
        variables = {'username': 'John'}
        result = EmailTemplate.render_template(html, variables)
        assert 'John' in result
        assert '{role}' in result

    def test_render_template_none_variables(self):
        html = '<p>Hello {username}</p>'
        result = EmailTemplate.render_template(html, None)
        assert result == '<p>Hello {username}</p>'

    def test_render_template_empty_html(self):
        result = EmailTemplate.render_template('', {'username': 'John'})
        assert result == ''

    def test_render_template_no_variables(self):
        html = '<p>Hello World</p>'
        result = EmailTemplate.render_template(html, {'username': 'John'})
        assert result == '<p>Hello World</p>'

    def test_to_dict(self, test_template):
        data = test_template.to_dict()
        assert 'id' in data
        assert 'name' in data
        assert 'subject' in data
        assert 'html_content' in data
        assert 'creator_name' in data
        assert 'is_system' in data