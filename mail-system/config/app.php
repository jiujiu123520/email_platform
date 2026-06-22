<?php
/**
 * 应用配置
 */

return [
    'app' => [
        'name'     => env('APP_NAME', 'MailSystem'),
        'env'      => env('APP_ENV', 'production'),
        'debug'    => filter_var(env('APP_DEBUG', false), FILTER_VALIDATE_BOOLEAN),
        'url'      => env('APP_URL', 'http://localhost'),
        'timezone' => env('APP_TIMEZONE', 'Asia/Shanghai'),
        'key'      => env('APP_KEY', 'please-change-me'),
        'version'  => '1.0.0',
    ],

    'database' => [
        'host'     => env('DB_HOST', '127.0.0.1'),
        'port'     => (int) env('DB_PORT', 3306),
        'database' => env('DB_DATABASE', 'mail_system'),
        'username' => env('DB_USERNAME', 'root'),
        'password' => env('DB_PASSWORD', ''),
        'charset'  => env('DB_CHARSET', 'utf8mb4'),
    ],

    'admin' => [
        'path' => env('ADMIN_PATH', 'admin'),
        'port' => (int) env('ADMIN_PORT', 8080),
    ],

    'web' => [
        'port' => (int) env('WEB_PORT', 80),
    ],

    'mail' => [
        'hostname'       => env('MAIL_HOSTNAME', 'mail.local'),
        'max_size'       => (int) env('MAX_MAIL_SIZE', 26214400),
        'default_quota'  => (int) env('DEFAULT_QUOTA_MB', 1024),
        'storage_path'   => env('MAIL_STORAGE_PATH', __DIR__ . '/../data/mailboxes'),
        'ssl_cert'       => env('SSL_CERT_PATH', ''),
        'ssl_key'        => env('SSL_KEY_PATH', ''),
        'smtp_banner'    => env('SMTP_BANNER', 'MailSystem ESMTP'),
        'imap_idle_timeout' => (int) env('IMAP_IDLE_TIMEOUT', 1800),
    ],

    'api' => [
        'enabled'    => true,
        'rate_limit' => (int) env('API_RATE_LIMIT', 60),
        'prefix'     => '/api/v1',
    ],

    'log' => [
        'path'  => env('LOG_PATH', __DIR__ . '/../logs'),
        'level' => env('LOG_LEVEL', 'info'),
    ],
];
