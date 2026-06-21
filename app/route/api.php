<?php
// +----------------------------------------------------------------------
// | 路由配置
// +----------------------------------------------------------------------

use think\facade\Route;

// 首页
Route::get('/', 'index/index');

// API v2 路由组
Route::group('api/v2', function () {
    // 认证（不需要登录）
    Route::post('auth/login', 'auth/login');
    Route::post('auth/register', 'auth/register');
    Route::post('auth/logout', 'auth/logout')->middleware(\app\middleware\AuthMiddleware::class);
    Route::get('auth/me', 'auth/me')->middleware(\app\middleware\AuthMiddleware::class);

    // 用户管理
    Route::get('users', 'user/index')->middleware(\app\middleware\AuthMiddleware::class);
    Route::post('users', 'user/save')->middleware(\app\middleware\AuthMiddleware::class);
    Route::get('users/:id', 'user/read')->middleware(\app\middleware\AuthMiddleware::class);
    Route::put('users/:id', 'user/update')->middleware(\app\middleware\AuthMiddleware::class);
    Route::delete('users/:id', 'user/delete')->middleware(\app\middleware\AuthMiddleware::class);

    // 用户组
    Route::get('groups', 'group/index')->middleware(\app\middleware\AuthMiddleware::class);
    Route::post('groups', 'group/save')->middleware(\app\middleware\AuthMiddleware::class);
    Route::get('groups/:id', 'group/read')->middleware(\app\middleware\AuthMiddleware::class);
    Route::put('groups/:id', 'group/update')->middleware(\app\middleware\AuthMiddleware::class);
    Route::delete('groups/:id', 'group/delete')->middleware(\app\middleware\AuthMiddleware::class);

    // 邮件模板
    Route::get('templates', 'template/index')->middleware(\app\middleware\AuthMiddleware::class);
    Route::post('templates', 'template/save')->middleware(\app\middleware\AuthMiddleware::class);
    Route::get('templates/:id', 'template/read')->middleware(\app\middleware\AuthMiddleware::class);
    Route::put('templates/:id', 'template/update')->middleware(\app\middleware\AuthMiddleware::class);
    Route::delete('templates/:id', 'template/delete')->middleware(\app\middleware\AuthMiddleware::class);

    // 邮件发送
    Route::post('email/send', 'email/send')->middleware(\app\middleware\AuthMiddleware::class);
    Route::post('email/batch', 'email/batch')->middleware(\app\middleware\AuthMiddleware::class);
    Route::get('email/records', 'email/records')->middleware(\app\middleware\AuthMiddleware::class);
    Route::get('email/records/:id', 'email/record')->middleware(\app\middleware\AuthMiddleware::class);

    // SMTP中继
    Route::get('relays', 'relay/index')->middleware(\app\middleware\AuthMiddleware::class);
    Route::post('relays', 'relay/save')->middleware(\app\middleware\AuthMiddleware::class);
    Route::get('relays/:id', 'relay/read')->middleware(\app\middleware\AuthMiddleware::class);
    Route::put('relays/:id', 'relay/update')->middleware(\app\middleware\AuthMiddleware::class);
    Route::delete('relays/:id', 'relay/delete')->middleware(\app\middleware\AuthMiddleware::class);

    // 审计日志
    Route::get('audit/logs', 'audit/logs')->middleware(\app\middleware\AuthMiddleware::class);

    // API配置
    Route::get('api/config', 'apiconfig/index')->middleware(\app\middleware\AuthMiddleware::class);
    Route::post('api/config', 'apiconfig/save')->middleware(\app\middleware\AuthMiddleware::class);

    // 个人中心
    Route::get('profile', 'profile/index')->middleware(\app\middleware\AuthMiddleware::class);
    Route::put('profile', 'profile/update')->middleware(\app\middleware\AuthMiddleware::class);

    // FAQ
    Route::get('faq', 'faq/index')->middleware(\app\middleware\AuthMiddleware::class);
});
