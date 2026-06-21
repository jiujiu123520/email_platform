<?php
namespace app\controller;

use app\BaseController;

class Group extends BaseController
{
    /**
     * 用户组列表
     */
    public function index()
    {
        $page = $this->request->param('page', 1, 'intval');
        $limit = $this->request->param('limit', 20, 'intval');

        $list = \app\model\UserGroup::page($page, $limit)->select();
        $total = \app\model\UserGroup::count();

        return $this->paginate($list, $total, $page, $limit);
    }

    /**
     * 创建用户组
     */
    public function save()
    {
        $data = $this->request->param();

        if (empty($data['name'])) {
            return $this->error('组名不能为空');
        }

        $group = \app\model\UserGroup::create($data);

        return $this->success(['id' => $group->id], '创建成功');
    }

    /**
     * 用户组详情
     */
    public function read($id)
    {
        $group = \app\model\UserGroup::find($id);
        if (!$group) {
            return $this->error('用户组不存在');
        }

        return $this->success($group);
    }

    /**
     * 更新用户组
     */
    public function update($id)
    {
        $group = \app\model\UserGroup::find($id);
        if (!$group) {
            return $this->error('用户组不存在');
        }

        $data = $this->request->param();
        $group->save($data);

        return $this->success([], '更新成功');
    }

    /**
     * 删除用户组
     */
    public function delete($id)
    {
        $group = \app\model\UserGroup::find($id);
        if (!$group) {
            return $this->error('用户组不存在');
        }

        // 检查是否有用户属于该组
        $userCount = \app\model\User::where('group_id', $id)->where('is_deleted', 0)->count();
        if ($userCount > 0) {
            return $this->error('该组下还有用户，无法删除');
        }

        $group->delete();

        return $this->success([], '删除成功');
    }
}
