<?php
/**
 * POP3 服务端 (支持明文 / SSL)
 *
 * 实现命令:
 *   USER, PASS, STAT, LIST, RETR, DELE, NOOP, QUIT, UIDL, TOP, CAPA
 */

namespace MailSystem\Services;

use MailSystem\Core\MailStorage;
use MailSystem\Models\Mailbox;

class Pop3Server extends BaseServer
{
    private string $hostname;

    public function __construct(array $config = [])
    {
        parent::__construct($config);
        $this->hostname = config('mail.hostname', 'mail.local');
    }

    protected function onConnect(int $cid): void
    {
        $this->setClientState($cid, 'authorize');
        $this->send($cid, "+OK MailSystem POP3 server ready\r\n");
    }

    protected function onClose(int $cid): void
    {
        $c = $this->getClient($cid);
        $this->logger->info('POP3 close', ['peer' => $c['peer'] ?? '']);
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

    private function handleCommand(int $cid, string $line): void
    {
        if ($line === '') return;
        $parts = explode(' ', $line, 2);
        $cmd = strtoupper($parts[0]);
        $arg = $parts[1] ?? '';
        $state = $this->getClientState($cid);
        $c = $this->getClient($cid);

        switch ($cmd) {
            case 'USER':
                if ($state !== 'authorize') { $this->send($cid, "-ERR Unknown state\r\n"); return; }
                $this->clients[$cid]['user'] = $arg;
                $this->send($cid, "+OK User accepted\r\n");
                break;
            case 'PASS':
                if ($state !== 'authorize' || empty($c['user'])) {
                    $this->send($cid, "-ERR USER first\r\n");
                    return;
                }
                $this->tryLogin($cid, $c['user'], $arg);
                break;
            case 'QUIT':
                $this->commitDeletes($cid);
                $this->send($cid, "+OK Bye\r\n");
                $this->closeClient($cid);
                break;
            case 'STAT':
                $this->cmdStat($cid);
                break;
            case 'LIST':
                $this->cmdList($cid, $arg);
                break;
            case 'RETR':
                $this->cmdRetr($cid, $arg);
                break;
            case 'DELE':
                $this->cmdDele($cid, $arg);
                break;
            case 'NOOP':
                $this->send($cid, "+OK\r\n");
                break;
            case 'RSET':
                $this->resetDeletes($cid);
                $this->send($cid, "+OK\r\n");
                break;
            case 'UIDL':
                $this->cmdUidl($cid, $arg);
                break;
            case 'TOP':
                $this->cmdTop($cid, $arg);
                break;
            case 'CAPA':
                $this->send($cid, "+OK Capabilities\r\n");
                $this->send($cid, "USER\r\n");
                $this->send($cid, "UIDL\r\n");
                $this->send($cid, "TOP\r\n");
                $this->send($cid, ".\r\n");
                break;
            default:
                $this->send($cid, "-ERR Unknown command\r\n");
        }
    }

    private function tryLogin(int $cid, string $user, string $pass): void
    {
        $mailbox = Mailbox::findByAddress($user);
        if (!$mailbox || !password_verify($pass, $mailbox['password'])) {
            $this->send($cid, "-ERR Invalid credentials\r\n");
            return;
        }
        $storage = new MailStorage($mailbox['full_address']);
        $emails = $storage->listFolder('INBOX');
        $this->clients[$cid]['mailbox']  = $mailbox;
        $this->clients[$cid]['storage']  = $storage;
        $this->clients[$cid]['emails']   = $emails;
        $this->clients[$cid]['delete']   = [];
        $this->setClientState($cid, 'transaction');
        $this->send($cid, "+OK Mailbox locked, " . count($emails) . " messages\r\n");
        $this->logger->info('POP3 login ok', ['user' => $user]);
    }

    private function cmdStat(int $cid): void
    {
        $emails = $this->clients[$cid]['emails'] ?? [];
        $count = 0;
        $size  = 0;
        $deleted = $this->clients[$cid]['delete'] ?? [];
        foreach ($emails as $i => $e) {
            if (in_array($i, $deleted, true)) continue;
            $count++;
            $size += $e['size'];
        }
        $this->send($cid, "+OK $count $size\r\n");
    }

    private function cmdList(int $cid, string $arg): void
    {
        $emails = $this->clients[$cid]['emails'] ?? [];
        $deleted = $this->clients[$cid]['delete'] ?? [];
        if ($arg === '') {
            $count = 0;
            foreach ($emails as $i => $e) if (!in_array($i, $deleted, true)) $count++;
            $this->send($cid, "+OK $count messages\r\n");
            foreach ($emails as $i => $e) {
                if (in_array($i, $deleted, true)) continue;
                $this->send($cid, ($i + 1) . ' ' . $e['size'] . "\r\n");
            }
            $this->send($cid, ".\r\n");
        } else {
            $idx = (int) $arg - 1;
            if (!isset($emails[$idx]) || in_array($idx, $deleted, true)) {
                $this->send($cid, "-ERR No such message\r\n");
                return;
            }
            $this->send($cid, "+OK {$emails[$idx]['size']}\r\n");
        }
    }

    private function cmdRetr(int $cid, string $arg): void
    {
        $idx = (int) $arg - 1;
        $emails = $this->clients[$cid]['emails'] ?? [];
        $deleted = $this->clients[$cid]['delete'] ?? [];
        if (!isset($emails[$idx]) || in_array($idx, $deleted, true)) {
            $this->send($cid, "-ERR No such message\r\n");
            return;
        }
        $content = $this->clients[$cid]['storage']->read($emails[$idx]['path']);
        if ($content === null) {
            $this->send($cid, "-ERR Read error\r\n");
            return;
        }
        // dot-stuff
        $content = preg_replace('/^\./', '..', $content);
        $this->send($cid, "+OK " . strlen($content) . " octets\r\n");
        $this->send($cid, $content . "\r\n.\r\n");
    }

    private function cmdDele(int $cid, string $arg): void
    {
        $idx = (int) $arg - 1;
        $emails = $this->clients[$cid]['emails'] ?? [];
        if (!isset($emails[$idx])) {
            $this->send($cid, "-ERR No such message\r\n");
            return;
        }
        $this->clients[$cid]['delete'][] = $idx;
        $this->send($cid, "+OK Message deleted\r\n");
    }

    private function cmdUidl(int $cid, string $arg): void
    {
        $emails = $this->clients[$cid]['emails'] ?? [];
        $deleted = $this->clients[$cid]['delete'] ?? [];
        if ($arg === '') {
            $this->send($cid, "+OK\r\n");
            foreach ($emails as $i => $e) {
                if (in_array($i, $deleted, true)) continue;
                $uid = substr(md5($e['path']), 0, 16);
                $this->send($cid, ($i + 1) . ' ' . $uid . "\r\n");
            }
            $this->send($cid, ".\r\n");
        } else {
            $idx = (int) $arg - 1;
            if (!isset($emails[$idx])) {
                $this->send($cid, "-ERR No such message\r\n");
                return;
            }
            $uid = substr(md5($emails[$idx]['path']), 0, 16);
            $this->send($cid, "+OK $uid\r\n");
        }
    }

    private function cmdTop(int $cid, string $arg): void
    {
        $parts = explode(' ', $arg);
        $idx = (int) ($parts[0] ?? 0) - 1;
        $lines = (int) ($parts[1] ?? 0);
        $emails = $this->clients[$cid]['emails'] ?? [];
        if (!isset($emails[$idx])) {
            $this->send($cid, "-ERR No such message\r\n");
            return;
        }
        $content = $this->clients[$cid]['storage']->read($emails[$idx]['path']);
        if ($content === null) {
            $this->send($cid, "-ERR Read error\r\n");
            return;
        }
        $split = preg_split("/\r?\n\r?\n/", $content, 2);
        $head = $split[0] ?? '';
        $body = $split[1] ?? '';
        $bodyLines = explode("\n", $body);
        $bodySnippet = implode("\r\n", array_slice($bodyLines, 0, $lines));
        $this->send($cid, "+OK\r\n");
        $this->send($cid, $head . "\r\n\r\n" . $bodySnippet . "\r\n.\r\n");
    }

    private function commitDeletes(int $cid): void
    {
        $emails = $this->clients[$cid]['emails'] ?? [];
        $deleted = $this->clients[$cid]['delete'] ?? [];
        $storage = $this->clients[$cid]['storage'] ?? null;
        if (!$storage) return;
        foreach ($deleted as $i) {
            if (isset($emails[$i])) {
                $storage->delete($emails[$i]['path']);
            }
        }
    }

    private function resetDeletes(int $cid): void
    {
        $this->clients[$cid]['delete'] = [];
    }
}
