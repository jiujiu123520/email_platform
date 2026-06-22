<?php
/**
 * Maildir 风格邮件存储
 * 目录结构: data/mailboxes/<local>@<domain>/{cur,new,tmp}
 */

namespace MailSystem\Core;

class MailStorage
{
    private string $basePath;
    private string $mailbox;
    private string $format; // maildir / mbox

    public function __construct(string $mailbox, ?string $basePath = null, string $format = 'maildir')
    {
        $this->basePath = rtrim($basePath ?? config('mail.storage_path', base_path('data/mailboxes')), '/');
        $this->mailbox = $mailbox;
        $this->format = $format;
        $this->ensureDir();
    }

    public function path(): string
    {
        return $this->basePath . '/' . $this->mailbox;
    }

    private function ensureDir(): void
    {
        $p = $this->path();
        if (!is_dir($p)) {
            @mkdir($p, 0700, true);
        }
        foreach (['cur', 'new', 'tmp'] as $sub) {
            $d = $p . '/' . $sub;
            if (!is_dir($d)) @mkdir($d, 0700, true);
        }
    }

    /**
     * 投递邮件到 INBOX
     */
    public function deliver(string $raw): string
    {
        $this->ensureDir();
        if ($this->format === 'mbox') {
            return $this->appendMbox($raw);
        }
        return $this->appendMaildir($raw, 'INBOX');
    }

    /**
     * 追加到指定文件夹
     */
    public function append(string $raw, string $folder = 'INBOX'): string
    {
        $this->ensureDir();
        if ($this->format === 'mbox') {
            return $this->appendMbox($raw);
        }
        return $this->appendMaildir($raw, $folder);
    }

    private function appendMaildir(string $raw, string $folder): string
    {
        if ($folder === 'INBOX') {
            $sub = 'new';
        } else {
            $folderDir = $this->path() . '/.' . $folder;
            if (!is_dir($folderDir)) {
                @mkdir($folderDir . '/cur', 0700, true);
                @mkdir($folderDir . '/new', 0700, true);
                @mkdir($folderDir . '/tmp', 0700, true);
            }
            $sub = $folder;
        }

        $base = $this->path() . '/' . $sub;
        $filename = sprintf('%d.%06d.%s.%s%s',
            time(),
            random_int(0, 999999),
            bin2hex(random_bytes(8)),
            getmypid(),
            $sub === 'cur' ? ':2,S' : ''
        );
        $tmp = $base . '/' . $filename . '.tmp';
        $final = rtrim($base, '/') . '/' . $filename;
        if (str_ends_with($final, '.tmp')) $final = substr($final, 0, -4);

        $target = $sub === 'cur' ? $this->path() . '/cur/' . $filename : $this->path() . '/new/' . $filename;
        $tmpFile = $target . '.tmp';

        if (file_put_contents($tmpFile, $raw, LOCK_EX) === false) {
            throw new \RuntimeException('Failed to write mail tmp file');
        }
        if (!rename($tmpFile, $target)) {
            @unlink($tmpFile);
            throw new \RuntimeException('Failed to rename mail file');
        }
        return $target;
    }

    private function appendMbox(string $raw): string
    {
        $mboxFile = $this->path() . '/INBOX.mbox';
        $separator = "\nFrom " . $this->mailbox . ' ' . date('D M j H:i:s Y') . "\n";
        $content = $raw;
        if (!str_starts_with($content, 'From ')) {
            $content = $separator . $content;
        }
        // 确保以换行结尾
        if (!str_ends_with($content, "\n")) {
            $content .= "\n";
        }
        $content .= "\n";
        file_put_contents($mboxFile, $content, FILE_APPEND | LOCK_EX);
        return $mboxFile;
    }

    /**
     * 列出某文件夹下所有邮件 (new + cur)
     */
    public function listFolder(string $folder = 'INBOX'): array
    {
        $this->ensureDir();
        $emails = [];
        if ($this->format === 'mbox') {
            // 不支持 mbox 列表
            return [];
        }
        $bases = [];
        if ($folder === 'INBOX') {
            $bases = [$this->path() . '/cur', $this->path() . '/new'];
        } else {
            $base = $this->path() . '/.' . $folder;
            $bases = [$base . '/cur', $base . '/new'];
            if (!is_dir($base . '/cur')) @mkdir($base . '/cur', 0700, true);
            if (!is_dir($base . '/new')) @mkdir($base . '/new', 0700, true);
        }

        foreach ($bases as $base) {
            if (!is_dir($base)) continue;
            $files = glob($base . '/*') ?: [];
            foreach ($files as $f) {
                $emails[] = [
                    'path' => $f,
                    'filename' => basename($f),
                    'size' => filesize($f),
                    'mtime' => filemtime($f),
                    'flags' => self::parseFlags(basename($f)),
                ];
            }
        }
        usort($emails, fn($a, $b) => $a['mtime'] <=> $b['mtime']);
        return $emails;
    }

    private static function parseFlags(string $filename): array
    {
        $flags = [];
        if (strpos($filename, ':2,') !== false) {
            $f = substr($filename, strpos($filename, ':2,') + 3);
            for ($i = 0; $i < strlen($f); $i++) {
                $c = $f[$i];
                if ($c === 'S') $flags[] = 'seen';
                elseif ($c === 'R') $flags[] = 'answered';
                elseif ($c === 'A') $flags[] = 'flagged';
                elseif ($c === 'T') $flags[] = 'deleted';
                elseif ($c === 'D') $flags[] = 'draft';
            }
        }
        return $flags;
    }

    /**
     * 读取邮件
     */
    public function read(string $filepath): ?string
    {
        if (!file_exists($filepath)) return null;
        $content = file_get_contents($filepath);
        return $content;
    }

    /**
     * 移动邮件到新文件夹
     */
    public function move(string $filepath, string $targetFolder): ?string
    {
        if (!file_exists($filepath)) return null;
        $filename = basename($filepath);
        $base = $this->path() . '/.' . $targetFolder;
        if (!is_dir($base)) {
            @mkdir($base . '/cur', 0700, true);
            @mkdir($base . '/new', 0700, true);
            @mkdir($base . '/tmp', 0700, true);
        }
        $isNew = strpos($filename, ':2,') === false;
        $target = $base . '/' . ($isNew ? 'new' : 'cur') . '/' . $filename;
        if (rename($filepath, $target)) {
            return $target;
        }
        return null;
    }

    /**
     * 删除邮件
     */
    public function delete(string $filepath): bool
    {
        if (!file_exists($filepath)) return false;
        return @unlink($filepath);
    }

    /**
     * 计算使用量 (字节)
     */
    public function usage(): int
    {
        $total = 0;
        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($this->path(), \FilesystemIterator::SKIP_DOTS)
        );
        foreach ($iterator as $f) {
            if ($f->isFile()) $total += $f->getSize();
        }
        return $total;
    }
}
