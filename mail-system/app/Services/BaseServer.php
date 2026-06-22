<?php
/**
 * 邮件协议服务端基类 - 通用 Socket 服务
 */

namespace MailSystem\Services;

use MailSystem\Core\Logger;

abstract class BaseServer
{
    protected string $bindIp = '0.0.0.0';
    protected int $port;
    protected bool $ssl = false;
    protected bool $tls = false;
    protected ?string $certFile = null;
    protected ?string $keyFile = null;
    protected Logger $logger;
    protected $socket = null;
    protected bool $running = false;
    protected int $maxClients = 50;
    protected int $timeout = 600;
    protected array $clients = [];
    protected int $clientCounter = 0;

    public function __construct(array $config = [])
    {
        $this->bindIp   = $config['bind_ip'] ?? '0.0.0.0';
        $this->port     = (int) ($config['port'] ?? 0);
        $this->ssl      = (bool) ($config['ssl'] ?? false);
        $this->tls      = (bool) ($config['tls'] ?? false);
        $this->certFile = $config['cert'] ?? config('mail.ssl_cert', '') ?: null;
        $this->keyFile  = $config['key']  ?? config('mail.ssl_key', '')  ?: null;
        $this->logger   = new Logger();
    }

    public function getPort(): int { return $this->port; }

    public function getService(): string
    {
        $cls = get_class($this);
        $cls = substr($cls, strrpos($cls, '\\') + 1);
        return strtolower(str_replace('Server', '', $cls));
    }

    public function start(): void
    {
        $ctx = stream_context_create();
        if (($this->ssl || $this->tls) && $this->certFile && $this->keyFile && file_exists($this->certFile)) {
            stream_context_set_option($ctx, 'ssl', 'local_cert', $this->certFile);
            stream_context_set_option($ctx, 'ssl', 'local_key',  $this->keyFile);
            stream_context_set_option($ctx, 'ssl', 'verify_peer', false);
        }

        $address = "tcp://{$this->bindIp}:{$this->port}";
        $errno = 0; $errstr = '';
        $this->socket = @stream_socket_server(
            $address,
            $errno,
            $errstr,
            STREAM_SERVER_BIND | STREAM_SERVER_LISTEN,
            ($this->ssl && $this->certFile && $this->keyFile) ? $ctx : null
        );
        if (!$this->socket) {
            throw new \RuntimeException("无法监听 {$address}: {$errstr} ({$errno})");
        }
        stream_set_blocking($this->socket, false);
        $this->running = true;
        $this->logger->info(static::class . " listening on {$address}");

        $this->loop();
    }

    public function stop(): void
    {
        $this->running = false;
        foreach ($this->clients as $cid => $c) {
            $this->closeClient($cid);
        }
        if ($this->socket) {
            @fclose($this->socket);
            $this->socket = null;
        }
    }

    protected function loop(): void
    {
        $lastIdleCheck = time();
        while ($this->running) {
            $read = [$this->socket];
            $write = null;
            $except = null;
            $changed = @stream_select($read, $write, $except, 1);
            if ($changed > 0) {
                $client = @stream_socket_accept($this->socket, 30, $peer);
                if ($client) {
                    if (count($this->clients) >= $this->maxClients) {
                        @fclose($client);
                        continue;
                    }
                    $cid = ++$this->clientCounter;
                    stream_set_blocking($client, true);
                    stream_set_timeout($client, 30);
                    $this->clients[$cid] = [
                        'socket'   => $client,
                        'peer'     => $peer,
                        'buffer'   => '',
                        'last_active' => time(),
                        'state'    => 'init',
                    ];
                    $this->onConnect($cid);
                }
            }

            // 复制 keys 以便在迭代中安全修改
            $cids = array_keys($this->clients);
            foreach ($cids as $cid) {
                if (!isset($this->clients[$cid])) continue;
                $c = $this->clients[$cid];
                $sock = $c['socket'] ?? null;
                if (!is_resource($sock)) {
                    $this->closeClient($cid);
                    continue;
                }
                $r = [$sock]; $w = null; $e = null;
                $changed = @stream_select($r, $w, $e, 0, 200000);
                if ($changed === false || $changed < 0) {
                    continue;
                }
                if ($changed > 0) {
                    $data = @fread($sock, 8192);
                    if ($data === '' || $data === false) {
                        if (feof($sock)) {
                            $this->closeClient($cid);
                            continue;
                        }
                    } elseif ($data !== false) {
                        $this->clients[$cid]['buffer'] .= $data;
                        $this->clients[$cid]['last_active'] = time();
                        $this->onData($cid);
                    }
                }
                if (isset($this->clients[$cid])) {
                    $last = $this->clients[$cid]['last_active'] ?? time();
                    if (time() - $last > $this->timeout) {
                        $this->closeClient($cid);
                    }
                }
            }

            if (time() - $lastIdleCheck > 30) {
                $lastIdleCheck = time();
                if (function_exists('gc_collect_cycles')) gc_collect_cycles();
            }
        }
    }

    protected function send(int $cid, string $data): void
    {
        if (!isset($this->clients[$cid])) return;
        @fwrite($this->clients[$cid]['socket'], $data);
        $this->clients[$cid]['last_active'] = time();
    }

    protected function closeClient(int $cid): void
    {
        if (!isset($this->clients[$cid])) return;
        $sock = $this->clients[$cid]['socket'] ?? null;
        if (is_resource($sock)) {
            @fclose($sock);
        }
        $this->onClose($cid);
        unset($this->clients[$cid]);
    }

    protected function getClient(int $cid): array
    {
        return $this->clients[$cid] ?? [];
    }

    protected function setClientState(int $cid, string $state): void
    {
        if (isset($this->clients[$cid])) {
            $this->clients[$cid]['state'] = $state;
        }
    }

    protected function getClientState(int $cid): string
    {
        return $this->clients[$cid]['state'] ?? '';
    }

    protected function getBuffer(int $cid): string
    {
        return $this->clients[$cid]['buffer'] ?? '';
    }

    protected function clearBuffer(int $cid): void
    {
        if (isset($this->clients[$cid])) $this->clients[$cid]['buffer'] = '';
    }

    abstract protected function onConnect(int $cid): void;
    abstract protected function onData(int $cid): void;
    abstract protected function onClose(int $cid): void;
}
