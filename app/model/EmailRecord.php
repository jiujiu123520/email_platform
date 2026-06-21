<?php
namespace app\model;

use think\Model;
use think\model\concern\SoftDelete;

class EmailRecord extends Model
{
    protected $table = 'email_records';

    use SoftDelete;
    protected $deleteTime = 'deleted_at';
    protected $defaultSoftDelete = null;

    protected $type = [
        'sender_id' => 'integer',
        'template_id' => 'integer',
        'smtp_relay_id' => 'integer',
        'retry_count' => 'integer',
        'sent_at' => 'datetime',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // 发送者
    public function sender()
    {
        return $this->belongsTo('User', 'sender_id');
    }

    // 模板
    public function template()
    {
        return $this->belongsTo('EmailTemplate', 'template_id');
    }

    // SMTP中继
    public function relay()
    {
        return $this->belongsTo('SmtpRelay', 'smtp_relay_id');
    }
}
