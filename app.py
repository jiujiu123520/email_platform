"""
邮件发送平台 - 根目录入口文件
用于直接运行 python app.py
"""
import os
from app.app import create_app, init_db

# 创建应用实例
app = create_app(os.environ.get('FLASK_ENV', 'development'))

if __name__ == '__main__':
    with app.app_context():
        init_db(app)
    app.run(host='0.0.0.0', port=5000, debug=True)
