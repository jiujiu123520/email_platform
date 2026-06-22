import pytest
import time
import hashlib
from app.utils.helpers import (
    success_response, error_response, verify_api_sign,
    generate_api_key, generate_api_secret
)


class TestHelpers:

    def test_success_response(self, app):
        with app.app_context():
            response, code = success_response()
            assert code == 200
            data = response.get_json()
            assert data['code'] == 200
            assert data['message'] == '操作成功'
            assert 'data' not in data

    def test_success_response_with_data(self, app):
        with app.app_context():
            response, code = success_response(data={'key': 'value'})
            assert code == 200
            data = response.get_json()
            assert data['data'] == {'key': 'value'}

    def test_success_response_custom_message(self, app):
        with app.app_context():
            response, code = success_response(message='创建成功', code=201)
            assert code == 201
            data = response.get_json()
            assert data['message'] == '创建成功'

    def test_error_response(self, app):
        with app.app_context():
            response, code = error_response()
            assert code == 400
            data = response.get_json()
            assert data['code'] == 400
            assert data['message'] == '操作失败'

    def test_error_response_custom(self, app):
        with app.app_context():
            response, code = error_response(message='参数错误', code=400, data={'field': 'email'})
            assert code == 400
            data = response.get_json()
            assert data['message'] == '参数错误'
            assert data['data'] == {'field': 'email'}

    def test_verify_api_sign_valid(self):
        api_key = 'testkey'
        api_secret = 'testsecret'
        timestamp = str(int(time.time() * 1000))
        nonce = 'abc123'
        sign_str = f"{api_key}{timestamp}{nonce}{api_secret}"
        sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()

        valid, message = verify_api_sign(api_key, timestamp, nonce, sign, api_secret)
        assert valid
        assert message == '验证成功'

    def test_verify_api_sign_invalid_sign(self):
        api_key = 'testkey'
        api_secret = 'testsecret'
        timestamp = str(int(time.time() * 1000))
        nonce = 'abc123'
        invalid_sign = 'invalid123456789012345678901234567890'

        valid, message = verify_api_sign(api_key, timestamp, nonce, invalid_sign, api_secret)
        assert not valid
        assert message == '签名验证失败'

    def test_verify_api_sign_expired(self):
        api_key = 'testkey'
        api_secret = 'testsecret'
        timestamp = str(int(time.time() * 1000) - 600000)
        nonce = 'abc123'
        sign_str = f"{api_key}{timestamp}{nonce}{api_secret}"
        sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()

        valid, message = verify_api_sign(api_key, timestamp, nonce, sign, api_secret)
        assert not valid
        assert message == '请求已过期'

    def test_generate_api_key(self):
        key = generate_api_key()
        assert len(key) == 64

        key2 = generate_api_key()
        assert key != key2

    def test_generate_api_secret(self):
        secret = generate_api_secret()
        assert len(secret) == 64

        secret2 = generate_api_secret()
        assert secret != secret2