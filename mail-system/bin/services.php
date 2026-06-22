<?php
/**
 * 邮件服务启动脚本 (常驻进程)
 *
 * 用法:
 *   php bin/services.php start    - 启动所有启用服务
 *   php bin/services.php stop     - 停止所有服务
 *   php bin/services.php status   - 查看状态
 *   php bin/services.php restart  - 重启
 *   php bin/services.php test     - 测试 SMTP 连接
 */

require __DIR__ . '/../app/Core/Bootstrap.php';

use MailSystem\Services\ServiceManager;

$action = $argv[1] ?? 'status';
$manager = new ServiceManager();

switch ($action) {
    case 'start':
        echo "Starting mail services...\n";
        $manager->start();
        echo "Done.\n";
        break;
    case 'stop':
        echo "Stopping mail services...\n";
        $manager->stop();
        break;
    case 'status':
        $st = $manager->status();
        if (empty($st)) {
            echo "No services running.\n";
        } else {
            echo "Running services:\n";
            foreach ($st as $s) {
                echo "  PID {$s['pid']} ({$s['file']}) - " . ($s['alive'] ? 'ALIVE' : 'DEAD') . "\n";
            }
        }
        break;
    case 'restart':
        $manager->stop();
        sleep(1);
        $manager->start();
        echo "Restarted.\n";
        break;
    case 'test':
        $ports = \MailSystem\Models\Port::allEnabled();
        echo "Testing mail services...\n";
        foreach ($ports as $p) {
            $errno = 0; $errstr = '';
            $sock = @stream_socket_client("tcp://127.0.0.1:{$p['port']}", $errno, $errstr, 3);
            if ($sock) {
                stream_set_timeout($sock, 3);
                $banner = '';
                $r = [$sock]; $w = null; $e = null;
                if (@stream_select($r, $w, $e, 2) > 0) {
                    $banner = trim(fread($sock, 1024));
                }
                fclose($sock);
                echo "  [OK] {$p['service']} port {$p['port']}: $banner\n";
            } else {
                echo "  [FAIL] {$p['service']} port {$p['port']}: $errstr\n";
            }
        }
        break;
    default:
        echo "Usage: php bin/services.php {start|stop|status|restart|test}\n";
        break;
}
