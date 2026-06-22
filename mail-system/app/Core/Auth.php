<?php
/**
 * 认证（基于 Session 和 JWT）
 */

namespace MailSystem\Core;

class Auth
{
    private const SESSION_KEY = 'ms_auth_user';
    private const TOKEN_KEY   = 'ms_auth_token';

    /**
     * 登录
     */
    public static function login(string $username, string $password): ?array
    {
        $db = Database::getInstance();
        $user = $db->fetchOne('SELECT * FROM ms_users WHERE username = ? AND status = 1', [$username]);
        if (!$user) return null;
        if (!password_verify($password, $user['password'])) return null;

        // 更新登录信息
        $db->update('ms_users', [
            'last_login_at' => date('Y-m-d H:i:s'),
            'last_login_ip' => (new Request())->ip(),
        ], 'id = :id', ['id' => $user['id']]);

        $_SESSION[self::SESSION_KEY] = $user['id'];
        return $user;
    }

    public static function logout(): void
    {
        unset($_SESSION[self::SESSION_KEY]);
    }

    public static function check(): bool
    {
        return !empty($_SESSION[self::SESSION_KEY]);
    }

    public static function user(): ?array
    {
        if (!self::check()) return null;
        $db = Database::getInstance();
        return $db->fetchOne('SELECT id, username, email, display_name, role, status FROM ms_users WHERE id = ?', [$_SESSION[self::SESSION_KEY]]);
    }

    public static function id(): ?int
    {
        return $_SESSION[self::SESSION_KEY] ?? null;
    }

    public static function isAdmin(): bool
    {
        $u = self::user();
        return $u && $u['role'] === 'admin';
    }

    /**
     * 基于 Token 的 API 认证 (通过 ms_api_keys 表)
     */
    public static function authByApiKey(string $accessKey, string $secretKey): ?array
    {
        $db = Database::getInstance();
        $apiKey = $db->fetchOne(
            'SELECT * FROM ms_api_keys WHERE access_key = ? AND status = 1',
            [$accessKey]
        );
        if (!$apiKey) return null;
        if ($apiKey['expires_at'] && strtotime($apiKey['expires_at']) < time()) return null;
        if (!hash_equals($apiKey['secret_key'], $secretKey)) return null;

        $db->update('ms_api_keys', ['last_used_at' => date('Y-m-d H:i:s')], 'id = :id', ['id' => $apiKey['id']]);

        $user = $db->fetchOne('SELECT * FROM ms_users WHERE id = ?', [$apiKey['user_id']]);
        return $user;
    }

    public static function requireLogin(): void
    {
        if (!self::check()) {
            Response::unauthorized('请先登录');
        }
    }

    public static function requireAdmin(): void
    {
        self::requireLogin();
        if (!self::isAdmin()) {
            Response::forbidden('需要管理员权限');
        }
    }
}
