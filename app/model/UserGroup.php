<?php
namespace app\model;

use think\Model;

class UserGroup extends Model
{
    protected $table = 'user_groups';

    protected $type = [
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    // 用户数
    public function users()
    {
        return $this->hasMany('User', 'group_id');
    }
}
