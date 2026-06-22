<?php
/**
 * Webmail 登录 - 邮箱用户登录 (区别于管理员)
 */

namespace MailSystem\Controllers;

use MailSystem\Core\Database;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Mailbox;

class WebmailController extends BaseController
{
    public function login(Request $req): void
    {
        $address = strtolower(trim((string) $req->input('address')));
        $password = (string) $req->input('password');
        if ($address === '' || $password === '') {
            Response::error('请输入邮箱和密码', 400, 400);
        }
        $m = Mailbox::findByAddress($address);
        if (!$m || !password_verify($password, $m['password'])) {
            Response::error('邮箱或密码错误', 401, 401);
        }
        if (!$m['status']) {
            Response::error('该邮箱已禁用', 403, 403);
        }
        // 保存到 session
        if (session_status() === PHP_SESSION_NONE) session_start();
        $_SESSION['ms_webmail_user'] = $m['id'];
        // 更新最后登录
        Database::getInstance()->update('ms_mailboxes', ['last_login_at' => date('Y-m-d H:i:s')], 'id = :id', ['id' => $m['id']]);
        unset($m['password']);
        $this->ok(['mailbox' => $m]);
    }

    public function logout(Request $req): void
    {
        if (session_status() === PHP_SESSION_NONE) session_start();
        unset($_SESSION['ms_webmail_user']);
        $this->ok(null, '已退出');
    }

    public function me(Request $req): void
    {
        if (session_status() === PHP_SESSION_NONE) session_start();
        if (empty($_SESSION['ms_webmail_user'])) {
            Response::unauthorized('未登录');
        }
        $m = Mailbox::find((int) $_SESSION['ms_webmail_user']);
        if (!$m) {
            Response::unauthorized('用户不存在');
        }
        unset($m['password']);
        $this->ok($m);
    }
}
