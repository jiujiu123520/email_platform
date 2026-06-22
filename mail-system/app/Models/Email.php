<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class Email
{
    public static function find(int $id): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_emails WHERE id = ?', [$id]);
    }
    public static function listByMailbox(int $mailboxId, string $folder = 'INBOX', int $limit = 50, int $offset = 0, string $keyword = ''): array
    {
        $sql = 'SELECT id, message_id, from_address, from_name, to_addresses, subject, folder, is_read, is_starred, direction, status, size_bytes, created_at FROM ms_emails WHERE mailbox_id = ? AND folder = ?';
        $params = [$mailboxId, $folder];
        if ($keyword !== '') {
            $sql .= ' AND (subject LIKE ? OR from_address LIKE ? OR body_text LIKE ?)';
            $kw = '%' . $keyword . '%';
            $params[] = $kw; $params[] = $kw; $params[] = $kw;
        }
        $sql .= ' ORDER BY created_at DESC LIMIT ' . (int) $limit . ' OFFSET ' . (int) $offset;
        return Database::getInstance()->fetchAll($sql, $params);
    }
    public static function countByMailbox(int $mailboxId, string $folder = 'INBOX', string $keyword = ''): int
    {
        $sql = 'SELECT COUNT(*) FROM ms_emails WHERE mailbox_id = ? AND folder = ?';
        $params = [$mailboxId, $folder];
        if ($keyword !== '') {
            $sql .= ' AND (subject LIKE ? OR from_address LIKE ? OR body_text LIKE ?)';
            $kw = '%' . $keyword . '%';
            $params[] = $kw; $params[] = $kw; $params[] = $kw;
        }
        return (int) Database::getInstance()->fetchValue($sql, $params);
    }
    public static function create(array $data): int
    {
        return Database::getInstance()->insert('ms_emails', $data);
    }
    public static function update(int $id, array $data): int
    {
        return Database::getInstance()->update('ms_emails', $data, 'id = :id', ['id' => $id]);
    }
    public static function delete(int $id): int
    {
        return Database::getInstance()->delete('ms_emails', 'id = :id', ['id' => $id]);
    }
}
