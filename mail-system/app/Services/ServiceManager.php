<?php
/**
 * 邮件服务管理器 - 同时运行 SMTP/POP3/IMAP 守护进程
 *
 * 用法:
 *   php bin/services.php start
 *   php bin/services.php stop
 *   php bin/services.php status
 *   php bin/services.php restart
 */

namespace MailSystem\Services;

use MailSystem\Core\Logger;
use MailSystem\Models\Port;

class ServiceManager
{
    private Logger $logger;
    private array $servers = [];
    private string $pidDir;

    public function __construct()
    {
        $this->logger = new Logger();
        $this->pidDir = base_path('storage/cache');
        if (!is_dir($this->pidDir)) @mkdir($this->pidDir, 0755, true);
    }

    public function loadFromDb(): void
    {
        $ports = Port::allEnabled();
        foreach ($ports as $p) {
            $config = [
                'bind_ip' => $p['bind_ip'],
                'port'    => (int) $p['port'],
                'ssl'     => (bool) $p['ssl'],
                'tls'     => (bool) $p['tls'],
            ];
            $class = null;
            switch ($p['service']) {
                case 'smtp': $class = SmtpServer::class; break;
                case 'pop3': $class = Pop3Server::class; break;
                case 'imap': $class = ImapServer::class; break;
            }
            if ($class) {
                $this->servers[] = new $class($config);
            }
        }
    }

    public function start(): void
    {
        $this->logger->info('ServiceManager starting');
        $this->loadFromDb();
        if (empty($this->servers)) {
            echo "No enabled services to start\n";
            return;
        }
        foreach ($this->servers as $s) {
            try {
                // 启动一个独立进程
                $this->fork($s);
            } catch (\Throwable $e) {
                $this->logger->error('Start failed: ' . $e->getMessage());
            }
        }
    }

    public function stop(): void
    {
        foreach (glob($this->pidDir . '/mail-*.pid') as $f) {
            $pid = (int) file_get_contents($f);
            if ($pid > 0) {
                @posix_kill($pid, SIGTERM);
            }
            @unlink($f);
        }
        echo "Stopped.\n";
    }

    public function status(): array
    {
        $status = [];
        foreach (glob($this->pidDir . '/mail-*.pid') as $f) {
            $pid = (int) file_get_contents($f);
            $alive = $pid > 0 && @posix_kill($pid, 0);
            $status[] = ['pid' => $pid, 'file' => basename($f), 'alive' => $alive];
        }
        return $status;
    }

    private function fork($server): void
    {
        $portVal = $server->getPort();
        $service = $server->getService();
        $pidFile = "{$this->pidDir}/mail-{$service}-{$portVal}.pid";

        $pid = pcntl_fork();
        if ($pid === 0) {
            // 子进程 - 重置数据库连接以避免父进程 socket 继承问题
            if (class_exists('\MailSystem\Core\Database')) {
                \MailSystem\Core\Database::reset();
            }
            file_put_contents($pidFile, getmypid());
            $this->logger->info("$service started on port $portVal", ['pid' => getmypid()]);
            try {
                $server->start();
            } catch (\Throwable $e) {
                $this->logger->error("$service crashed: " . $e->getMessage());
            }
            exit(0);
        } elseif ($pid > 0) {
            // 父进程
            usleep(200000);
        } else {
            $this->logger->error("Failed to fork for $service:$portVal");
        }
    }
}
