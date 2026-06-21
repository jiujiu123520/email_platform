<?php
namespace app\controller;

use app\BaseController;

class Index extends BaseController
{
    public function index()
    {
        return view('', [
            'title' => '邮件发送平台',
            'version' => '2.0.0 (PHP)',
        ]);
    }
}
