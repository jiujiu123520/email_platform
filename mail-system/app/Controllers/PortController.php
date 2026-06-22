<?php

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Port;

class PortController extends BaseController
{
    public function index(Request $req): void
    {
        Auth::requireLogin();
        $list = Port::all();
        $this->ok(['list' => $list]);
    }

    public function create(Request $req): void
    {
        Auth::requireAdmin();
        $service = strtolower((string) $req->input('service'));
        $port    = (int) $req->input('port');
        $ssl     = (int) $req->input('ssl', 0);
        $tls     = (int) $req->input('tls', 0);
        $bindIp  = (string) $req->input('bind_ip', '0.0.0.0');
        $desc    = (string) $req->input('description', '');

        if (!in_array($service, ['smtp', 'pop3', 'imap'], true)) {
            Response::error('service 必须为 smtp/pop3/imap', 400, 400);
        }
        if ($port < 1 || $port > 65535) {
            Response::error('端口范围不正确', 400, 400);
        }
        // 验证常见组合
        if ($service === 'smtp') {
            if (!in_array($port, [25, 465, 587, 2525], true)) {
                Response::error('SMTP 端口推荐 25/465/587/2525', 400, 400);
            }
        } elseif ($service === 'pop3') {
            if (!in_array($port, [110, 995], true)) {
                Response::error('POP3 端口推荐 110/995', 400, 400);
            }
        } elseif ($service === 'imap') {
            if (!in_array($port, [143, 993], true)) {
                Response::error('IMAP 端口推荐 143/993', 400, 400);
            }
        }
        // SSL 端口必须是 465/995/993
        if ($ssl && !in_array($port, [465, 995, 993], true)) {
            Response::error('SSL 端口必须为 465/995/993', 400, 400);
        }
        if ($tls && $ssl) {
            Response::error('SSL 与 STARTTLS 不能同时启用', 400, 400);
        }
        // 检查是否占用
        $db = \MailSystem\Core\Database::getInstance();
        $exists = $db->fetchOne('SELECT id FROM ms_ports WHERE service = ? AND port = ? AND ssl = ?', [$service, $port, $ssl]);
        if ($exists) {
            Response::error('该端口已存在', 400, 400);
        }

        $id = Port::create([
            'service'     => $service,
            'port'        => $port,
            'ssl'         => $ssl,
            'tls'         => $tls,
            'bind_ip'     => $bindIp,
            'enabled'     => 1,
            'description' => $desc,
        ]);
        $this->log('port.create', "$service:$port");
        $this->ok(['id' => $id], '端口已添加');
    }

    public function update(Request $req, array $params): void
    {
        Auth::requireAdmin();
        $id = (int) $params['id'];
        $p = Port::find($id);
        if (!$p) Response::notFound('端口不存在');
        $data = [];
        foreach (['enabled', 'bind_ip', 'description', 'ssl', 'tls'] as $f) {
            if ($req->input($f) !== null) $data[$f] = $req->input($f);
        }
        if (!empty($data)) Port::update($id, $data);
        $this->log('port.update', $p['service'] . ':' . $p['port']);
        $this->ok(null, '已更新');
    }

    public function delete(Request $req, array $params): void
    {
        Auth::requireAdmin();
        $id = (int) $params['id'];
        $p = Port::find($id);
        if (!$p) Response::notFound('端口不存在');
        Port::delete($id);
        $this->log('port.delete', $p['service'] . ':' . $p['port']);
        $this->ok(null, '已删除');
    }

    /**
     * 端口测试 - 通过 socket 尝试连接
     */
    public function test(Request $req, array $params): void
    {
        Auth::requireAdmin();
        $id = (int) $params['id'];
        $p = Port::find($id);
        if (!$p) Response::notFound('端口不存在');
        $bindIp = $p['bind_ip'] ?: '127.0.0.1';
        $errno = 0; $errstr = '';
        $sock = @stream_socket_client("tcp://{$bindIp}:{$p['port']}", $errno, $errstr, 3);
        if (!$sock) {
            $this->ok(['success' => false, 'message' => "连接失败: $errstr ($errno)"]);
            return;
        }
        stream_set_timeout($sock, 3);
        $banner = '';
        // 读欢迎语
        $start = microtime(true);
        while (microtime(true) - $start < 3) {
            $r = [$sock]; $w = null; $e = null;
            if (@stream_select($r, $w, $e, 2) > 0) {
                $data = fread($sock, 1024);
                if ($data) { $banner = $data; break; }
            } else break;
        }
        fclose($sock);
        $this->ok(['success' => true, 'banner' => trim($banner), 'port' => $p['port'], 'service' => $p['service']]);
    }
}
