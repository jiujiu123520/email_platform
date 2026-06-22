<?php

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\MailStorage;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Domain;
use MailSystem\Models\Mailbox;

class MailboxController extends BaseController
{
    public function index(Request $req): void
    {
        Auth::requireLogin();
        $u = Auth::user();
        $all = ($u['role'] === 'admin') && $req->query('all') == '1';
        $list = Mailbox::allByUser((int) $u['id'], $all);
        // 同步使用量
        foreach ($list as &$m) {
            try {
                $storage = new MailStorage($m['full_address']);
                $bytes = $storage->usage();
                $m['used_bytes'] = $bytes;
                $m['used_mb'] = round($bytes / 1024 / 1024, 2);
            } catch (\Throwable $e) {
                $m['used_bytes'] = 0;
                $m['used_mb'] = 0;
            }
        }
        $this->ok(['list' => $list, 'total' => count($list)]);
    }

    public function show(Request $req, array $params): void
    {
        Auth::requireLogin();
        $m = Mailbox::find((int) $params['id']);
        if (!$m) Response::notFound('邮箱不存在');
        $this->ok($m);
    }

    public function create(Request $req): void
    {
        Auth::requireLogin();
        $u = Auth::user();
        $domainId = (int) $req->input('domain_id');
        $localPart = trim(strtolower((string) $req->input('local_part')));
        $password = (string) $req->input('password', '');
        $displayName = (string) $req->input('display_name', '');
        $quotaMb = (int) $req->input('quota_mb', config('mail.default_quota', 1024));

        if (!preg_match('/^[a-z0-9][a-z0-9._-]{0,63}$/i', $localPart)) {
            Response::error('邮箱前缀格式不正确', 400, 400);
        }
        if (strlen($password) < 6) {
            Response::error('密码长度至少 6 位', 400, 400);
        }
        $d = Domain::find($domainId);
        if (!$d) Response::error('域名不存在', 400, 400);

        $full = $localPart . '@' . $d['domain'];
        if (Mailbox::findByAddress($full)) {
            Response::error('该邮箱已存在', 400, 400);
        }

        $id = Mailbox::create([
            'user_id'      => (int) $u['id'],
            'domain_id'    => $domainId,
            'local_part'   => $localPart,
            'full_address' => $full,
            'password'     => password_hash($password, PASSWORD_DEFAULT),
            'display_name' => $displayName,
            'quota_mb'     => $quotaMb,
            'used_mb'      => 0,
            'status'       => 1,
        ]);
        $this->log('mailbox.create', $full);
        $this->ok(['id' => $id, 'full_address' => $full], '邮箱已创建');
    }

    public function update(Request $req, array $params): void
    {
        Auth::requireLogin();
        $id = (int) $params['id'];
        $m = Mailbox::find($id);
        if (!$m) Response::notFound('邮箱不存在');
        $data = [];
        foreach (['display_name', 'quota_mb', 'status'] as $f) {
            if ($req->input($f) !== null) $data[$f] = $req->input($f);
        }
        $newPwd = (string) $req->input('password', '');
        if ($newPwd !== '') {
            if (strlen($newPwd) < 6) Response::error('密码长度至少 6 位', 400, 400);
            $data['password'] = password_hash($newPwd, PASSWORD_DEFAULT);
        }
        if (!empty($data)) Mailbox::update($id, $data);
        $this->log('mailbox.update', $m['full_address']);
        $this->ok(null, '已更新');
    }

    public function delete(Request $req, array $params): void
    {
        Auth::requireLogin();
        $id = (int) $params['id'];
        $m = Mailbox::find($id);
        if (!$m) Response::notFound('邮箱不存在');
        Mailbox::delete($id);
        // 删除目录
        $storage = new MailStorage($m['full_address']);
        if (is_dir($storage->path())) {
            self::rmdirRecursive($storage->path());
        }
        $this->log('mailbox.delete', $m['full_address']);
        $this->ok(null, '已删除');
    }

    private static function rmdirRecursive(string $dir): bool
    {
        if (!is_dir($dir)) return false;
        $items = scandir($dir);
        foreach ($items as $i) {
            if ($i === '.' || $i === '..') continue;
            $p = $dir . '/' . $i;
            if (is_dir($p)) self::rmdirRecursive($p);
            else @unlink($p);
        }
        return @rmdir($dir);
    }
}
