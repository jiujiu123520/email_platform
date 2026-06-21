"""
FAQ路由 - 模块十：常见问题
"""
from flask import Blueprint
from app.utils.helpers import success_response

faq_bp = Blueprint('faq', __name__, url_prefix='/api/v2/faq')


@faq_bp.route('', methods=['GET'])
def get_faq():
    """获取常见问题列表"""
    faqs = [
        {
            'id': 1,
            'question': '邮件发送失败怎么办？',
            'answer': '系统会自动通过其他中继重试发送。如果仍然失败，请检查SMTP中继仪表盘，确认中继状态是否正常。也可以在发送记录中查看具体错误信息。'
        },
        {
            'id': 2,
            'question': '模板变量替换失败怎么办？',
            'answer': '请检查变量名格式是否正确（使用 {变量名} 格式），可在模板预览功能中测试变量替换效果。可用变量包括：{username}、{toEmail}、{sendTime}、{today}、{subject}。'
        },
        {
            'id': 3,
            'question': '移动端看不到菜单怎么办？',
            'answer': '在移动端，菜单默认隐藏。请点击右上角菜单按钮（三击展开）即可显示导航菜单。系统已对移动端进行了表格、弹窗、按钮的拖拽优化。'
        },
        {
            'id': 4,
            'question': 'API调用返回401错误怎么办？',
            'answer': '请检查以下项目：1) API签名是否正确（Sign = MD5(Key + Timestamp + Nonce + Secret)）；2) 时间戳是否在5分钟有效期内；3) IP地址是否在白名单中；4) 账户状态是否正常。'
        },
        {
            'id': 5,
            'question': 'SMTP中继自动停止怎么办？',
            'answer': '当SMTP中继连续发送失败达到5次时，系统会自动暂停该中继。请在修复问题后，到SMTP中继管理页面手动重置健康状态，或进行连接测试。每日零点配额会自动重置。'
        },
        {
            'id': 6,
            'question': '如何使用API发送邮件？',
            'answer': '请参考API完整调用文档。基本步骤：1) 获取API Key和Secret；2) 按照签名算法生成签名；3) 调用 /api/v2/email/send 接口发送邮件。请求需包含 ApiKey、Timestamp、Nonce、Sign 四个认证参数。'
        },
        {
            'id': 7,
            'question': '每日发送配额用完了怎么办？',
            'answer': '每日配额在零点自动重置。如果需要增加配额，请联系管理员调整。您可以在个人中心查看当前配额使用情况。'
        },
        {
            'id': 8,
            'question': '如何切换界面主题？',
            'answer': '系统支持自动主题切换（7:00-19:00为亮色主题，其他时间为暗色主题）。您也可以手动切换主题，设置会保存在本地。'
        },
    ]
    return success_response(faqs)
