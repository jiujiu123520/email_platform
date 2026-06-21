<?php
namespace app\model;

use think\Model;
use think\model\concern\SoftDelete;

class EmailTemplate extends Model
{
    protected $table = 'email_templates';

    use SoftDelete;
    protected $deleteTime = 'deleted_at';
    protected $defaultSoftDelete = null;

    protected $type = [
        'is_default' => 'integer',
        'created_by' => 'integer',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // 创建者
    public function creator()
    {
        return $this->belongsTo('User', 'created_by');
    }
}
