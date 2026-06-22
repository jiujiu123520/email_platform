<?php

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Setting;

class SettingController extends BaseController
{
    public function all(Request $req): void
    {
        Auth::requireLogin();
        $settings = Setting::all();
        $this->ok(['list' => $settings]);
    }

    public function public(Request $req): void
    {
        $list = Setting::allPublic();
        $this->ok(['list' => $list]);
    }

    public function update(Request $req): void
    {
        Auth::requireAdmin();
        $payload = $req->input('settings', []);
        if (!is_array($payload)) Response::error('参数错误', 400, 400);
        foreach ($payload as $k => $v) {
            Setting::set($k, is_array($v) ? json_encode($v) : (string) $v);
        }
        $this->log('settings.update', null, 'update settings');
        $this->ok(null, '设置已更新');
    }

    public function getAdminPath(Request $req): void
    {
        $path = Setting::get('admin_path', 'admin');
        $this->ok(['admin_path' => $path, 'admin_port' => Setting::get('admin_port', '8080')]);
    }
}
