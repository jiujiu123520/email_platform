<?php
namespace app\controller;

use app\BaseController;
use app\model\SmtpRelay;
use app\model\AuditLog;

class Relay extends BaseController
{
    /**
     * 中继列表
     */
    public function index()
    {
        $page = $this->request->param('page', 1, 'intval');
        $limit = $this->request->param('limit', 20, 'intval');

        $list = SmtpRelay::where('is_deleted', 0)
            ->page($page, $limit)
            ->order('priority', 'desc')
            ->select();
        $total = SmtpRelay::where('is_deleted', 0)->count();

        return $this->paginate($list, $total, $page, $limit);
    }

    /**
     * 创建中继
     */
    public function save()
    {
        $data = $this->request->param();

        // 验证
        if (empty($data['name']) || empty($data['host']) || empty($data['username']) || empty($data['password'])) {
            return $this->error('名称、主机、用户名、密码不能为空');
        }

        $relay = SmtpRelay::create($data);

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'relay_create',
            'details' => json_encode(['relay_id' => $relay->id]),
        ]);

        return $this->success(['id' => $relay->id], '创建成功');
    }

    /**
     * 中继详情
     */
    public function read($id)
    {
        $relay = SmtpRelay::find($id);
        if (!$relay || $relay->is_deleted) {
            return $this->error('中继不存在');
        }

        return $this->success($relay);
    }

    /**
     * 更新中继
     */
    public function update($id)
    {
        $relay = SmtpRelay::find($id);
        if (!$relay || $relay->is_deleted) {
            return $this->error('中继不存在');
        }

        $data = $this->request->param();

        // 如果更新密码
        if (isset($data['password']) && !empty($data['password'])) {
            $relay->password = $data['password'];
        }

        $relay->save($data);

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'relay_update',
            'details' => json_encode(['relay_id' => $id]),
        ]);

        return $this->success([], '更新成功');
    }

    /**
     * 删除中继
     */
    public function delete($id)
    {
        $relay = SmtpRelay::find($id);
        if (!$relay || $relay->is_deleted) {
            return $this->error('中继不存在');
        }

        $relay->deleted_at = date('Y-m-d H:i:s');
        $relay->is_deleted = 1;
        $relay->save();

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'relay_delete',
            'details' => json_encode(['relay_id' => $id]),
        ]);

        return $this->success([], '删除成功');
    }
}
