<?php
/**
 * 认证控制器
 */

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\Request;
use MailSystem\Core\Response;

class AuthController extends BaseController
{
    public function login(Request $req): void
    {
        $username = trim((string) $req->input('username'));
        $password = (string) $req->input('password');
        if ($username === '' || $password === '') {
            Response::error('请输入用户名和密码', 400, 400);
        }
        $user = Auth::login($username, $password);
        if (!$user) {
            Response::error('用户名或密码错误', 401, 401);
        }
        $this->log('login', $user['username'], 'login success');
        unset($user['password']);
        $this->ok([
            'user' => $user,
            'token' => self::issueToken($user),
        ]);
    }

    public function logout(Request $req): void
    {
        Auth::logout();
        $this->ok(null, '已退出登录');
    }

    public function me(Request $req): void
    {
        Auth::requireLogin();
        $user = Auth::user();
        $this->ok($user);
    }

    public function changePassword(Request $req): void
    {
        Auth::requireLogin();
        $old = (string) $req->input('old_password');
        $new = (string) $req->input('new_password');
        if (strlen($new) < 6) {
            Response::error('新密码长度至少 6 位', 400, 400);
        }
        $u = \MailSystem\Models\User::find(Auth::id());
        if (!$u || !password_verify($old, $u['password'])) {
            Response::error('原密码错误', 400, 400);
        }
        \MailSystem\Models\User::update(Auth::id(), [
            'password' => password_hash($new, PASSWORD_DEFAULT),
        ]);
        $this->ok(null, '密码已更新');
    }

    /**
     * 简单 Token (HMAC), 避免引入 JWT 库
     */
    public static function issueToken(array $user): string
    {
        $payload = [
            'uid'      => $user['id'],
            'username' => $user['username'],
            'role'     => $user['role'],
            'exp'      => time() + 86400 * 7,
        ];
        $key = config('app.key', 'default');
        $json = json_encode($payload);
        $b64 = rtrim(strtr(base64_encode($json), '+/', '-_'), '=');
        $sig = rtrim(strtr(base64_encode(hash_hmac('sha256', $b64, $key, true)), '+/', '-_'), '=');
        return $b64 . '.' . $sig;
    }

    public static function verifyToken(string $token): ?array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 2) return null;
        [$b64, $sig] = $parts;
        $key = config('app.key', 'default');
        $expect = rtrim(strtr(base64_encode(hash_hmac('sha256', $b64, $key, true)), '+/', '-_'), '=');
        if (!hash_equals($expect, $sig)) return null;
        $json = base64_decode(strtr($b64, '-_', '+/'), true);
        if (!$json) return null;
        $payload = json_decode($json, true);
        if (!$payload) return null;
        if ($payload['exp'] < time()) return null;
        return $payload;
    }
}
