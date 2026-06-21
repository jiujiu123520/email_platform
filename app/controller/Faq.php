<?php
namespace app\controller;

use app\BaseController;

class Faq extends BaseController
{
    /**
     * FAQ列表
     */
    public function index()
    {
        $faqs = [
            ['id' => 1, 'question' => '如何发送邮件？', 'answer' => '通过 POST /api/v2/email/send 接口发送邮件，需要先登录获取 Token。'],
            ['id' => 2, 'question' => '如何获取 API Token？', 'answer' => '通过 POST /api/v2/auth/login 接口登录获取 Token。'],
            ['id' => 3, 'question' => '如何创建邮件模板？', 'answer' => '通过 POST /api/v2/templates 接口创建模板，支持变量替换。'],
            ['id' => 4, 'question' => '如何配置 SMTP 中继？', 'answer' => '通过 POST /api/v2/relays 接口添加 SMTP 中继服务器配置。'],
            ['id' => 5, 'question' => '发送失败怎么办？', 'answer' => '检查 SMTP 中继配置，确保服务器可用，查看审计日志获取详细错误信息。'],
        ];

        return $this->success($faqs);
    }
}
