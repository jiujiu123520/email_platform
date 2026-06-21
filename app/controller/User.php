<?php
namespace app\controller;

use app\BaseController;
use app\model\User;
use app\model\AuditLog;

class UserController extends BaseController
{
    /**
     * 用户列表
     */
    public function index()
    {
        $page = $this->request->param('page', 1, 'intval');
        $limit = $this->request->param('limit', 20, 'intval');
        $keyword = $this->request->param('keyword', '');

        $where = [['is_deleted', '=', 0]];
        if ($keyword) {
            $where[] = ['username|display_name|email', 'like', "%{$keyword}%"];
        }

        $list = User::where($where)
            ->page($page, $limit)
            ->select();
        $total = User::where($where)->count();

        return $this->paginate($list, $total, $page, $limit);
    }

    /**
     * 创建用户
     */
    public function save()
    {
        $data = $this->request->param();

        // 验证
        if (empty($data['username']) || empty($data['password'])) {
            return $this->error('用户名和密码不能为空');
        }

        // 检查用户名
        if (User::where('username', $data['username'])->find()) {
            return $this->error('用户名已存在');
        }

        $user = User::create($data);

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'user_create',
            'details' => json_encode(['user_id' => $user->id]),
        ]);

        return $this->success(['id' => $user->id], '创建成功');
    }

    /**
     * 用户详情
     */
    public function read($id)
    {
        $user = User::find($id);
        if (!$user || $user->is_deleted) {
            return $this->error('用户不存在');
        }

        return $this->success($user);
    }

    /**
     * 更新用户
     */
    public function update($id)
    {
        $user = User::find($id);
        if (!$user || $user->is_deleted) {
            return $this->error('用户不存在');
        }

        $data = $this->request->param();

        // 如果更新密码
        if (isset($data['password']) && !empty($data['password'])) {
            $user->password = $data['password'];
        }

        $user->save($data);

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'user_update',
            'details' => json_encode(['user_id' => $id]),
        ]);

        return $this->success([], '更新成功');
    }

    /**
     * 删除用户
     */
    public function delete($id)
    {
        $user = User::find($id);
        if (!$user || $user->is_deleted) {
            return $this->error('用户不存在');
        }

        $user->deleted_at = date('Y-m-d H:i:s');
        $user->is_deleted = 1;
        $user->save();

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'user_delete',
            'details' => json_encode(['user_id' => $id]),
        ]);

        return $this->success([], '删除成功');
    }
}
