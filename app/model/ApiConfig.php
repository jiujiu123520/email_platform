<?php
namespace app\model;

use think\Model;
use think\model\concern\SoftDelete;

class ApiConfig extends Model
{
    protected $table = 'api_configs';

    use SoftDelete;
    protected $deleteTime = 'deleted_at';
    protected $defaultSoftDelete = null;

    protected $type = [
        'enabled' => 'integer',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];
}
