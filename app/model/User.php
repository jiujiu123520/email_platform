<?php
namespace app\model;

use think\Model;
use think\model\concern\SoftDelete;

class User extends Model
{
    protected $table = 'users';

    // 软删除
    use SoftDelete;
    protected $deleteTime = 'deleted_at';
    protected $defaultSoftDelete = null;

    // 类型转换
    protected $type = [
        'is_deleted' => 'integer',
        'role' => 'string',
        'daily_quota' => 'integer',
        'used_quota' => 'integer',
        'total_sent' => 'integer',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // 设置密码
    public function setPasswordAttr($value)
    {
        return password_hash($value, PASSWORD_DEFAULT);
    }

    // 验证密码
    public function checkPassword($password)
    {
        return password_verify($password, $this->password);
    }

    // 检查配额
    public function checkQuota($count = 1)
    {
        return ($this->daily_quota - $this->used_quota) >= $count;
    }

    // 使用配额
    public function useQuota($count = 1)
    {
        $this->used_quota += $count;
        $this->total_sent += $count;
        $this->save();
    }

    // 重置每日配额
    public function resetDailyQuota()
    {
        $this->used_quota = 0;
        $this->save();
    }

    // 获取用户组
    public function group()
    {
        return $this->belongsTo('UserGroup', 'group_id');
    }

    // 获取审计日志
    public function auditLogs()
    {
        return $this->hasMany('AuditLog', 'user_id');
    }

    // 邮箱记录
    public function emailRecords()
    {
        return $this->hasMany('EmailRecord', 'sender_id');
    }
}
