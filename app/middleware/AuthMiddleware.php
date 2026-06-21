<?php
namespace app\middleware;

use app\model\User;
use think\facade\Cache;

class AuthMiddleware
{
    public function handle($request, \Closure $next)
    {
        $token = $request->header('Authorization', '');
        $token = str_replace('Bearer ', '', $token);

        if (empty($token)) {
            return json(['code' => 401, 'message' => '未授权，请先登录', 'data' => []], 401);
        }

        // 验证 Token
        $cacheKey = 'token:' . md5($token);
        $userId = Cache::get($cacheKey);

        if (!$userId) {
            return json(['code' => 401, 'message' => 'Token 已过期', 'data' => []], 401);
        }

        $user = User::find($userId);
        if (!$user || $user->is_deleted) {
            return json(['code' => 401, 'message' => '用户不存在', 'data' => []], 401);
        }

        // 将用户信息绑定到请求
        $request->userId = $userId;
        $request->user = $user;

        return $next($request);
    }
}
