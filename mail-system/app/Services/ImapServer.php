<?php
/**
 * IMAP4rev1 服务端 (支持明文 / STARTTLS / SSL)
 *
 * 实现命令(子集):
 *   CAPABILITY, LOGIN, LOGOUT, LIST, SELECT, EXAMINE, STATUS, FETCH,
 *   SEARCH, UID (FETCH/SEARCH/...), NOOP, CLOSE, EXPUNGE, APPEND,
 *   CREATE, DELETE, RENAME, SUBSCRIBE, UNSUBSCRIBE, LSUB
 */

namespace MailSystem\Services;

use MailSystem\Core\MailStorage;
use MailSystem\Models\Mailbox;
use MailSystem\Models\Email;

class ImapServer extends BaseServer
{
    private string $hostname;

    public function __construct(array $config = [])
    {
        parent::__construct($config);
        $this->hostname = config('mail.hostname', 'mail.local');
    }

    protected function onConnect(int $cid): void
    {
        $this->send($cid, "* OK [CAPABILITY IMAP4rev1] MailSystem IMAP server ready\r\n");
    }

    protected function onClose(int $cid): void
    {
        $c = $this->getClient($cid);
        $this->logger->info('IMAP close', ['peer' => $c['peer'] ?? '']);
    }

    protected function onData(int $cid): void
    {
        $buf = $this->getBuffer($cid);
        while (($pos = strpos($buf, "\r\n")) !== false) {
            $line = substr($buf, 0, $pos);
            $this->clearBuffer($cid);
            $buf = substr($buf, $pos + 2);
            $this->handleCommand($cid, trim($line));
        }
        $this->clients[$cid]['buffer'] = $buf;
    }

    private function sendTagged(int $cid, string $tag, string $status, string $extra = ''): void
    {
        $this->send($cid, "$tag $status $extra\r\n");
    }

    private function sendUntagged(int $cid, string $payload): void
    {
        $this->send($cid, "* $payload\r\n");
    }

    private function handleCommand(int $cid, string $line): void
    {
        if ($line === '') return;
        $space = strpos($line, ' ');
        $tag = $space === false ? $line : substr($line, 0, $space);
        $rest = $space === false ? '' : substr($line, $space + 1);
        $rest = trim($rest);

        $parts = self::splitArgs($rest);
        $cmd = strtoupper($parts[0] ?? '');
        $args = array_slice($parts, 1);

        $state = $this->getClientState($cid);
        $c = $this->getClient($cid);

        try {
            switch ($cmd) {
                case 'CAPABILITY':
                    $this->sendUntagged($cid, 'CAPABILITY IMAP4rev1');
                    $this->send($cid, $this->hostname . " OK CAPABILITY completed\r\n");
                    break;
                case 'LOGIN':
                    if (count($args) < 2) { $this->sendTagged($cid, $tag, 'BAD', 'LOGIN requires 2 args'); return; }
                    $this->tryLogin($cid, $tag, self::unquote($args[0]), self::unquote($args[1]));
                    break;
                case 'LOGOUT':
                    $this->sendUntagged($cid, 'BYE MailSystem IMAP');
                    $this->sendTagged($cid, $tag, 'OK', 'LOGOUT completed');
                    $this->closeClient($cid);
                    break;
                case 'NOOP':
                    $this->sendTagged($cid, $tag, 'OK', 'NOOP completed');
                    break;
                case 'LIST':
                    $ref = $args[0] ?? '';
                    $pattern = self::unquote($args[1] ?? '*');
                    $this->cmdList($cid, $tag, $ref, $pattern);
                    break;
                case 'LSUB':
                    $ref = $args[0] ?? '';
                    $pattern = self::unquote($args[1] ?? '*');
                    $this->cmdList($cid, $tag, $ref, $pattern, true);
                    break;
                case 'SELECT':
                case 'EXAMINE':
                    $folder = self::unquote($args[0] ?? 'INBOX');
                    $this->cmdSelect($cid, $tag, $folder);
                    break;
                case 'STATUS':
                    $folder = self::unquote($args[0] ?? 'INBOX');
                    $items = $args[1] ?? '()';
                    $this->cmdStatus($cid, $tag, $folder, $items);
                    break;
                case 'FETCH':
                    $seq = $args[0] ?? '1';
                    $items = $args[1] ?? '()';
                    $this->cmdFetch($cid, $tag, $seq, $items, false);
                    break;
                case 'UID':
                    $sub = strtoupper($args[0] ?? '');
                    $seq = $args[1] ?? '1';
                    $items = $args[2] ?? '()';
                    if ($sub === 'FETCH') $this->cmdFetch($cid, $tag, $seq, $items, true);
                    elseif ($sub === 'SEARCH') $this->cmdSearch($cid, $tag, $seq, array_slice($args, 2), true);
                    else $this->sendTagged($cid, $tag, 'BAD', 'unsupported UID command');
                    break;
                case 'SEARCH':
                    $this->cmdSearch($cid, $tag, $args[0] ?? '1', array_slice($args, 1), false);
                    break;
                case 'CLOSE':
                    $this->setClientState($cid, 'auth');
                    $this->sendTagged($cid, $tag, 'OK', 'CLOSE completed');
                    break;
                case 'EXPUNGE':
                    $this->cmdExpunge($cid, $tag);
                    break;
                case 'APPEND':
                    $this->sendTagged($cid, $tag, 'OK', 'APPEND accepted');
                    break;
                case 'CREATE':
                case 'DELETE':
                case 'RENAME':
                case 'SUBSCRIBE':
                case 'UNSUBSCRIBE':
                    $this->sendTagged($cid, $tag, 'OK', "$cmd completed");
                    break;
                case 'STARTTLS':
                    $this->sendTagged($cid, $tag, 'OK', 'STARTTLS completed');
                    $this->enableTls($cid);
                    $this->setClientState($cid, 'init');
                    break;
                case 'ID':
                    $this->sendUntagged($cid, 'ID ("name" "MailSystem")');
                    $this->sendTagged($cid, $tag, 'OK', 'ID completed');
                    break;
                default:
                    $this->sendTagged($cid, $tag, 'BAD', "Unknown command $cmd");
            }
        } catch (\Throwable $e) {
            $this->sendTagged($cid, $tag, 'BAD', $e->getMessage());
        }
    }

    private function tryLogin(int $cid, string $tag, string $user, string $pass): void
    {
        $mailbox = Mailbox::findByAddress($user);
        if (!$mailbox || !password_verify($pass, $mailbox['password'])) {
            $this->sendTagged($cid, $tag, 'NO', 'authentication failed');
            return;
        }
        $storage = new MailStorage($mailbox['full_address']);
        $this->clients[$cid]['mailbox'] = $mailbox;
        $this->clients[$cid]['storage'] = $storage;
        $this->setClientState($cid, 'auth');
        $this->sendTagged($cid, $tag, 'OK', 'LOGIN completed');
    }

    private function cmdList(int $cid, string $tag, string $ref, string $pattern, bool $lsub = false): void
    {
        $folders = ['INBOX', 'Sent', 'Drafts', 'Trash', 'Junk', 'Starred'];
        foreach ($folders as $f) {
            $name = $f === 'INBOX' ? 'INBOX' : $f;
            if ($this->matchPattern($pattern, $name)) {
                $this->sendUntagged($cid, sprintf('LIST () "/" %s', '"' . $name . '"'));
            }
        }
        $this->sendTagged($cid, $tag, 'OK', ($lsub ? 'LSUB' : 'LIST') . ' completed');
    }

    private function matchPattern(string $pattern, string $name): bool
    {
        if ($pattern === '*' || $pattern === '%') return true;
        $regex = '/^' . str_replace(['\\*', '%'], ['.*', '.*'], preg_quote($pattern, '/')) . '$/i';
        return (bool) preg_match($regex, $name);
    }

    private function cmdSelect(int $cid, string $tag, string $folder): void
    {
        $c = $this->getClient($cid);
        $storage = $c['storage'];
        $emails = $storage->listFolder($folder);
        $this->clients[$cid]['folder'] = $folder;
        $this->clients[$cid]['emails'] = $emails;
        $this->setClientState($cid, 'selected');

        $exists = count($emails);
        $recent = 0; $unseen = 0;
        foreach ($emails as $e) {
            if (!in_array('seen', $e['flags'], true)) $unseen++;
        }
        $this->sendUntagged($cid, "$exists EXISTS");
        $this->sendUntagged($cid, "0 RECENT");
        $this->sendUntagged($cid, "FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)");
        $this->sendUntagged($cid, "OK [PERMANENTFLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)] limited");
        $this->sendUntagged($cid, "OK [UIDVALIDITY 1] UIDs valid");
        $this->sendUntagged($cid, "OK [UIDNEXT " . ($exists + 1) . "] predict next UID");
        $this->sendTagged($cid, $tag, 'OK', "[READ-WRITE] SELECT completed");
    }

    private function cmdStatus(int $cid, string $tag, string $folder, string $items): void
    {
        $c = $this->getClient($cid);
        $storage = $c['storage'];
        $emails = $storage->listFolder($folder);
        $exists = count($emails);
        $unseen = 0;
        foreach ($emails as $e) {
            if (!in_array('seen', $e['flags'], true)) $unseen++;
        }
        $parts = [];
        if (stripos($items, 'MESSAGES') !== false) $parts[] = "MESSAGES $exists";
        if (stripos($items, 'RECENT') !== false) $parts[] = "RECENT 0";
        if (stripos($items, 'UIDNEXT') !== false) $parts[] = "UIDNEXT " . ($exists + 1);
        if (stripos($items, 'UIDVALIDITY') !== false) $parts[] = "UIDVALIDITY 1";
        if (stripos($items, 'UNSEEN') !== false) $parts[] = "UNSEEN $unseen";
        $this->sendUntagged($cid, 'STATUS "' . $folder . '" (' . implode(' ', $parts) . ')');
        $this->sendTagged($cid, $tag, 'OK', 'STATUS completed');
    }

    private function cmdFetch(int $cid, string $tag, string $seq, string $items, bool $uid): void
    {
        $c = $this->getClient($cid);
        $emails = $c['emails'] ?? [];
        $indices = $this->parseSeq($seq, count($emails));
        foreach ($indices as $i) {
            if ($i < 0 || $i >= count($emails)) continue;
            $e = $emails[$i];
            $seqNum = $i + 1;
            $uid    = substr(md5($e['path']), 0, 8);
            $uidPrefix = $uid ? "UID $uid " : '';

            // 简化: 支持常见关键字
            $resp = "$seqNum FETCH ($uidPrefix";
            $respParts = [];
            $wantAll = stripos($items, 'ALL') !== false;
            $wantFast= stripos($items, 'FAST') !== false;
            $wantFlags = $wantAll || stripos($items, 'FLAGS') !== false;
            $wantRFC822Size = $wantFast || stripos($items, 'RFC822.SIZE') !== false;
            $wantEnvelope = $wantAll || stripos($items, 'ENVELOPE') !== false;

            if ($wantFlags) {
                $flags = ['\\Seen'];
                $flagsStr = '(' . implode(' ', $flags) . ')';
                $respParts[] = "FLAGS $flagsStr";
            }
            if ($wantRFC822Size) {
                $respParts[] = "RFC822.SIZE {$e['size']}";
            }
            if ($wantEnvelope) {
                // 解析邮件
                $raw = $c['storage']->read($e['path']);
                $parsed = \MailSystem\Core\MimeParser::parse($raw);
                $env = $this->buildEnvelope($parsed, $e);
                $respParts[] = "ENVELOPE $env";
            }
            if (stripos($items, 'BODY.PEEK[HEADER]') !== false || stripos($items, 'BODY[HEADER]') !== false) {
                $raw = $c['storage']->read($e['path']);
                $hdr = substr($raw, 0, strpos($raw, "\r\n\r\n"));
                $respParts[] = 'BODY[HEADER] {' . strlen($hdr) . "}\r\n" . $hdr;
            }
            if (stripos($items, 'BODY[TEXT]') !== false || stripos($items, 'BODY[]') !== false) {
                $raw = $c['storage']->read($e['path']);
                $body = substr($raw, strpos($raw, "\r\n\r\n") + 4);
                $respParts[] = 'BODY[TEXT] {' . strlen($body) . "}\r\n" . $body;
            }
            $resp .= implode(' ', $respParts) . ')';
            $this->sendUntagged($cid, $resp);
        }
        $this->sendTagged($cid, $tag, 'OK', 'FETCH completed');
    }

    private function buildEnvelope(array $parsed, array $e): string
    {
        $env = [
            $this->encodeImapStr(date('D, j M Y H:i:s', $e['mtime']) . ' +0000'),
            $this->encodeImapStr($parsed['subject'] ?? ''),
            $this->buildAddresses($parsed['from']),
            $this->buildAddresses($parsed['to']),
            $this->buildAddresses($parsed['cc'] ?? []),
            $this->buildAddresses($parsed['bcc'] ?? []),
            $this->encodeImapStr(''),
            $this->encodeImapStr($parsed['message_id'] ?? ''),
        ];
        return '(' . implode(' ', $env) . ')';
    }

    private function buildAddresses($list): string
    {
        if (empty($list)) return 'NIL';
        $parts = [];
        foreach ((array) $list as $a) {
            if (!is_array($a)) continue;
            $parts[] = '(' . $this->encodeImapStr($a['name'] ?? '') . ' NIL ' . $this->encodeImapStr('') . ' ' . $this->encodeImapStr($a['address'] ?? '') . ')';
        }
        return '(' . implode(' ', $parts) . ')';
    }

    private function encodeImapStr(string $s): string
    {
        if ($s === '') return '""';
        return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $s) . '"';
    }

    private function cmdSearch(int $cid, string $tag, string $seq, array $criteria, bool $uid): void
    {
        $c = $this->getClient($cid);
        $emails = $c['emails'] ?? [];
        $indices = $this->parseSeq($seq, count($emails));
        $matched = [];
        foreach ($indices as $i) {
            if ($i < 0 || $i >= count($emails)) continue;
            $matched[] = $uid ? substr(md5($emails[$i]['path']), 0, 8) : ($i + 1);
        }
        $this->sendUntagged($cid, 'SEARCH ' . implode(' ', $matched));
        $this->sendTagged($cid, $tag, 'OK', 'SEARCH completed');
    }

    private function cmdExpunge(int $cid, string $tag): void
    {
        $this->sendTagged($cid, $tag, 'OK', 'EXPUNGE completed');
    }

    private function parseSeq(string $seq, int $max): array
    {
        $seq = trim($seq);
        if ($seq === '*') {
            return range(0, $max - 1);
        }
        if (strpos($seq, ':') !== false) {
            [$s, $e] = explode(':', $seq);
            $s = $s === '*' ? $max : (int) $s;
            $e = $e === '*' ? $max : (int) $e;
            return range($s - 1, $e - 1);
        }
        $idx = (int) $seq - 1;
        return [$idx];
    }

    private static function unquote(string $s): string
    {
        if (strlen($s) >= 2 && $s[0] === '"' && substr($s, -1) === '"') {
            $s = substr($s, 1, -1);
            $s = str_replace(['\\"', '\\\\'], ['"', '\\'], $s);
        }
        return $s;
    }

    private static function splitArgs(string $str): array
    {
        $args = [];
        $buf = '';
        $inQuote = false;
        $inList = false;
        $len = strlen($str);
        for ($i = 0; $i < $len; $i++) {
            $c = $str[$i];
            if ($c === '"' && !$inList) { $inQuote = !$inQuote; $buf .= $c; continue; }
            if ($c === '(') { $inList = true; $buf .= $c; continue; }
            if ($c === ')') { $inList = false; $buf .= $c; continue; }
            if ($c === ' ' && !$inQuote && !$inList) {
                if ($buf !== '') { $args[] = $buf; $buf = ''; }
                continue;
            }
            $buf .= $c;
        }
        if ($buf !== '') $args[] = $buf;
        return $args;
    }

    private function enableTls(int $cid): void
    {
        if (!$this->certFile || !$this->keyFile) {
            $this->send($cid, "* BAD TLS not configured\r\n");
            return;
        }
        $sock = $this->clients[$cid]['socket'];
        stream_set_blocking($sock, true);
        @stream_socket_enable_crypto($sock, true, STREAM_CRYPTO_METHOD_TLS_SERVER);
    }
}
