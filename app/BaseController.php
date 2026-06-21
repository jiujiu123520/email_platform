<?php
namespace app;

use think\App;
use think\Controller;

class BaseController extends Controller
{
    protected $middleware = [];

    public function __construct(App $app)
    {
        parent::__construct($app);
    }

    /**
     * 返回成功 JSON
     */
    protected function success($data = [], $message = '操作成功', $code = 200)
    {
        return json([
            'code' => $code,
            'message' => $message,
            'data' => $data,
        ]);
    }

    /**
     * 返回错误 JSON
     */
    protected function error($message = '操作失败', $code = 400, $data = [])
    {
        return json([
            'code' => $code,
            'message' => $message,
            'data' => $data,
        ]);
    }

    /**
     * 返回分页 JSON
     */
    protected function paginate($list, $total, $page, $limit)
    {
        return json([
            'code' => 200,
            'message' => 'success',
            'data' => [
                'list' => $list,
                'total' => $total,
                'page' => $page,
                'limit' => $limit,
            ],
        ]);
    }
}
