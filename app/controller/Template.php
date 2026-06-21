<?php
namespace app\controller;

use app\BaseController;
use app\model\EmailTemplate;
use app\model\AuditLog;

class Template extends BaseController
{
    /**
     * 模板列表
     */
    public function index()
    {
        $page = $this->request->param('page', 1, 'intval');
        $limit = $this->request->param('limit', 20, 'intval');
        $keyword = $this->request->param('keyword', '');

        $where = [['is_deleted', '=', 0]];
        if ($keyword) {
            $where[] = ['name|subject', 'like', "%{$keyword}%"];
        }

        $list = EmailTemplate::where($where)
            ->page($page, $limit)
            ->select();
        $total = EmailTemplate::where($where)->count();

        return $this->paginate($list, $total, $page, $limit);
    }

    /**
     * 创建模板
     */
    public function save()
    {
        $data = $this->request->param();
        $data['created_by'] = $this->request->userId;

        $template = EmailTemplate::create($data);

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'template_create',
            'details' => json_encode(['template_id' => $template->id]),
        ]);

        return $this->success(['id' => $template->id], '创建成功');
    }

    /**
     * 模板详情
     */
    public function read($id)
    {
        $template = EmailTemplate::find($id);
        if (!$template || $template->is_deleted) {
            return $this->error('模板不存在');
        }

        return $this->success($template);
    }

    /**
     * 更新模板
     */
    public function update($id)
    {
        $template = EmailTemplate::find($id);
        if (!$template || $template->is_deleted) {
            return $this->error('模板不存在');
        }

        $data = $this->request->param();
        $template->save($data);

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'template_update',
            'details' => json_encode(['template_id' => $id]),
        ]);

        return $this->success([], '更新成功');
    }

    /**
     * 删除模板
     */
    public function delete($id)
    {
        $template = EmailTemplate::find($id);
        if (!$template || $template->is_deleted) {
            return $this->error('模板不存在');
        }

        $template->deleted_at = date('Y-m-d H:i:s');
        $template->is_deleted = 1;
        $template->save();

        AuditLog::create([
            'user_id' => $this->request->userId,
            'action' => 'template_delete',
            'details' => json_encode(['template_id' => $id]),
        ]);

        return $this->success([], '删除成功');
    }
}
