<?php

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Domain;

class DomainController extends BaseController
{
    public function index(Request $req): void
    {
        Auth::requireLogin();
        $u = Auth::user();
        $all = ($u['role'] === 'admin') && $req->query('all') == '1';
        $domains = Domain::allByOwner((int) $u['id'], $all);
        $this->ok(['list' => $domains, 'total' => count($domains)]);
    }

    public function show(Request $req, array $params): void
    {
        Auth::requireLogin();
        $d = Domain::find((int) $params['id']);
        if (!$d) Response::notFound('域名不存在');
        $this->ok($d);
    }

    public function create(Request $req): void
    {
        Auth::requireLogin();
        $u = Auth::user();
        $domain = trim(strtolower((string) $req->input('domain')));
        $description = (string) $req->input('description', '');
        if (!preg_match('/^[a-z0-9\-\.]+\.[a-z]{2,}$/i', $domain)) {
            Response::error('域名格式不正确', 400, 400);
        }
        if (Domain::findByName($domain)) {
            Response::error('域名已存在', 400, 400);
        }
        $id = Domain::create([
            'domain'      => $domain,
            'owner_id'    => (int) $u['id'],
            'status'      => 1,
            'description' => $description,
            'is_default'  => 0,
        ]);
        $this->log('domain.create', $domain);
        $this->ok(['id' => $id], '域名已添加');
    }

    public function update(Request $req, array $params): void
    {
        Auth::requireLogin();
        $id = (int) $params['id'];
        $d = Domain::find($id);
        if (!$d) Response::notFound('域名不存在');
        $data = [];
        foreach (['description', 'status', 'is_default'] as $f) {
            if ($req->input($f) !== null) {
                $data[$f] = $req->input($f);
            }
        }
        if (!empty($data)) Domain::update($id, $data);
        $this->log('domain.update', $d['domain']);
        $this->ok(null, '已更新');
    }

    public function delete(Request $req, array $params): void
    {
        Auth::requireAdmin();
        $id = (int) $params['id'];
        $d = Domain::find($id);
        if (!$d) Response::notFound('域名不存在');
        // 检查是否还有邮箱
        $cnt = \MailSystem\Models\Mailbox::countByDomain($id);
        if ($cnt > 0) {
            Response::error('该域名下还有 ' . $cnt . ' 个邮箱，无法删除', 400, 400);
        }
        Domain::delete($id);
        $this->log('domain.delete', $d['domain']);
        $this->ok(null, '已删除');
    }

    public function dnsRecords(Request $req, array $params): void
    {
        Auth::requireLogin();
        $d = Domain::find((int) $params['id']);
        if (!$d) Response::notFound('域名不存在');
        $hostname = config('mail.hostname', 'mail.' . $d['domain']);
        $ip = $req->server['SERVER_ADDR'] ?? ($_SERVER['SERVER_ADDR'] ?? '');
        $this->ok([
            'domain'    => $d['domain'],
            'records'   => [
                ['type' => 'A',     'host' => '@',                'value' => $ip, 'priority' => null, 'note' => 'mail server ip'],
                ['type' => 'A',     'host' => 'mail',             'value' => $ip, 'priority' => null, 'note' => 'mail subdomain'],
                ['type' => 'MX',    'host' => '@',                'value' => $hostname, 'priority' => 10, 'note' => 'mail exchange'],
                ['type' => 'TXT',   'host' => '@',                'value' => 'v=spf1 mx ~all', 'priority' => null, 'note' => 'SPF'],
                ['type' => 'TXT',   'host' => '_dmarc',           'value' => 'v=DMARC1; p=quarantine; rua=mailto:admin@' . $d['domain'], 'priority' => null, 'note' => 'DMARC'],
            ],
        ]);
    }
}
