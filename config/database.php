<?php
// +----------------------------------------------------------------------
// | 数据库配置
// +----------------------------------------------------------------------

use think\facade\Env;

return [
    // 默认连接
    'default' => 'sqlsrv',

    // 数据库连接配置
    'connections' => [
        'sqlsrv' => [
            'type'            => 'sqlsrv',
            'hostname'        => Env::get('DB_HOST', '127.0.0.1'),
            'database'        => Env::get('DB_DATABASE', 'email_platform'),
            'username'        => Env::get('DB_USERNAME', 'sa'),
            'password'        => Env::get('DB_PASSWORD', ''),
            'hostport'        => Env::get('DB_PORT', '1433'),
            'charset'         => 'utf8',
            'prefix'          => '',
            'deploy'          => 0,
            'rw_separate'     => false,
            'master_num'      => 1,
            'slave_no'        => '',
            'fields_strict'   => true,
            'resultset_type'  => 'array',
            'auto_timestamp'  => false,
            'datetime_format' => 'Y-m-d H:i:s',
            'sqlexplain'      => false,
        ],
    ],
];
