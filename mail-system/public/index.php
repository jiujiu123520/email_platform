<?php
/**
 * 统一入口
 *
 * 路径说明:
 *   /                - 前台首页
 *   /api/...         - API
 *   /{adminPath}/    - 后台管理 (adminPath 默认 admin, 可在后台修改)
 *   /assets/...      - 静态资源
 */

$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$uri = '/' . trim($uri, '/');

// 已安装检测
$installed = file_exists(dirname(__DIR__) . '/storage/installed.lock');
if (!$installed) {
    if (file_exists(dirname(__DIR__) . '/install/install.php')) {
        header('Location: /install/install.php');
        exit;
    }
}

// 加载 .env
$envFile = dirname(__DIR__) . '/.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || strpos($line, '#') === 0) continue;
        if (strpos($line, '=') === false) continue;
        [$k, $v] = explode('=', $line, 2);
        $k = trim($k); $v = trim($v);
        if ((str_starts_with($v, '"') && str_ends_with($v, '"')) ||
            (str_starts_with($v, "'") && str_ends_with($v, "'"))) {
            $v = substr($v, 1, -1);
        }
        putenv("$k=$v");
    }
}

// 读取后台路径
$adminPath = getenv('ADMIN_PATH') ?: 'admin';

// API 路由
if (str_starts_with($uri, '/api/')) {
    require __DIR__ . '/api.php';
    exit;
}

// 后台入口
if (str_starts_with($uri, '/' . $adminPath) || $uri === '/' . $adminPath) {
    $file = __DIR__ . '/admin/index.html';
    if (file_exists($file)) {
        readfile($file);
        exit;
    }
    http_response_code(404);
    echo 'Admin UI not found';
    exit;
}

// 静态资源
$staticFile = __DIR__ . $uri;
if ($uri !== '/' && file_exists($staticFile) && !is_dir($staticFile)) {
    $ext = strtolower(pathinfo($staticFile, PATHINFO_EXTENSION));
    $mimeMap = [
        'css' => 'text/css',
        'js'  => 'application/javascript',
        'json'=> 'application/json',
        'png' => 'image/png',
        'jpg' => 'image/jpeg',
        'jpeg'=> 'image/jpeg',
        'gif' => 'image/gif',
        'svg' => 'image/svg+xml',
        'ico' => 'image/x-icon',
        'woff'=> 'font/woff',
        'woff2'=>'font/woff2',
        'ttf' => 'font/ttf',
        'map' => 'application/json',
        'html'=> 'text/html; charset=utf-8',
        'txt' => 'text/plain; charset=utf-8',
    ];
    $mime = $mimeMap[$ext] ?? 'application/octet-stream';
    header('Content-Type: ' . $mime);
    readfile($staticFile);
    exit;
}

// 前台首页
$file = __DIR__ . '/web/index.html';
if (file_exists($file)) {
    readfile($file);
    exit;
}

http_response_code(404);
echo 'Not Found';
