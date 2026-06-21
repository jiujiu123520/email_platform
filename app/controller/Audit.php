<?php
namespace app\controller;

use app\BaseController;
use app\model\AuditLog;

class Audit extends BaseController
{
    /**
     * 审计日志列表
     */
    public function logs()
    {
        $page = $this->request->param('page', 1, 'intval');
        $limit = $this->request->param('limit', 20, 'intval');
        $action = $this->request->param('action', '');

        $where = [];
        if ($action) {
            $where[] = ['action', '=', $action];
        }

        // 管理员可以看所有日志，普通用户只能看自己的
        $user = $this->request->user;
        if ($user->role !== 'super_admin') {
            $where[] = ['user_id', '=', $user->id];
        }

        $list = AuditLog::where($where)
            ->page($page, $limit)
            ->order('created_at', 'desc')
            ->select();
        $total = AuditLog::where($where)->count();

        return $this->paginate($list, $total, $page, $limit);
    }
}
