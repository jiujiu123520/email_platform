<?php
namespace app\model;

use think\Model;
use think\model\concern\SoftDelete;

class AuditLog extends Model
{
    protected $table = 'audit_logs';

    use SoftDelete;
    protected $deleteTime = 'deleted_at';
    protected $defaultSoftDelete = null;

    protected $type = [
        'user_id' => 'integer',
        'action' => 'string',
        'created_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // 用户
    public function user()
    {
        return $this->belongsTo('User', 'user_id');
    }
}
