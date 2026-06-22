<?php
/**
 * RFC 822 / MIME 邮件解析与组装
 */

namespace MailSystem\Core;

class MimeParser
{
    /**
     * 解析邮件原始内容，返回结构化数据
     */
    public static function parse(string $raw): array
    {
        // 分离头与体
        $split = preg_split("/\r?\n\r?\n/", $raw, 2);
        $headerRaw = $split[0] ?? '';
        $bodyRaw   = $split[1] ?? '';

        $headers = self::parseHeaders($headerRaw);

        $result = [
            'headers'     => $headers,
            'from'        => self::decodeMime($headers['from']    ?? ''),
            'from_name'   => self::extractName($headers['from']  ?? ''),
            'to'          => self::parseAddressList($headers['to'] ?? ''),
            'cc'          => self::parseAddressList($headers['cc'] ?? ''),
            'bcc'         => self::parseAddressList($headers['bcc'] ?? ''),
            'subject'     => self::decodeMime($headers['subject'] ?? ''),
            'message_id'  => $headers['message-id'] ?? '',
            'date'        => $headers['date'] ?? '',
            'body_text'   => '',
            'body_html'   => '',
            'attachments' => [],
            'raw_size'    => strlen($raw),
        ];

        $contentType = $headers['content-type'] ?? 'text/plain';
        $contentTypeLower = strtolower($contentType);
        $encoding    = strtolower($headers['content-transfer-encoding'] ?? '7bit');

        if (strpos($contentTypeLower, 'multipart/') === 0) {
            $boundary = self::extractBoundary($contentType);
            if ($boundary) {
                $parts = self::splitMultipart($bodyRaw, $boundary);
                foreach ($parts as $part) {
                    self::processMimePart($part, $result);
                }
            } else {
                $decoded = self::decodeBody($bodyRaw, $encoding);
                $result['body_text'] = $decoded;
            }
        } else {
            $decoded = self::decodeBody($bodyRaw, $encoding);
            if (strpos($contentTypeLower, 'text/html') !== false) {
                $result['body_html'] = $decoded;
            } else {
                $result['body_text'] = $decoded;
            }
        }

        return $result;
    }

    private static function parseHeaders(string $raw): array
    {
        $headers = [];
        $lines = preg_split("/\r?\n/", $raw);
        $current = '';
        foreach ($lines as $line) {
            if ($line === '') break;
            if ($line[0] === ' ' || $line[0] === "\t") {
                $headers[$current] .= ' ' . trim($line);
            } else {
                $pos = strpos($line, ':');
                if ($pos !== false) {
                    $current = strtolower(trim(substr($line, 0, $pos)));
                    $headers[$current] = trim(substr($line, $pos + 1));
                }
            }
        }
        return $headers;
    }

    private static function extractBoundary(string $contentType): ?string
    {
        if (preg_match('/boundary\s*=\s*"?([^";]+)"?/i', $contentType, $m)) {
            return $m[1];
        }
        return null;
    }

    private static function splitMultipart(string $body, string $boundary): array
    {
        $delimiter = '--' . $boundary;
        $parts = explode($delimiter, $body);
        $result = [];
        for ($i = 1; $i < count($parts); $i++) {
            $part = $parts[$i];
            if (strpos($part, '--') === 0) break;
            $part = ltrim($part, "\r\n");
            $result[] = $part;
        }
        return $result;
    }

    public static function processMimePart(string $part, array &$result): void
    {
        $split = preg_split("/\r?\n\r?\n/", $part, 2);
        $h = $split[0] ?? '';
        $b = $split[1] ?? '';
        $headers = self::parseHeaders($h);
        $contentType = $headers['content-type'] ?? 'text/plain';
        $contentTypeLower = strtolower($contentType);
        $encoding    = strtolower($headers['content-transfer-encoding'] ?? '7bit');
        $disposition = strtolower($headers['content-disposition'] ?? '');

        if (strpos($contentTypeLower, 'multipart/') === 0) {
            $boundary = self::extractBoundary($contentType);
            if ($boundary) {
                foreach (self::splitMultipart($b, $boundary) as $sub) {
                    self::processMimePart($sub, $result);
                }
            }
            return;
        }

        $decoded = self::decodeBody(rtrim($b, "\r\n"), $encoding);

        if (strpos($disposition, 'attachment') !== false || (strpos($contentTypeLower, 'application/') !== false && strpos($disposition, 'inline') === false)) {
            $filename = self::extractFilename($headers);
            $result['attachments'][] = [
                'filename'     => $filename,
                'content_type' => $contentType,
                'data'         => $decoded,
            ];
        } elseif (strpos($contentTypeLower, 'text/html') !== false) {
            $result['body_html'] .= $decoded;
        } else {
            $result['body_text'] .= $decoded;
        }
    }

    private static function extractFilename(array $headers): string
    {
        if (!empty($headers['content-disposition'])) {
            if (preg_match('/filename\*?=\s*"?([^";]+)"?/i', $headers['content-disposition'], $m)) {
                return self::decodeMime(trim($m[1]));
            }
        }
        if (!empty($headers['content-type']) && preg_match('/name\*?=\s*"?([^";]+)"?/i', $headers['content-type'], $m)) {
            return self::decodeMime(trim($m[1]));
        }
        return 'attachment';
    }

    private static function decodeBody(string $body, string $encoding): string
    {
        switch ($encoding) {
            case 'quoted-printable':
                return quoted_printable_decode($body);
            case 'base64':
                $body = preg_replace('/\s+/', '', $body);
                $decoded = base64_decode($body, true);
                return $decoded !== false ? $decoded : '';
            default:
                return $body;
        }
    }

    public static function decodeMime(string $str): string
    {
        if ($str === '') return '';
        // =?charset?Q?encoded?=  or =?charset?B?encoded?=
        if (strpos($str, '=?') !== false) {
            $decoded = iconv_mime_decode($str, ICONV_MIME_DECODE_CONTINUE_ON_ERROR, 'UTF-8');
            // iconv_mime_decode may fail on raw non-ASCII; fall back to original
            if ($decoded === '' && $str !== '') {
                return $str;
            }
            return $decoded;
        }
        return $str;
    }

    public static function encodeMime(string $str, string $charset = 'UTF-8'): string
    {
        if (preg_match('/[^\x20-\x7E]/', $str)) {
            return '=?' . $charset . '?B?' . base64_encode($str) . '?=';
        }
        return $str;
    }

    public static function extractName(string $addr): string
    {
        $info = self::parseAddress($addr);
        return $info['name'];
    }

    public static function parseAddressList(string $raw): array
    {
        $result = [];
        if ($raw === '') return $result;
        // 简化: 逗号分隔，但引号内不算
        $list = self::splitAddresses($raw);
        foreach ($list as $a) {
            $result[] = self::parseAddress($a);
        }
        return $result;
    }

    private static function splitAddresses(string $raw): array
    {
        $result = [];
        $buf = '';
        $inQuote = false;
        $len = strlen($raw);
        for ($i = 0; $i < $len; $i++) {
            $c = $raw[$i];
            if ($c === '"') { $inQuote = !$inQuote; $buf .= $c; continue; }
            if ($c === ',' && !$inQuote) {
                $result[] = trim($buf);
                $buf = '';
                continue;
            }
            $buf .= $c;
        }
        if (trim($buf) !== '') $result[] = trim($buf);
        return $result;
    }

    public static function parseAddress(string $raw): array
    {
        $raw = trim($raw);
        $name = '';
        $addr = '';
        if (preg_match('/^(.+?)\s*<([^>]+)>\s*$/', $raw, $m)) {
            $name = self::decodeMime(trim($m[1], " \t\""));
            $addr = trim($m[2]);
        } else {
            $addr = $raw;
        }
        return ['name' => $name, 'address' => strtolower($addr)];
    }

    /**
     * 构造简单邮件
     */
    public static function build(array $params): string
    {
        $from     = $params['from'];
        $to       = $params['to'];
        $subject  = $params['subject'] ?? '';
        $bodyText = $params['body_text'] ?? '';
        $bodyHtml = $params['body_html'] ?? '';
        $cc       = $params['cc'] ?? null;
        $bcc      = $params['bcc'] ?? null;
        $headers  = $params['headers'] ?? [];
        $boundary = '=_NextPart_' . md5(uniqid('', true));
        $messageId = '<' . bin2hex(random_bytes(16)) . '@' . ($headers['hostname'] ?? 'localhost') . '>';

        $lines = [];
        $lines[] = 'Date: ' . date('r');
        $lines[] = 'From: ' . self::formatAddress($from);
        if (is_array($to)) {
            $toList = array_map(fn($a) => is_array($a) ? self::formatAddress($a) : $a, $to);
            $lines[] = 'To: ' . implode(', ', $toList);
        } else {
            $lines[] = 'To: ' . $to;
        }
        if ($cc) {
            $ccList = is_array($cc) ? array_map(fn($a) => is_array($a) ? self::formatAddress($a) : $a, $cc) : [$cc];
            $lines[] = 'Cc: ' . implode(', ', $ccList);
        }
        if ($bcc) {
            $bccList = is_array($bcc) ? array_map(fn($a) => is_array($a) ? self::formatAddress($a) : $a, $bcc) : [$bcc];
            $lines[] = 'Bcc: ' . implode(', ', $bccList);
        }
        $lines[] = 'Subject: ' . self::encodeMime($subject);
        $lines[] = 'Message-ID: ' . $messageId;
        $lines[] = 'MIME-Version: 1.0';
        $lines[] = 'X-Mailer: MailSystem/1.0';
        $lines[] = "Content-Type: multipart/alternative; boundary=\"$boundary\"";

        $body = '';
        $body .= "--$boundary\r\n";
        $body .= "Content-Type: text/plain; charset=UTF-8\r\n";
        $body .= "Content-Transfer-Encoding: base64\r\n\r\n";
        $body .= chunk_split(base64_encode($bodyText)) . "\r\n";
        $body .= "--$boundary\r\n";
        $body .= "Content-Type: text/html; charset=UTF-8\r\n";
        $body .= "Content-Transfer-Encoding: base64\r\n\r\n";
        $body .= chunk_split(base64_encode($bodyHtml ?: '<pre>' . htmlspecialchars($bodyText) . '</pre>')) . "\r\n";
        $body .= "--$boundary--\r\n";

        return implode("\r\n", $lines) . "\r\n\r\n" . $body;
    }

    public static function formatAddress($a): string
    {
        if (is_string($a)) return $a;
        $addr = $a['address'] ?? ($a['email'] ?? '');
        $name = $a['name'] ?? '';
        if ($name) {
            return self::encodeMime($name) . ' <' . $addr . '>';
        }
        return $addr;
    }
}
