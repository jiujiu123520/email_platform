<?php
// +----------------------------------------------------------------------
// | ThinkPHP 引导文件
// +----------------------------------------------------------------------

// 定义应用目录
define('APP_PATH', __DIR__ . '/../app/');

// 定义运行时目录
define('RUNTIME_PATH', __DIR__ . '/../runtime/');

// 定义配置文件
define('CONF_PATH', __DIR__ . '/../config/');

// 加载Composer自动加载
require __DIR__ . '/../vendor/autoload.php';

// 执行应用
$http = (new think\App())->run();
$http->send();
