<?php
namespace app\controller;

use app\BaseController;
use app\model\User;
use app\model\AuditLog;

class Profile extends BaseController
{
    /**
     * 个人中心 - 获取信息
     */
    public function index()
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
            'total_sent' => $user->total_sent,
            'group_id' => $user->group_id,
        ]);
    }

    /**
     * 更新个人信息
     */
    public function update()
    {
        $user = $this->request->user;
        $data = $this->request->param();

        // 只允许更新部分字段
        $allowedFields = ['display_name', 'email'];
        $updateData = array_intersect_key($data, array_flip($allowedFields));

        // 如果要更新密码
        if (!empty($data['old_password']) && !empty($data['new_password'])) {
            if (!$user->checkPassword($data['old_password'])) {
                return $this->error('原密码错误');
            }
            $updateData['password'] = $data['new_password'];
        }

        if (!empty($updateData)) {
            $user->save($updateData);
        }

        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'profile_update',
            'details' => json_encode(['updated_fields' => array_keys($updateData)]),
        ]);

        return $this->success([], '更新成功');
    }
}
