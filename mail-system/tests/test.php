<?php
/**
 * MailSystem 自检测试脚本
 *
 * 运行: php tests/test.php
 *
 * 测试项:
 *   1. PHP 扩展检测
 *   2. 配置加载
 *   3. 数据库连接
 *   4. 数据库 schema
 *   5. MimeParser (parse/build)
 *   6. MailStorage (Maildir)
 *   7. 加密 / 哈希
 */

error_reporting(E_ALL);
ini_set('display_errors', '1');

$base = dirname(__DIR__);
$pass = 0;
$fail = 0;
$skipped = 0;

function test($name, $cb) {
    global $pass, $fail, $skipped;
    echo "  → $name ... ";
    try {
        $r = $cb();
        if ($r === 'SKIP') {
            echo "SKIP\n";
            $skipped++;
        } else {
            echo "PASS\n";
            $pass++;
        }
    } catch (Throwable $e) {
        echo "FAIL: " . $e->getMessage() . "\n";
        $fail++;
    }
}

echo "===========================================\n";
echo " MailSystem 自检测试\n";
echo "===========================================\n\n";

// 1. PHP 版本
echo "1. PHP 环境\n";
test('PHP >= 7.4', function() {
    if (version_compare(PHP_VERSION, '7.4.0', '<')) throw new Exception('PHP version too low: ' . PHP_VERSION);
    return true;
});
test('PDO MySQL 扩展', function() {
    if (!extension_loaded('pdo_mysql')) throw new Exception('pdo_mysql not loaded');
    return true;
});
test('OpenSSL 扩展', function() {
    if (!extension_loaded('openssl')) throw new Exception('openssl not loaded');
    return true;
});
test('mbstring 扩展', function() {
    if (!extension_loaded('mbstring')) throw new Exception('mbstring not loaded');
    return true;
});
test('iconv 扩展', function() {
    if (!extension_loaded('iconv')) throw new Exception('iconv not loaded');
    return true;
});
test('Sockets 扩展 (推荐)', function() {
    if (!extension_loaded('sockets')) return 'SKIP';
    return true;
});
test('pcntl 扩展 (推荐)', function() {
    if (!extension_loaded('pcntl')) return 'SKIP';
    return true;
});

echo "\n2. 配置加载\n";
test('helpers 加载', function() use ($base) {
    require $base . '/config/helpers.php';
    return true;
});
test('env() 函数', function() {
    putenv('MS_TEST=hello');
    if (env('MS_TEST') !== 'hello') throw new Exception('env() failed');
    if (env('MS_NOT_EXISTS', 'default') !== 'default') throw new Exception('env default failed');
    return true;
});
test('config() 函数', function() {
    $appName = config('app.name', 'fallback');
    if (empty($appName)) throw new Exception('config() failed');
    return true;
});
test('base_path() 函数', function() use ($base) {
    if (base_path() !== $base) throw new Exception('base_path() failed: ' . base_path());
    return true;
});

echo "\n3. 密码与加密\n";
test('password_hash / verify', function() {
    $h = password_hash('test123', PASSWORD_DEFAULT);
    if (!password_verify('test123', $h)) throw new Exception('verify failed');
    if (password_verify('wrong', $h)) throw new Exception('wrong should not verify');
    return true;
});
test('hash_equals', function() {
    if (!hash_equals('abc', 'abc')) throw new Exception('hash_equals failed');
    return true;
});
test('random_bytes', function() {
    $b = random_bytes(16);
    if (strlen($b) !== 16) throw new Exception('random_bytes length wrong');
    return true;
});

echo "\n4. MimeParser\n";
test('解析简单邮件', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MimeParser')) require $base . '/app/Core/MimeParser.php';
    $raw = "From: sender@example.com\r\nTo: rcpt@example.com\r\nSubject: =?UTF-8?B?5rWL6K+V?=\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nHello World 你好世界";
    $p = MailSystem\Core\MimeParser::parse($raw);
    if ($p['subject'] !== '测试') throw new Exception('subject decode failed: ' . $p['subject']);
    if (trim($p['body_text']) !== 'Hello World 你好世界') throw new Exception('body failed');
    return true;
});
test('解析 multipart 邮件', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MimeParser')) require $base . '/app/Core/MimeParser.php';
    $raw = "From: a@a.com\r\nTo: b@b.com\r\nSubject: multipart\r\nMIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=\"=B=\"\r\n\r\n--=B=\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\ntext body\r\n--=B=\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n<p>html body</p>\r\n--=B=--\r\n";
    $p = MailSystem\Core\MimeParser::parse($raw);
    if (trim($p['body_text']) !== 'text body') throw new Exception('text part failed: ' . $p['body_text']);
    if (trim($p['body_html']) !== '<p>html body</p>') throw new Exception('html part failed: ' . $p['body_html']);
    return true;
});
test('解析 base64 编码', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MimeParser')) require $base . '/app/Core/MimeParser.php';
    $encoded = base64_encode('Hello Base64 测试');
    $raw = "From: a@a.com\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n$encoded";
    $p = MailSystem\Core\MimeParser::parse($raw);
    if (trim($p['body_text']) !== 'Hello Base64 测试') throw new Exception('base64 decode failed');
    return true;
});
test('解析 quoted-printable', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MimeParser')) require $base . '/app/Core/MimeParser.php';
    $raw = "From: a@a.com\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nHello=Q3=80=8C=E4=B8=96=E7=95=8C";
    $p = MailSystem\Core\MimeParser::parse($raw);
    if (strpos($p['body_text'], '世界') === false) throw new Exception('qp decode failed: ' . $p['body_text']);
    return true;
});
test('构造邮件', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MimeParser')) require $base . '/app/Core/MimeParser.php';
    $raw = MailSystem\Core\MimeParser::build([
        'from' => 'test@example.com',
        'to' => ['user@example.com'],
        'subject' => 'Subject 测试',
        'body_text' => 'hello',
        'body_html' => '<p>hello</p>',
        'headers' => ['hostname' => 'mail.example.com'],
    ]);
    if (strpos($raw, 'Subject: =?UTF-8?B?') === false) throw new Exception('subject not encoded');
    if (strpos($raw, 'multipart/alternative') === false) throw new Exception('not multipart');
    if (strpos($raw, 'Message-ID:') === false) throw new Exception('no message id');
    return true;
});
test('解析地址 (含显示名)', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MimeParser')) require $base . '/app/Core/MimeParser.php';
    $a = MailSystem\Core\MimeParser::parseAddress('"张三" <zhangsan@example.com>');
    if ($a['name'] !== '张三') throw new Exception('name decode failed: ' . $a['name']);
    if ($a['address'] !== 'zhangsan@example.com') throw new Exception('address failed: ' . $a['address']);
    return true;
});

echo "\n5. MailStorage (Maildir)\n";
test('创建/投递/读取邮件', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MailStorage')) require $base . '/app/Core/MailStorage.php';
    $tmp = sys_get_temp_dir() . '/ms-test-' . uniqid();
    $s = new MailSystem\Core\MailStorage('user@test.com', $tmp);
    $raw = "From: a@a.com\r\nTo: user@test.com\r\nSubject: T1\r\n\r\nbody1";
    $path = $s->deliver($raw);
    if (!file_exists($path)) throw new Exception('file not written');
    $content = $s->read($path);
    if (strpos($content, 'Subject: T1') === false) throw new Exception('content mismatch');
    $list = $s->listFolder('INBOX');
    if (count($list) !== 1) throw new Exception('list count: ' . count($list));
    return true;
});
test('投递到自定义文件夹', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MailStorage')) require $base . '/app/Core/MailStorage.php';
    $tmp = sys_get_temp_dir() . '/ms-test-' . uniqid();
    $s = new MailSystem\Core\MailStorage('user@test.com', $tmp);
    $s->append("X-Test: 1\r\n\r\n", 'Sent');
    $sentDir = $tmp . '/user@test.com/.Sent/cur';
    if (!is_dir($sentDir)) throw new Exception('sent dir not created');
    return true;
});
test('使用量统计', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MailStorage')) require $base . '/app/Core/MailStorage.php';
    $tmp = sys_get_temp_dir() . '/ms-test-' . uniqid();
    $s = new MailSystem\Core\MailStorage('u@t.com', $tmp);
    $s->deliver(str_repeat('a', 1000));
    $usage = $s->usage();
    if ($usage < 1000) throw new Exception('usage too small: ' . $usage);
    return true;
});
test('删除邮件', function() use ($base) {
    if (!class_exists('MailSystem\\Core\\MailStorage')) require $base . '/app/Core/MailStorage.php';
    $tmp = sys_get_temp_dir() . '/ms-test-' . uniqid();
    $s = new MailSystem\Core\MailStorage('u@t.com', $tmp);
    $p = $s->deliver("From: a\r\nSubject: T\r\n\r\nbody");
    $s->delete($p);
    if (file_exists($p)) throw new Exception('file not deleted');
    return true;
});

echo "\n6. 数据库 (SQL 语法)\n";
test('schema.sql 语法', function() use ($base) {
    $sql = file_get_contents($base . '/database/schema.sql');
    // 移除 DEFINER 等 MySQL 特定
    $sql = preg_replace('/SET FOREIGN_KEY_CHECKS = [01];/i', '', $sql);
    // 计数 CREATE TABLE
    preg_match_all('/CREATE TABLE `?(\w+)`?/i', $sql, $m);
    if (count($m[1]) < 8) throw new Exception('not enough tables: ' . count($m[1]));
    return true;
});

echo "\n7. .env.example\n";
test('.env.example 存在', function() use ($base) {
    if (!file_exists($base . '/.env.example')) throw new Exception('missing .env.example');
    return true;
});
test('.env.example 必填项', function() use ($base) {
    $content = file_get_contents($base . '/.env.example');
    foreach (['DB_HOST', 'DB_DATABASE', 'APP_KEY', 'MAIL_HOSTNAME'] as $k) {
        if (strpos($content, $k . '=') === false) throw new Exception("missing $k");
    }
    return true;
});

echo "\n8. 脚本可执行性\n";
test('install.sh', function() use ($base) {
    $f = $base . '/scripts/install.sh';
    if (!file_exists($f)) throw new Exception('not found');
    if (!is_executable($f)) chmod($f, 0755);
    // 语法检查
    $out = shell_exec("bash -n $f 2>&1");
    if ($out) throw new Exception(trim($out));
    return true;
});
test('service.sh', function() use ($base) {
    $f = $base . '/scripts/service.sh';
    if (!file_exists($f)) throw new Exception('not found');
    if (!is_executable($f)) chmod($f, 0755);
    $out = shell_exec("bash -n $f 2>&1");
    if ($out) throw new Exception(trim($out));
    return true;
});
test('uninstall.sh', function() use ($base) {
    $f = $base . '/scripts/uninstall.sh';
    if (!file_exists($f)) throw new Exception('not found');
    if (!is_executable($f)) chmod($f, 0755);
    $out = shell_exec("bash -n $f 2>&1");
    if ($out) throw new Exception(trim($out));
    return true;
});

echo "\n9. 协议测试 (单元)\n";
test('SMTP 命令响应', function() use ($base) {
    if (!class_exists('MailSystem\\Services\\BaseServer')) require $base . '/app/Services/BaseServer.php';
    if (!class_exists('MailSystem\\Services\\SmtpServer')) require $base . '/app/Services/SmtpServer.php';
    $ref = new ReflectionClass(MailSystem\Services\SmtpServer::class);
    foreach (['onConnect', 'onData', 'onClose'] as $m) {
        if (!$ref->hasMethod($m)) throw new Exception("missing method $m");
    }
    return true;
});
test('POP3 命令响应', function() use ($base) {
    if (!class_exists('MailSystem\\Services\\BaseServer')) require $base . '/app/Services/BaseServer.php';
    if (!class_exists('MailSystem\\Services\\Pop3Server')) require $base . '/app/Services/Pop3Server.php';
    $ref = new ReflectionClass(MailSystem\Services\Pop3Server::class);
    foreach (['onConnect', 'onData', 'onClose'] as $m) {
        if (!$ref->hasMethod($m)) throw new Exception("missing method $m");
    }
    return true;
});
test('IMAP 命令响应', function() use ($base) {
    if (!class_exists('MailSystem\\Services\\BaseServer')) require $base . '/app/Services/BaseServer.php';
    if (!class_exists('MailSystem\\Services\\ImapServer')) require $base . '/app/Services/ImapServer.php';
    $ref = new ReflectionClass(MailSystem\Services\ImapServer::class);
    foreach (['onConnect', 'onData', 'onClose'] as $m) {
        if (!$ref->hasMethod($m)) throw new Exception("missing method $m");
    }
    return true;
});

echo "\n10. 前端资源\n";
test('admin/index.html', function() use ($base) {
    $f = $base . '/public/admin/index.html';
    if (!file_exists($f)) throw new Exception('missing');
    $size = filesize($f);
    if ($size < 1000) throw new Exception('too small: ' . $size);
    return true;
});
test('admin/assets/app.js', function() use ($base) {
    $f = $base . '/public/admin/assets/app.js';
    if (!file_exists($f)) throw new Exception('missing');
    return true;
});
test('web/index.html', function() use ($base) {
    $f = $base . '/public/web/index.html';
    if (!file_exists($f)) throw new Exception('missing');
    return true;
});

// 输出结果
echo "\n===========================================\n";
echo " 测试结果:  通过 $pass / 失败 $fail / 跳过 $skipped\n";
echo "===========================================\n";

exit($fail > 0 ? 1 : 0);
