<?php
/**
 * 对外 API (v1) - 第三方对接
 *
 * 所有 API 都需要 API Key 认证
 * Header:
 *   X-Access-Key: ak_xxxx
 *   X-Secret-Key: sk_xxxx
 *
 * 或
 *   Authorization: Bearer ak_xxxx:sk_xxxx
 */

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\Database;
use MailSystem\Core\MimeParser;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\ApiKey;
use MailSystem\Models\Email;
use MailSystem\Models\Mailbox;
use MailSystem\Models\Setting;

class PublicApiController extends BaseController
{
    public function __construct()
    {
        if (!Setting::get('api_enabled', '1')) {
            Response::error('API 已关闭', 503, 503);
        }
        $this->authenticate();
    }

    private function authenticate(): void
    {
        $req = new Request();
        $accessKey = $req->header('x-access-key');
        $secretKey = $req->header('x-secret-key');

        if (!$accessKey) {
            $auth = $req->header('authorization', '');
            if (stripos($auth, 'Bearer ') === 0) {
                $token = substr($auth, 7);
                if (strpos($token, ':') !== false) {
                    [$accessKey, $secretKey] = explode(':', $token, 2);
                }
            }
        }
        if (!$accessKey || !$secretKey) {
            Response::unauthorized('缺少 API Key');
        }
        $apiKey = ApiKey::findByAccessKey($accessKey);
        if (!$apiKey) Response::unauthorized('无效的 Access Key');
        if (!$apiKey['status']) Response::unauthorized('API Key 已禁用');
        if ($apiKey['expires_at'] && strtotime($apiKey['expires_at']) < time()) {
            Response::unauthorized('API Key 已过期');
        }
        if (!password_verify($secretKey, $apiKey['secret_key'])) {
            Response::unauthorized('无效的 Secret Key');
        }
        // 保存到全局
        $GLOBALS['__api_user_id'] = (int) $apiKey['user_id'];
        $GLOBALS['__api_key_id']  = (int) $apiKey['id'];
        $GLOBALS['__api_perms']   = explode(',', $apiKey['permissions']);

        // 记录使用
        Database::getInstance()->update('ms_api_keys', ['last_used_at' => date('Y-m-d H:i:s')], 'id = :id', ['id' => $apiKey['id']]);
    }

    private function requirePerm(string $p): void
    {
        if (!in_array($p, $GLOBALS['__api_perms'] ?? [], true) && !in_array('*', $GLOBALS['__api_perms'] ?? [], true)) {
            Response::forbidden("权限不足，需要 {$p}");
        }
    }

    /**
     * POST /api/v1/send
     * body: { from, to, subject, body_text, body_html, cc, bcc }
     */
    public function send(Request $req): void
    {
        $this->requirePerm('send');
        $from = (string) $req->input('from');
        $to   = (array) $req->input('to', []);
        $cc   = (array) $req->input('cc', []);
        $bcc  = (array) $req->input('bcc', []);
        $subject  = (string) $req->input('subject', '');
        $bodyText = (string) $req->input('body_text', '');
        $bodyHtml = (string) $req->input('body_html', '');

        if ($from === '' || empty($to)) {
            Response::error('from 和 to 必填', 400, 400);
        }
        $m = Mailbox::findByAddress($from);
        if (!$m) Response::error('发件人不存在', 400, 400);
        if ($m['user_id'] != ($GLOBALS['__api_user_id'] ?? 0)) {
            Response::forbidden('无权使用该发件人');
        }

        $raw = MimeParser::build([
            'from'     => ['name' => $m['display_name'] ?: $m['local_part'], 'address' => $m['full_address']],
            'to'       => $to,
            'cc'       => $cc,
            'bcc'      => $bcc,
            'subject'  => $subject,
            'body_text'=> $bodyText,
            'body_html'=> $bodyHtml,
            'headers'  => ['hostname' => config('mail.hostname', 'localhost')],
        ]);

        $messageId = '';
        if (preg_match('/^Message-ID:\s*<?([^>\s]+)/mi', $raw, $mm)) $messageId = $mm[1];

        $emailId = Email::create([
            'mailbox_id'   => $m['id'],
            'message_id'   => $messageId,
            'from_address' => $m['full_address'],
            'from_name'    => $m['display_name'] ?: $m['local_part'],
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

        // 投递
        $delivered = 0; $failed = [];
        foreach (array_merge($to, $cc, $bcc) as $addr) {
            $a = is_array($addr) ? $addr['address'] : $addr;
            $t = Mailbox::findByAddress($a);
            if (!$t) { $failed[] = $a; continue; }
            try {
                $st = new \MailSystem\Core\MailStorage($t['full_address']);
                $st->deliver($raw);
                Email::create([
                    'mailbox_id'   => $t['id'],
                    'message_id'   => $messageId,
                    'from_address' => $m['full_address'],
                    'from_name'    => $m['display_name'] ?: $m['local_part'],
                    'to_addresses' => $a,
                    'subject'      => $subject,
                    'body_text'    => $bodyText,
                    'body_html'    => $bodyHtml,
                    'size_bytes'   => strlen($raw),
                    'folder'       => 'INBOX',
                    'direction'    => 'in',
                    'status'       => 'received',
                ]);
                $delivered++;
            } catch (\Throwable $e) {
                $failed[] = $a;
            }
        }

        $this->ok([
            'id'        => $emailId,
            'message_id'=> $messageId,
            'delivered' => $delivered,
            'failed'    => $failed,
        ], '已发送');
    }

    /**
     * GET /api/v1/inbox?mailbox=&folder=INBOX&limit=20&offset=0
     */
    public function inbox(Request $req): void
    {
        $this->requirePerm('read');
        $mailboxAddr = $req->query('mailbox', '');
        $folder = $req->query('folder', 'INBOX');
        $limit  = max(1, min(200, (int) $req->query('limit', 20)));
        $offset = max(0, (int) $req->query('offset', 0));

        $m = Mailbox::findByAddress($mailboxAddr);
        if (!$m) Response::error('邮箱不存在', 400, 400);
        if ($m['user_id'] != ($GLOBALS['__api_user_id'] ?? 0)) {
            Response::forbidden('无权访问');
        }
        $list = Email::listByMailbox($m['id'], $folder, $limit, $offset);
        $total = Email::countByMailbox($m['id'], $folder);
        $this->ok(['list' => $list, 'total' => $total, 'limit' => $limit, 'offset' => $offset]);
    }

    /**
     * GET /api/v1/email/{id}
     */
    public function email(Request $req, array $params): void
    {
        $this->requirePerm('read');
        $id = (int) $params['id'];
        $e = Email::find($id);
        if (!$e) Response::notFound('邮件不存在');
        $m = Mailbox::find($e['mailbox_id']);
        if ($m['user_id'] != ($GLOBALS['__api_user_id'] ?? 0)) {
            Response::forbidden('无权访问');
        }
        if (!empty($e['headers'])) {
            $e['headers'] = json_decode($e['headers'], true);
        }
        $this->ok($e);
    }

    /**
     * GET /api/v1/mailboxes
     */
    public function mailboxes(Request $req): void
    {
        $this->requirePerm('read');
        $list = Mailbox::allByUser((int) ($GLOBALS['__api_user_id'] ?? 0));
        $this->ok(['list' => $list]);
    }
}
