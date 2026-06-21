<?php
namespace app\controller;

use app\BaseController;
use app\model\User;
use app\model\AuditLog;
use think\facade\Cache;
use think\facade\Env;

class Auth extends BaseController
{
    /**
     * 用户登录
     */
    public function login()
    {
        $username = $this->request->param('username', '');
        $password = $this->request->param('password', '');

        if (empty($username) || empty($password)) {
            return $this->error('用户名和密码不能为空');
        }

        $user = User::where('username', $username)
            ->where('is_deleted', 0)
            ->find();

        if (!$user || !$user->checkPassword($password)) {
            // 记录登录失败
            AuditLog::create([
                'user_id' => 0,
                'action' => 'login_failed',
                'ip' => $this->request->ip(),
                'user_agent' => $this->request->header('user-agent', ''),
                'details' => json_encode(['username' => $username]),
            ]);
            return $this->error('用户名或密码错误');
        }

        // 生成 Token
        $token = bin2hex(random_bytes(32));
        $cacheKey = 'token:' . md5($token);
        $expire = Env::get('JWT_EXPIRE', 7200); // 2小时

        Cache::set($cacheKey, $user->id, $expire);

        // 记录登录成功
        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'login',
            'ip' => $this->request->ip(),
            'user_agent' => $this->request->header('user-agent', ''),
            'details' => json_encode(['username' => $username]),
        ]);

        return $this->success([
            'token' => $token,
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'email' => $user->email,
                'role' => $user->role,
                'display_name' => $user->display_name,
            ],
        ], '登录成功');
    }

    /**
     * 用户注册
     */
    public function register()
    {
        $username = $this->request->param('username', '');
        $password = $this->request->param('password', '');
        $email = $this->request->param('email', '');
        $displayName = $this->request->param('display_name', $username);

        if (empty($username) || empty($password) || empty($email)) {
            return $this->error('用户名、密码、邮箱不能为空');
        }

        // 检查用户名是否存在
        if (User::where('username', $username)->find()) {
            return $this->error('用户名已存在');
        }

        // 检查邮箱是否存在
        if (User::where('email', $email)->find()) {
            return $this->error('邮箱已被使用');
        }

        $user = User::create([
            'username' => $username,
            'password' => $password,
            'email' => $email,
            'display_name' => $displayName,
            'role' => 'user',
            'daily_quota' => 100,
            'used_quota' => 0,
            'total_sent' => 0,
        ]);

        return $this->success([
            'id' => $user->id,
            'username' => $user->username,
        ], '注册成功');
    }

    /**
     * 登出
     */
    public function logout()
    {
        $token = $this->request->header('Authorization', '');
        $token = str_replace('Bearer ', '', $token);

        if ($token) {
            $cacheKey = 'token:' . md5($token);
            Cache::delete($cacheKey);
        }

        return $this->success([], '登出成功');
    }

    /**
     * 获取当前用户信息
     */
    public function me()
    {
        $user = $this->request->user;

        return $this->success([
            'id' => $user->id,
            'username' => $user->username,
            'email' => $user->email,
            'display_name' => $user->display_name,
            'role' => $user->role,
            'daily_quota' => $user->daily_quota,
            'used_quota' => $user->used_quota,
            'group_id' => $user->group_id,
        ]);
    }
}
