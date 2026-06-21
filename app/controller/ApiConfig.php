<?php
namespace app\controller;

use app\BaseController;
use app\model\ApiConfig;

class ApiConfig extends BaseController
{
    /**
     * 获取API配置
     */
    public function index()
    {
        $configs = ApiConfig::where('is_deleted', 0)->select();

        return $this->success($configs);
    }

    /**
     * 保存API配置
     */
    public function save()
    {
        $data = $this->request->param();

        if (empty($data['name'])) {
            return $this->error('配置名称不能为空');
        }

        if (isset($data['id']) && $data['id']) {
            // 更新
            $config = ApiConfig::find($data['id']);
            if ($config) {
                $config->save($data);
            }
        } else {
            // 创建
            ApiConfig::create($data);
        }

        return $this->success([], '保存成功');
    }
}
