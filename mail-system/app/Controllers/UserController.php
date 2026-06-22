<?php

namespace MailSystem\Controllers;

use MailSystem\Core\Auth;
use MailSystem\Core\Request;
use MailSystem\Core\Response;
use MailSystem\Models\Log as LogModel;
use MailSystem\Models\User;

class UserController extends BaseController
{
    public function index(Request $req): void
    {
        Auth::requireAdmin();
        $list = User::all();
        foreach ($list as &$u) unset($u['password']);
        $this->ok(['list' => $list]);
    }

    public function create(Request $req): void
    {
        Auth::requireAdmin();
        $username = trim((string) $req->input('username'));
        $password = (string) $req->input('password');
        $email    = (string) $req->input('email', '');
        $role     = $req->input('role', 'user') === 'admin' ? 'admin' : 'user';
        if ($username === '' || strlen($password) < 6) {
            Response::error('用户名必填，密码至少 6 位', 400, 400);
        }
        if (User::findByUsername($username)) {
            Response::error('用户名已存在', 400, 400);
        }
        $id = User::create([
            'username' => $username,
            'password' => password_hash($password, PASSWORD_DEFAULT),
            'email'    => $email,
            'role'     => $role,
            'status'   => 1,
        ]);
        $this->log('user.create', $username);
        $this->ok(['id' => $id]);
    }

    public function update(Request $req, array $params): void
    {
        Auth::requireAdmin();
        $id = (int) $params['id'];
        $u = User::find($id);
        if (!$u) Response::notFound('用户不存在');
        $data = [];
        foreach (['email', 'display_name', 'role', 'status'] as $f) {
            if ($req->input($f) !== null) $data[$f] = $req->input($f);
        }
        $np = (string) $req->input('password', '');
        if ($np !== '') {
            if (strlen($np) < 6) Response::error('密码至少 6 位', 400, 400);
            $data['password'] = password_hash($np, PASSWORD_DEFAULT);
        }
        if (!empty($data)) User::update($id, $data);
        $this->ok(null, '已更新');
    }

    public function delete(Request $req, array $params): void
    {
        Auth::requireAdmin();
        $id = (int) $params['id'];
        if ($id === Auth::id()) Response::error('不能删除自己', 400, 400);
        User::delete($id);
        $this->ok(null, '已删除');
    }

    public function logs(Request $req): void
    {
        Auth::requireAdmin();
        $limit  = max(1, min(500, (int) $req->query('limit', 100)));
        $offset = max(0, (int) $req->query('offset', 0));
        $list = LogModel::list($limit, $offset, [
            'action' => $req->query('action'),
            'user_id'=> $req->query('user_id'),
        ]);
        $this->ok(['list' => $list]);
    }
}
