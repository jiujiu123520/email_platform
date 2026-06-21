<?php
namespace app\controller;

use app\BaseController;

class Index extends BaseController
{
    public function index()
    {
        $html = <<<'HTML'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>邮件发送平台</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; }
        .container { background: white; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); width: 100%; max-width: 420px; padding: 40px; text-align: center; }
        .logo h1 { color: #667eea; font-size: 28px; margin-bottom: 8px; }
        .logo p { color: #888; font-size: 14px; margin-bottom: 30px; }
        .btn { display: inline-block; padding: 14px 30px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-decoration: none; border-radius: 10px; font-weight: 600; margin: 10px; transition: transform 0.2s; }
        .btn:hover { transform: translateY(-2px); }
        .version { margin-top: 20px; color: #999; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">
            <h1>邮件发送平台</h1>
            <p>企业级邮件营销解决方案 - PHP Version</p>
        </div>
        <a href="app/view/index.html" class="btn">登录</a>
        <a href="app/view/register.html" class="btn">注册</a>
        <p class="version">v2.0.0 (PHP+ThinkPHP6+SQL Server)</p>
    </div>
</body>
</html>
HTML;
        return response($html, 200, ['Content-Type' => 'text/html; charset=utf-8']);
    }
}
