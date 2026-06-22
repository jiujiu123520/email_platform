<?php
/**
 * 基础控制器
 */

namespace MailSystem\Controllers;

use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Log as LogModel;

abstract class BaseController
{
    protected function log(string $action, ?string $target = null, ?string $desc = null): void
    {
        $req = new Request();
        try {
            LogModel::create([
                'user_id'     => \MailSystem\Core\Auth::id(),
                'action'      => $action,
                'target'      => $target,
                'description' => $desc,
                'ip_address'  => $req->ip(),
                'user_agent'  => $req->userAgent(),
                'status'      => 1,
            ]);
        } catch (\Throwable $e) {
            // 静默
        }
    }

    protected function ok($data = null, string $message = 'OK'): void
    {
        Response::success($data, $message);
    }
}
