<?php
namespace app\controller;

use app\BaseController;
use app\model\EmailRecord;
use app\model\EmailTemplate;
use app\model\SmtpRelay;
use app\model\AuditLog;
use app\service\EmailService;
use app\service\SmtpService;

class Email extends BaseController
{
    protected $emailService;

    public function __construct()
    {
        $this->emailService = new EmailService();
    }

    /**
     * 发送邮件
     */
    public function send()
    {
        $user = $this->request->user;
        $data = $this->request->param();

        $toEmail = $data['to_email'] ?? '';
        $toName = $data['to_name'] ?? '';
        $subject = $data['subject'] ?? '';
        $htmlContent = $data['html_content'] ?? '';
        $textContent = $data['text_content'] ?? '';
        $templateId = $data['template_id'] ?? null;
        $variables = $data['variables'] ?? [];

        // 验证邮箱
        if (!filter_var($toEmail, FILTER_VALIDATE_EMAIL)) {
            return $this->error('收件人邮箱格式不正确');
        }

        // 检查配额
        if (!$user->checkQuota(1)) {
            return $this->error('今日发送配额已用完');
        }

        // 渲染模板
        if ($templateId) {
            $template = EmailTemplate::find($templateId);
            if (!$template || $template->is_deleted) {
                return $this->error('模板不存在');
            }
            $subject = $this->renderTemplate($template->subject, $variables);
            $htmlContent = $this->renderTemplate($template->html_content, $variables);
            $textContent = $this->renderTemplate($template->text_content, $variables);
        }

        // 获取可用中继
        $relay = SmtpRelay::where('is_active', 1)->where('is_paused', 0)->find();
        if (!$relay) {
            return $this->error('没有可用的SMTP中继');
        }

        // 创建发送记录
        $record = EmailRecord::create([
            'sender_id' => $user->id,
            'from_email' => $relay->from_email,
            'from_name' => $relay->from_name,
            'to_email' => $toEmail,
            'to_name' => $toName,
            'subject' => $subject,
            'html_content' => $htmlContent,
            'text_content' => $textContent,
            'template_id' => $templateId,
            'status' => 'sending',
        ]);

        // 发送邮件
        $result = $this->emailService->send($relay, $toEmail, $toName, $subject, $htmlContent, $textContent);

        if ($result['success']) {
            $record->status = 'sent';
            $record->sent_at = date('Y-m-d H:i:s');
            $record->smtp_relay_id = $relay->id;
            $user->useQuota(1);
            $relay->markSuccess();

            AuditLog::create([
                'user_id' => $user->id,
                'action' => 'email_send',
                'details' => json_encode(['record_id' => $record->id, 'to' => $toEmail]),
            ]);

            return $this->success(['record_id' => $record->id], '发送成功');
        } else {
            $record->status = 'failed';
            $record->error_message = $result['error'];
            $relay->markFailed();

            return $this->error('发送失败: ' . $result['error']);
        }
    }

    /**
     * 批量发送
     */
    public function batch()
    {
        $user = $this->request->user;
        $data = $this->request->param();

        $recipients = $data['recipients'] ?? [];
        $subject = $data['subject'] ?? '';
        $htmlContent = $data['html_content'] ?? '';
        $templateId = $data['template_id'] ?? null;

        if (empty($recipients)) {
            return $this->error('收件人不能为空');
        }

        // 检查配额
        if (!$user->checkQuota(count($recipients))) {
            return $this->error('发送配额不足');
        }

        $successCount = 0;
        $failedCount = 0;
        $errors = [];

        foreach ($recipients as $recipient) {
            $toEmail = $recipient['email'] ?? '';
            $toName = $recipient['name'] ?? '';
            $variables = $recipient['variables'] ?? [];

            $result = $this->sendInternal($user, $toEmail, $toName, $subject, $htmlContent, '', $templateId, $variables);

            if ($result['success']) {
                $successCount++;
            } else {
                $failedCount++;
                $errors[] = $result['error'];
            }
        }

        return $this->success([
            'success_count' => $successCount,
            'failed_count' => $failedCount,
            'errors' => $errors,
        ], '批量发送完成');
    }

    /**
     * 发送记录列表
     */
    public function records()
    {
        $page = $this->request->param('page', 1, 'intval');
        $limit = $this->request->param('limit', 20, 'intval');
        $status = $this->request->param('status', '');

        $where = [['sender_id', '=', $this->request->userId]];
        if ($status) {
            $where[] = ['status', '=', $status];
        }

        $list = EmailRecord::where($where)
            ->page($page, $limit)
            ->order('created_at', 'desc')
            ->select();
        $total = EmailRecord::where($where)->count();

        return $this->paginate($list, $total, $page, $limit);
    }

    /**
     * 发送记录详情
     */
    public function record($id)
    {
        $record = EmailRecord::find($id);
        if (!$record) {
            return $this->error('记录不存在');
        }

        return $this->success($record);
    }

    /**
     * 内部发送方法
     */
    protected function sendInternal($user, $toEmail, $toName, $subject, $htmlContent, $textContent, $templateId, $variables)
    {
        if (!filter_var($toEmail, FILTER_VALIDATE_EMAIL)) {
            return ['success' => false, 'error' => '邮箱格式不正确'];
        }

        // 渲染模板
        if ($templateId) {
            $template = EmailTemplate::find($templateId);
            if ($template) {
                $subject = $this->renderTemplate($template->subject, $variables);
                $htmlContent = $this->renderTemplate($template->html_content, $variables);
            }
        }

        $relay = SmtpRelay::where('is_active', 1)->where('is_paused', 0)->find();
        if (!$relay) {
            return ['success' => false, 'error' => '没有可用的SMTP中继'];
        }

        $result = $this->emailService->send($relay, $toEmail, $toName, $subject, $htmlContent, $textContent);

        if ($result['success']) {
            $user->useQuota(1);
            $relay->markSuccess();
        } else {
            $relay->markFailed();
        }

        return $result;
    }

    /**
     * 渲染模板变量
     */
    protected function renderTemplate($content, $variables)
    {
        if (empty($variables)) {
            return $content;
        }

        foreach ($variables as $key => $value) {
            $content = str_replace('${' . $key . '}', $value, $content);
        }

        return $content;
    }
}
