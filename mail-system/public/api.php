<?php
/**
 * API 入口 - 处理所有 /api/* 请求
 */

require __DIR__ . '/../app/Core/Bootstrap.php';

use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Core\Router;
use MailSystem\Controllers\AuthController;
use MailSystem\Controllers\DomainController;
use MailSystem\Controllers\MailboxController;
use MailSystem\Controllers\PortController;
use MailSystem\Controllers\EmailController;
use MailSystem\Controllers\ApiKeyController;
use MailSystem\Controllers\SettingController;
use MailSystem\Controllers\UserController;
use MailSystem\Controllers\SystemController;
use MailSystem\Controllers\PublicApiController;
use MailSystem\Controllers\WebmailController;

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

$req = new Request();
$path = $req->path();
$method = $req->method();

// 静态资源请求直接放行 (由 nginx 处理)
if (preg_match('#^/(\.well-known|assets|static|upload|storage|favicon\.ico|robots\.txt)#', $path)) {
    return false;
}

// 安装检测
$installed = file_exists(base_path('storage/installed.lock'));
if (!$installed && !str_starts_with($path, '/install')) {
    if (file_exists(base_path('install/install.php'))) {
        Response::redirect('/install/install.php');
    } else {
        Response::error('系统未安装，请访问 /install/install.php', 503, 503);
    }
}

$router = new Router();

// 公开 API (无需登录)
$router->post('/api/auth/login', [AuthController::class, 'login']);
$router->post('/api/webmail/login', [WebmailController::class, 'login']);
$router->post('/api/webmail/logout', [WebmailController::class, 'logout']);
$router->get('/api/webmail/me', [WebmailController::class, 'me']);
$router->get('/api/setting/public', [SettingController::class, 'public']);
$router->get('/api/setting/admin-path', [SettingController::class, 'getAdminPath']);

// 需登录 API
$router->group('/api', function (Router $r) {
    $r->get('/auth/me', [AuthController::class, 'me']);
    $r->post('/auth/logout', [AuthController::class, 'logout']);
    $r->post('/auth/change-password', [AuthController::class, 'changePassword']);

    $r->get('/domains', [DomainController::class, 'index']);
    $r->get('/domains/{id}', [DomainController::class, 'show']);
    $r->post('/domains', [DomainController::class, 'create']);
    $r->put('/domains/{id}', [DomainController::class, 'update']);
    $r->delete('/domains/{id}', [DomainController::class, 'delete']);
    $r->get('/domains/{id}/dns', [DomainController::class, 'dnsRecords']);

    $r->get('/mailboxes', [MailboxController::class, 'index']);
    $r->get('/mailboxes/{id}', [MailboxController::class, 'show']);
    $r->post('/mailboxes', [MailboxController::class, 'create']);
    $r->put('/mailboxes/{id}', [MailboxController::class, 'update']);
    $r->delete('/mailboxes/{id}', [MailboxController::class, 'delete']);

    $r->get('/ports', [PortController::class, 'index']);
    $r->post('/ports', [PortController::class, 'create']);
    $r->put('/ports/{id}', [PortController::class, 'update']);
    $r->delete('/ports/{id}', [PortController::class, 'delete']);
    $r->post('/ports/{id}/test', [PortController::class, 'test']);

    $r->get('/mailboxes/{id}/emails', [EmailController::class, 'list']);
    $r->post('/emails/send', [EmailController::class, 'send']);
    $r->get('/emails/{id}', [EmailController::class, 'show']);
    $r->delete('/emails/{id}', [EmailController::class, 'delete']);
    $r->post('/emails/{id}/move', [EmailController::class, 'move']);
    $r->post('/emails/{id}/star', [EmailController::class, 'star']);

    $r->get('/api-keys', [ApiKeyController::class, 'index']);
    $r->post('/api-keys', [ApiKeyController::class, 'create']);
    $r->put('/api-keys/{id}', [ApiKeyController::class, 'update']);
    $r->delete('/api-keys/{id}', [ApiKeyController::class, 'delete']);

    $r->get('/settings', [SettingController::class, 'all']);
    $r->post('/settings', [SettingController::class, 'update']);

    $r->get('/users', [UserController::class, 'index']);
    $r->post('/users', [UserController::class, 'create']);
    $r->put('/users/{id}', [UserController::class, 'update']);
    $r->delete('/users/{id}', [UserController::class, 'delete']);
    $r->get('/logs', [UserController::class, 'logs']);

    $r->get('/system/stats', [SystemController::class, 'stats']);
    $r->get('/system/services', [SystemController::class, 'services']);
    $r->get('/system/info', [SystemController::class, 'info']);
});

// 对外 API (v1)
$router->group('/api/v1', function (Router $r) {
    $r->post('/send', [PublicApiController::class, 'send']);
    $r->get('/inbox', [PublicApiController::class, 'inbox']);
    $r->get('/email/{id}', [PublicApiController::class, 'email']);
    $r->get('/mailboxes', [PublicApiController::class, 'mailboxes']);
});

$router->dispatch($req);
