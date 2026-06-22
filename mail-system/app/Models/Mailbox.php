<?php

namespace MailSystem\Models;

use MailSystem\Core\Database;

class Mailbox
{
    public static function find(int $id): ?array
    {
        return Database::getInstance()->fetchOne('SELECT * FROM ms_mailboxes WHERE id = ?', [$id]);
    }
    public static function findByAddress(string $addr): ?array
    {
        $addr = strtolower($addr);
        return Database::getInstance()->fetchOne('SELECT * FROM ms_mailboxes WHERE LOWER(full_address) = ?', [$addr]);
    }
    public static function allByUser(int $userId, bool $all = false): array
    {
        $sql = 'SELECT m.*, d.domain FROM ms_mailboxes m JOIN ms_domains d ON m.domain_id = d.id';
        $params = [];
        if (!$all) {
            $sql .= ' WHERE m.user_id = ?';
            $params[] = $userId;
        }
        $sql .= ' ORDER BY m.id ASC';
        return Database::getInstance()->fetchAll($sql, $params);
    }
    public static function create(array $data): int
    {
        return Database::getInstance()->insert('ms_mailboxes', $data);
    }
    public static function update(int $id, array $data): int
    {
        return Database::getInstance()->update('ms_mailboxes', $data, 'id = :id', ['id' => $id]);
    }
    public static function delete(int $id): int
    {
        return Database::getInstance()->delete('ms_mailboxes', 'id = :id', ['id' => $id]);
    }
    public static function countByDomain(int $domainId): int
    {
        return (int) Database::getInstance()->fetchValue(
            'SELECT COUNT(*) FROM ms_mailboxes WHERE domain_id = ?',
            [$domainId]
        );
    }
}
