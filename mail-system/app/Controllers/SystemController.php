<?php

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\Database;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Port;

class SystemController extends BaseController
{
    /**
     * 获取面板统计信息
     */
    public function stats(Request $req): void
    {
        Auth::requireLogin();
        $db = Database::getInstance();
        $stats = [
            'users'    => (int) $db->fetchValue('SELECT COUNT(*) FROM ms_users'),
            'domains'  => (int) $db->fetchValue('SELECT COUNT(*) FROM ms_domains'),
            'mailboxes'=> (int) $db->fetchValue('SELECT COUNT(*) FROM ms_mailboxes'),
            'emails'   => (int) $db->fetchValue('SELECT COUNT(*) FROM ms_emails'),
            'inbox'    => (int) $db->fetchValue("SELECT COUNT(*) FROM ms_emails WHERE folder = 'INBOX'"),
            'sent'     => (int) $db->fetchValue("SELECT COUNT(*) FROM ms_emails WHERE folder = 'SENT'"),
            'unread'   => (int) $db->fetchValue("SELECT COUNT(*) FROM ms_emails WHERE is_read = 0 AND folder = 'INBOX'"),
            'api_keys' => (int) $db->fetchValue('SELECT COUNT(*) FROM ms_api_keys'),
        ];
        $this->ok($stats);
    }

    /**
     * 获取系统服务状态
     */
    public function services(Request $req): void
    {
        Auth::requireLogin();
        $ports = Port::allEnabled();
        $list = [];
        foreach ($ports as $p) {
            $errno = 0; $errstr = '';
            $sock = @stream_socket_client("tcp://127.0.0.1:{$p['port']}", $errno, $errstr, 1);
            $running = $sock !== false;
            if ($sock) fclose($sock);
            $list[] = [
                'id'      => $p['id'],
                'service' => $p['service'],
                'port'    => $p['port'],
                'ssl'     => (bool) $p['ssl'],
                'tls'     => (bool) $p['tls'],
                'running' => $running,
            ];
        }
        $this->ok(['list' => $list]);
    }

    /**
     * 获取 PHP 与系统信息
     */
    public function info(Request $req): void
    {
        Auth::requireAdmin();
        $info = [
            'php_version'   => PHP_VERSION,
            'os'            => PHP_OS,
            'sapi'          => php_sapi_name(),
            'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? '',
            'extensions'    => [
                'pdo_mysql' => extension_loaded('pdo_mysql'),
                'openssl'   => extension_loaded('openssl'),
                'sockets'   => extension_loaded('sockets'),
                'pcntl'     => extension_loaded('pcntl'),
                'mbstring'  => extension_loaded('mbstring'),
                'iconv'     => extension_loaded('iconv'),
                'curl'      => extension_loaded('curl'),
                'zip'       => extension_loaded('zip'),
            ],
            'memory_limit'  => ini_get('memory_limit'),
            'max_execution_time' => ini_get('max_execution_time'),
            'upload_max_filesize' => ini_get('upload_max_filesize'),
            'post_max_size' => ini_get('post_max_size'),
            'timezone'      => date_default_timezone_get(),
            'disk_free'    => disk_free_space(base_path()) ?: 0,
        ];
        $this->ok($info);
    }
}
