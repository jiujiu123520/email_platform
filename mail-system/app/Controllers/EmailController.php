<?php

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\MailStorage;
use MailSystem\Core\MimeParser;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Email;
use MailSystem\Models\Mailbox;

class EmailController extends BaseController
{
    public function list(Request $req, array $params): void
    {
        Auth::requireLogin();
        $mailboxId = (int) $params['id'];
        $m = Mailbox::find($mailboxId);
        if (!$m) Response::notFound('邮箱不存在');
        $folder = $req->query('folder', 'INBOX');
        $limit = max(1, min(200, (int) $req->query('limit', 50)));
        $offset = max(0, (int) $req->query('offset', 0));
        $kw = (string) $req->query('keyword', '');

        $list = Email::listByMailbox($mailboxId, $folder, $limit, $offset, $kw);
        $total = Email::countByMailbox($mailboxId, $folder, $kw);
        $this->ok(['list' => $list, 'total' => $total, 'limit' => $limit, 'offset' => $offset]);
    }

    public function show(Request $req, array $params): void
    {
        Auth::requireLogin();
        $id = (int) $params['id'];
        $e = Email::find($id);
        if (!$e) Response::notFound('邮件不存在');
        $mailbox = Mailbox::find($e['mailbox_id']);
        // 权限：邮箱所有者或管理员
        $u = Auth::user();
        if ($mailbox['user_id'] != $u['id'] && $u['role'] !== 'admin') {
            Response::forbidden('无权访问');
        }
        // 标记已读
        if (!$e['is_read']) {
            Email::update($id, ['is_read' => 1]);
            $e['is_read'] = 1;
        }
        // 解析 headers
        if (!empty($e['headers'])) {
            $e['headers'] = json_decode($e['headers'], true);
        }
        $this->ok($e);
    }

    public function send(Request $req): void
    {
        Auth::requireLogin();
        $fromMailboxId = (int) $req->input('from_mailbox_id');
        $to = (array) $req->input('to', []);
        $cc = (array) $req->input('cc', []);
        $bcc = (array) $req->input('bcc', []);
        $subject = (string) $req->input('subject', '');
        $bodyText = (string) $req->input('body_text', '');
        $bodyHtml = (string) $req->input('body_html', '');

        if (empty($to)) Response::error('收件人不能为空', 400, 400);
        $m = Mailbox::find($fromMailboxId);
        if (!$m) Response::error('发件邮箱不存在', 400, 400);

        // 权限
        $u = Auth::user();
        if ($m['user_id'] != $u['id'] && $u['role'] !== 'admin') {
            Response::forbidden('无权使用该邮箱');
        }

        $from = ['name' => $m['display_name'] ?: $m['local_part'], 'address' => $m['full_address']];
        $raw = MimeParser::build([
            'from'     => $from,
            'to'       => $to,
            'cc'       => $cc,
            'bcc'      => $bcc,
            'subject'  => $subject,
            'body_text'=> $bodyText,
            'body_html'=> $bodyHtml,
            'headers'  => ['hostname' => config('mail.hostname', 'localhost')],
        ]);

        // 投递到 SENT
        try {
            $storage = new MailStorage($m['full_address']);
            $storage->append($raw, 'SENT');
        } catch (\Throwable $e) {
            Response::error('写入发件箱失败: ' . $e->getMessage(), 500, 500);
        }

        $messageId = '';
        if (preg_match('/^Message-ID:\s*<?([^>\s]+)/mi', $raw, $mm)) $messageId = $mm[1];

        $emailId = Email::create([
            'mailbox_id'   => $m['id'],
            'message_id'   => $messageId,
            'from_address' => $m['full_address'],
            'from_name'    => $from['name'],
            'to_addresses' => implode(', ', array_map(fn($a) => is_array($a) ? $a['address'] : $a, $to)),
            'cc_addresses' => implode(', ', array_map(fn($a) => is_array($a) ? $a['address'] : $a, $cc)),
            'bcc_addresses'=> implode(', ', array_map(fn($a) => is_array($a) ? $a['address'] : $a, $bcc)),
            'subject'      => $subject,
            'body_text'    => $bodyText,
            'body_html'    => $bodyHtml,
            'size_bytes'   => strlen($raw),
            'folder'       => 'SENT',
            'direction'    => 'out',
            'status'       => 'sent',
        ]);

        // 投递给收件人
        $fail = [];
        foreach (array_merge($to, $cc, $bcc) as $addr) {
            $target = is_array($addr) ? $addr['address'] : $addr;
            $t = Mailbox::findByAddress($target);
            if (!$t) { $fail[] = $target; continue; }
            try {
                $st = new MailStorage($t['full_address']);
                $st->deliver($raw);
                Email::create([
                    'mailbox_id'   => $t['id'],
                    'message_id'   => $messageId,
                    'from_address' => $m['full_address'],
                    'from_name'    => $from['name'],
                    'to_addresses' => $target,
                    'subject'      => $subject,
                    'body_text'    => $bodyText,
                    'body_html'    => $bodyHtml,
                    'size_bytes'   => strlen($raw),
                    'folder'       => 'INBOX',
                    'direction'    => 'in',
                    'status'       => 'received',
                ]);
            } catch (\Throwable $e) {
                $fail[] = $target;
            }
        }

        $this->log('email.send', $m['full_address'], $subject);
        $this->ok(['id' => $emailId, 'failed' => $fail], $fail ? '已发送（部分收件人不存在）' : '发送成功');
    }

    public function delete(Request $req, array $params): void
    {
        Auth::requireLogin();
        $id = (int) $params['id'];
        $e = Email::find($id);
        if (!$e) Response::notFound('邮件不存在');
        $m = Mailbox::find($e['mailbox_id']);
        $u = Auth::user();
        if ($m['user_id'] != $u['id'] && $u['role'] !== 'admin') {
            Response::forbidden('无权操作');
        }
        // 标记为已删除 (TRASH) 或彻底删除
        $permanent = $req->query('permanent') == '1';
        if ($permanent) {
            Email::delete($id);
            // 删除文件
            if ($m) {
                $storage = new MailStorage($m['full_address']);
                $files = $storage->listFolder($e['folder']);
                foreach ($files as $f) {
                    if (strpos($f['filename'], substr(md5($e['message_id'] ?: ''), 0, 8)) !== false) {
                        $storage->delete($f['path']);
                    }
                }
            }
        } else {
            Email::update($id, ['folder' => 'TRASH']);
        }
        $this->log('email.delete', $e['subject'] ?? '');
        $this->ok(null, '已删除');
    }

    public function move(Request $req, array $params): void
    {
        Auth::requireLogin();
        $id = (int) $params['id'];
        $folder = strtoupper((string) $req->input('folder', 'INBOX'));
        $e = Email::find($id);
        if (!$e) Response::notFound('邮件不存在');
        $m = Mailbox::find($e['mailbox_id']);
        $u = Auth::user();
        if ($m['user_id'] != $u['id'] && $u['role'] !== 'admin') {
            Response::forbidden('无权操作');
        }
        Email::update($id, ['folder' => $folder]);
        $this->ok(null, '已移动');
    }

    public function star(Request $req, array $params): void
    {
        Auth::requireLogin();
        $id = (int) $params['id'];
        $star = (int) $req->input('starred', 1);
        $e = Email::find($id);
        if (!$e) Response::notFound('邮件不存在');
        Email::update($id, ['is_starred' => $star ? 1 : 0]);
        $this->ok(null, '已操作');
    }
}
