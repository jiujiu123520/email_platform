<?php
/**
 * SMTP 服务端 (支持明文 / STARTTLS / SSL)
 *
 * 实现命令:
 *   EHLO/HELO, AUTH LOGIN/PLAIN, MAIL FROM, RCPT TO, DATA, RSET, NOOP, QUIT, VRFY
 */

namespace MailSystem\Services;

use MailSystem\Core\Auth;
use MailSystem\Core\MailStorage;
use MailSystem\Core\MimeParser;
use MailSystem\Models\Mailbox;
use MailSystem\Models\Email;

class SmtpServer extends BaseServer
{
    private string $hostname;

    public function __construct(array $config = [])
    {
        parent::__construct($config);
        $this->hostname = config('mail.hostname', 'mail.local');
    }

    protected function onConnect(int $cid): void
    {
        $banner = config('mail.smtp_banner', 'MailSystem ESMTP');
        $this->send($cid, "220 {$this->hostname} {$banner}\r\n");
    }

    protected function onClose(int $cid): void
    {
        $c = $this->getClient($cid);
        $this->logger->info('SMTP close', ['peer' => $c['peer'] ?? '']);
    }

    protected function onData(int $cid): void
    {
        $buf = $this->getBuffer($cid);
        $state = $this->getClientState($cid);
        if ($state === 'data') {
            // 邮件数据模式
            if (str_contains($buf, "\r\n.\r\n") || str_ends_with($buf, "\r\n.\r\n")) {
                $endPos = strpos($buf, "\r\n.\r\n");
                $mailData = substr($buf, 0, $endPos);
                // 反 quoted-printable 转义
                $mailData = preg_replace('/\r\n\.\r\n/', "\r\n", $mailData);
                $mailData = preg_replace('/^\.\./m', '.', $mailData);
                $this->handleMailData($cid, $mailData);
                $this->clearBuffer($cid);
                $this->send($cid, "250 OK: queued\r\n");
                $this->setClientState($cid, 'ready');
            } elseif (strlen($buf) > 50 * 1024 * 1024) {
                $this->send($cid, "552 Message size exceeds maximum\r\n");
                $this->setClientState($cid, 'ready');
                $this->clearBuffer($cid);
            }
            return;
        }

        // 命令模式 - 一次取一行
        while (($pos = strpos($buf, "\r\n")) !== false) {
            $line = substr($buf, 0, $pos);
            $this->clearBuffer($cid);
            $buf = substr($buf, $pos + 2);
            $this->handleCommand($cid, $line);
        }
        // 缓存剩余
        $this->clients[$cid]['buffer'] = $buf;
    }

    private function handleCommand(int $cid, string $line): void
    {
        $line = trim($line);
        if ($line === '') return;

        $parts = explode(' ', $line, 2);
        $cmd = strtoupper($parts[0]);
        $arg = $parts[1] ?? '';

        $state = $this->getClientState($cid);
        $c = $this->getClient($cid);

        switch ($cmd) {
            case 'EHLO':
                $this->clients[$cid]['helo'] = $arg ?: 'unknown';
                $this->setClientState($cid, 'ready');
                $this->send($cid, "250-{$this->hostname} Hello {$arg}\r\n");
                $this->send($cid, "250-SIZE 26214400\r\n");
                $this->send($cid, "250-8BITMIME\r\n");
                $this->send($cid, "250-AUTH PLAIN LOGIN\r\n");
                $this->send($cid, "250-STARTTLS\r\n");
                $this->send($cid, "250 SMTPUTF8\r\n");
                break;
            case 'HELO':
                $this->clients[$cid]['helo'] = $arg ?: 'unknown';
                $this->setClientState($cid, 'ready');
                $this->send($cid, "250 {$this->hostname} Hello {$arg}\r\n");
                break;
            case 'AUTH':
                $this->handleAuth($cid, $arg);
                break;
            case 'MAIL':
                $this->handleMail($cid, $arg);
                break;
            case 'RCPT':
                $this->handleRcpt($cid, $arg);
                break;
            case 'DATA':
                if ($state !== 'mail') {
                    $this->send($cid, "503 Error: MAIL first\r\n");
                    return;
                }
                $this->setClientState($cid, 'data');
                $this->send($cid, "354 End data with <CR><LF>.<CR><LF>\r\n");
                break;
            case 'RSET':
                $this->setClientState($cid, 'ready');
                $this->clients[$cid]['mail_from'] = null;
                $this->clients[$cid]['rcpt_to']   = [];
                $this->send($cid, "250 OK\r\n");
                break;
            case 'NOOP':
                $this->send($cid, "250 OK\r\n");
                break;
            case 'QUIT':
                $this->send($cid, "221 Bye\r\n");
                $this->closeClient($cid);
                break;
            case 'VRFY':
                $this->send($cid, "252 Cannot VRFY user\r\n");
                break;
            case 'STARTTLS':
                if ($this->ssl) {
                    $this->send($cid, "454 TLS not available\r\n");
                    return;
                }
                $this->send($cid, "220 Ready to start TLS\r\n");
                $this->enableTls($cid);
                $this->setClientState($cid, 'init');
                break;
            default:
                $this->send($cid, "500 Command not recognized\r\n");
        }
    }

    private function enableTls(int $cid): void
    {
        if (!$this->certFile || !$this->keyFile) {
            $this->send($cid, "454 TLS not configured\r\n");
            return;
        }
        $sock = $this->clients[$cid]['socket'];
        // 启用 TLS
        stream_set_blocking($sock, true);
        $result = @stream_socket_enable_crypto($sock, true, STREAM_CRYPTO_METHOD_TLS_SERVER);
        if (!$result) {
            $this->send($cid, "454 TLS negotiation failed\r\n");
            $this->closeClient($cid);
            return;
        }
        $this->logger->info('SMTP STARTTLS established', ['peer' => $this->clients[$cid]['peer'] ?? '']);
    }

    private function handleAuth(int $cid, string $arg): void
    {
        $parts = explode(' ', $arg, 2);
        $mech = strtoupper($parts[0]);
        $rest = $parts[1] ?? '';

        if ($mech === 'PLAIN') {
            $decoded = base64_decode($rest, true);
            if (!$decoded) {
                $this->send($cid, "334 \r\n");
                return;
            }
            $cred = explode("\0", $decoded);
            $user = $cred[1] ?? '';
            $pass = $cred[2] ?? '';
            $this->tryAuth($cid, $user, $pass);
        } elseif ($mech === 'LOGIN') {
            $this->send($cid, "334 " . base64_encode('Username:') . "\r\n");
            $this->setClientState($cid, 'auth_login_user');
        } else {
            $this->send($cid, "504 Unrecognized authentication mechanism\r\n");
        }
    }

    /**
     * 处理 AUTH LOGIN 多步 - 我们将其作为状态机
     * 这里通过 onData 中检测
     */
    public function continueAuth(int $cid, string $line): void
    {
        $state = $this->getClientState($cid);
        if ($state === 'auth_login_user') {
            $user = base64_decode(trim($line), true) ?: '';
            $this->clients[$cid]['auth_user'] = $user;
            $this->send($cid, "334 " . base64_encode('Password:') . "\r\n");
            $this->setClientState($cid, 'auth_login_pass');
        } elseif ($state === 'auth_login_pass') {
            $pass = base64_decode(trim($line), true) ?: '';
            $user = $this->clients[$cid]['auth_user'] ?? '';
            $this->tryAuth($cid, $user, $pass);
        }
    }

    private function tryAuth(int $cid, string $user, string $pass): void
    {
        if ($user === '' || $pass === '') {
            $this->send($cid, "501 Invalid credentials\r\n");
            $this->setClientState($cid, 'ready');
            return;
        }
        $mailbox = Mailbox::findByAddress($user);
        if (!$mailbox || !password_verify($pass, $mailbox['password'])) {
            $this->send($cid, "535 Authentication failed\r\n");
            $this->setClientState($cid, 'ready');
            return;
        }
        $this->clients[$cid]['auth_user'] = $user;
        $this->clients[$cid]['mailbox']   = $mailbox;
        $this->setClientState($cid, 'ready');
        $this->send($cid, "235 Authentication successful\r\n");
        $this->logger->info('SMTP auth ok', ['user' => $user]);
    }

    private function handleMail(int $cid, string $arg): void
    {
        if ($this->getClientState($cid) === 'init') {
            $this->send($cid, "503 EHLO first\r\n");
            return;
        }
        // 提取 FROM:<address>
        if (!preg_match('/FROM:\s*<([^>]*)>/i', $arg, $m)) {
            $this->send($cid, "501 Syntax: MAIL FROM:<address>\r\n");
            return;
        }
        $this->clients[$cid]['mail_from'] = $m[1];
        $this->clients[$cid]['rcpt_to']   = [];
        $this->setClientState($cid, 'mail');
        $this->send($cid, "250 OK\r\n");
    }

    private function handleRcpt(int $cid, string $arg): void
    {
        if ($this->getClientState($cid) !== 'mail') {
            $this->send($cid, "503 MAIL first\r\n");
            return;
        }
        if (!preg_match('/TO:\s*<([^>]*)>/i', $arg, $m)) {
            $this->send($cid, "501 Syntax: RCPT TO:<address>\r\n");
            return;
        }
        $this->clients[$cid]['rcpt_to'][] = $m[1];
        $this->send($cid, "250 OK\r\n");
    }

    private function handleMailData(int $cid, string $raw): void
    {
        $c = $this->getClient($cid);
        $from = $c['mail_from'] ?? '';
        $to   = $c['rcpt_to']   ?? [];
        $authUser = $c['auth_user'] ?? null;

        // 解析
        $parsed = MimeParser::parse($raw);
        $messageId = $parsed['message_id'] ?: '<' . bin2hex(random_bytes(8)) . '@' . $this->hostname . '>';

        $toAddrs = is_array($to) ? implode(', ', $to) : $to;
        $ccAddrs = is_array($parsed['cc']) ? implode(', ', array_column($parsed['cc'], 'address')) : '';
        $bccAddrs= is_array($parsed['bcc']) ? implode(', ', array_column($parsed['bcc'], 'address')) : '';

        // 已登录用户: 投递到自己的发件箱(SENT) 和目标收件箱
        if ($authUser) {
            $senderBox = Mailbox::findByAddress($authUser);
            if ($senderBox) {
                Email::create([
                    'mailbox_id'   => $senderBox['id'],
                    'message_id'   => $messageId,
                    'from_address' => $from,
                    'from_name'    => $parsed['from_name'] ?: '',
                    'to_addresses' => $toAddrs,
                    'cc_addresses' => $ccAddrs,
                    'bcc_addresses'=> $bccAddrs,
                    'subject'      => $parsed['subject'],
                    'body_text'    => $parsed['body_text'],
                    'body_html'    => $parsed['body_html'],
                    'headers'      => $parsed['headers'] ? json_encode($parsed['headers'], JSON_UNESCAPED_UNICODE) : '',
                    'size_bytes'   => strlen($raw),
                    'folder'       => 'SENT',
                    'direction'    => 'out',
                    'status'       => 'sent',
                ]);
            }
        }

        // 投递给每个收件人
        foreach ($to as $addr) {
            $target = Mailbox::findByAddress($addr);
            if (!$target) {
                $this->logger->warn('SMTP recipient not found', ['addr' => $addr]);
                continue;
            }
            try {
                $storage = new MailStorage($target['full_address']);
                $storage->deliver($raw);

                Email::create([
                    'mailbox_id'   => $target['id'],
                    'message_id'   => $messageId,
                    'from_address' => $from,
                    'from_name'    => $parsed['from_name'] ?: '',
                    'to_addresses' => $addr,
                    'cc_addresses' => $ccAddrs,
                    'bcc_addresses'=> $bccAddrs,
                    'subject'      => $parsed['subject'],
                    'body_text'    => $parsed['body_text'],
                    'body_html'    => $parsed['body_html'],
                    'headers'      => $parsed['headers'] ? json_encode($parsed['headers'], JSON_UNESCAPED_UNICODE) : '',
                    'size_bytes'   => strlen($raw),
                    'folder'       => 'INBOX',
                    'direction'    => 'in',
                    'status'       => 'received',
                ]);
            } catch (\Throwable $e) {
                $this->logger->error('SMTP deliver error: ' . $e->getMessage(), ['addr' => $addr]);
            }
        }
    }
}
