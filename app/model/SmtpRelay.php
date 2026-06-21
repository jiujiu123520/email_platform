<?php
namespace app\model;

use think\Model;
use think\model\concern\SoftDelete;

class SmtpRelay extends Model
{
    protected $table = 'smtp_relays';

    use SoftDelete;
    protected $deleteTime = 'deleted_at';
    protected $defaultSoftDelete = null;

    protected $type = [
        'port' => 'integer',
        'is_active' => 'integer',
        'is_global' => 'integer',
        'priority' => 'integer',
        'max_daily_quota' => 'integer',
        'used_today' => 'integer',
        'consecutive_failures' => 'integer',
        'is_paused' => 'integer',
        'last_used_at' => 'datetime',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // 检查是否可用
    public function isAvailable()
    {
        if ($this->is_paused) {
            return false;
        }
        if ($this->used_today >= $this->max_daily_quota) {
            return false;
        }
        return true;
    }

    // 标记使用
    public function markUsed()
    {
        $this->used_today++;
        $this->last_used_at = date('Y-m-d H:i:s');
        $this->save();
    }

    // 标记失败
    public function markFailed()
    {
        $this->consecutive_failures++;
        if ($this->consecutive_failures >= 5) {
            $this->is_paused = 1;
        }
        $this->save();
    }

    // 标记成功
    public function markSuccess()
    {
        $this->consecutive_failures = 0;
        $this->last_used_at = date('Y-m-d H:i:s');
        $this->save();
    }
}
