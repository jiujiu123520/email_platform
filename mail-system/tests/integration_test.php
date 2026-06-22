<?php
// 集成测试: 启动 SMTP/POP3/IMAP 服务并验证
error_reporting(E_ALL);
ini_set('display_errors', '1');

$base = '/workspace/mail-system';
chdir($base);

require $base . '/config/helpers.php';
require $base . '/app/Core/Bootstrap.php';

use MailSystem\Core\Database;
use MailSystem\Models\Port;
use MailSystem\Models\Setting;

echo "=== 集成测试 ===\n\n";

// 1. 数据库连接
echo "1. 数据库连接\n";
try {
    $pdo = Database::getInstance();
    echo "  ✓ PDO connected\n";
    $row = $pdo->query("SELECT COUNT(*) c FROM ms_ports")->fetch();
    echo "  ✓ ms_ports has " . $row['c'] . " rows\n";
    $row = $pdo->query("SELECT COUNT(*) c FROM ms_settings")->fetch();
    echo "  ✓ ms_settings has " . $row['c'] . " rows\n";
} catch (Throwable $e) {
    echo "  ✗ DB error: " . $e->getMessage() . "\n";
    exit(1);
}

// 2. 端口管理
echo "\n2. 端口管理\n";
$ports = Port::all();
echo "  ✓ Found " . count($ports) . " ports\n";
foreach ($ports as $p) {
    echo "    - {$p['service']} :{$p['port']} (ssl=" . ($p['ssl'] ? 'Y' : 'N') . ")\n";
}

// 3. 创建测试数据
echo "\n3. 创建测试数据\n";
try {
    $pdo = Database::getInstance();
    $pdo->query("DELETE FROM ms_mailboxes WHERE full_address = 'admin@test.local'");
    $pdo->query("DELETE FROM ms_domains WHERE domain = 'test.local'");
    $pdo->query("DELETE FROM ms_users WHERE username = 'testadmin'");

    $hash = password_hash('test123', PASSWORD_DEFAULT);
    $stmt = $pdo->pdo()->prepare(
        "INSERT INTO ms_users (username, password, email, display_name, role, status) VALUES (?, ?, ?, ?, ?, 1)"
    );
    $stmt->execute(['testadmin', $hash, 'admin@test.local', 'Test Admin', 'admin']);
    $userId = (int) $pdo->pdo()->lastInsertId();
    echo "  ✓ User created (id=$userId)\n";

    $stmt = $pdo->pdo()->prepare(
        "INSERT INTO ms_domains (domain, owner_id, status, is_default) VALUES (?, ?, 1, 1)"
    );
    $stmt->execute(['test.local', $userId]);
    $domainId = (int) $pdo->pdo()->lastInsertId();
    echo "  ✓ Domain created (id=$domainId)\n";

    $stmt = $pdo->pdo()->prepare(
        "INSERT INTO ms_mailboxes (user_id, domain_id, local_part, full_address, password, display_name, status) VALUES (?, ?, ?, ?, ?, ?, 1)"
    );
    $stmt->execute([$userId, $domainId, 'admin', 'admin@test.local', $hash, 'Admin']);
    $mailboxId = (int) $pdo->pdo()->lastInsertId();
    echo "  ✓ Mailbox created (id=$mailboxId)\n";

} catch (Throwable $e) {
    echo "  ✗ Error: " . $e->getMessage() . "\n";
    exit(1);
}

// 4. 设置 hostname
echo "\n4. 设置 hostname\n";
Setting::set('mail_hostname', 'mail.test.local');
$h = Setting::get('mail_hostname');
echo "  ✓ mail_hostname = $h\n";

// 5. 启动服务
echo "\n5. 启动服务 (在后台)\n";
$smtpPort = 25025;
$pop3Port = 25110;
$imapPort = 25143;

$services = [];
$services[] = new \MailSystem\Services\SmtpServer([
    'bind_ip' => '127.0.0.1',
    'port'    => $smtpPort,
    'ssl'     => false,
    'tls'     => false,
]);
$services[] = new \MailSystem\Services\Pop3Server([
    'bind_ip' => '127.0.0.1',
    'port'    => $pop3Port,
    'ssl'     => false,
]);
$services[] = new \MailSystem\Services\ImapServer([
    'bind_ip' => '127.0.0.1',
    'port'    => $imapPort,
    'ssl'     => false,
]);

$pidDir = $base . '/storage/cache';
if (!is_dir($pidDir)) @mkdir($pidDir, 0755, true);

if (!function_exists('pcntl_fork')) {
    echo "  ✗ pcntl extension is required for service tests\n";
    exit(1);
}

$pids = [];
foreach ($services as $s) {
    $pid = pcntl_fork();
    if ($pid === 0) {
        // child
        // 重置数据库连接，避免父进程 socket 继承问题
        \MailSystem\Core\Database::reset();
        $ref = new \ReflectionClass($s);
        $portProp = $ref->getProperty('port');
        $portProp->setAccessible(true);
        $portVal = $portProp->getValue($s);
        $name = strtolower(str_replace('Server', '', $ref->getShortName()));
        $pidFile = "$pidDir/test-mail-{$name}-{$portVal}.pid";
        file_put_contents($pidFile, getmypid());
        try {
            $s->start();
        } catch (\Throwable $e) {
            fwrite(STDERR, "Service error: " . $e->getMessage() . "\n");
        }
        exit(0);
    } else {
        $pids[] = $pid;
    }
}
echo "  ✓ Started " . count($pids) . " services (PIDs: " . implode(',', $pids) . ")\n";
sleep(2);

// 6. SMTP 简单握手测试
echo "\n6. SMTP 握手测试\n";
$fp = @fsockopen('127.0.0.1', $smtpPort, $errno, $errstr, 3);
if ($fp) {
    $banner = fgets($fp, 1024);
    echo "  ✓ Banner: " . trim($banner) . "\n";
    fwrite($fp, "EHLO test.local\r\n");
    $cap = '';
    while (($line = fgets($fp, 1024)) !== false) {
        $cap .= $line;
        if (substr($line, 3, 1) === ' ') break;
    }
    echo "  ✓ EHLO OK (got " . substr_count($cap, "\n") . " lines)\n";
    if (strpos($cap, 'AUTH') !== false) echo "  ✓ AUTH advertised\n";
    if (strpos($cap, 'STARTTLS') !== false) echo "  ✓ STARTTLS advertised\n";
    fwrite($fp, "QUIT\r\n");
    fclose($fp);
} else {
    echo "  ✗ Cannot connect to SMTP: $errstr\n";
}

// 7. POP3 简单握手测试
echo "\n7. POP3 握手测试\n";
$fp = @fsockopen('127.0.0.1', $pop3Port, $errno, $errstr, 3);
if ($fp) {
    $banner = fgets($fp, 1024);
    echo "  ✓ Banner: " . trim($banner) . "\n";
    fwrite($fp, "USER admin@test.local\r\n");
    echo "  ✓ USER: " . trim(fgets($fp, 1024)) . "\n";
    fwrite($fp, "PASS test123\r\n");
    echo "  ✓ PASS: " . trim(fgets($fp, 1024)) . "\n";
    fwrite($fp, "STAT\r\n");
    echo "  ✓ STAT: " . trim(fgets($fp, 1024)) . "\n";
    fwrite($fp, "QUIT\r\n");
    fclose($fp);
} else {
    echo "  ✗ Cannot connect to POP3: $errstr\n";
}

// 8. IMAP 简单握手测试
echo "\n8. IMAP 握手测试\n";
$fp = @fsockopen('127.0.0.1', $imapPort, $errno, $errstr, 3);
if ($fp) {
    $banner = fgets($fp, 1024);
    echo "  ✓ Banner: " . trim($banner) . "\n";
    fwrite($fp, "A001 CAPABILITY\r\n");
    $cap = '';
    while (($line = fgets($fp, 1024)) !== false) {
        $cap .= $line;
        if (substr($line, 0, 1) === 'A' && strpos($line, ' OK') !== false) break;
    }
    echo "  ✓ CAPABILITY OK (" . substr_count($cap, "\n") . " lines)\n";
    fwrite($fp, "A002 LOGIN admin@test.local test123\r\n");
    $line = fgets($fp, 1024);
    echo "  ✓ LOGIN: " . trim($line) . "\n";
    fwrite($fp, "A003 LOGOUT\r\n");
    fclose($fp);
} else {
    echo "  ✗ Cannot connect to IMAP: $errstr\n";
}

// 9. 邮件投递测试 (SMTP -> Maildir)
echo "\n9. 邮件投递测试 (SMTP -> Maildir)\n";
$fp = @fsockopen('127.0.0.1', $smtpPort, $errno, $errstr, 3);
if ($fp) {
    fgets($fp, 1024); // banner
    fwrite($fp, "EHLO test.local\r\n");
    while (substr(fgets($fp, 1024), 3, 1) === '-') { }
    fwrite($fp, "MAIL FROM:<from@example.com>\r\n");
    echo "  MAIL FROM: " . trim(fgets($fp, 1024)) . "\n";
    fwrite($fp, "RCPT TO:<admin@test.local>\r\n");
    echo "  RCPT TO: " . trim(fgets($fp, 1024)) . "\n";
    fwrite($fp, "DATA\r\n");
    echo "  DATA: " . trim(fgets($fp, 1024)) . "\n";
    $msg = "From: from@example.com\r\nTo: admin@test.local\r\nSubject: Test Mail\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nThis is a test email body.\r\n.\r\n";
    fwrite($fp, $msg);
    echo "  Response: " . trim(fgets($fp, 1024)) . "\n";
    fwrite($fp, "QUIT\r\n");
    fclose($fp);
} else {
    echo "  ✗ Cannot connect: $errstr\n";
}

// Wait for delivery
sleep(1);
$mailboxDir = $base . '/data/mailboxes/admin@test.local/new';
if (is_dir($mailboxDir)) {
    $files = glob($mailboxDir . '/*');
    echo "  ✓ Mailbox has " . count($files) . " files in new/\n";
    if (count($files) > 0) {
        $content = file_get_contents($files[0]);
        if (strpos($content, 'Subject: Test Mail') !== false) {
            echo "  ✓ Subject found in delivered mail\n";
        }
    }
} else {
    echo "  ✗ Mailbox dir not created: $mailboxDir\n";
}

// 10. POP3 接收测试
echo "\n10. POP3 接收测试 (STAT/LIST/RETR)\n";
$fp = @fsockopen('127.0.0.1', $pop3Port, $errno, $errstr, 3);
if ($fp) {
    fgets($fp, 1024);
    fwrite($fp, "USER admin@test.local\r\n");
    fgets($fp, 1024);
    fwrite($fp, "PASS test123\r\n");
    fgets($fp, 1024);
    fwrite($fp, "STAT\r\n");
    $stat = trim(fgets($fp, 1024));
    echo "  ✓ STAT: $stat\n";
    fwrite($fp, "LIST\r\n");
    $listResp = '';
    while (($line = fgets($fp, 1024)) !== false) {
        $listResp .= $line;
        if (trim($line) === '.') break;
    }
    echo "  ✓ LIST: " . count(explode("\n", trim($listResp))) . " entries\n";
    fwrite($fp, "RETR 1\r\n");
    $retr = '';
    while (($line = fgets($fp, 4096)) !== false) {
        $retr .= $line;
        if (trim($line) === '.') break;
    }
    if (strpos($retr, 'Test Mail') !== false) {
        echo "  ✓ RETR retrieved the email\n";
    } else {
        echo "  ✗ RETR body did not match\n";
    }
    fwrite($fp, "QUIT\r\n");
    fclose($fp);
}

// 11. 停止服务
echo "\n11. 停止服务\n";
foreach (glob("$pidDir/test-mail-*.pid") as $f) {
    $pid = (int) file_get_contents($f);
    if ($pid > 0) @posix_kill($pid, SIGTERM);
    @unlink($f);
}
sleep(1);
echo "  ✓ Services stopped\n";

// 清理测试数据
echo "\n12. 清理测试数据\n";
$pdo = Database::getInstance();
$pdo->query("DELETE FROM ms_mailboxes WHERE full_address = 'admin@test.local'");
$pdo->query("DELETE FROM ms_domains WHERE domain = 'test.local'");
$pdo->query("DELETE FROM ms_users WHERE username = 'testadmin'");
echo "  ✓ Cleaned up\n";

echo "\n=== 集成测试完成 ===\n";
