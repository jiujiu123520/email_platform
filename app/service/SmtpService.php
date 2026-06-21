<?php
namespace app\service;

use app\model\SmtpRelay;

class SmtpService
{
    /**
     * 通过 SMTP 中继发送邮件
     */
    public function send($relay, $toEmail, $toName, $subject, $htmlContent, $textContent = '')
    {
        if (!$relay instanceof SmtpRelay) {
            $relay = SmtpRelay::find($relay);
        }

        if (!$relay) {
            return ['success' => false, 'error' => 'SMTP中继不存在'];
        }

        // 检查配额
        if ($relay->used_today >= $relay->max_daily_quota) {
            return ['success' => false, 'error' => 'SMTP中继今日配额已用完'];
        }

        // 发送邮件
        try {
            $result = $this->sendMail($relay, $toEmail, $toName, $subject, $htmlContent, $textContent);

            if ($result) {
                return ['success' => true];
            } else {
                return ['success' => false, 'error' => '邮件发送失败'];
            }
        } catch (\Exception $e) {
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }

    /**
     * 实际发送邮件
     */
    protected function sendMail($relay, $toEmail, $toName, $subject, $htmlContent, $textContent)
    {
        // 构造邮件头
        $headers = [
            'From' => $relay->from_name . ' <' . $relay->from_email . '>',
            'Reply-To' => $relay->from_email,
            'X-Mailer' => 'PHP/' . phpversion(),
            'MIME-Version' => '1.0',
            'Content-Type' => 'text/html; charset=UTF-8',
        ];

        $headerString = '';
        foreach ($headers as $key => $value) {
            $headerString .= "$key: $value\r\n";
        }

        // 如果没有纯文本内容，从HTML提取
        if (empty($textContent) && !empty($htmlContent)) {
            $textContent = strip_tags($htmlContent);
        }

        // 添加 multipart 版本
        $boundary = md5(uniqid(time()));
        $headers['Content-Type'] = "multipart/alternative; boundary=\"$boundary\"";

        $body = "--$boundary\r\n";
        $body .= "Content-Type: text/plain; charset=UTF-8\r\n";
        $body .= "Content-Transfer-Encoding: 8bit\r\n\r\n";
        $body .= $textContent . "\r\n\r\n";
        $body .= "--$boundary\r\n";
        $body .= "Content-Type: text/html; charset=UTF-8\r\n";
        $body .= "Content-Transfer-Encoding: 8bit\r\n\r\n";
        $body .= $htmlContent . "\r\n\r\n";
        $body .= "--$boundary--";

        // 重新构造 header
        $headerString = '';
        foreach ($headers as $key => $value) {
            if ($key !== 'Content-Type') {
                $headerString .= "$key: $value\r\n";
            } else {
                $headerString .= "$key: $value\r\n";
            }
        }

        // 实际发送
        $result = mail($toEmail, $subject, $body, $headerString);

        return $result;
    }

    /**
     * 测试 SMTP 连接
     */
    public function testConnection($host, $port, $username, $password, $fromEmail, $fromName)
    {
        $socket = @fsockopen($host, $port, $errno, $errstr, 10);

        if (!$socket) {
            return ['success' => false, 'error' => "连接失败: $errstr ($errno)"];
        }

        $response = fgets($socket, 515);
        fclose($socket);

        if (substr($response, 0, 3) !== '220') {
            return ['success' => false, 'error' => '服务器响应异常'];
        }

        return ['success' => true, 'message' => '连接成功'];
    }
}
