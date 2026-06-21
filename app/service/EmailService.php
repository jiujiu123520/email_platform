<?php
namespace app\service;

use app\model\SmtpRelay;

class EmailService
{
    protected $smtpService;

    public function __construct()
    {
        $this->smtpService = new SmtpService();
    }

    /**
     * 发送邮件
     */
    public function send($relay, $toEmail, $toName, $subject, $htmlContent, $textContent = '')
    {
        return $this->smtpService->send($relay, $toEmail, $toName, $subject, $htmlContent, $textContent);
    }

    /**
     * 批量发送
     */
    public function batchSend($relay, $recipients, $subject, $htmlContent, $textContent = '')
    {
        $results = [
            'success_count' => 0,
            'failed_count' => 0,
            'errors' => [],
        ];

        foreach ($recipients as $recipient) {
            $toEmail = $recipient['email'] ?? '';
            $toName = $recipient['name'] ?? '';
            $variables = $recipient['variables'] ?? [];

            // 渲染变量
            $renderedSubject = $this->renderVariables($subject, $variables);
            $renderedHtml = $this->renderVariables($htmlContent, $variables);
            $renderedText = $this->renderVariables($textContent, $variables);

            $result = $this->send($relay, $toEmail, $toName, $renderedSubject, $renderedHtml, $renderedText);

            if ($result['success']) {
                $results['success_count']++;
            } else {
                $results['failed_count']++;
                $results['errors'][] = $result['error'];
            }
        }

        return $results;
    }

    /**
     * 渲染变量
     */
    protected function renderVariables($content, $variables)
    {
        if (empty($variables) || empty($content)) {
            return $content;
        }

        foreach ($variables as $key => $value) {
            $content = str_replace('${' . $key . '}', $value, $content);
        }

        return $content;
    }
}
