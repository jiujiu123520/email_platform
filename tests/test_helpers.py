"""
工具函数测试
测试API签名验证、响应格式化等核心工具函数
"""
import pytest
import time
import hashlib
from app.utils.helpers import (
    verify_api_sign,
    generate_api_key,
    generate_api_secret,
    success_response,
    error_response,
    paginate_response
)
from app.models.user import User
from app.models.api_config import ApiConfig
from app.models.database import db
from config import Config


class TestApiSignatureVerification:
    """API签名验证测试"""

    def test_verify_api_sign_success(self, session, normal_user):
        """测试签名验证成功"""
        # 为用户生成API密钥
        from app.utils.helpers import generate_api_key, generate_api_secret
        normal_user.api_key = generate_api_key()
        normal_user.api_secret = generate_api_secret()
        session.commit()
        
        timestamp = str(int(time.time() * 1000))
        nonce = 'testnonce123456'
        
        # 计算正确的签名
        sign_str = f"{normal_user.api_key}{timestamp}{nonce}{normal_user.api_secret}"
        expected_sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()
        
        valid, message = verify_api_sign(
            normal_user.api_key,
            timestamp,
            nonce,
            expected_sign,
            normal_user.api_secret
        )
        
        assert valid is True
        assert message == '验证成功'

    def test_verify_api_sign_wrong_signature(self, session, normal_user):
        """测试签名错误"""
        from app.utils.helpers import generate_api_key, generate_api_secret
        normal_user.api_key = generate_api_key()
        normal_user.api_secret = generate_api_secret()
        session.commit()
        
        timestamp = str(int(time.time() * 1000))
        nonce = 'testnonce123456'
        wrong_sign = 'wrong_signature_12345'
        
        valid, message = verify_api_sign(
            normal_user.api_key,
            timestamp,
            nonce,
            wrong_sign,
            normal_user.api_secret
        )
        
        assert valid is False
        assert '签名验证失败' in message

    def test_verify_api_sign_expired_timestamp(self, session, normal_user):
        """测试时间戳过期"""
        from app.utils.helpers import generate_api_key, generate_api_secret
        normal_user.api_key = generate_api_key()
        normal_user.api_secret = generate_api_secret()
        session.commit()
        
        # 使用一个过期的时间戳（6分钟前）
        expired_timestamp = str(int((time.time() - 360) * 1000))
        nonce = 'testnonce123456'
        
        sign_str = f"{normal_user.api_key}{expired_timestamp}{nonce}{normal_user.api_secret}"
        sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()
        
        valid, message = verify_api_sign(
            normal_user.api_key,
            expired_timestamp,
            nonce,
            sign,
            normal_user.api_secret
        )
        
        assert valid is False
        assert '请求已过期' in message

    def test_verify_api_sign_within_tolerance(self, session, normal_user):
        """测试时间戳在容忍范围内"""
        from app.utils.helpers import generate_api_key, generate_api_secret
        normal_user.api_key = generate_api_key()
        normal_user.api_secret = generate_api_secret()
        session.commit()
        
        # 使用4分59秒前的时间戳（在5分钟容忍范围内）
        timestamp = str(int((time.time() - 299) * 1000))
        nonce = 'testnonce123456'
        
        sign_str = f"{normal_user.api_key}{timestamp}{nonce}{normal_user.api_secret}"
        sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest()
        
        valid, message = verify_api_sign(
            normal_user.api_key,
            timestamp,
            nonce,
            sign,
            normal_user.api_secret
        )
        
        assert valid is True


class TestApiKeyGeneration:
    """API密钥生成测试"""

    def test_generate_api_key(self):
        """测试生成API Key"""
        key1 = generate_api_key()
        key2 = generate_api_key()
        
        # 验证长度
        assert len(key1) == 64
        assert len(key2) == 64
        
        # 验证唯一性
        assert key1 != key2
        
        # 验证格式（十六进制）
        assert all(c in '0123456789abcdef' for c in key1)

    def test_generate_api_secret(self):
        """测试生成API Secret"""
        secret1 = generate_api_secret()
        secret2 = generate_api_secret()
        
        # 验证长度
        assert len(secret1) == 64
        assert len(secret2) == 64
        
        # 验证唯一性
        assert secret1 != secret2
        
        # 验证格式（十六进制）
        assert all(c in '0123456789abcdef' for c in secret1)


class TestResponseFormatting:
    """响应格式化测试"""

    def test_success_response_default(self):
        """测试成功响应默认参数"""
        response, status_code = success_response()
        
        assert status_code == 200
        assert response.json['code'] == 200
        assert response.json['message'] == '操作成功'
        assert 'data' not in response.json

    def test_success_response_with_data(self):
        """测试成功响应带数据"""
        data = {'user': 'test', 'id': 123}
        response, status_code = success_response(data=data, message='创建成功', code=201)
        
        assert status_code == 201
        assert response.json['code'] == 201
        assert response.json['message'] == '创建成功'
        assert response.json['data'] == data

    def test_error_response_default(self):
        """测试错误响应默认参数"""
        response, status_code = error_response()
        
        assert status_code == 400
        assert response.json['code'] == 400
        assert response.json['message'] == '操作失败'
        assert 'data' not in response.json

    def test_error_response_with_data(self):
        """测试错误响应带数据"""
        data = {'errors': ['字段1错误', '字段2错误']}
        response, status_code = error_response(
            message='验证失败',
            code=422,
            data=data
        )
        
        assert status_code == 422
        assert response.json['code'] == 422
        assert response.json['message'] == '验证失败'
        assert response.json['data'] == data


class TestUserModel:
    """用户模型测试"""

    def test_set_and_check_password(self, session):
        """测试密码设置和验证"""
        user = User(
            username='pwdtest',
            email='pwdtest@test.com',
            role='user',
            status='active'
        )
        user.set_password('MyPassword123')
        session.add(user)
        session.commit()
        
        # 验证正确密码
        assert user.check_password('MyPassword123') is True
        
        # 验证错误密码
        assert user.check_password('WrongPassword') is False
        assert user.check_password('mypassword123') is False  # 大小写敏感
        assert user.check_password('') is False

    def test_user_roles(self, session):
        """测试用户角色判断"""
        import uuid
        unique_id = str(uuid.uuid4())[:8]
        
        super_admin = User(username=f'sa1_{unique_id}', email=f'sa1_{unique_id}@test.com', role='super_admin')
        super_admin.set_password('password123')
        
        admin = User(username=f'a1_{unique_id}', email=f'a1_{unique_id}@test.com', role='admin')
        admin.set_password('password123')
        
        normal_user = User(username=f'u1_{unique_id}', email=f'u1_{unique_id}@test.com', role='user')
        normal_user.set_password('password123')
        
        session.add_all([super_admin, admin, normal_user])
        session.commit()
        
        # 测试is_super_admin
        assert super_admin.is_super_admin() is True
        assert admin.is_super_admin() is False
        assert normal_user.is_super_admin() is False
        
        # 测试is_admin
        assert super_admin.is_admin() is True
        assert admin.is_admin() is True
        assert normal_user.is_admin() is False

    def test_user_quota_management(self, session):
        """测试用户配额管理"""
        import uuid
        unique_id = str(uuid.uuid4())[:8]
        
        user = User(
            username=f'quotatest_{unique_id}',
            email=f'quota_{unique_id}@test.com',
            role='user',
            status='active',
            daily_quota=100,
            used_quota_today=0
        )
        user.set_password('password123')
        session.add(user)
        session.commit()
        
        # 检查配额
        assert user.check_quota(50) is True
        assert user.check_quota(100) is True
        assert user.check_quota(101) is False
        
        # 使用配额
        user.use_quota(30)
        assert user.used_quota_today == 30
        
        user.use_quota(20)
        assert user.used_quota_today == 50
        
        # 再次检查配额
        assert user.check_quota(50) is True
        assert user.check_quota(51) is False

    def test_user_avatar_url(self, session):
        """测试头像URL获取"""
        import uuid
        unique_id = str(uuid.uuid4())[:8]
        
        # 优先使用QQ头像
        user1 = User(
            username=f'avatar1_{unique_id}',
            email=f'avatar1_{unique_id}@test.com',
            avatar='http://example.com/avatar.jpg',
            qq_avatar='http://q.qlogo.cn/qq.jpg'
        )
        user1.set_password('password123')
        
        # 使用普通头像
        user2 = User(
            username=f'avatar2_{unique_id}',
            email=f'avatar2_{unique_id}@test.com',
            avatar='http://example.com/avatar.jpg'
        )
        user2.set_password('password123')
        
        # 无头像
        user3 = User(
            username=f'avatar3_{unique_id}',
            email=f'avatar3_{unique_id}@test.com'
        )
        user3.set_password('password123')
        
        session.add_all([user1, user2, user3])
        session.commit()
        
        assert user1.get_avatar_url() == 'http://q.qlogo.cn/qq.jpg'
        assert user2.get_avatar_url() == 'http://example.com/avatar.jpg'
        assert user3.get_avatar_url() == ''

    def test_user_to_dict(self, session):
        """测试用户序列化"""
        user = User(
            username='dicttest',
            email='dict@test.com',
            display_name='测试用户',
            role='admin',
            status='active',
            daily_quota=1000,
            phone='13800138000',
            qq_number='123456789'
        )
        user.set_password('password123')
        session.add(user)
        session.commit()
        
        # 不包含敏感信息
        data = user.to_dict()
        assert data['username'] == 'dicttest'
        assert data['email'] == 'dict@test.com'
        assert data['role'] == 'admin'
        assert 'api_key' not in data
        
        # 包含敏感信息
        data_sensitive = user.to_dict(include_sensitive=True)
        assert 'api_key' in data_sensitive