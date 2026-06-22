<?php
/**
 * 自动加载 & 启动器
 */

require __DIR__ . '/../../config/helpers.php';

// 加载 .env
$envFile = base_path('.env');
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || strpos($line, '#') === 0) continue;
        if (strpos($line, '=') === false) continue;
        [$k, $v] = explode('=', $line, 2);
        $k = trim($k);
        $v = trim($v);
        // 去除引号
        if ((str_starts_with($v, '"') && str_ends_with($v, '"')) ||
            (str_starts_with($v, "'") && str_ends_with($v, "'"))) {
            $v = substr($v, 1, -1);
        }
        putenv("$k=$v");
        $_ENV[$k] = $v;
    }
}

date_default_timezone_set(config('app.timezone', 'UTC'));

// 错误处理
if (config('app.debug', false)) {
    error_reporting(E_ALL);
    ini_set('display_errors', '1');
} else {
    error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED);
    ini_set('display_errors', '0');
}

// 自动加载
spl_autoload_register(function ($class) {
    $prefix = 'MailSystem\\';
    if (strpos($class, $prefix) !== 0) return;
    $relative = substr($class, strlen($prefix));
    $file = base_path('app/' . str_replace('\\', '/', $relative) . '.php');
    if (file_exists($file)) require $file;
});

// Composer-free PSR-4 stub: 简化版
if (!function_exists('class_exists') || true) {
    // 引入核心
    foreach (glob(base_path('app/Core/*.php')) as $f) {
        require_once $f;
    }
    foreach (glob(base_path('app/Models/*.php')) as $f) {
        require_once $f;
    }
    foreach (glob(base_path('app/Services/*.php')) as $f) {
        require_once $f;
    }
    foreach (glob(base_path('app/Controllers/*.php')) as $f) {
        require_once $f;
    }
}
