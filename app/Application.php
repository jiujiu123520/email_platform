<?php
namespace app;

use think\App;

class Application extends App
{
    public function run()
    {
        // 加载路由
        $this->loadRoute();

        // 执行请求
        return $this->handle();
    }

    protected function loadRoute()
    {
        $routePath = $this->app->getRootPath() . 'app/route';
        if (is_dir($routePath)) {
            $files = glob($routePath . '/*.php');
            foreach ($files as $file) {
                include $file;
            }
        }
    }
}
